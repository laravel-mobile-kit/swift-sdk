import Foundation

import LaravelMobileKit

/// The models and values the documented examples refer to.
struct Event: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String
    let startsAt: Date?
}

struct AppUser: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let email: String
}

struct AvatarResponse: Codable, Sendable {
    let path: String
}

struct GalleryResponse: Codable, Sendable {
    let count: Int
}

struct Receipt: Codable, Sendable {
    let id: Int
}

struct Attachment: Codable, Sendable {
    let id: Int
}

struct EventDraft: Codable, Sendable {
    let title: String
    let startsAt: Date
}

let baseURL = URL(string: "https://api.example.com")!
let appVersion = "1.0.0"
