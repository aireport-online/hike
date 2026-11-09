import HikeCore
import MapKit
import SwiftUI

struct MapView: UIViewRepresentable {
    var style: MapStyle
    var showsTrails: Bool
    var showsUserLocation: Bool
    var segments: [MapSegment]
    /// Bumped whenever `segments` changes; cheaper to compare than thousands of coordinates.
    var segmentsVersion: Int
    var waypoints: [Waypoint]
    var scrubCoordinate: Coordinate?
    var searchPin: MapPin?
    var camera: CameraCommand?
    /// Space at the top and bottom covered by controls, so the map keeps its content clear of them.
    var topInset: CGFloat
    var bottomInset: CGFloat

    var onTap: (Coordinate) -> Void
    var onMoveWaypoint: (Waypoint.ID, Coordinate) -> Void
    var onSelectWaypoint: (Waypoint.ID?) -> Void
    var onTapSearchPin: () -> Void

    private static let regionKey = "lastMapRegion"

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        // A region set on a map without a size does not stick, so it is given a plausible size
        // now and the region is applied again at the first real layout.
        let mapView = SizedMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        mapView.pendingRegion = Self.initialRegion()
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.accessibilityIdentifier = "map"
        mapView.register(WaypointAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.waypointReuseID)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.searchPinReuseID)
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.scrubReuseID)
        mapView.setRegion(Self.initialRegion(), animated: false)

        // The double tap does nothing itself; it only makes the single tap wait, so zooming with
        // a double tap does not drop a waypoint.
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        mapView.addGestureRecognizer(doubleTap)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: doubleTap)
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
        }
        coordinator.applyInsets(to: mapView)
        coordinator.applyTiles(to: mapView)
        coordinator.applyRoute(to: mapView)
        coordinator.applyWaypoints(to: mapView)
        coordinator.applyScrub(to: mapView)
        coordinator.applySearchPin(to: mapView)
        coordinator.applyCamera(to: mapView)
    }

    /// Where the map was last time, or all of Europe on first launch.
    private static func initialRegion() -> MKCoordinateRegion {
        if let saved = UserDefaults.standard.array(forKey: regionKey) as? [Double], saved.count == 4,
           (-90...90).contains(saved[0]), (-180...180).contains(saved[1]), saved[2] > 0, saved[3] > 0 {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: saved[0], longitude: saved[1]),
                span: MKCoordinateSpan(latitudeDelta: min(saved[2], 90), longitudeDelta: min(saved[3], 180))
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.5, longitude: 10.5),
            span: MKCoordinateSpan(latitudeDelta: 34, longitudeDelta: 46)
        )
    }

    fileprivate static func remember(_ region: MKCoordinateRegion) {
        UserDefaults.standard.set(
            [region.center.latitude, region.center.longitude, region.span.latitudeDelta, region.span.longitudeDelta],
            forKey: regionKey
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let waypointReuseID = "waypoint"
        static let searchPinReuseID = "searchPin"
        static let scrubReuseID = "scrub"

        var parent: MapView

        private var appliedStyle: MapStyle?
        private var appliedShowsTrails: Bool?
        private var appliedSegmentsVersion = -1
        private var appliedWaypoints: [Waypoint]?
        private var appliedSearchPin: MapPin?
        private var appliedCameraID: Int?
        private var appliedInsets: UIEdgeInsets?

        private var tileOverlays: [MKOverlay] = []
        private var routeOverlays: [MKOverlay] = []
        private var scrubAnnotation: ScrubAnnotation?
        private var searchPinAnnotation: SearchPinAnnotation?
        /// Whether a marker was selected when the current touch began. Such a tap only deselects.
        private var touchBeganWithSelection = false

        init(parent: MapView) {
            self.parent = parent
        }

        // MARK: Applying state

        func applyInsets(to mapView: MKMapView) {
            let insets = UIEdgeInsets(top: parent.topInset, left: 0, bottom: parent.bottomInset, right: 0)
            guard appliedInsets != insets else { return }
            appliedInsets = insets
            // Keeps the scale, the Apple logo and the centre of the map clear of our controls.
            mapView.layoutMargins = insets
        }

        func applyTiles(to mapView: MKMapView) {
            guard appliedStyle != parent.style || appliedShowsTrails != parent.showsTrails else { return }
            appliedStyle = parent.style
            appliedShowsTrails = parent.showsTrails

            mapView.removeOverlays(tileOverlays)
            tileOverlays = []

            if parent.style == .satellite {
                mapView.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
            } else {
                mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            }

            // Past the deepest tiles there is nothing to draw, so zooming in stops a little
            // beyond the point where they are shown at full size.
            let closest: CLLocationDistance
            switch parent.style.tileSource?.maxZoom {
            case .some(let maxZoom) where maxZoom <= 17: closest = 300
            case .some: closest = 120
            case .none: closest = 100
            }
            mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: closest)

            // Tiles go underneath the route: base map first, then the trail overlay.
            var index = 0
            if let source = parent.style.tileSource {
                let base = CachedTileOverlay(source: source, replacesMap: true)
                mapView.insertOverlay(base, at: index, level: .aboveLabels)
                tileOverlays.append(base)
                index += 1
            }
            if parent.showsTrails {
                let trails = CachedTileOverlay(source: .waymarkedHiking, replacesMap: false)
                mapView.insertOverlay(trails, at: index, level: .aboveLabels)
                tileOverlays.append(trails)
            }
        }

        func applyRoute(to mapView: MKMapView) {
            guard appliedSegmentsVersion != parent.segmentsVersion else { return }
            appliedSegmentsVersion = parent.segmentsVersion

            mapView.removeOverlays(routeOverlays)
            var casings: [RoutePolyline] = []
            var lines: [RoutePolyline] = []
            for segment in parent.segments where segment.coordinates.count >= 2 {
                let coordinates = segment.coordinates.map(\.clCoordinate)
                if segment.kind == .trail || segment.kind == .straight {
                    let casing = RoutePolyline(coordinates: coordinates, count: coordinates.count)
                    casing.look = .casing
                    casings.append(casing)
                }
                let line = RoutePolyline(coordinates: coordinates, count: coordinates.count)
                switch segment.kind {
                case .trail: line.look = .trail
                case .straight: line.look = .straight
                case .pending: line.look = .pending
                case .failed: line.look = .failed
                }
                lines.append(line)
            }
            routeOverlays = casings + lines
            mapView.addOverlays(routeOverlays, level: .aboveLabels)
        }

        func applyWaypoints(to mapView: MKMapView) {
            guard appliedWaypoints != parent.waypoints else { return }
            appliedWaypoints = parent.waypoints

            let existing = mapView.annotations.filter { $0 is WaypointAnnotation }
            mapView.removeAnnotations(existing)

            let waypoints = parent.waypoints
            let annotations = waypoints.enumerated().map { index, waypoint -> WaypointAnnotation in
                let role: WaypointAnnotation.Role
                if index == 0 {
                    role = .start
                } else if index == waypoints.count - 1 {
                    role = .end
                } else {
                    role = .via
                }
                return WaypointAnnotation(waypoint: waypoint, index: index, role: role)
            }
            mapView.addAnnotations(annotations)
        }

        func applyScrub(to mapView: MKMapView) {
            if let coordinate = parent.scrubCoordinate {
                if let annotation = scrubAnnotation {
                    annotation.coordinate = coordinate.clCoordinate
                } else {
                    let annotation = ScrubAnnotation()
                    annotation.coordinate = coordinate.clCoordinate
                    scrubAnnotation = annotation
                    mapView.addAnnotation(annotation)
                }
            } else if let annotation = scrubAnnotation {
                mapView.removeAnnotation(annotation)
                scrubAnnotation = nil
            }
        }

        func applySearchPin(to mapView: MKMapView) {
            guard appliedSearchPin != parent.searchPin else { return }
            appliedSearchPin = parent.searchPin
            if let annotation = searchPinAnnotation {
                mapView.removeAnnotation(annotation)
                searchPinAnnotation = nil
            }
            if let pin = parent.searchPin {
                let annotation = SearchPinAnnotation()
                annotation.coordinate = pin.coordinate.clCoordinate
                annotation.title = pin.title
                searchPinAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func applyCamera(to mapView: MKMapView) {
            guard let command = parent.camera, command.id != appliedCameraID else { return }
            appliedCameraID = command.id
            (mapView as? SizedMapView)?.pendingRegion = nil

            switch command.request {
            case .followUser:
                mapView.setUserTrackingMode(.follow, animated: true)

            case .center(let coordinate, let meters):
                let region = MKCoordinateRegion(
                    center: coordinate.clCoordinate,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                )
                mapView.setRegion(region, animated: true)

            case .fit(let coordinates):
                let points = coordinates.map { MKMapPoint($0.clCoordinate) }
                guard let first = points.first else { return }
                var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
                for point in points.dropFirst() {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
                if maxX - minX < 1, maxY - minY < 1 {
                    let region = MKCoordinateRegion(center: first.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)
                    mapView.setRegion(region, animated: true)
                } else {
                    let rect = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    let padding = UIEdgeInsets(top: 50, left: 40, bottom: 50, right: 40)
                    mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
                }
            }
        }

        // MARK: Gestures

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {}

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView = recognizer.view as? MKMapView else { return }
            guard !touchBeganWithSelection else { return }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            parent.onTap(Coordinate(coordinate))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Touches on markers and on the map's own buttons are theirs, not a new waypoint.
            var view = touch.view
            while let current = view, !(current is MKMapView) {
                if current is MKAnnotationView || current is UIControl {
                    return false
                }
                view = current.superview
            }
            if let mapView = gestureRecognizer.view as? MKMapView {
                touchBeganWithSelection = !mapView.selectedAnnotations.isEmpty
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            guard let line = overlay as? RoutePolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineJoin = .round
            renderer.lineCap = .round
            // Signpost colours: a yellow line in a charcoal outline stands out on any map.
            switch line.look {
            case .casing:
                renderer.strokeColor = Brand.UI.ink
                renderer.lineWidth = 9
            case .trail:
                renderer.strokeColor = Brand.UI.yellow
                renderer.lineWidth = 5
            case .straight:
                renderer.strokeColor = Brand.UI.yellow
                renderer.lineWidth = 5
                renderer.lineCap = .butt
                renderer.lineDashPattern = [9, 7]
            case .pending:
                renderer.strokeColor = Brand.UI.ink.withAlphaComponent(0.7)
                renderer.lineWidth = 3
                renderer.lineCap = .butt
                renderer.lineDashPattern = [6, 6]
            case .failed:
                renderer.strokeColor = Brand.UI.blaze
                renderer.lineWidth = 3
                renderer.lineCap = .butt
                renderer.lineDashPattern = [6, 6]
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let waypoint = annotation as? WaypointAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.waypointReuseID, for: annotation)
                view.isDraggable = true
                view.canShowCallout = false
                view.displayPriority = .required
                view.isAccessibilityElement = true
                switch waypoint.role {
                case .start:
                    view.image = MarkerArt.start
                    view.centerOffset = .zero
                    view.zPriority = .defaultUnselected
                    view.accessibilityLabel = "Startpunt"
                case .end:
                    view.image = MarkerArt.end
                    view.centerOffset = MarkerArt.endOffset
                    view.zPriority = .max
                    view.accessibilityLabel = "Eindpunt"
                case .via:
                    view.image = MarkerArt.via(waypoint.index)
                    view.centerOffset = .zero
                    view.zPriority = .defaultUnselected
                    view.accessibilityLabel = "Punt \(waypoint.index)"
                }
                return view
            }

            if annotation is SearchPinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.searchPinReuseID, for: annotation)
                view.canShowCallout = false
                view.displayPriority = .required
                if let marker = view as? MKMarkerAnnotationView {
                    marker.markerTintColor = Brand.UI.ink
                    marker.glyphTintColor = Brand.UI.yellow
                    marker.glyphImage = UIImage(systemName: "magnifyingglass")
                    marker.titleVisibility = .visible
                }
                return view
            }

            if annotation is ScrubAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.scrubReuseID, for: annotation)
                view.image = MarkerArt.scrub
                view.isEnabled = false
                view.canShowCallout = false
                view.displayPriority = .required
                view.zPriority = .max
                return view
            }

            // The user's position keeps the system's blue dot.
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if view.annotation is SearchPinAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                let callback = parent.onTapSearchPin
                DispatchQueue.main.async { callback() }
            } else if let waypoint = view.annotation as? WaypointAnnotation {
                let callback = parent.onSelectWaypoint
                let id = waypoint.waypointID
                DispatchQueue.main.async { callback(id) }
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard view.annotation is WaypointAnnotation else { return }
            let callback = parent.onSelectWaypoint
            DispatchQueue.main.async { callback(nil) }
        }

        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            switch newState {
            case .ending:
                view.setDragState(.none, animated: true)
                if let waypoint = view.annotation as? WaypointAnnotation {
                    let callback = parent.onMoveWaypoint
                    let id = waypoint.waypointID
                    let coordinate = Coordinate(waypoint.coordinate)
                    DispatchQueue.main.async { callback(id, coordinate) }
                }
            case .canceling:
                view.setDragState(.none, animated: true)
            default:
                break
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            MapView.remember(mapView.region)
        }
    }
}

