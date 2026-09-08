import Combine
import Foundation

import LaravelMobileKitCore

/// Observable authentication state for one app.
///
/// The session owns the answer to "is someone signed in, and who": it restores
/// a stored credential on launch, verifies it against the API, and publishes the
/// result for SwiftUI to switch on.
///
/// ```swift
/// @StateObject private var session = AuthSession<AppUser>(
///     client: client,
///     credentialStore: keychain,
///     tokenProvider: provider
/// )
///
/// var body: some View {
///     Group {
///         switch session.state {
///         case .unknown, .restoring: ProgressView()
///         case .unauthenticated: LoginView()
///         case .authenticated(let user): HomeView(user: user)
///         case .unverified: OfflineRetryView()
///         }
///     }
///     .task { await session.restore() }
/// }
/// ```
///
/// The client passed in is expected to carry an ``AuthMiddleware`` backed by the
/// same credential store, so verifying the session sends the stored token.
@MainActor
public final class AuthSession<User: Decodable & Sendable>: ObservableObject {
    /// The current state, published for SwiftUI.
    @Published public private(set) var state: AuthState<User> = .unknown
    /// Why the last operation could not settle the state, when it could not.
    @Published public private(set) var lastError: (any Error)?

    private let client: LaravelClient
    private let credentialStore: any CredentialStore
    private let tokenProvider: (any TokenProvider)?
    private let loadUser: @Sendable (LaravelClient) async throws -> User

    /// Creates a session that verifies credentials against `userEndpoint`.
    ///
    /// - Parameters:
    ///   - client: The client used to verify the session.
    ///   - credentialStore: Where the credential is persisted.
    ///   - tokenProvider: Consulted to refresh an expired credential. Without
    ///     one, an expired credential ends the session.
    ///   - userEndpoint: The endpoint returning the current user. Laravel's
    ///     convention is `/api/user`, and it is not API-versioned.
    public init(
        client: LaravelClient,
        credentialStore: any CredentialStore,
        tokenProvider: (any TokenProvider)? = nil,
        userEndpoint: String = "/api/user"
    ) {
        self.client = client
        self.credentialStore = credentialStore
        self.tokenProvider = tokenProvider
        self.loadUser = { client in try await client.get(userEndpoint) }
    }

    /// Creates a session that verifies credentials with a custom request.
    ///
    /// Use this when the current-user endpoint wraps its payload — a Laravel API
    /// resource returning `{"data": {...}}`, for example.
    public init(
        client: LaravelClient,
        credentialStore: any CredentialStore,
        tokenProvider: (any TokenProvider)? = nil,
        loadUser: @escaping @Sendable (LaravelClient) async throws -> User
    ) {
        self.client = client
        self.credentialStore = credentialStore
        self.tokenProvider = tokenProvider
        self.loadUser = loadUser
    }

    /// The signed-in user, when there is one.
    public var user: User? { state.user }

    // MARK: - Lifecycle

    /// Restores a stored credential and verifies it against the API.
    ///
    /// Call this once at launch. It never throws: every outcome is expressed as
    /// a state, which is what a view needs to render.
    public func restore() async {
        lastError = nil
        state = .restoring

        do {
            guard let credential = try await credentialStore.retrieve() else {
                state = .unauthenticated
                return
            }
            if credential.isExpired {
                try await refreshExpiredCredential()
            }
            state = .authenticated(try await loadUser(client))
        } catch {
            await handle(error)
        }
    }

    /// Adopts a credential obtained elsewhere — a login response, say — and
    /// verifies it.
    ///
    /// - Returns: The signed-in user.
    @discardableResult
    public func signIn(with credential: AuthCredential) async throws -> User {
        lastError = nil
        state = .restoring

        do {
            try await credentialStore.store(credential)
            let user = try await loadUser(client)
            state = .authenticated(user)
            return user
        } catch {
            await handle(error)
            throw error
        }
    }

    /// Reflects a session established elsewhere — by ``AuthManager`` after a
    /// login, for instance.
    ///
    /// The caller is responsible for having stored the credential; this only
    /// moves the published state.
    public func adopt(user: User) {
        lastError = nil
        state = .authenticated(user)
    }

    /// Re-reads the current user, keeping the stored credential.
    @discardableResult
    public func reloadUser() async throws -> User {
        do {
            let user = try await loadUser(client)
            state = .authenticated(user)
            return user
        } catch {
            await handle(error)
            throw error
        }
    }

    /// Signs the user out locally: the credential is removed and the state
    /// becomes ``AuthState/unauthenticated``.
    ///
    /// Telling the server about it is a separate call, because an app must be
    /// able to sign out while offline.
    public func logout() async {
        try? await tokenProvider?.clearToken()
        try? await credentialStore.delete()
        lastError = nil
        state = .unauthenticated
    }

    /// Ends the session because the credential is no longer usable.
    ///
    /// Unlike ``logout()`` this keeps the reason, so a view can explain why the
    /// user is looking at a sign-in screen again.
    public func endSession(reason: (any Error)? = nil) async {
        await logout()
        lastError = reason
    }

    /// A handler that ends this session, for wiring into the refresh flow.
    ///
    /// ```swift
    /// await client.use(retryDecider: AuthRefreshRetryDecider(
    ///     coordinator: coordinator,
    ///     onAuthFailure: session.authFailureHandler()
    /// ))
    /// ```
    ///
    /// This is what moves the UI to a signed-out state when a refresh fails: the
    /// state becomes ``AuthState/unauthenticated`` and ``lastError`` explains it.
    public nonisolated func authFailureHandler() -> @Sendable (any Error) async -> Void {
        { [weak self] error in
            await self?.endSession(reason: error)
        }
    }

    // MARK: - Failure handling

    /// Refreshes an expired credential, or gives up in a way `restore` can act on.
    private func refreshExpiredCredential() async throws {
        guard let tokenProvider else {
            // Nothing can renew it, so the credential is dead weight.
            throw AuthError.refreshNotSupported
        }
        _ = try await tokenProvider.refreshToken()
    }

    /// Decides what a failure means for the session.
    ///
    /// Only the server saying "this credential is no good" ends the session. A
    /// network failure leaves the credential in place: the user is not signed
    /// out for being in a tunnel.
    private func handle(_ error: any Error) async {
        lastError = error

        if isCredentialRejected(error) {
            try? await tokenProvider?.clearToken()
            try? await credentialStore.delete()
            state = .unauthenticated
        } else {
            state = .unverified
        }
    }

    /// Whether `error` means the stored credential is no longer usable.
    private func isCredentialRejected(_ error: any Error) -> Bool {
        if let error = error as? LaravelError {
            return error.isUnauthorized || error.isForbidden
        }
        if let error = error as? AuthError {
            return error == .refreshNotSupported || error == .notAuthenticated
        }
        return false
    }
}
