import Foundation

/// A provider backed by a ``CredentialStore``.
///
/// This is the provider an app normally uses: the credential lives in the
/// Keychain, and every request reads the current one.
///
/// An expired credential reports no token rather than sending a token the
/// server will reject. The request then goes out unauthenticated and comes back
/// `401`, which is the signal the refresh flow acts on.
public actor CredentialTokenProvider: TokenProvider {
    private let store: any CredentialStore
    private let expiryLeeway: TimeInterval

    /// Creates a provider reading from `store`.
    ///
    /// - Parameters:
    ///   - store: Where the credential is persisted.
    ///   - expiryLeeway: How long before the stated expiry a token is already
    ///     treated as expired, so it does not lapse mid-flight.
    public init(store: any CredentialStore, expiryLeeway: TimeInterval = 0) {
        self.store = store
        self.expiryLeeway = expiryLeeway
    }

    /// The stored credential, expired or not.
    public func currentCredential() async throws -> AuthCredential? {
        try await store.retrieve()
    }

    /// Replaces the stored credential.
    public func store(_ credential: AuthCredential) async throws {
        try await store.store(credential)
    }

    public func currentToken() async throws -> String? {
        guard let credential = try await store.retrieve() else { return nil }
        guard !credential.expires(within: expiryLeeway) else { return nil }
        return credential.accessToken
    }

    public func clearToken() async throws {
        try await store.delete()
    }
}
