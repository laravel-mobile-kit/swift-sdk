import Foundation

import LaravelMobileKitCore

/// Runs the authentication flows of a cookie-session Laravel API.
///
/// This is the counterpart to ``AuthManager`` for APIs that issue no token —
/// Laravel's own API starter kit among them. The session lives in a cookie that
/// `URLSession` stores, so there is nothing to put in the Keychain and no
/// credential to refresh: signing in is a request, and staying signed in is the
/// cookie jar.
///
/// ```swift
/// let client = await LaravelClient.sanctumSPA(baseURL: baseURL)
/// let auth = SanctumSPAAuth<AppUser>(client: client, session: session)
///
/// try await auth.login(email: email, password: password)
/// ```
///
/// Every flow performs the CSRF handshake first, so a caller never has to
/// remember it. Request fields are sent exactly as written — Breeze expects
/// `password_confirmation`, and that is what it gets.
public actor SanctumSPAAuth<User: Decodable & Sendable> {
    /// Where the flows send their requests.
    public let configuration: SanctumSPAConfiguration

    private let client: LaravelClient
    private let session: SanctumSPASession<User>?
    private let encoder = JSONEncoder()

    /// - Parameters:
    ///   - client: A client wired for a cookie session — see
    ///     ``LaravelClient/sanctumSPA(baseURL:cookieStorage:timeoutInterval:retryPolicy:additionalHeaders:)``.
    ///   - configuration: Endpoint paths. Defaults to the starter kit's.
    ///   - session: Updated as flows succeed, so SwiftUI follows along.
    public init(
        client: LaravelClient,
        configuration: SanctumSPAConfiguration = .breeze,
        session: SanctumSPASession<User>? = nil
    ) {
        self.client = client
        self.configuration = configuration
        self.session = session
    }

    // MARK: - Flows

    /// Fetches the CSRF cookie the session is built on.
    ///
    /// The other flows call this themselves; call it directly only when you
    /// send the sign-in request by hand.
    public func startSession() async throws {
        _ = try await client.raw(.get, configuration.csrfCookieEndpoint)
    }

    /// Signs in with an email and password.
    @discardableResult
    public func login(
        email: String,
        password: String,
        extraFields: [String: String] = [:]
    ) async throws -> User {
        var fields = extraFields
        fields["email"] = email
        fields["password"] = password
        return try await login(fields: fields)
    }

    /// Signs in with whatever fields the endpoint expects.
    @discardableResult
    public func login(fields: [String: String]) async throws -> User {
        try await authenticate(at: configuration.loginEndpoint, fields: fields)
    }

    /// Registers an account. Laravel's starter kit signs it in at the same time.
    @discardableResult
    public func register(fields: [String: String]) async throws -> User {
        try await authenticate(at: configuration.registerEndpoint, fields: fields)
    }

    /// Loads the authenticated user.
    public func currentUser() async throws -> User {
        try await client.get(configuration.userEndpoint)
    }

    /// Signs out.
    ///
    /// The server is told first, but a failure there — offline, session already
    /// gone — never blocks the local sign-out.
    public func logout() async {
        try? await startSession()
        _ = try? await client.raw(.post, configuration.logoutEndpoint)

        if let session {
            await session.signedOut()
        }
    }

    /// Asks the API to start a password reset.
    public func requestPasswordReset(email: String) async throws {
        guard let endpoint = configuration.passwordResetEndpoint else {
            throw AuthError.endpointNotConfigured("password reset")
        }
        try await startSession()
        _ = try await client.raw(.post, endpoint, body: try encoder.encode(["email": email]))
    }

    /// Asks the API to send another email verification link.
    public func resendEmailVerification() async throws {
        guard let endpoint = configuration.emailVerificationEndpoint else {
            throw AuthError.endpointNotConfigured("email verification")
        }
        try await startSession()
        _ = try await client.raw(.post, endpoint)
    }

    // MARK: - Shared flow

    /// Handshakes, posts the credentials, and loads the user the session now has.
    ///
    /// The starter kit answers a successful sign-in with `204 No Content`, so
    /// the user is a second request — which is also the check that the session
    /// cookie really took.
    private func authenticate(at endpoint: String, fields: [String: String]) async throws -> User {
        try await startSession()
        _ = try await client.raw(.post, endpoint, body: try encoder.encode(fields))

        let user = try await currentUser()
        if let session {
            await session.adopt(user: user)
        }
        return user
    }
}
