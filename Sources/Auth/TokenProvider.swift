import Foundation

/// Supplies the token sent with authenticated requests.
///
/// The protocol is what lets the kit stay out of the way of an existing API:
/// a token can come from the Keychain, from memory, from a server-side session,
/// or from an app that manages credentials itself.
public protocol TokenProvider: Sendable {
    /// The token to send with the next request, or `nil` when signed out.
    func currentToken() async throws -> String?
    /// Obtains a fresh token, replacing whatever is stored.
    func refreshToken() async throws -> String
    /// Drops the stored token.
    func clearToken() async throws
}

extension TokenProvider {
    /// Providers that cannot refresh — a static API key, for instance — inherit
    /// this and report the fact instead of pretending to succeed.
    public func refreshToken() async throws -> String {
        throw AuthError.refreshNotSupported
    }
}
