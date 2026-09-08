import Foundation
import Testing

import LaravelMobileKitAuth
import LaravelMobileKitCore

struct AppUser: Codable, Hashable, Sendable {
    let id: Int
    let name: String
}

/// A provider that can renew the credential it is given.
private actor RefreshingTokenProvider: TokenProvider {
    private let store: any CredentialStore
    private let refreshed: Result<AuthCredential, any Error>
    private(set) var refreshCalls = 0
    private(set) var clearCalls = 0

    init(store: any CredentialStore, refreshed: Result<AuthCredential, any Error>) {
        self.store = store
        self.refreshed = refreshed
    }

    func currentToken() async throws -> String? {
        try await store.retrieve()?.accessToken
    }

    func refreshToken() async throws -> String {
        refreshCalls += 1
        let credential = try refreshed.get()
        try await store.store(credential)
        return credential.accessToken
    }

    func clearToken() async throws {
        clearCalls += 1
        try await store.delete()
    }
}

@MainActor
@Suite("Auth session")
struct AuthSessionTests {
    let baseURL = URL(string: "https://api.example.com")!
    let userJSON = #"{"id":1,"name":"Ada"}"#
    let expectedUser = AppUser(id: 1, name: "Ada")

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    private func validCredential() -> AuthCredential {
        AuthCredential(accessToken: "abc", expiresAt: Date().addingTimeInterval(3600))
    }

