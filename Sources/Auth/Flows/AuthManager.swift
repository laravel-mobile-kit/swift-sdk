import Foundation

import LaravelMobileKitCore

/// The outcome of a login or registration.
public struct AuthResult<User: Sendable>: Sendable {
    /// The credential the API issued.
    public let credential: AuthCredential
    /// The user, when the flow could determine one.
    public let user: User?

    public init(credential: AuthCredential, user: User?) {
        self.credential = credential
        self.user = user
    }
}

/// Runs the authentication flows against an existing Laravel API.
///
/// ```swift
/// let auth = AuthManager<AppUser>(
///     client: client,
///     credentialStore: keychain,
///     session: session
/// )
///
/// try await auth.login(email: "ada@example.com", password: "secret")
/// try await auth.logout()
/// ```
///
/// Every endpoint is configurable and none of them inherit an API version
/// prefix: `/api/login` sits next to `/api/v1/events` in most Laravel apps.
///
/// Request fields are sent as written — `device_name` stays `device_name` —
/// because they are the API's contract, not Swift property names.
public actor AuthManager<User: Decodable & Sendable> {
    /// Where the flows send their requests.
    public let configuration: AuthConfiguration

    private let client: LaravelClient
    private let credentialStore: any CredentialStore
    private let session: AuthSession<User>?
    private let refreshCoordinator: TokenRefreshCoordinator?
    private let mapper: AuthResponseMapper<User>
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    /// - Parameters:
    ///   - client: Client used for the flows. It should carry the
    ///     ``AuthMiddleware`` so requests after login are authenticated.
    ///   - configuration: Endpoint paths. Defaults to Laravel's conventions.
    ///   - credentialStore: Where the issued credential is persisted.
    ///   - session: Updated as flows succeed, so SwiftUI follows along.
    ///   - refreshCoordinator: Invalidated on logout, so a refresh in flight
    ///     cannot re-store a credential the user just discarded.
    ///   - mapper: Reads the credential and user out of the response.
    ///   - decoder: Decodes the user model.
    public init(
        client: LaravelClient,
        configuration: AuthConfiguration = .laravel,
        credentialStore: any CredentialStore,
        session: AuthSession<User>? = nil,
        refreshCoordinator: TokenRefreshCoordinator? = nil,
        mapper: AuthResponseMapper<User> = .laravel,
        decoder: JSONDecoder = LaravelJSONDecoder.makeDefault()
    ) {
        self.client = client
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.session = session
        self.refreshCoordinator = refreshCoordinator
        self.mapper = mapper
        self.decoder = decoder
    }

    // MARK: - Flows

    /// Signs in with an email and password.
    ///
    /// - Parameters:
    ///   - deviceName: Sanctum's token endpoint requires one; other APIs ignore
    ///     it, and it is omitted when `nil`.
    ///   - extraFields: Anything else the endpoint expects, such as a 2FA code.
    @discardableResult
    public func login(
        email: String,
        password: String,
        deviceName: String? = nil,
        extraFields: [String: String] = [:]
    ) async throws -> AuthResult<User> {
        var fields = extraFields
        fields["email"] = email
        fields["password"] = password
        if let deviceName {
            fields["device_name"] = deviceName
        }
        return try await login(fields: fields)
    }

    /// Signs in with whatever fields the endpoint expects.
    @discardableResult
    public func login(fields: [String: String]) async throws -> AuthResult<User> {
        try await authenticate(at: configuration.loginEndpoint, fields: fields)
    }

    /// Exchanges a third-party identity token for one of the API's own.
    ///
    /// This is the second half of Sign in with Apple — and of any other provider
    /// that hands the app a signed JWT. The first half belongs to the app,
    /// because it needs a view to present from; see
    /// [Authentication](https://github.com/laravel-mobile-kit/swift-sdk/blob/main/Documentation/AUTHENTICATION.md)
    /// for the `ASAuthorizationController` wiring.
    ///
    /// ```swift
    /// let nonce = SignInWithAppleNonce()
    /// request.nonce = nonce.hashed
    /// // …
    /// try await auth.login(identityToken: token, nonce: nonce.raw)
    /// ```
    ///
    /// Pass the **raw** nonce, not the hashed one: the server hashes it and
    /// compares the result against the claim inside the token, which is what
    /// makes the token non-replayable.
    ///
    /// Verifying the token — against Apple's JWKS, checking `aud`, `iss`, `exp`
    /// and that nonce claim — is the server's job. A client cannot do it
    /// meaningfully; anything it checked, an attacker could skip.
    ///
    /// - Parameters:
    ///   - identityToken: The signed JWT the provider returned.
    ///   - nonce: The raw nonce, when the flow used one.
    ///   - provider: Which provider issued the token.
    ///   - extraFields: Anything else the endpoint expects — an authorization
    ///     code, or the name Apple only sends on first sign-in.
    ///   - fieldNames: The names to send these under, for APIs that spell them
    ///     differently.
    @discardableResult
    public func login(
        identityToken: String,
        nonce: String? = nil,
        provider: String = "apple",
        extraFields: [String: String] = [:],
        fieldNames: IdentityTokenFieldNames = .default
    ) async throws -> AuthResult<User> {
        var fields = extraFields
        fields[fieldNames.identityToken] = identityToken
        fields[fieldNames.provider] = provider
        if let nonce {
            fields[fieldNames.nonce] = nonce
        }
        return try await authenticate(
            at: configuration.resolvedIdentityTokenEndpoint,
            fields: fields
        )
    }

    /// Registers an account and adopts the credential the API issues.
    ///
    /// APIs that return no token on registration leave the session untouched:
    /// the flow then throws ``AuthError/invalidAuthResponse``, and the app
    /// should call ``login(fields:)`` instead.
    @discardableResult
    public func register(fields: [String: String]) async throws -> AuthResult<User> {
        try await authenticate(at: configuration.registerEndpoint, fields: fields)
    }

    /// Signs out.
    ///
    /// The server is told first, but a failure there — offline, expired token —
    /// never blocks the local sign-out: an app must be able to sign out without
    /// a network.
    public func logout() async {
        _ = try? await client.raw(.post, configuration.logoutEndpoint)

        await refreshCoordinator?.invalidate()
        try? await credentialStore.delete()
        if let session {
            await session.logout()
        }
    }

    /// Loads the authenticated user.
    public func currentUser() async throws -> User {
        try await client.get(configuration.userEndpoint)
    }

    /// Asks the API to start a password reset.
    public func requestPasswordReset(email: String) async throws {
        guard let endpoint = configuration.passwordResetEndpoint else {
            throw AuthError.endpointNotConfigured("password reset")
        }
        _ = try await client.raw(.post, endpoint, body: try encoder.encode(["email": email]))
    }

    /// Asks the API to send another email verification link.
    public func resendEmailVerification() async throws {
        guard let endpoint = configuration.emailVerificationEndpoint else {
            throw AuthError.endpointNotConfigured("email verification")
        }
        _ = try await client.raw(.post, endpoint)
    }

    // MARK: - Shared flow

    /// Posts credentials, stores the issued token, and settles the session.
    private func authenticate(
        at endpoint: String,
        fields: [String: String]
    ) async throws -> AuthResult<User> {
        let response = try await client.raw(.post, endpoint, body: try encoder.encode(fields))

        let credential = try mapper.makeCredential(response.rawData)
        try await credentialStore.store(credential)

        let user = try? mapper.makeUser(response.rawData, decoder)
        guard let session else {
            return AuthResult(credential: credential, user: user)
        }

        // The session needs a user; ask the API only when the response had none.
        let resolved: User
        if let user {
            resolved = user
        } else {
            resolved = try await currentUser()
        }
        await session.adopt(user: resolved)
        return AuthResult(credential: credential, user: resolved)
    }
}
