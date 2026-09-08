import Foundation

/// A version of the Laravel API the app talks to.
///
/// This is the API's version, not the kit's and not Laravel's: the three move
/// independently, and shipping Mobile Kit 2.0 never implies API v2.
public enum APIVersion: Sendable, Hashable {
    /// The API is not versioned: `/api/events`.
    case none
    /// `/api/v1/…`
    case v1
    /// `/api/v2/…`
    case v2
    /// `/api/v3/…`
    case v3
    /// Any other segment, such as `beta`.
    case custom(String)

    /// The path segment this version inserts, or `nil` when unversioned.
    public var pathSegment: String? {
        switch self {
        case .none: nil
        case .v1: "v1"
        case .v2: "v2"
        case .v3: "v3"
        case let .custom(segment): segment
        }
    }
}
