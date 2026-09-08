import Foundation
import Testing

import LaravelMobileKitAuth
import LaravelMobileKitCore

struct Account: Codable, Hashable, Sendable {
    let id: Int
    let displayName: String
}

@Suite("Auth configuration")
struct AuthConfigurationTests {
    @Test("The Laravel defaults point at the conventional routes")
    func laravelDefaults() {
        let configuration = AuthConfiguration.laravel

        #expect(configuration.loginEndpoint == "/api/login")
        #expect(configuration.registerEndpoint == "/api/register")
        #expect(configuration.logoutEndpoint == "/api/logout")
        #expect(configuration.userEndpoint == "/api/user")
    }

    @Test("Every configured endpoint is listed for versioning to skip")
    func allEndpoints() {
        let configuration = AuthConfiguration(
            loginEndpoint: "/auth/sign-in",
            passwordResetEndpoint: nil,
            emailVerificationEndpoint: nil
        )

        #expect(configuration.allEndpoints.contains("/auth/sign-in"))
        #expect(configuration.allEndpoints.contains("/api/user"))
        #expect(configuration.allEndpoints.count == 5)
    }
}

@Suite("Auth response mapping")
struct AuthResponseMapperTests {
    let mapper = AuthResponseMapper<Account>.laravel
    let decoder = LaravelJSONDecoder.makeDefault()

    private func credential(from json: String) throws -> AuthCredential {
        try mapper.makeCredential(Data(json.utf8))
    }

    @Test("A bare Sanctum token is understood")
    func sanctumToken() throws {
        let credential = try credential(from: #"{"token":"abc"}"#)

        #expect(credential.accessToken == "abc")
        #expect(credential.tokenType == "Bearer")
        #expect(credential.expiresAt == nil)
    }

    @Test("An OAuth-style payload is understood")
    func oauthPayload() throws {
        let credential = try credential(
            from: #"{"access_token":"abc","refresh_token":"def","token_type":"Bearer","expires_in":3600}"#
        )

        #expect(credential.accessToken == "abc")
        #expect(credential.refreshToken == "def")
        #expect(credential.expiresAt != nil)
        #expect(credential.expires(within: 3601))
        #expect(!credential.expires(within: 3500))
    }

    @Test("An explicit expiry date is understood")
    func explicitExpiry() throws {
        let credential = try credential(
            from: #"{"token":"abc","expires_at":"2024-01-15T10:30:00.000000Z"}"#
        )

        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_705_314_600))
    }

    @Test("A token wrapped in a resource envelope is found")
    func wrappedToken() throws {
        let credential = try credential(from: #"{"data":{"token":"abc","token_type":"Token"}}"#)

        #expect(credential.accessToken == "abc")
        #expect(credential.tokenType == "Token")
    }

    @Test("A response with no token is rejected")
    func missingToken() {
        #expect(throws: AuthError.invalidAuthResponse) {
            try credential(from: #"{"message":"Signed in"}"#)
        }
        #expect(throws: AuthError.invalidAuthResponse) {
            try credential(from: "not json")
        }
    }

    @Test("A user in the payload is decoded with Laravel conventions")
    func userIsDecoded() throws {
        let json = #"{"token":"abc","user":{"id":1,"display_name":"Ada"}}"#

        let user = try mapper.makeUser(Data(json.utf8), decoder)

        #expect(user == Account(id: 1, displayName: "Ada"))
    }

    @Test("A user inside the envelope is decoded")
    func wrappedUserIsDecoded() throws {
        let json = #"{"data":{"token":"abc","user":{"id":2,"display_name":"Grace"}}}"#

        let user = try mapper.makeUser(Data(json.utf8), decoder)

        #expect(user == Account(id: 2, displayName: "Grace"))
    }

    @Test("A response without a user yields none")
    func noUserInPayload() throws {
        #expect(try mapper.makeUser(Data(#"{"token":"abc"}"#.utf8), decoder) == nil)
    }
}

