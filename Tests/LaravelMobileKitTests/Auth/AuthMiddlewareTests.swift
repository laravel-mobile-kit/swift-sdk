import Foundation
import Testing

import LaravelMobileKitAuth
import LaravelMobileKitCore

/// A provider whose behaviour each test dictates.
private actor StubTokenProvider: TokenProvider {
    private var token: String?
    private(set) var currentTokenCalls = 0
    private(set) var clearCalls = 0

    init(token: String?) {
        self.token = token
    }

    func currentToken() async throws -> String? {
        currentTokenCalls += 1
        return token
    }

    func clearToken() async throws {
        clearCalls += 1
        token = nil
    }
}

@Suite("Token providers")
struct TokenProviderTests {
    @Test("A static provider returns its token and cannot refresh")
    func staticProvider() async throws {
        let provider = StaticTokenProvider("abc")

        #expect(try await provider.currentToken() == "abc")
        await #expect(throws: AuthError.refreshNotSupported) {
            _ = try await provider.refreshToken()
        }
    }

    @Test("A static provider with no token reports none")
    func staticProviderWithoutToken() async throws {
        #expect(try await StaticTokenProvider(nil).currentToken() == nil)
    }

    @Test("A credential-backed provider returns the stored access token")
    func credentialProviderReadsStore() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "abc"))
        let provider = CredentialTokenProvider(store: store)

        #expect(try await provider.currentToken() == "abc")
    }

    @Test("An empty store yields no token")
    func credentialProviderWithoutCredential() async throws {
        let provider = CredentialTokenProvider(store: InMemoryCredentialStore())

        #expect(try await provider.currentToken() == nil)
    }

    @Test("An expired credential yields no token but is still readable")
    func expiredCredentialYieldsNoToken() async throws {
        let expired = AuthCredential(
            accessToken: "abc",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )
        let provider = CredentialTokenProvider(store: InMemoryCredentialStore(credential: expired))

        #expect(try await provider.currentToken() == nil)
        #expect(try await provider.currentCredential() == expired)
    }

    @Test("Leeway treats a token that expires shortly as already expired")
    func expiryLeeway() async throws {
        let credential = AuthCredential(
            accessToken: "abc",
            expiresAt: Date().addingTimeInterval(20)
        )
        let store = InMemoryCredentialStore(credential: credential)

        #expect(try await CredentialTokenProvider(store: store).currentToken() == "abc")
        #expect(
            try await CredentialTokenProvider(store: store, expiryLeeway: 60).currentToken() == nil
        )
    }

    /// The provider holds no copy of the credential: every call reads the store.
    ///
    /// That is what makes a shared Keychain item work across processes. An app,
    /// a share extension and a capture extension each build their own provider
    /// over one access-group item, and whichever of them refreshes the token
    /// last is the one the others must use. Caching here — an obvious-looking
    /// optimisation, since the read is not free — would strand the other
    /// processes on a token the server has already stopped accepting, and they
    /// would not find out until a 401.
    ///
    /// The write below stands in for that other process.
    @Test("A credential rotated underneath the provider is picked up immediately")
    func rotationOutsideTheProviderIsPickedUp() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "first"))
        let provider = CredentialTokenProvider(store: store)

        #expect(try await provider.currentToken() == "first")

        try await store.store(AuthCredential(accessToken: "second"))

        // Not "after the next 401" — on the very next request.
        #expect(try await provider.currentToken() == "second")
        #expect(try await provider.currentCredential()?.accessToken == "second")
    }

    /// The same property, one layer up: the header the middleware writes has to
    /// follow the store too, not just the provider's own accessor.
    @Test("The middleware sends the rotated token, not the one it first saw")
    func middlewareFollowsRotation() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "first"))
        let transport = MockTransport(statusCode: 200, json: "{}")
        let client = LaravelClient(
            baseURL: URL(string: "https://api.example.com")!,
            transport: transport
        )
        await client.use(AuthMiddleware(tokenProvider: CredentialTokenProvider(store: store)))

        let _: EmptyResponse = try await client.get("/api/user")
        try await store.store(AuthCredential(accessToken: "second"))
        let _: EmptyResponse = try await client.get("/api/user")

        let sent = await transport.executedRequests.map {
            $0.value(forHTTPHeaderField: "Authorization")
        }
        #expect(sent == ["Bearer first", "Bearer second"])
    }

    @Test("Clearing removes the credential from the store")
    func clearingDeletesCredential() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "abc"))
        let provider = CredentialTokenProvider(store: store)

        try await provider.clearToken()

        #expect(try await store.retrieve() == nil)
        #expect(try await provider.currentToken() == nil)
    }

    @Test("Storing through the provider updates the store")
    func storingUpdatesStore() async throws {
        let store = InMemoryCredentialStore()
        let provider = CredentialTokenProvider(store: store)

        try await provider.store(AuthCredential(accessToken: "new"))

        #expect(try await store.retrieve()?.accessToken == "new")
    }
}

