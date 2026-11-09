import CoreLocation
import Foundation
import HikeCore
import Observation

/// Everything the screens show: the route being planned, its computed track and statistics,
/// and the routes saved on this device.
@MainActor
@Observable
final class PlannerModel {
    // MARK: Route being planned

    private(set) var plan = RoutePlan()
    private(set) var segments: [MapSegment] = []
    private(set) var segmentsVersion = 0
    private(set) var geometry = RouteGeometry(points: [])
    private(set) var stats = RouteStats.empty
    private(set) var profile: [RouteGeometry.Sample] = []
    private(set) var isRouting = false
    /// Why a stretch could not be computed, if any.
    private(set) var routingError: RoutingError?
    /// True when every stretch between the waypoints has a track.
    private(set) var isComplete = false

    /// How the next stretch is drawn.
    var legMode: LegMode = .trail
    var selectedWaypointID: Waypoint.ID?
    /// Distance from the start that the finger is on in the elevation profile.
    var scrubDistance: Double?

    // MARK: Saved routes

    private(set) var savedRoutes: [HikeRoute] = []
    private(set) var currentRouteID: UUID?
    private(set) var currentRouteName: String?
    private(set) var hasUnsavedChanges = false

    // MARK: Map

    private(set) var camera: CameraCommand?
    private(set) var searchPin: MapPin?
    /// Centre of the last search result, so the next search favours places near it.
    private(set) var searchBias: Coordinate?

    /// A message the user should see, e.g. a failed import.
    var alertMessage: String?

    private let provider: LegProvider
    private let store: RouteStore
    @ObservationIgnored private var legCache: [LegKey: [TrackPoint]] = [:]
    @ObservationIgnored private var failures: [LegKey: RoutingError] = [:]
    @ObservationIgnored private var routingTask: Task<Void, Never>?
    @ObservationIgnored private var cameraCounter = 0

    init(service: RoutingService? = nil, store: RouteStore? = nil) {
        self.provider = LegProvider(service: service ?? BRouterClient())
        self.store = store ?? RouteStore(
            directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Routes", isDirectory: true)
        )
        savedRoutes = self.store.all()
    }

    // MARK: Derived state

    var waypoints: [Waypoint] { plan.waypoints }
    var canUndo: Bool { plan.canUndo }
    var isLoop: Bool { plan.isLoop }

    var selectedWaypointIndex: Int? {
        guard let selectedWaypointID else { return nil }
        return plan.waypoints.firstIndex { $0.id == selectedWaypointID }
    }

    var scrubCoordinate: Coordinate? {
        guard let scrubDistance else { return nil }
        return geometry.coordinate(atDistance: scrubDistance)
    }

    // MARK: Editing

    func addWaypoint(_ coordinate: Coordinate) {
        plan.append(coordinate, mode: legMode)
        planChanged()
    }

    func moveWaypoint(id: Waypoint.ID, to coordinate: Coordinate) {
        plan.move(id: id, to: coordinate)
        planChanged()
    }

    func removeWaypoint(id: Waypoint.ID) {
        plan.remove(id: id)
        planChanged()
    }

    func undo() {
        plan.undo()
        planChanged()
    }

    func closeLoop() {
        plan.closeLoop(mode: legMode)
        planChanged()
    }

    func reverseRoute() {
        // The same track walked backwards needs no new request.
        for key in plan.legKeys {
            if let points = legCache[key], legCache[key.reversed] == nil {
                legCache[key.reversed] = points.reversed()
            }
        }
        plan.reverse()
        planChanged()
    }

    /// Empties the map but keeps the edit history, so it can be undone.
    func clearRoute() {
        plan.clear()
        planChanged()
    }

    /// Starts from scratch, detached from any saved route.
    func startNewRoute() {
        plan = RoutePlan()
        currentRouteID = nil
        currentRouteName = nil
        selectedWaypointID = nil
        scrubDistance = nil
        failures = [:]
        refreshRoute()
        hasUnsavedChanges = false
    }

    func retryFailedLegs() {
        failures = [:]
        refreshRoute()
    }

    /// Draws every stretch that could not be routed as a straight line instead.
    func useStraightLinesForFailedLegs() {
        let keys = plan.legKeys
        var ids = Set<Waypoint.ID>()
        for (index, key) in keys.enumerated() where failures[key] != nil {
            ids.insert(plan.waypoints[index + 1].id)
        }
        plan.setMode(.straight, forLegsEndingAt: ids)
        planChanged()
    }

    private func planChanged() {
        if let selectedWaypointID, !plan.waypoints.contains(where: { $0.id == selectedWaypointID }) {
            self.selectedWaypointID = nil
        }
        scrubDistance = nil
        hasUnsavedChanges = !plan.isEmpty || currentRouteID != nil
        refreshRoute()
    }

    // MARK: Routing

    private func refreshRoute() {
        routingTask?.cancel()
        routingTask = nil
        rebuildTrack()

        var seen = Set<LegKey>()
        let missing = plan.legKeys.filter { key in
            legCache[key] == nil && failures[key] == nil && seen.insert(key).inserted
        }
        guard !missing.isEmpty else {
            isRouting = false
            return
        }

        isRouting = true
        // One stretch at a time: the routing server is a shared public service.
        let provider = self.provider
        routingTask = Task { [weak self] in
            for key in missing {
                let result: Result<[TrackPoint], Error>
                do {
                    result = .success(try await provider.points(for: key))
                } catch {
                    result = .failure(error)
                }
                guard let self, !Task.isCancelled else { return }
                switch result {
                case .success(let points):
                    self.legCache[key] = points
                case .failure(let error):
                    self.failures[key] = (error as? RoutingError) ?? .invalidResponse
                }
                self.rebuildTrack()
            }
            self?.isRouting = false
        }
    }

