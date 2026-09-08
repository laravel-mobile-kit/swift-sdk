import Foundation

/// A stored authentication credential.
///
/// The kit is deliberately agnostic about how a credential was obtained —
/// Sanctum personal access token, Passport OAuth token, or a session cookie all
/// arrive here as an opaque `accessToken`.
public struct AuthCredential: Codable, Sendable, Hashable {
    /// The token sent with authenticated requests.
    public let accessToken: String
    /// Token used to obtain a new access token, when the API issues one.
    public let refreshToken: String?
    /// Authorization scheme, `Bearer` unless the API says otherwise.
    public let tokenType: String
    /// When the access token stops being valid, when the API says.
    public let expiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        tokenType: String = "Bearer",
        expiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
    }

    /// Whether the token has expired.
    ///
    /// A credential without an expiry never reports itself expired: Sanctum
    /// tokens are commonly issued without one, and guessing would log users out
    /// for no reason.
    public var isExpired: Bool {
        isExpired(at: Date())
    }

    /// Whether the token has expired at `date`.
    public func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return date >= expiresAt
    }

    /// Whether the token expires within `interval` from `date`.
    ///
    /// Refreshing slightly early avoids sending a token that expires while the
    /// request is in flight.
    public func expires(within interval: TimeInterval, from date: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(date) <= interval
    }

    /// The value for an `Authorization` header, for example `Bearer abc123`.
    public var authorizationHeaderValue: String {
        tokenType.isEmpty ? accessToken : "\(tokenType) \(accessToken)"
    }
}