@Suite("Auth middleware")
struct AuthMiddlewareTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func sentRequest(
        provider: any TokenProvider,
        transport: AuthTransport = .bearer,
        options: RequestOptions = .none
    ) async throws -> URLRequest {
        let mock = MockTransport(json: "[]")
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: mock)
        await client.use(.auth(provider, transport: transport))

        let _: [Event] = try await client.get("/api/events", options: options)

        return try #require(await mock.lastRequest)
    }

    @Test("A bearer token becomes an Authorization header")
    func bearerHeaderIsAdded() async throws {
        let request = try await sentRequest(provider: StaticTokenProvider("abc"))

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test("A custom scheme replaces Bearer")
    func customScheme() async throws {
        let request = try await sentRequest(
            provider: StaticTokenProvider("abc"),
            transport: .scheme("Token")
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token abc")
    }

    @Test("Cookie transport sends the token as a cookie")
    func cookieHeaderIsAdded() async throws {
        let request = try await sentRequest(
            provider: StaticTokenProvider("session=abc"),
            transport: .cookie
        )

        #expect(request.value(forHTTPHeaderField: "Cookie") == "session=abc")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A custom transport decides how the token is attached")
    func customTransport() async throws {
        let transport = AuthTransport.custom { request, token in
            var request = request
            request.setValue(token, forHTTPHeaderField: "X-Api-Key")
            return request
        }

        let request = try await sentRequest(provider: StaticTokenProvider("abc"), transport: transport)

        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "abc")
    }

    @Test("No token means no header, and the request still goes out")
    func missingTokenSendsNoHeader() async throws {
        let request = try await sentRequest(provider: StaticTokenProvider(nil))

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("An expired credential sends no Authorization header")
    func expiredCredentialSendsNoHeader() async throws {
        let expired = AuthCredential(
            accessToken: "abc",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )
        let provider = CredentialTokenProvider(store: InMemoryCredentialStore(credential: expired))

        let request = try await sentRequest(provider: provider)

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A caller-supplied Authorization header wins over the provider")
    func perRequestHeaderWins() async throws {
        let request = try await sentRequest(
            provider: StaticTokenProvider("abc"),
            options: .headers(["Authorization": "Bearer override"])
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer override")
    }

    @Test("The provider is consulted once per request")
    func providerIsConsultedPerRequest() async throws {
        let provider = StubTokenProvider(token: "abc")
        let mock = MockTransport(json: "[]")
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: mock)
        await client.use(.auth(provider))

        let _: [Event] = try await client.get("/api/events")
        let _: [Event] = try await client.get("/api/events")

        #expect(await provider.currentTokenCalls == 2)
    }

    @Test("A token cleared between requests stops being sent")
    func clearedTokenIsNotSent() async throws {
        let provider = StubTokenProvider(token: "abc")
        let mock = MockTransport(json: "[]")
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: mock)
        await client.use(.auth(provider))

        let _: [Event] = try await client.get("/api/events")
        try await provider.clearToken()
        let _: [Event] = try await client.get("/api/events")

        let requests = await mock.executedRequests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
    }
}
