import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

import LaravelMobileKit

/// The payload shape used by the custom-mapper example.
private struct TokenPayload: Decodable, Sendable {
    let jwt: String
    let renewal: String?
    let validUntil: Date?
    let profile: AppUser?
}

/// Examples from `Documentation/AUTHENTICATION.md`.
enum AuthenticationSnippets {
    // MARK: - Sign in with Apple

    /// The half that belongs to the app: build the request carrying the hashed
    /// nonce. `AuthenticationServices` is Apple-only, so this is guarded.
    #if canImport(AuthenticationServices)
    static func appleRequest(nonce: SignInWithAppleNonce) -> ASAuthorizationAppleIDRequest {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashed
        return request
    }
    #endif

    /// The half the kit covers: exchange the identity token for the API's own,
    /// sending the raw nonce.
    static func appleExchange(
        auth: AuthManager<AppUser>,
        identityToken: String,
        nonce: SignInWithAppleNonce
    ) async throws {
        try await auth.login(identityToken: identityToken, nonce: nonce.raw)
    }

    /// Apple sends the name only on the first authorization for an Apple ID.
    static func appleFirstSignIn(
        auth: AuthManager<AppUser>,
        identityToken: String,
        nonce: SignInWithAppleNonce,
        givenName: String?,
        familyName: String?
    ) async throws {
        try await auth.login(
            identityToken: identityToken,
            nonce: nonce.raw,
            extraFields: [
                "given_name": givenName ?? "",
                "family_name": familyName ?? "",
            ]
        )
    }

    /// A provider whose API spells the field the OIDC way, on its own route.
    static func googleExchange(auth: AuthManager<AppUser>, idToken: String) async throws {
        try await auth.login(identityToken: idToken, provider: "google", fieldNames: .oidc)
    }

    static var dedicatedAppleRoute: AuthConfiguration {
        AuthConfiguration(identityTokenEndpoint: "/api/auth/apple")
    }

    static func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(
            service: "com.example.app",
            account: "credentials",
            accessGroup: nil,
            accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    static func inspect(_ credential: AuthCredential) {
        _ = credential.isExpired
        _ = credential.expires(within: 60)
        _ = credential.authorizationHeaderValue
    }

    static func flows(
        client: LaravelClient,
        session: AuthSession<AppUser>,
        coordinator: TokenRefreshCoordinator,
        store: any CredentialStore,
        email: String,
        password: String,
        name: String
    ) async throws {
        let auth = AuthManager<AppUser>(
            client: client,
            configuration: .laravel,
            credentialStore: store,
            session: session,
            refreshCoordinator: coordinator
        )

        _ = try await auth.login(email: email, password: password, deviceName: "iPhone")
        _ = try await auth.register(fields: ["name": name, "email": email, "password": password])
        _ = try await auth.currentUser()
        await auth.logout()
    }

    static var customEndpoints: AuthConfiguration {
        AuthConfiguration(
            loginEndpoint: "/api/auth/token",
            registerEndpoint: "/api/auth/register",
            logoutEndpoint: "/api/auth/revoke",
            userEndpoint: "/api/me",
            refreshEndpoint: "/api/auth/refresh",
            passwordResetEndpoint: "/api/auth/forgot",
            emailVerificationEndpoint: nil
        )
    }

    static func customMapper(client: LaravelClient, store: any CredentialStore) -> AuthManager<AppUser> {
        let mapper = AuthResponseMapper<AppUser>(
            makeCredential: { data in
                let payload = try JSONDecoder().decode(TokenPayload.self, from: data)
                return AuthCredential(
                    accessToken: payload.jwt,
                    refreshToken: payload.renewal,
                    expiresAt: payload.validUntil
                )
            },
            makeUser: { data, decoder in
                try decoder.decode(TokenPayload.self, from: data).profile
            }
        )

        return AuthManager<AppUser>(client: client, credentialStore: store, mapper: mapper)
    }

    static func transports(client: LaravelClient, provider: any TokenProvider) async {
        await client.use(.auth(provider, transport: .bearer))
        await client.use(.auth(provider, transport: .scheme("Token")))
        await client.use(.auth(provider, transport: .cookie))
        await client.use(
            .auth(
                provider,
                transport: .custom { request, token in
                    var request = request
                    request.setValue(token, forHTTPHeaderField: "X-API-Key")
                    return request
                }
            )
        )
    }

    @MainActor
    static func sessionLifecycle(
        session: AuthSession<AppUser>,
        credential: AuthCredential,
        error: any Error
    ) async throws {
        await session.restore()
        _ = try await session.signIn(with: credential)
        _ = try await session.reloadUser()
        await session.logout()
        await session.endSession(reason: error)
    }

    @MainActor
    static func refreshWiring(
        client: LaravelClient,
        refreshClient: LaravelClient,
        store: any CredentialStore,
        session: AuthSession<AppUser>
    ) async {
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            guard let refreshToken = credential.refreshToken else { throw AuthError.noRefreshToken }
            let response = try await refreshClient.raw(
                .post,
                "/api/auth/refresh",
                body: try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
            )
            return try AuthResponseMapper<AppUser>.laravel.makeCredential(response.rawData)
        }

        await client.use(
            retryDecider: AuthRefreshRetryDecider(
                coordinator: coordinator,
                maxAttempts: 1,
                onAuthFailure: session.authFailureHandler()
            )
        )
    }
}
