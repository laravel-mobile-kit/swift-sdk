import Foundation
import Testing

import LaravelMobileKitCore

/// A decider whose answer each test dictates.
private actor StubDecider: RetryDecider {
    private let answer: Bool
    private let failure: (any Error)?
    private(set) var seenErrors: [LaravelError] = []
    private(set) var seenAttempts: [Int] = []

    init(answer: Bool, failure: (any Error)? = nil) {
        self.answer = answer
        self.failure = failure
    }

    func shouldRetry(_ error: LaravelError, request: Request, attempt: Int) async throws -> Bool {
        seenErrors.append(error)
        seenAttempts.append(attempt)
        if let failure { throw failure }
        return answer
    }

    var callCount: Int { seenAttempts.count }
}

/// Retries once, then gives up.
private actor OnceDecider: RetryDecider {
    private(set) var callCount = 0

    func shouldRetry(_ error: LaravelError, request: Request, attempt: Int) async throws -> Bool {
        callCount += 1
        return attempt == 0
    }
}

private struct DeciderFailure: Error, Equatable {}

@Suite("Retry deciders")
struct RetryDeciderTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("A decider that says yes gets the request sent again")
    func deciderDrivesOneRetry() async throws {
        let transport = MockTransport(statusCodes: [401, 200], json: #"{"id":1,"title":"Launch"}"#)
        let client = makeClient(transport)
        let decider = OnceDecider()
        await client.use(retryDecider: decider)

        let event: Event = try await client.get("/api/events/1")

        #expect(event == Event(id: 1, title: "Launch"))
        #expect(await transport.attemptCount == 2)
        #expect(await decider.callCount == 1)
    }

    @Test("A decider that says no lets the error through")
    func deciderDeclines() async throws {
        let transport = MockTransport(statusCodes: [401])
        let client = makeClient(transport)
        let decider = StubDecider(answer: false)
        await client.use(retryDecider: decider)

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await transport.attemptCount == 1)
        #expect(await decider.callCount == 1)
    }

    @Test("Deciders are not consulted when the request succeeds")
    func deciderIsNotConsultedOnSuccess() async throws {
        let transport = MockTransport(json: #"{"id":1,"title":"Launch"}"#)
        let client = makeClient(transport)
        let decider = StubDecider(answer: true)
        await client.use(retryDecider: decider)

        let _: Event = try await client.get("/api/events/1")

        #expect(await decider.callCount == 0)
    }

    @Test("A decider sees the failure and its own retry count")
    func deciderSeesContext() async throws {
        let transport = MockTransport(statusCodes: [503])
        let client = makeClient(transport)
        let decider = StubDecider(answer: false)
        await client.use(retryDecider: decider)

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await decider.seenAttempts == [0])
        #expect(await decider.seenErrors.first?.statusCode == 503)
    }

    @Test("A decider that throws replaces the server error")
    func deciderCanThrow() async throws {
        let transport = MockTransport(statusCodes: [401])
        let client = makeClient(transport)
        await client.use(retryDecider: StubDecider(answer: true, failure: DeciderFailure()))

        await #expect(throws: DeciderFailure.self) {
            let _: Event = try await client.get("/api/events/1")
        }
    }

    @Test("A decider cannot retry a request forever")
    func recoveryRetriesAreCapped() async throws {
        let transport = MockTransport(statusCodes: [401])
        let client = makeClient(transport)
        let decider = StubDecider(answer: true)
        await client.use(retryDecider: decider)

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        // The first attempt plus the capped recovery retries.
        #expect(await transport.attemptCount == 4)
        #expect(await decider.seenAttempts == [0, 1, 2])
    }

    @Test("The policy retries a transient failure before deciders are asked")
    func policyRetriesComeFirst() async throws {
        let transport = MockTransport(statusCodes: [503, 200], json: #"{"id":1,"title":"Launch"}"#)
        let policy = RetryPolicy(maxRetries: 1, backoffStrategy: .none)
        let client = LaravelClient(
            configuration: LaravelClientConfiguration(baseURL: baseURL, retryPolicy: policy),
            transport: transport
        )
        let decider = StubDecider(answer: false)
        await client.use(retryDecider: decider)

        let _: Event = try await client.get("/api/events/1")

        #expect(await transport.attemptCount == 2)
        #expect(await decider.callCount == 0)
    }

    @Test("Middleware runs again on a retried request")
    func middlewareRunsPerAttempt() async throws {
        let transport = MockTransport(statusCodes: [401, 200], json: #"{"id":1,"title":"Launch"}"#)
        let client = makeClient(transport)
        let counter = HeaderStampMiddleware()
        await client.use(counter)
        await client.use(retryDecider: OnceDecider())

        let _: Event = try await client.get("/api/events/1")

        let requests = await transport.executedRequests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "X-Attempt") == "1")
        #expect(requests[1].value(forHTTPHeaderField: "X-Attempt") == "2")
    }
}

/// Stamps each outgoing request with the number of times it has been built.
private struct HeaderStampMiddleware: Middleware {
    private let counter = Counter()

    func process(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("\(await counter.next())", forHTTPHeaderField: "X-Attempt")
        return request
    }

    private actor Counter {
        private var value = 0

        func next() -> Int {
            value += 1
            return value
        }
    }
}
