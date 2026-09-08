import Foundation

/// How a token is attached to a request.
public enum AuthTransport: Sendable {
    /// `Authorization: Bearer <token>` — what Sanctum and Passport expect.
    case bearer
    /// `Authorization: <scheme> <token>` for APIs using another scheme.
    case scheme(String)
    /// `Cookie: <token>`, for APIs authenticating with a session cookie.
    case cookie
    /// Anything else: the closure receives the request and the token.
    case custom(@Sendable (URLRequest, String) async throws -> URLRequest)

    /// Applies `token` to `request`.
    func apply(_ token: String, to request: URLRequest) async throws -> URLRequest {
        var request = request
        switch self {
        case .bearer:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case let .scheme(scheme):
            request.setValue("\(scheme) \(token)", forHTTPHeaderField: "Authorization")
        case .cookie:
            request.setValue(token, forHTTPHeaderField: "Cookie")
        case let .custom(handler):
            request = try await handler(request, token)
        }
        return request
    }

    /// The header this transport writes, used to detect a caller-supplied one.
    var headerField: String? {
        switch self {
        case .bearer, .scheme:
            "Authorization"
        case .cookie:
            "Cookie"
        case .custom:
            nil
        }
    }
}
