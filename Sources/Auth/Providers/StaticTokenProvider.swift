import Foundation

/// A provider returning one fixed token.
///
/// Useful for API keys, previews, and tests. It cannot refresh, and clearing it
/// has no effect — the token is a constant, not a session.
public struct StaticTokenProvider: TokenProvider {
    private let token: String?

    public init(_ token: String?) {
        self.token = token
    }

    public func currentToken() async throws -> String? { token }

    public func clearToken() async throws {}
}
