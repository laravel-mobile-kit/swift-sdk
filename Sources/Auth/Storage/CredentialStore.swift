import Foundation

/// Persists the current authentication credential.
///
/// Implementations must be safe to call from several tasks at once. The kit
/// ships a Keychain-backed store for apps and an in-memory store for tests and
/// previews; anything else — a shared container, a server-side store — can
/// conform.
public protocol CredentialStore: Sendable {
    /// Saves `credential`, replacing whatever was stored before.
    func store(_ credential: AuthCredential) async throws
    /// Returns the stored credential, or `nil` when there is none.
    func retrieve() async throws -> AuthCredential?
    /// Removes the stored credential. Removing nothing is not an error.
    func delete() async throws
}