    private func rebuildTrack() {
        let keys = plan.legKeys
        var points: [TrackPoint] = []
        var newSegments: [MapSegment] = []
        var firstError: RoutingError?
        var complete = !keys.isEmpty

        for key in keys {
            if let legPoints = legCache[key] {
                points.append(contentsOf: legPoints)
                newSegments.append(MapSegment(
                    coordinates: legPoints.map(\.coordinate),
                    kind: key.mode == .straight ? .straight : .trail
                ))
            } else {
                complete = false
                let failure = failures[key]
                if firstError == nil {
                    firstError = failure
                }
                newSegments.append(MapSegment(
                    coordinates: [key.from, key.to],
                    kind: failure == nil ? .pending : .failed
                ))
            }
        }

        segments = newSegments
        segmentsVersion += 1
        geometry = RouteGeometry(points: points)
        stats = RouteStats(points: points)
        profile = geometry.elevationProfile(maxSamples: 300)
        routingError = firstError
        isComplete = complete
    }

    // MARK: Saved routes

    /// A name to offer when saving: the route's own name, or one based on where it starts.
    func suggestedName() async -> String {
        if let currentRouteName {
            return currentRouteName
        }
        let fallback = "Wandeling"
        guard let start = plan.waypoints.first?.coordinate else { return fallback }
        let location = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        guard let place = placemark?.locality ?? placemark?.name else { return fallback }
        return plan.isLoop ? "Rondje \(place)" : "Wandeling bij \(place)"
    }

    func save(name: String) {
        guard let route = currentRoute(named: name) else { return }
        do {
            try store.save(route)
            currentRouteID = route.id
            currentRouteName = route.name
            hasUnsavedChanges = false
            savedRoutes = store.all()
        } catch {
            alertMessage = "Opslaan is mislukt: \(error.localizedDescription)"
        }
    }

    private func currentRoute(named name: String) -> HikeRoute? {
        let keys = plan.legKeys
        let legs = keys.compactMap { key in
            legCache[key].map { RouteLeg(mode: key.mode, points: $0) }
        }
        guard !keys.isEmpty, legs.count == keys.count else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = savedRoutes.first { $0.id == currentRouteID }
        let now = Date()
        return HikeRoute(
            id: existing?.id ?? UUID(),
            name: trimmed.isEmpty ? "Wandeling" : trimmed,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            waypoints: plan.waypoints,
            legs: legs
        )
    }

    func open(_ route: HikeRoute) {
        plan = RoutePlan(waypoints: route.waypoints)
        for (key, leg) in zip(plan.legKeys, route.legs) {
            legCache[key] = leg.points
        }
        currentRouteID = route.id
        currentRouteName = route.name
        selectedWaypointID = nil
        scrubDistance = nil
        failures = [:]
        searchPin = nil
        refreshRoute()
        hasUnsavedChanges = false
        fitRoute()
    }

    func delete(_ route: HikeRoute) {
        do {
            try store.delete(id: route.id)
        } catch {
            alertMessage = "Verwijderen is mislukt: \(error.localizedDescription)"
        }
        savedRoutes = store.all()
        if currentRouteID == route.id {
            currentRouteID = nil
            currentRouteName = nil
            hasUnsavedChanges = !plan.isEmpty
        }
    }

    // MARK: GPX

    /// Reads a GPX file, saves it as a route and opens it. Returns false when it could not be read.
    @discardableResult
    func importGPX(from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let document = try GPX.parse(try Data(contentsOf: url))
            let name = document.name ?? url.deletingPathExtension().lastPathComponent
            guard let route = HikeRoute(name: name, importedTrack: document.points) else {
                throw GPXError.noTrack
            }
            try store.save(route)
            savedRoutes = store.all()
            open(route)
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// Writes the route being planned to a temporary GPX file for sharing.
    func exportCurrentRoute() -> URL? {
        guard let route = currentRoute(named: currentRouteName ?? "Wandeling") else { return nil }
        return export(route)
    }

    func export(_ route: HikeRoute) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gpx-export", isDirectory: true)
        let url = directory.appendingPathComponent(GPX.fileName(for: route.name))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try GPX.data(for: route).write(to: url, options: .atomic)
            return url
        } catch {
            alertMessage = "Het GPX-bestand kon niet worden gemaakt: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Map

    func fitRoute() {
        let coordinates = geometry.points.map(\.coordinate) + plan.waypoints.map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        send(.fit(coordinates))
    }

    func show(_ place: Place) {
        searchPin = MapPin(title: place.name, coordinate: place.coordinate)
        searchBias = place.coordinate
        // Towns need a wider view than a hut or a summit.
        send(.center(place.coordinate, meters: place.kind == .settlement ? 12_000 : 4_000))
    }

    /// Turns the search result on the map into the next waypoint.
    func addSearchPinToRoute() {
        guard let pin = searchPin else { return }
        searchPin = nil
        addWaypoint(pin.coordinate)
    }

    func followUser() {
        send(.followUser)
    }

    private func send(_ request: CameraCommand.Request) {
        cameraCounter += 1
        camera = CameraCommand(id: cameraCounter, request: request)
    }
}
