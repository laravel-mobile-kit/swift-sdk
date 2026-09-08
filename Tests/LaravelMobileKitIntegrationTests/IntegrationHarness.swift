import Foundation

import LaravelMobileKit

/// Builds the clients the integration suites talk to.
///
/// The wiring here is deliberately the wiring an application would write: the
/// point of the suite is that the documented composition works against a real
/// Laravel API, so nothing is shortcut for the tests' convenience.
enum IntegrationHarness {
    /// A client with no authentication.
    static func makeClient(
        version: APIVersion = .v1,
        timeout: TimeInterval = 15,
        retryPolicy: RetryPolicy = .none
    ) async -> LaravelClient {
        let client = LaravelClient(
            configuration: LaravelClientConfiguration(
                baseURL: IntegrationEnvironment.url,
                timeoutInterval: timeout,
                retryPolicy: retryPolicy
            )
        )
        await client.use(.validationErrors)
        if version != .none {
            await client.use(
                .apiVersion(
                    version,
                    // The fixture's whole /api/auth surface — including the test
                    // hook that expires a token — lives outside the version
                    // prefix, exactly as Laravel's own auth routes do.
                    excludedPaths: APIVersionMiddleware.defaultExcludedPaths.union(["/api/auth"])
                )
            )
        }
        return client
    }

    /// Everything an app assembles to sign a user in and keep them signed in.
    struct AuthStack {
        let client: LaravelClient
        let auth: AuthManager<APIUser>
        let session: AuthSession<APIUser>
        let store: any CredentialStore
        let coordinator: TokenRefreshCoordinator

        /// Signs the seeded user in.
        @discardableResult
        func login() async throws -> AuthResult<APIUser> {
            try await auth.login(
                email: IntegrationEnvironment.seededEmail,
                password: IntegrationEnvironment.seededPassword,
                deviceName: "integration-tests"
            )
        }
    }

    /// A full authentication stack: token middleware, refresh coordinator,
    /// refresh-driven retry, and a session for the UI to observe.
    @MainActor
    static func makeAuthStack(
        version: APIVersion = .v1,
        store: any CredentialStore = InMemoryCredentialStore(),
        timeout: TimeInterval = 15
    ) async -> AuthStack {
        let client = await makeClient(version: version, timeout: timeout)
        let provider = CredentialTokenProvider(store: store)
        await client.use(.auth(provider))

        // The refresh call runs on its own client: it must not carry the
        // Authorization header of the token being replaced, and it must not be
        // able to trigger a second refresh.
        let refreshClient = await makeClient(version: version, timeout: timeout)
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            guard let refreshToken = credential.refreshToken else {
                throw AuthError.noRefreshToken
            }
            let response = try await refreshClient.raw(
                .post,
                "/api/auth/refresh",
                body: try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
            )
            return try AuthResponseMapper<APIUser>.laravel.makeCredential(response.rawData)
        }

        let session = AuthSession<APIUser>(
            client: client,
            credentialStore: store,
            tokenProvider: provider
        )
        await client.use(
            retryDecider: AuthRefreshRetryDecider(
                coordinator: coordinator,
                onAuthFailure: session.authFailureHandler()
            )
        )

        let auth = AuthManager<APIUser>(
            client: client,
            credentialStore: store,
            session: session,
            refreshCoordinator: coordinator
        )

        return AuthStack(
            client: client,
            auth: auth,
            session: session,
            store: store,
            coordinator: coordinator
        )
    }

    /// A 1×1 PNG, small enough to embed and real enough for Laravel's file rules.
    static let pixelPNG: Data = Data(
        base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
            """
    )!
}
