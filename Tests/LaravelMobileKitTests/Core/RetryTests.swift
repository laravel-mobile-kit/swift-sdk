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

    // MARK: - Retry-After and jitter

    /// A failure carrying the response headers a server would have sent.
    private func failure(status: Int, headers: [String: String] = [:]) -> LaravelError {
        let response = HTTPURLResponse(
            url: baseURL,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return .httpError(HTTPError(statusCode: status, data: nil, response: response))
    }

    private var unjittered: RetryPolicy {
        RetryPolicy(maxRetries: 3, backoffStrategy: .exponential(base: 0.5, maxDelay: 30), jitter: .none)
    }

    @Test("Retry-After in seconds wins over the backoff schedule")
    func retryAfterSeconds() {
        let wait = unjittered.wait(
            forAttempt: 0,
            after: failure(status: 429, headers: ["Retry-After": "7"])
        )

        // The schedule would have said 0.5s; the server said 7.
        #expect(wait == 7)
    }

    @Test("Retry-After as an HTTP date is honoured")
    func retryAfterHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_445_412_480)  // 21 Oct 2015 07:28:00 GMT
        let wait = unjittered.wait(
            forAttempt: 0,
            after: failure(status: 503, headers: ["Retry-After": "Wed, 21 Oct 2015 07:28:30 GMT"]),
            now: now
        )

        #expect(wait == 30)
    }

    @Test("A Retry-After date already in the past means no wait, not a negative one")
    func retryAfterInThePast() {
        let now = Date(timeIntervalSince1970: 1_445_412_480)
        let wait = unjittered.wait(
            forAttempt: 0,
            after: failure(status: 503, headers: ["Retry-After": "Wed, 21 Oct 2015 07:27:00 GMT"]),
            now: now
        )

        #expect(wait == 0)
    }

    @Test("An unparseable Retry-After falls back to the backoff schedule")
    func retryAfterGarbage() {
        let wait = unjittered.wait(
            forAttempt: 1,
            after: failure(status: 503, headers: ["Retry-After": "soon-ish"])
        )

        #expect(wait == 1)  // exponential: 0.5 * 2^1
    }

    @Test("A Retry-After longer than the client will wait ends the retries")
    func retryAfterBeyondTheCap() {
        var policy = unjittered
        policy.maximumRetryAfter = 60

        #expect(policy.wait(forAttempt: 0, after: failure(status: 429, headers: ["Retry-After": "60"])) == 60)
        #expect(policy.wait(forAttempt: 0, after: failure(status: 429, headers: ["Retry-After": "61"])) == nil)
    }

    @Test("A server asking for an unreasonable wait is not retried at all")
    func hugeRetryAfterStopsTheRequest() async throws {
        let transport = MockTransport(statusCode: 429, headers: ["Retry-After": "3600"])
        let client = makeClient(transport: transport, policy: RetryPolicy(maxRetries: 3))

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }
        // Without the cap this would have been four attempts an hour apart.
        #expect(await transport.attemptCount == 1)
    }

    @Test("Full jitter keeps every wait inside the computed ceiling")
    func fullJitterStaysWithinTheCeiling() {
        let policy = RetryPolicy(
            maxRetries: 3,
            backoffStrategy: .exponential(base: 0.5, maxDelay: 30),
            jitter: .full
        )
        let ceiling = BackoffStrategy.exponential(base: 0.5, maxDelay: 30).delay(for: 3)

        let draws = (0 ..< 200).map { _ in
            policy.wait(forAttempt: 3, after: failure(status: 503)) ?? -1
        }

        #expect(draws.allSatisfy { $0 >= 0 && $0 <= ceiling })
        // Spreading is the whole point, so the draws must not all be identical.
        #expect(Set(draws).count > 1)
    }

    @Test("Jitter never shortens a wait the server asked for")
    func jitterDoesNotUndercutRetryAfter() {
        let policy = RetryPolicy(maxRetries: 3, jitter: .full)

        let draws = (0 ..< 50).map { _ in
            policy.wait(forAttempt: 0, after: failure(status: 429, headers: ["Retry-After": "5"]))
        }

        #expect(draws.allSatisfy { $0 == 5 })
    }

    @Test("Without jitter the wait is exactly what the schedule computed")
    func noJitterIsExact() {
        #expect(unjittered.wait(forAttempt: 2, after: failure(status: 503)) == 2)
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