// MARK: - Map view

/// Applies its starting region at the first layout with a real size.
final class SizedMapView: MKMapView {
    var pendingRegion: MKCoordinateRegion?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let region = pendingRegion, bounds.width > 0, bounds.height > 0, window != nil {
            pendingRegion = nil
            setRegion(region, animated: false)
        }
    }
}

// MARK: - Overlays and annotations

final class RoutePolyline: MKPolyline {
    enum Look {
        case casing, trail, straight, pending, failed
    }

    var look: Look = .trail
}

final class WaypointAnnotation: MKPointAnnotation {
    enum Role {
        case start, via, end
    }

    let waypointID: Waypoint.ID
    let index: Int
    let role: Role

    init(waypoint: Waypoint, index: Int, role: Role) {
        self.waypointID = waypoint.id
        self.index = index
        self.role = role
        super.init()
        coordinate = waypoint.coordinate.clCoordinate
    }
}

final class SearchPinAnnotation: MKPointAnnotation {}

/// The spot on the route that belongs to the finger position on the elevation profile.
final class ScrubAnnotation: MKPointAnnotation {}

/// A waypoint marker that can be picked up and dragged.
final class WaypointAnnotationView: MKAnnotationView {
    override func setDragState(_ newDragState: MKAnnotationView.DragState, animated: Bool) {
        super.setDragState(newDragState, animated: animated)
        // A plain annotation view has to walk through the drag states itself.
        switch newDragState {
        case .starting:
            dragState = .dragging
            setLifted(true)
        case .ending, .canceling:
            dragState = .none
            setLifted(false)
        default:
            break
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        if dragState == .none {
            setLifted(selected)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
    }

    private func setLifted(_ lifted: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.transform = lifted ? CGAffineTransform(scaleX: 1.35, y: 1.35) : .identity
        }
    }
}

/// Marker drawings in the signpost colours, each with a white edge so it reads on any map.
enum MarkerArt {
    /// Start: a charcoal ring.
    static let start: UIImage = {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 1, dy: 1))
            cg.setFillColor(Brand.UI.ink.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 3, dy: 3))
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 9, dy: 9))
        }
    }()

    /// End: a charcoal pennant on a pole, standing on the point it marks.
    static let end: UIImage = {
        let size = CGSize(width: 36, height: 42)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let foot = CGPoint(x: 9, y: 36)
            let top = CGPoint(x: 9, y: 5)

            let pennant = UIBezierPath()
            pennant.move(to: top)
            pennant.addLine(to: CGPoint(x: 32, y: 12.5))
            pennant.addLine(to: CGPoint(x: 9, y: 20))
            pennant.close()

            let pole = UIBezierPath()
            pole.move(to: top)
            pole.addLine(to: foot)

            // White edge first, charcoal on top.
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            UIColor.white.setStroke()
            pennant.lineWidth = 5
            pennant.stroke()
            pole.lineWidth = 7.5
            pole.stroke()
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: foot.x - 5.5, y: foot.y - 5.5, width: 11, height: 11))

            Brand.UI.ink.setFill()
            Brand.UI.ink.setStroke()
            pennant.lineWidth = 1.5
            pennant.fill()
            pennant.stroke()
            pole.lineWidth = 3.5
            pole.stroke()
            cg.fillEllipse(in: CGRect(x: foot.x - 3.5, y: foot.y - 3.5, width: 7, height: 7))
        }
    }()

    /// Moves the end marker so the foot of its pole, not its centre, sits on the coordinate.
    static let endOffset = CGPoint(x: 36 / 2 - 9, y: -(36 - 42 / 2))

    private static var viaCache: [Int: UIImage] = [:]

    /// An intermediate point: a numbered yellow disc.
    static func via(_ number: Int) -> UIImage {
        if let cached = viaCache[number] {
            return cached
        }
        let size = CGSize(width: 26, height: 26)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: bounds)
            cg.setFillColor(Brand.UI.ink.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 1.5, dy: 1.5))
            cg.setFillColor(Brand.UI.yellow.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 3.5, dy: 3.5))

            let text = String(number) as NSString
            let font = UIFont(name: Brand.FontName.sign, size: number > 9 ? 13 : 15)
                ?? UIFont.systemFont(ofSize: 13, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Brand.UI.ink]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes
            )
        }
        viaCache[number] = image
        return image
    }

    /// The spot on the route that matches the finger on the elevation profile.
    static let scrub: UIImage = {
        let size = CGSize(width: 20, height: 20)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            cg.setFillColor(Brand.UI.ink.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 1, dy: 1))
            cg.setFillColor(Brand.UI.blaze.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 3.5, dy: 3.5))
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: bounds.insetBy(dx: 7, dy: 7))
        }
    }()
}
