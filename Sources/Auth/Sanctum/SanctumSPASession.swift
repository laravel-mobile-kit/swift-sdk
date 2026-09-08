import Combine
import Foundation

import LaravelMobileKitCore

/// Observable session state for a cookie-authenticated Laravel API.
///
/// The token-based ``AuthSession`` restores a credential from the Keychain and
/// verifies it. There is no credential here: the session cookie either still
/// works or it does not, so restoring is one request to the user endpoint.
///
/// ```swift
/// @StateObject private var session = SanctumSPASession<AppUser>(client: client)
///
/// var body: some View {
///     Group {
///         switch session.state {
///         case .unknown, .restoring: ProgressView()
///         case .unauthenticated: LoginView()
///         case let .authenticated(user): HomeView(user: user)
///         case .unverified: OfflineRetryView()
///         }
///     }
///     .task { await session.restore() }
/// }
/// ```
///
/// Cookies survive a relaunch only when the client keeps a persistent jar,
/// which is what `URLSessionConfiguration.default` and the shared storage give
/// you. An ephemeral jar signs the user out when the process exits.
@MainActor
public final class SanctumSPASession<User: Decodable & Sendable>: ObservableObject {
    /// The current state, published for SwiftUI.
    @Published public private(set) var state: AuthState<User> = .unknown
    /// Why the last operation could not settle the state, when it could not.
    @Published public private(set) var lastError: (any Error)?

    private let client: LaravelClient
    private let loadUser: @Sendable (LaravelClient) async throws -> User

    /// Creates a session that verifies the cookie against `userEndpoint`.
    public init(client: LaravelClient, userEndpoint: String = "/api/user") {
        self.client = client
        self.loadUser = { client in try await client.get(userEndpoint) }
    }

    /// Creates a session that verifies the cookie with a custom request.
    ///
    /// Use this when the user endpoint wraps its payload in a `data` envelope.
    public init(
        client: LaravelClient,
        loadUser: @escaping @Sendable (LaravelClient) async throws -> User
    ) {
        self.client = client
        self.loadUser = loadUser
    }

    /// The signed-in user, when there is one.
    public var user: User? { state.user }

    // MARK: - Lifecycle

    /// Asks the API who the cookie belongs to.
    ///
    /// Call this once at launch. It never throws: every outcome is a state,
    /// which is what a view needs to render. A 401 means signed out; anything
    /// else — offline, server down — leaves the session ``AuthState/unverified``
    /// rather than discarding a cookie that may still be good.
    public func restore() async {
        lastError = nil
        state = .restoring

        do {
            state = .authenticated(try await loadUser(client))
        } catch let error as LaravelError where error.isUnauthorized {
            state = .unauthenticated
        } catch {
            lastError = error
            state = .unverified
        }
    }

    /// Adopts a user the sign-in flow already loaded.
    public func adopt(user: User) {
        lastError = nil
        state = .authenticated(user)
    }

    /// Re-reads the user, keeping the session state in step.
    @discardableResult
    public func reloadUser() async throws -> User {
        let user = try await loadUser(client)
        state = .authenticated(user)
        return user
    }

    /// Moves to the signed-out state. ``SanctumSPAAuth/logout()`` calls this.
    public func signedOut() {
        lastError = nil
        state = .unauthenticated
    }

    /// Ends the session because it could not be kept — an expired cookie, say.
    public func endSession(reason: (any Error)? = nil) {
        lastError = reason
        state = .unauthenticated
    }
}
