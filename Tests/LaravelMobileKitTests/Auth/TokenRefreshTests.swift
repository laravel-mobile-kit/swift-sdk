import Foundation
import Testing

import LaravelMobileKitAuth
import LaravelMobileKitCore

/// A transport that accepts exactly one token and answers 401 for anything else.
private actor TokenAwareTransport: HTTPTransport {
    private let validToken: String
    private let url = URL(string: "https://api.example.com/api/events/1")!
    private(set) var executedRequests: [URLRequest] = []

    init(validToken: String) {
        self.validToken = validToken
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        executedRequests.append(request)

        let isAuthorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(validToken)"
        let body = isAuthorized
            ? #"{"id":1,"title":"Launch"}"#
            : #"{"message":"Unauthenticated."}"#
        let response = HTTPURLResponse(
            url: url,
            statusCode: isAuthorized ? 200 : 401,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }

    var attemptCount: Int { executedRequests.count }

    var sentTokens: [String?] {
        executedRequests.map { $0.value(forHTTPHeaderField: "Authorization") }
    }
}

/// Records how the refresh call was used.
private actor RefreshRecorder {
    private(set) var callCount = 0
    private(set) var failures: [any Error] = []

    func recordCall() {
        callCount += 1
    }

    func record(failure: any Error) {
        failures.append(failure)
    }
}

@Suite("Token refresh coordination")
struct TokenRefreshTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func expiredCredential() -> AuthCredential {
        AuthCredential(accessToken: "old", refreshToken: "refresh")
    }

    private func makeClient(
        transport: any HTTPTransport,
        store: any CredentialStore,
        decider: AuthRefreshRetryDecider
    ) async -> LaravelClient {
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
        await client.use(.auth(CredentialTokenProvider(store: store)))
        await client.use(retryDecider: decider)
        return client
    }

    // MARK: - Happy path

    @Test("A 401 refreshes the token once and the retry carries the new one")
    func refreshAndRetry() async throws {
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let transport = TokenAwareTransport(validToken: "fresh")
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            await recorder.recordCall()
            return AuthCredential(accessToken: "fresh", refreshToken: credential.refreshToken)
        }
        let client = await makeClient(
            transport: transport,
            store: store,
            decider: AuthRefreshRetryDecider(coordinator: coordinator)
        )

        let event: Event = try await client.get("/api/events/1")

        #expect(event == Event(id: 1, title: "Launch"))
        #expect(await recorder.callCount == 1)
        #expect(await transport.sentTokens == ["Bearer old", "Bearer fresh"])
        #expect(try await store.retrieve()?.accessToken == "fresh")
    }

    @Test("Concurrent 401s produce a single refresh")
    func concurrent401sRefreshOnce() async throws {
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let transport = TokenAwareTransport(validToken: "fresh")
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            await recorder.recordCall()
            // Hold the refresh open so every request fails before it lands.
            try await Task.sleep(nanoseconds: 50_000_000)
            return AuthCredential(accessToken: "fresh", refreshToken: credential.refreshToken)
        }
        let client = await makeClient(
            transport: transport,
            store: store,
            decider: AuthRefreshRetryDecider(coordinator: coordinator)
        )

        let events: [Event] = try await withThrowingTaskGroup(of: Event.self) { group in
            for _ in 0 ..< 5 {
                group.addTask { try await client.get("/api/events/1") }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(events.count == 5)
        #expect(await recorder.callCount == 1)
        #expect(await transport.attemptCount == 10)
    }

    @Test("A request that succeeds never refreshes")
    func successNeverRefreshes() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "fresh"))
        let transport = TokenAwareTransport(validToken: "fresh")
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { _ in
            await recorder.recordCall()
            return AuthCredential(accessToken: "other")
        }
        let client = await makeClient(
            transport: transport,
            store: store,
            decider: AuthRefreshRetryDecider(coordinator: coordinator)
        )

        let _: Event = try await client.get("/api/events/1")

        #expect(await recorder.callCount == 0)
        #expect(await transport.attemptCount == 1)
    }

    // MARK: - Failure paths

    @Test("A failed refresh ends the session and reports the cause")
    func failedRefreshEndsSession() async throws {
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let transport = TokenAwareTransport(validToken: "fresh")
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { _ in
            throw LaravelError.networkError(underlying: URLError(.notConnectedToInternet))
        }
        let decider = AuthRefreshRetryDecider(coordinator: coordinator) { error in
            await recorder.record(failure: error)
        }
        let client = await makeClient(transport: transport, store: store, decider: decider)

        await #expect(throws: AuthError.sessionExpired) {
            let _: Event = try await client.get("/api/events/1")
        }
        let failures = await recorder.failures
        #expect(failures.count == 1)
        #expect((failures.first as? LaravelError)?.errorDescription?.hasPrefix("Network error:") == true)
    }

    @Test("A credential without a refresh token cannot be renewed")
    func missingRefreshToken() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "old"))
        let transport = TokenAwareTransport(validToken: "fresh")
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            await recorder.recordCall()
            return credential
        }
        let decider = AuthRefreshRetryDecider(coordinator: coordinator) { error in
            await recorder.record(failure: error)
        }
        let client = await makeClient(transport: transport, store: store, decider: decider)

        await #expect(throws: AuthError.sessionExpired) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await recorder.callCount == 0)
        #expect(await recorder.failures.first as? AuthError == .noRefreshToken)
    }

    @Test("A second 401 after refreshing means the session is over")
    func secondUnauthorizedEndsSession() async throws {
        let store = InMemoryCredentialStore(credential: expiredCredential())
        // The server never accepts the refreshed token either.
        let transport = TokenAwareTransport(validToken: "never-issued")
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            await recorder.recordCall()
            return AuthCredential(accessToken: "fresh", refreshToken: credential.refreshToken)
        }
        let decider = AuthRefreshRetryDecider(coordinator: coordinator) { error in
            await recorder.record(failure: error)
        }
        let client = await makeClient(transport: transport, store: store, decider: decider)

        await #expect(throws: AuthError.sessionExpired) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await recorder.callCount == 1)
        #expect(await transport.attemptCount == 2)
        #expect(await recorder.failures.first as? AuthError == .sessionExpired)
    }

    @Test("Failures other than 401 are left alone")
    func otherFailuresAreIgnored() async throws {
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let mock = MockTransport(statusCodes: [500])
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            await recorder.recordCall()
            return credential
        }
        let client = await makeClient(
            transport: mock,
            store: store,
            decider: AuthRefreshRetryDecider(coordinator: coordinator)
        )

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await recorder.callCount == 0)
        #expect(await mock.attemptCount == 1)
    }

    // MARK: - Coordinator directly

    @Test("Waiters join the refresh already in flight")
    func waitersJoinTheSameRefresh() async throws {
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let recorder = RefreshRecorder()
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            await recorder.recordCall()
            try await Task.sleep(nanoseconds: 30_000_000)
            return AuthCredential(accessToken: "fresh", refreshToken: credential.refreshToken)
        }

        let credentials = try await withThrowingTaskGroup(of: AuthCredential.self) { group in
            for _ in 0 ..< 4 {
                group.addTask { try await coordinator.refreshIfNeeded() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(await recorder.callCount == 1)
        #expect(credentials.allSatisfy { $0.accessToken == "fresh" })
    }

    @Test("An empty store cannot be refreshed")
    func refreshWithoutCredential() async throws {
        let coordinator = TokenRefreshCoordinator(credentialStore: InMemoryCredentialStore()) { _ in
            AuthCredential(accessToken: "fresh")
        }

        await #expect(throws: AuthError.notAuthenticated) {
            _ = try await coordinator.refreshIfNeeded()
        }
    }

    @Test("Logging out during a refresh cancels it")
    func invalidateCancelsRefresh() async throws {
        let store = InMemoryCredentialStore(credential: expiredCredential())
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            try await Task.sleep(nanoseconds: 500_000_000)
            return AuthCredential(accessToken: "fresh", refreshToken: credential.refreshToken)
        }

        let refresh = Task { try await coordinator.refreshIfNeeded() }
        while await !coordinator.isRefreshing {
            await Task.yield()
        }
        await coordinator.invalidate()

        await #expect(throws: (any Error).self) {
            _ = try await refresh.value
        }
        #expect(await coordinator.isRefreshing == false)
    }
}

