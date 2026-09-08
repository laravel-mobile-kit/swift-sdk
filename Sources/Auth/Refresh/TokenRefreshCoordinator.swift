import Foundation

/// Runs one token refresh at a time.
///
/// Several requests failing with `401` at once must produce a single refresh,
/// not one per request. Callers that arrive while a refresh is running join it
/// and receive its result — the actor is what makes that deterministic.
///
/// The refresh call itself is supplied by the app, because there is no single
/// Laravel refresh contract: Sanctum commonly issues no refresh token at all,
/// Passport uses an OAuth token endpoint, and custom APIs do their own thing.
///
/// ```swift
/// let coordinator = TokenRefreshCoordinator(credentialStore: keychain) { credential in
///     // Use a client WITHOUT the 401 decider, so a failing refresh cannot loop.
///     let response: TokenResponse = try await refreshClient.post(
///         "/api/auth/refresh",
///         body: ["refresh_token": credential.refreshToken]
///     )
///     return response.credential
/// }
/// ```
///
/// ## Behaviour
///
/// - **Eligible requests**: whichever the ``RetryDecider`` retries — the kit's
///   decider retries a request that failed with `401`, once.
/// - **One refresh**: concurrent callers share the in-flight refresh. A `401`
///   that arrives *after* a refresh finished starts a new one; that is the cost
///   of not tracking which token each request carried.
/// - **Loop protection**: the refresh closure must not use a client carrying
///   the 401 decider, and Core caps decider-driven retries per request.
/// - **Failure**: the error is rethrown to every waiter, and the caller decides
///   what it means for the session.
/// - **Logout during refresh**: ``invalidate()`` cancels the in-flight refresh;
///   waiters see cancellation rather than a credential the user just discarded.
public actor TokenRefreshCoordinator {
    /// Exchanges the current credential for a fresh one.
    public typealias Refresh = @Sendable (AuthCredential) async throws -> AuthCredential

    private let credentialStore: any CredentialStore
    private let performRefresh: Refresh
    private var refreshTask: Task<AuthCredential, any Error>?

    public init(
        credentialStore: any CredentialStore,
        refresh: @escaping Refresh
    ) {
        self.credentialStore = credentialStore
        self.performRefresh = refresh
    }

    /// Whether a refresh is currently running.
    public var isRefreshing: Bool { refreshTask != nil }

    /// Refreshes the stored credential, joining a refresh already in progress.
    ///
    /// - Returns: The credential to use from now on.
    /// - Throws: ``AuthError/notAuthenticated`` when nothing is stored,
    ///   ``AuthError/noRefreshToken`` when the credential cannot be renewed, or
    ///   whatever the refresh call threw.
    @discardableResult
    public func refreshIfNeeded() async throws -> AuthCredential {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { [credentialStore, performRefresh] in
            guard let current = try await credentialStore.retrieve() else {
                throw AuthError.notAuthenticated
            }
            guard current.refreshToken != nil else {
                throw AuthError.noRefreshToken
            }

            let refreshed = try await performRefresh(current)
            try await credentialStore.store(refreshed)
            return refreshed
        }
        refreshTask = task

        defer { refreshTask = nil }
        return try await task.value
    }

    /// Cancels an in-flight refresh and forgets it.
    ///
    /// Call this when the user signs out: a refresh finishing afterwards would
    /// otherwise re-store a credential the user just discarded.
    public func invalidate() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
