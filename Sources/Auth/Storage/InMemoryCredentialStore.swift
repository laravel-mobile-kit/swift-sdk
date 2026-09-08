import Foundation

/// A credential store that keeps the credential in memory only.
///
/// Intended for tests and SwiftUI previews. Nothing is persisted, so the
/// credential disappears when the process exits — which is exactly what a
/// preview wants and never what an app wants.
public actor InMemoryCredentialStore: CredentialStore {
    private var credential: AuthCredential?

    public init(credential: AuthCredential? = nil) {
        self.credential = credential
    }

    public func store(_ credential: AuthCredential) async throws {
        self.credential = credential
    }

    public func retrieve() async throws -> AuthCredential? {
        credential
    }

    public func delete() async throws {
        credential = nil
    }
}
