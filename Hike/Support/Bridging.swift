import CoreLocation
import HikeCore

extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Pace {
    var title: String {
        switch self {
        case .relaxed: return "Rustig"
        case .normal: return "Normaal"
        case .brisk: return "Stevig"
        }
    }
}
