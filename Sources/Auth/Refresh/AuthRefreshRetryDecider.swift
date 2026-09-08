import Foundation

import LaravelMobileKitCore

/// Retries a request once after refreshing a rejected token.
///
/// ```swift
/// await client.use(retryDecider: AuthRefreshRetryDecider(coordinator: coordinator) { _ in
///     await session.logout()
/// })
/// ```
///
/// The retried request is rebuilt by the client, so the ``AuthMiddleware``
/// attaches the freshly refreshed token — the decider itself never touches
/// headers.
///
/// ## Retry rules
///
/// - Only `401` responses are eligible.
/// - One refresh-driven retry per request (`maxAttempts`).
/// - A second `401` means the new token was rejected too: the session is over,
///   `onAuthFailure` runs, and the request fails with ``AuthError/sessionExpired``.
/// - A failed refresh does the same, and the underlying error is handed to
///   `onAuthFailure` so the app can tell "expired" from "server down".
public struct AuthRefreshRetryDecider: RetryDecider {
    private let coordinator: TokenRefreshCoordinator
    private let maxAttempts: Int
    private let onAuthFailure: (@Sendable (any Error) async -> Void)?

    /// - Parameters:
    ///   - coordinator: Performs the single-flight refresh.
    ///   - maxAttempts: How many times one request may be retried after a
    ///     refresh. One is almost always right.
    ///   - onAuthFailure: Runs when the session cannot be renewed — wire it to
    ///     `AuthSession.logout()` to move the UI to a signed-out state.
    public init(
        coordinator: TokenRefreshCoordinator,
        maxAttempts: Int = 1,
        onAuthFailure: (@Sendable (any Error) async -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.maxAttempts = max(1, maxAttempts)
        self.onAuthFailure = onAuthFailure
    }

    public func shouldRetry(
        _ error: LaravelError,
        request: Request,
        attempt: Int
    ) async throws -> Bool {
        guard error.isUnauthorized else { return false }

        guard attempt < maxAttempts else {
            // The token was refreshed and the server still says no.
            await onAuthFailure?(AuthError.sessionExpired)
            throw AuthError.sessionExpired
        }

        do {
            _ = try await coordinator.refreshIfNeeded()
            return true
        } catch is CancellationError {
            // Logout cancelled the refresh; the session is gone by request.
            throw AuthError.sessionExpired
        } catch {
            await onAuthFailure?(error)
            throw AuthError.sessionExpired
        }
    }
}