@MainActor
@Suite("Auth flows")
struct AuthManagerTests {
    let baseURL = URL(string: "https://api.example.com")!
    let loginPayload = #"{"token":"abc","user":{"id":1,"display_name":"Ada"}}"#

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    private func makeSession(_ client: LaravelClient, store: any CredentialStore) -> AuthSession<Account> {
        AuthSession<Account>(client: client, credentialStore: store)
    }

    @Test("Logging in stores the credential and settles the session")
    func loginStoresCredential() async throws {
        let transport = MockTransport(json: loginPayload)
        let store = InMemoryCredentialStore()
        let client = makeClient(transport)
        let session = makeSession(client, store: store)
        let auth = AuthManager<Account>(client: client, credentialStore: store, session: session)

        let result = try await auth.login(email: "ada@example.com", password: "secret")

        #expect(result.credential.accessToken == "abc")
        #expect(result.user == Account(id: 1, displayName: "Ada"))
        #expect(try await store.retrieve()?.accessToken == "abc")
        #expect(session.state == .authenticated(Account(id: 1, displayName: "Ada")))
        #expect(await transport.lastRequest?.url?.path == "/api/login")
    }

    @Test("Login fields are sent exactly as named")
    func loginFieldsAreNotRewritten() async throws {
        let transport = MockTransport(json: loginPayload)
        let store = InMemoryCredentialStore()
        let auth = AuthManager<Account>(client: makeClient(transport), credentialStore: store)

        try await auth.login(
            email: "ada@example.com",
            password: "secret",
            deviceName: "iPhone",
            extraFields: ["two_factor_code": "123456"]
        )

        let body = try #require(await transport.lastRequest?.httpBody)
        let fields = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(fields == [
            "email": "ada@example.com",
            "password": "secret",
            "device_name": "iPhone",
            "two_factor_code": "123456",
        ])
    }

    @Test("A login response without a user loads one from the user endpoint")
    func loginFetchesUserWhenMissing() async throws {
        let transport = MockTransport(bodies: [
            #"{"token":"abc"}"#,
            #"{"id":3,"display_name":"Alan"}"#,
        ])
        let store = InMemoryCredentialStore()
        let client = makeClient(transport)
        let session = makeSession(client, store: store)
        let auth = AuthManager<Account>(client: client, credentialStore: store, session: session)

        let result = try await auth.login(email: "alan@example.com", password: "secret")

        #expect(result.user == Account(id: 3, displayName: "Alan"))
        let paths = await transport.executedRequests.map(\.url?.path)
        #expect(paths == ["/api/login", "/api/user"])
        #expect(session.state.isAuthenticated)
    }

    @Test("Without a session, a login response without a user asks for nothing more")
    func loginWithoutSessionSkipsUserLookup() async throws {
        let transport = MockTransport(json: #"{"token":"abc"}"#)
        let store = InMemoryCredentialStore()
        let auth = AuthManager<Account>(client: makeClient(transport), credentialStore: store)

        let result = try await auth.login(email: "ada@example.com", password: "secret")

        #expect(result.user == nil)
        #expect(await transport.attemptCount == 1)
    }

    @Test("Custom endpoints are used as written")
    func customEndpoints() async throws {
        let transport = MockTransport(json: loginPayload)
        let store = InMemoryCredentialStore()
        let configuration = AuthConfiguration(loginEndpoint: "/auth/sign-in")
        let auth = AuthManager<Account>(
            client: makeClient(transport),
            configuration: configuration,
            credentialStore: store
        )

        try await auth.login(email: "ada@example.com", password: "secret")

        #expect(await transport.lastRequest?.url?.path == "/auth/sign-in")
    }

    @Test("Registering adopts the issued credential")
    func register() async throws {
        let transport = MockTransport(json: loginPayload)
        let store = InMemoryCredentialStore()
        let auth = AuthManager<Account>(client: makeClient(transport), credentialStore: store)

        let result = try await auth.register(fields: [
            "name": "Ada",
            "email": "ada@example.com",
            "password": "secret",
        ])

        #expect(result.credential.accessToken == "abc")
        #expect(await transport.lastRequest?.url?.path == "/api/register")
        #expect(try await store.retrieve() != nil)
    }

    @Test("A response with no token leaves nothing stored")
    func loginWithInvalidResponse() async throws {
        let transport = MockTransport(json: #"{"message":"Signed in"}"#)
        let store = InMemoryCredentialStore()
        let auth = AuthManager<Account>(client: makeClient(transport), credentialStore: store)

        await #expect(throws: AuthError.invalidAuthResponse) {
            try await auth.login(email: "ada@example.com", password: "secret")
        }
        #expect(try await store.retrieve() == nil)
    }

    @Test("Logging out tells the server and clears the session")
    func logout() async throws {
        let transport = MockTransport(json: "{}")
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "abc"))
        let client = makeClient(transport)
        let session = makeSession(client, store: store)
        session.adopt(user: Account(id: 1, displayName: "Ada"))
        let auth = AuthManager<Account>(client: client, credentialStore: store, session: session)

