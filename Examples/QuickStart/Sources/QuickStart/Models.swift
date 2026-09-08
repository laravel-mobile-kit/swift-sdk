import Foundation

/// The application's own models: plain `Codable` types, no generated code and
/// no base class. Laravel's `snake_case` keys and ISO8601 dates are handled by
/// the kit's default decoder, so `starts_at` arrives as `startsAt`.
struct AppUser: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let createdAt: Date?
}

struct Event: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let startsAt: Date?
    let isPublished: Bool?
}

/// A Laravel API Resource wraps one record in `data`.
struct Wrapped<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: Value
}

/// What the fixture's `/api/avatar` endpoint answers with.
struct AvatarUpload: Codable, Hashable, Sendable {
    let path: String
    let originalName: String
    let mime: String
    let size: Int
}
