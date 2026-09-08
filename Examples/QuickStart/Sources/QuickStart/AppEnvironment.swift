import Foundation

import LaravelMobileKit

/// The one place the kit is wired up.
///
/// This is the canonical composition an application writes once at launch:
///
/// ```
/// KeychainCredentialStore   ← where the token lives
///         ↓
/// CredentialTokenProvider   ← reads it for every request
///         ↓
/// AuthMiddleware            ← attaches `Authorization: Bearer …`
///         ↓
/// AuthRefreshRetryDecider   ← turns a 401 into one refresh and one retry
///         ↓
/// AuthSession               ← what SwiftUI switches on
/// ```
///
/// Nothing below is specific to this sample: swap the configuration and the
/// user model and it is the wiring for any Laravel-backed app.
@MainActor
final class AppEnvironment: ObservableObject {
    let configuration: AppConfiguration
    let client: LaravelClient
    let session: AuthSession<AppUser>
    let auth: AuthManager<AppUser>

    private let credentialStore: any CredentialStore
    private var hasStarted = false

    init(configuration: AppConfiguration = .default) {
        self.configuration = configuration

        // Credentials belong in the Keychain, never in UserDefaults.
        #if os(macOS)
        // An unsigned macOS binary — which `swift run` produces — cannot reach
        // the data protection Keychain. A signed app keeps the default.
        let store = KeychainCredentialStore(
            service: configuration.keychainService,
            usesDataProtectionKeychain: false
        )
        #else
        let store = KeychainCredentialStore(service: configuration.keychainService)
        #endif
        self.credentialStore = store

        let client = LaravelClient(
            configuration: LaravelClientConfiguration(
                baseURL: configuration.baseURL,
                timeoutInterval: 30,
                // Idempotent requests are retried; POSTs are not.
                retryPolicy: .default
            )
        )
        self.client = client

        // The refresh call runs on its own client: it must not carry the token
        // being replaced, and it must not be able to trigger a second refresh.
        let refreshClient = LaravelClient(
            configuration: LaravelClientConfiguration(
                baseURL: configuration.baseURL,
                retryPolicy: .none
            )
        )
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            guard let refreshToken = credential.refreshToken else {
                throw AuthError.noRefreshToken
            }
            let response = try await refreshClient.raw(
                .post,
                "/api/auth/refresh",
                body: try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
            )
            return try AuthResponseMapper<AppUser>.laravel.makeCredential(response.rawData)
        }

        let provider = CredentialTokenProvider(store: store)
        let session = AuthSession<AppUser>(
            client: client,
            credentialStore: store,
            tokenProvider: provider
        )
        self.session = session

        self.auth = AuthManager<AppUser>(
            client: client,
            credentialStore: store,
            session: session,
            refreshCoordinator: coordinator
        )

        self.pendingMiddlewares = [
            .auth(provider),
            .validationErrors,
            .apiVersion(
                configuration.apiVersion,
                // The fixture's whole `/api/auth` surface stays unversioned.
                excludedPaths: APIVersionMiddleware.defaultExcludedPaths.union(["/api/auth"])
            ),
        ]
        self.pendingRetryDecider = AuthRefreshRetryDecider(
            coordinator: coordinator,
            onAuthFailure: session.authFailureHandler()
        )
    }

    private let pendingMiddlewares: [any Middleware]
    private let pendingRetryDecider: AuthRefreshRetryDecider

    /// Registers the pipeline and restores whatever session is on the device.
    ///
    /// Called once from the root view's `.task`, before the first request.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        await client.use(pendingMiddlewares)
        await client.use(retryDecider: pendingRetryDecider)
        await session.restore()
    }

    // MARK: - Flows the views call

    func signIn(email: String, password: String) async throws {
        try await auth.login(email: email, password: password, deviceName: deviceName)
    }

    func signOut() async {
        await auth.logout()
    }

    private var deviceName: String {
        #if os(iOS)
        "ios-quickstart"
        #else
        "macos-quickstart"
        #endif
    }
}