        await auth.logout()

        #expect(await transport.lastRequest?.url?.path == "/api/logout")
        #expect(try await store.retrieve() == nil)
        #expect(session.state == .unauthenticated)
    }

    @Test("Logging out succeeds even when the server cannot be reached")
    func logoutWhileOffline() async throws {
        let transport = MockTransport.alwaysFailing(
            with: LaravelError.networkError(underlying: URLError(.notConnectedToInternet))
        )
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "abc"))
        let client = makeClient(transport)
        let session = makeSession(client, store: store)
        let auth = AuthManager<Account>(client: client, credentialStore: store, session: session)

        await auth.logout()

        #expect(try await store.retrieve() == nil)
        #expect(session.state == .unauthenticated)
    }

    @Test("Logging out stops a refresh that is in flight")
    func logoutInvalidatesRefresh() async throws {
        let transport = MockTransport(json: "{}")
        let store = InMemoryCredentialStore(
            credential: AuthCredential(accessToken: "abc", refreshToken: "r")
        )
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            try await Task.sleep(nanoseconds: 500_000_000)
            return credential
        }
        let auth = AuthManager<Account>(
            client: makeClient(transport),
            credentialStore: store,
            refreshCoordinator: coordinator
        )

        let refresh = Task { try await coordinator.refreshIfNeeded() }
        while await !coordinator.isRefreshing {
            await Task.yield()
        }
        await auth.logout()

        await #expect(throws: (any Error).self) {
            _ = try await refresh.value
        }
        #expect(try await store.retrieve() == nil)
    }

    @Test("The current user comes from the configured endpoint")
    func currentUser() async throws {
        let transport = MockTransport(json: #"{"id":9,"display_name":"Grace"}"#)
        let auth = AuthManager<Account>(
            client: makeClient(transport),
            credentialStore: InMemoryCredentialStore()
        )

        let user = try await auth.currentUser()

        #expect(user == Account(id: 9, displayName: "Grace"))
        #expect(await transport.lastRequest?.url?.path == "/api/user")
    }

    @Test("Password reset posts the email")
    func passwordReset() async throws {
        let transport = MockTransport(json: "{}")
        let auth = AuthManager<Account>(
            client: makeClient(transport),
            credentialStore: InMemoryCredentialStore()
        )

        try await auth.requestPasswordReset(email: "ada@example.com")

        let request = try #require(await transport.lastRequest)
        #expect(request.url?.path == "/api/forgot-password")
        #expect(
            try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
                == ["email": "ada@example.com"]
        )
    }

    @Test("A flow whose endpoint is not configured says so")
    func missingEndpoint() async throws {
        let configuration = AuthConfiguration(
            passwordResetEndpoint: nil,
            emailVerificationEndpoint: nil
        )
        let auth = AuthManager<Account>(
            client: makeClient(MockTransport(json: "{}")),
            configuration: configuration,
            credentialStore: InMemoryCredentialStore()
        )

        await #expect(throws: AuthError.endpointNotConfigured("password reset")) {
            try await auth.requestPasswordReset(email: "ada@example.com")
        }
        await #expect(throws: AuthError.endpointNotConfigured("email verification")) {
            try await auth.resendEmailVerification()
        }
    }
}