@MainActor
@Suite("Refresh failure and session state")
struct RefreshFailureSessionTests {
    let baseURL = URL(string: "https://api.example.com")!

    @Test("A refresh that cannot be completed signs the user out")
    func failedRefreshSignsOut() async throws {
        let store = InMemoryCredentialStore(
            credential: AuthCredential(accessToken: "old", refreshToken: "refresh")
        )
        let transport = MockTransport(statusCodes: [401], json: #"{"message":"Unauthenticated."}"#)
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
        let session = AuthSession<AppUser>(client: client, credentialStore: store)
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { _ in
            throw AuthError.sessionExpired
        }
        await client.use(.auth(CredentialTokenProvider(store: store)))
        await client.use(retryDecider: AuthRefreshRetryDecider(
            coordinator: coordinator,
            onAuthFailure: session.authFailureHandler()
        ))

        await #expect(throws: AuthError.sessionExpired) {
            let _: Event = try await client.get("/api/events/1")
        }

        #expect(session.state == .unauthenticated)
        #expect(session.lastError as? AuthError == .sessionExpired)
        #expect(try await store.retrieve() == nil)
    }

    @Test("Ending a session keeps the reason, logging out does not")
    func endSessionKeepsReason() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "abc"))
        let client = LaravelClient(
            configuration: .withoutRetries(baseURL),
            transport: MockTransport(json: "{}")
        )
        let session = AuthSession<AppUser>(client: client, credentialStore: store)

        await session.endSession(reason: AuthError.sessionExpired)
        #expect(session.state == .unauthenticated)
        #expect(session.lastError as? AuthError == .sessionExpired)

        await session.logout()
        #expect(session.lastError == nil)
    }
}
