import HikeCore

/// One stretch of the route as drawn on the map.
struct MapSegment: Equatable {
    enum Kind {
        /// Follows paths, as computed by the routing service.
        case trail
        /// A straight line the user asked for.
        case straight
        /// Still being computed.
        case pending
        /// Could not be computed.
        case failed
    }

    var coordinates: [Coordinate]
    var kind: Kind
}

/// A one-off instruction to move the map. `id` changes for every new instruction, so repeating
/// the same request (fit the route again) is still carried out.
struct CameraCommand: Equatable {
    enum Request: Equatable {
        case fit([Coordinate])
        case center(Coordinate, meters: Double)
        case followUser
    }

    var id: Int
    var request: Request
}

struct MapPin: Equatable {
    var title: String
    var coordinate: Coordinate
}
