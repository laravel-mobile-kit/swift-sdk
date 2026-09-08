import Foundation

/// The fixture's user payload.
struct APIUser: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let email: String
    let createdAt: Date?
}

/// The fixture's event payload.
///
/// Every property is named in Swift's convention: the decoder's `snake_case`
/// conversion is part of what these tests exercise.
struct APIEvent: Codable, Hashable, Sendable {
    let id: Int
    let title: String
    let description: String?
    let startsAt: Date?
    let isPublished: Bool?
    let createdAt: Date?
}

/// A Laravel API Resource wraps a single record in `data`.
struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: Value
}

/// The fixture's multipart upload response.
struct AvatarUpload: Codable, Hashable, Sendable {
    let path: String
    let originalName: String
    let mime: String
    let size: Int
    let caption: String?
    let fields: [String: String]
}

/// The record the fixture creates once a direct upload has landed.
struct DirectUploadReceipt: Codable, Hashable, Sendable {
    let id: Int
    let uuid: String
    let key: String
    let filename: String
    let size: Int
}

/// The request reflection endpoint.
struct EchoedRequest: Codable, Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]

    /// Headers are compared case-insensitively: HTTP does not promise a case.
    func header(_ field: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }
}

/// The flaky endpoint's answer once it stops failing.
struct FlakyResult: Codable, Sendable {
    let attempts: Int
    let method: String
}

/// The counter the flaky endpoint reports when it is reset.
struct FlakyCounter: Codable, Sendable {
    let attempts: Int
}

/// The version the fixture served a request from.
struct ServedVersion: Codable, Sendable {
    let version: String
}
