import Foundation
import Testing

import LaravelMobileKitCore

@Suite("Retry policy")
struct RetryTests {
    let baseURL = URL(string: "https://api.example.com")!

    /// A policy that retries without waiting, so tests stay fast.
    private func immediatePolicy(
        maxRetries: Int = 3,
        methods: Set<HTTPMethod> = RetryPolicy.idempotentMethods,
        retriesNetworkFailures: Bool = true
    ) -> RetryPolicy {
        RetryPolicy(
            maxRetries: maxRetries,
            retryableMethods: methods,
            backoffStrategy: .none,
            retriesNetworkFailures: retriesNetworkFailures
        )
    }

    private func makeClient(
        transport: any HTTPTransport,
        policy: RetryPolicy
    ) -> LaravelClient {
        LaravelClient(
            configuration: LaravelClientConfiguration(baseURL: baseURL, retryPolicy: policy),
            transport: transport
        )
    }

    // MARK: - Backoff

    @Test("Exponential backoff doubles each attempt and clamps at the maximum")
    func exponentialBackoff() {
        let strategy = BackoffStrategy.exponential(base: 0.5, maxDelay: 30)

        #expect(strategy.delay(for: 0) == 0.5)
        #expect(strategy.delay(for: 1) == 1)
        #expect(strategy.delay(for: 2) == 2)
        #expect(strategy.delay(for: 3) == 4)
        #expect(strategy.delay(for: 20) == 30)
    }

    @Test("Constant and none backoff are unaffected by the attempt")
    func otherBackoffStrategies() {
        #expect(BackoffStrategy.constant(delay: 0.25).delay(for: 0) == 0.25)
        #expect(BackoffStrategy.constant(delay: 0.25).delay(for: 9) == 0.25)
        #expect(BackoffStrategy.none.delay(for: 0) == 0)
        #expect(BackoffStrategy.none.delay(for: 9) == 0)
    }

    // MARK: - Retry decisions

    @Test("A transient status is retried until the server answers")
    func retriesUntilSuccess() async throws {
        let transport = MockTransport(
            statusCodes: [503, 503, 200],
            json: #"{"id":1,"title":"Launch"}"#
        )
        let client = makeClient(transport: transport, policy: immediatePolicy())

        let event: Event = try await client.get("/api/events/1")

        #expect(event == Event(id: 1, title: "Launch"))
        #expect(await transport.attemptCount == 3)
    }

    @Test("Retries stop at the configured limit")
    func stopsAtMaxRetries() async throws {
        let transport = MockTransport(statusCodes: [503])
        let client = makeClient(transport: transport, policy: immediatePolicy(maxRetries: 2))

        do {
            let _: Event = try await client.get("/api/events/1")
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            #expect(error.statusCode == 503)
        }
        #expect(await transport.attemptCount == 3)
    }

    @Test("A non-retryable status fails on the first attempt", arguments: [400, 401, 404, 422])
    func nonRetryableStatus(statusCode: Int) async throws {
        let transport = MockTransport(statusCodes: [statusCode])
        let client = makeClient(transport: transport, policy: immediatePolicy())

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await transport.attemptCount == 1)
    }

    @Test("POST is not retried by default because it is not idempotent")
    func postIsNotRetriedByDefault() async throws {
        let transport = MockTransport(statusCodes: [503, 200], json: #"{"id":1,"title":"L"}"#)
        let client = makeClient(transport: transport, policy: immediatePolicy())

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.post("/api/events", body: CreateEvent(title: "L"))
        }
        #expect(await transport.attemptCount == 1)
    }

    @Test("A policy that opts POST in retries it")
    func customPolicyRetriesPost() async throws {
        let transport = MockTransport(statusCodes: [503, 200], json: #"{"id":1,"title":"L"}"#)
        let client = makeClient(
            transport: transport,
            policy: immediatePolicy(methods: [.post])
        )

        let event: Event = try await client.post("/api/events", body: CreateEvent(title: "L"))

        #expect(event == Event(id: 1, title: "L"))
        #expect(await transport.attemptCount == 2)
    }

    @Test("Network failures are retried when the policy allows it")
    func networkFailuresAreRetried() async throws {
        let transport = MockTransport.alwaysFailing(with: LaravelError.timeout)
        let client = makeClient(transport: transport, policy: immediatePolicy(maxRetries: 2))

        do {
            let _: Event = try await client.get("/api/events/1")
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            #expect(error.isTimeout)
        }
        #expect(await transport.attemptCount == 3)
    }

    @Test("Network failures are attempted once when the policy opts out")
    func networkFailuresCanBeExcluded() async throws {
        let transport = MockTransport.alwaysFailing(
            with: LaravelError.networkError(underlying: URLError(.networkConnectionLost))
        )
        let client = makeClient(
            transport: transport,
            policy: immediatePolicy(retriesNetworkFailures: false)
        )

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await transport.attemptCount == 1)
    }

    @Test("A malformed payload is not retried")
    func decodingFailuresAreNotRetried() async throws {
        let transport = MockTransport(json: #"{"id":"not-an-int"}"#)
        let client = makeClient(transport: transport, policy: immediatePolicy())

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await transport.attemptCount == 1)
    }

    @Test("The none policy attempts a retryable failure exactly once")
    func nonePolicyDoesNotRetry() async throws {
        let transport = MockTransport(statusCodes: [503])
        let client = makeClient(transport: transport, policy: .none)

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        #expect(await transport.attemptCount == 1)
    }

    @Test("A failure the policy does not recognise is attempted exactly once")
    func unclassifiedFailuresAreNotRetried() async throws {
        let transport = MockTransport.alwaysFailing(with: LaravelError.invalidResponse)
        let client = makeClient(transport: transport, policy: immediatePolicy())

        do {
            let _: Event = try await client.get("/api/events/1")
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            guard case .invalidResponse = error else {
                Issue.record("Expected an invalid response, got \(error)")
                return
            }
        }
        #expect(await transport.attemptCount == 1)
    }

    @Test("Cancelling during the backoff wait fails the request as cancelled")
    func cancellationDuringBackoff() async throws {
        let transport = MockTransport(statusCodes: [503])
        let policy = RetryPolicy(
            maxRetries: 3,
            backoffStrategy: .constant(delay: 5),
            retriesNetworkFailures: true
        )
        let client = makeClient(transport: transport, policy: policy)

        let task = Task { () async throws -> Event in
            try await client.get("/api/events/1")
        }
        while await transport.attemptCount == 0 {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the request to be cancelled")
        } catch let error as LaravelError {
            #expect(error.isCancelled)
        }
        #expect(await transport.attemptCount == 1)
    }
}