    private func expiredCredential() -> AuthCredential {
        AuthCredential(
            accessToken: "old",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    // MARK: - Restore

    @Test("Without a stored credential the session is unauthenticated")
    func restoreWithoutCredential() async {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore()
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        await session.restore()

        #expect(session.state == .unauthenticated)
        #expect(await transport.executedRequests.isEmpty)
    }

    @Test("A valid credential is verified against the user endpoint")
    func restoreWithValidCredential() async throws {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore(credential: validCredential())
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        await session.restore()

        #expect(session.state == .authenticated(expectedUser))
        #expect(session.user == expectedUser)
        #expect(try await store.retrieve() != nil)
        #expect(await transport.lastRequest?.url?.path == "/api/user")
    }

    @Test("A rejected credential ends the session and is discarded")
    func restoreWithRejectedCredential() async throws {
        let transport = MockTransport(statusCode: 401, json: #"{"message":"Unauthenticated."}"#)
        let store = InMemoryCredentialStore(credential: validCredential())
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        await session.restore()

        #expect(session.state == .unauthenticated)
        #expect(try await store.retrieve() == nil)
    }

    @Test("A network failure leaves the credential in place")
    func restoreWhileOffline() async throws {
        let transport = MockTransport.alwaysFailing(
            with: LaravelError.networkError(underlying: URLError(.notConnectedToInternet))
        )
        let store = InMemoryCredentialStore(credential: validCredential())
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        await session.restore()

        #expect(session.state == .unverified)
        #expect(session.lastError != nil)
        #expect(try await store.retrieve() != nil)
    }

    @Test("A timeout also leaves the credential in place")
    func restoreOnTimeout() async throws {
        let transport = MockTransport.alwaysFailing(with: LaravelError.timeout)
        let store = InMemoryCredentialStore(credential: validCredential())
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        await session.restore()

        #expect(session.state == .unverified)
        #expect(try await store.retrieve() != nil)
    }

    @Test("An expired credential with no way to refresh ends the session")
    func restoreWithExpiredCredentialAndNoProvider() async throws {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        await session.restore()

        #expect(session.state == .unauthenticated)
        #expect(try await store.retrieve() == nil)
        #expect(await transport.executedRequests.isEmpty)
    }

    @Test("An expired credential is refreshed before the user is loaded")
    func restoreRefreshesExpiredCredential() async throws {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let provider = RefreshingTokenProvider(
            store: store,
            refreshed: .success(AuthCredential(
                accessToken: "fresh",
                expiresAt: Date().addingTimeInterval(3600)
            ))
        )
        let session = AuthSession<AppUser>(
            client: makeClient(transport),
            credentialStore: store,
            tokenProvider: provider
        )

        await session.restore()

        #expect(await provider.refreshCalls == 1)
        #expect(session.state == .authenticated(expectedUser))
        #expect(try await store.retrieve()?.accessToken == "fresh")
    }

    @Test("A failed refresh ends the session")
    func restoreWithFailedRefresh() async throws {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let provider = RefreshingTokenProvider(
            store: store,
            refreshed: .failure(LaravelError.httpError(
                HTTPError(
                    statusCode: 401,
                    data: nil,
                    response: HTTPURLResponse(
                        url: URL(string: "https://api.example.com/api/refresh")!,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            ))
        )
        let session = AuthSession<AppUser>(
            client: makeClient(transport),
            credentialStore: store,
            tokenProvider: provider
        )

        await session.restore()

        #expect(session.state == .unauthenticated)
        #expect(try await store.retrieve() == nil)
    }

    // MARK: - Sign in, reload, logout

    @Test("Signing in stores the credential and returns the user")
    func signInStoresCredential() async throws {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore()
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        let user = try await session.signIn(with: validCredential())

        #expect(user == expectedUser)
        #expect(session.state == .authenticated(expectedUser))
        #expect(try await store.retrieve()?.accessToken == "abc")
    }

    @Test("Signing in with a credential the server rejects throws and signs out")
    func signInWithRejectedCredential() async throws {
        let transport = MockTransport(statusCode: 401, json: "{}")
        let store = InMemoryCredentialStore()
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        await #expect(throws: LaravelError.self) {
            try await session.signIn(with: validCredential())
        }
        #expect(session.state == .unauthenticated)
        #expect(try await store.retrieve() == nil)
    }

    @Test("Reloading the user refreshes the published state")
    func reloadUser() async throws {
        let transport = MockTransport(json: #"{"id":2,"name":"Grace"}"#)
        let store = InMemoryCredentialStore(credential: validCredential())
        let session = AuthSession<AppUser>(client: makeClient(transport), credentialStore: store)

        let user = try await session.reloadUser()

        #expect(user == AppUser(id: 2, name: "Grace"))
        #expect(session.user == user)
    }

    @Test("Logging out clears the credential without asking the server")
    func logoutClearsCredential() async throws {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore(credential: validCredential())
        let provider = RefreshingTokenProvider(store: store, refreshed: .failure(AuthError.refreshNotSupported))
        let session = AuthSession<AppUser>(
            client: makeClient(transport),
            credentialStore: store,
            tokenProvider: provider
        )
        await session.restore()

        await session.logout()

        #expect(session.state == .unauthenticated)
        #expect(session.lastError == nil)
        #expect(try await store.retrieve() == nil)
        #expect(await provider.clearCalls == 1)
    }

    @Test("A custom loader handles a wrapped payload")
    func customUserLoader() async throws {
        let transport = MockTransport(json: #"{"data":{"id":3,"name":"Alan"}}"#)
        let store = InMemoryCredentialStore(credential: validCredential())
        let session = AuthSession<AppUser>(
            client: makeClient(transport),
            credentialStore: store
        ) { client in
            struct Envelope: Decodable { let data: AppUser }
            let envelope: Envelope = try await client.get("/api/me")
            return envelope.data
        }

        await session.restore()

        #expect(session.state == .authenticated(AppUser(id: 3, name: "Alan")))
        #expect(await transport.lastRequest?.url?.path == "/api/me")
    }

    @Test("The session sends the stored token when the client authenticates")
    func restoreSendsAuthorizationHeader() async throws {
        let transport = MockTransport(json: userJSON)
        let store = InMemoryCredentialStore(credential: validCredential())
        let client = makeClient(transport)
        await client.use(.auth(CredentialTokenProvider(store: store)))
        let session = AuthSession<AppUser>(client: client, credentialStore: store)

        await session.restore()

        #expect(await transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }
}

@Suite("Auth state")
struct AuthStateTests {
    @Test("The state exposes the user only when authenticated")
    func userAccessor() {
        let user = AppUser(id: 1, name: "Ada")

        #expect(AuthState<AppUser>.authenticated(user).user == user)
        #expect(AuthState<AppUser>.unauthenticated.user == nil)
        #expect(AuthState<AppUser>.unverified.user == nil)
    }

    @Test("Only an authenticated state counts as signed in")
    func isAuthenticated() {
        #expect(AuthState.authenticated(AppUser(id: 1, name: "Ada")).isAuthenticated)
        #expect(!AuthState<AppUser>.unknown.isAuthenticated)
        #expect(!AuthState<AppUser>.restoring.isAuthenticated)
        #expect(!AuthState<AppUser>.unverified.isAuthenticated)
    }

    @Test("Pending states are not settled")
    func isSettled() {
        #expect(!AuthState<AppUser>.unknown.isSettled)
        #expect(!AuthState<AppUser>.restoring.isSettled)
        #expect(AuthState<AppUser>.unauthenticated.isSettled)
        #expect(AuthState<AppUser>.unverified.isSettled)
        #expect(AuthState.authenticated(AppUser(id: 1, name: "Ada")).isSettled)
    }
}
