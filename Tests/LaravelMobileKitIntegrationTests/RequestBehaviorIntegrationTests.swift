import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    @Suite("Request behaviour")
    struct RequestBehaviorIntegrationTests {
        // MARK: - Codable path

        @Test("A Laravel record decodes into a Swift model")
        func recordDecodesIntoAModel() async throws {
            let client = await IntegrationHarness.makeClient()

            let event: Envelope<APIEvent> = try await client.get("/api/events/1")

            #expect(event.data.id == 1)
            #expect(event.data.title == "Event 01")
            #expect(event.data.isPublished == true)
            // `starts_at` and `created_at` prove the snake_case and date
            // conventions are applied without any per-model configuration.
            #expect(event.data.startsAt != nil)
            #expect(event.data.createdAt != nil)
        }

        @Test("A missing record is a 404, not a decoding failure")
        func missingRecordIsNotFound() async throws {
            let client = await IntegrationHarness.makeClient()

            do {
                let _: Envelope<APIEvent> = try await client.get("/api/events/999999")
                Issue.record("Expected the request to fail")
            } catch let error as LaravelError {
                #expect(error.isNotFound)
            }
        }

        @Test("A non-standard payload stays reachable through the raw API")
        func rawResponseKeepsThePayload() async throws {
            let client = await IntegrationHarness.makeClient()

            let response = try await client.raw(.get, "/api/events", query: ["per_page": "1"])

            #expect(response.statusCode == 200)
            #expect(
                response.headers.keys.contains {
                    $0.caseInsensitiveCompare("Content-Type") == .orderedSame
                })
            let payload = try JSONSerialization.jsonObject(with: response.rawData) as? [String: Any]
            #expect(payload?["current_page"] as? Int == 1)
        }

        @Test("Server errors carry their status and body", arguments: [500, 503])
        func serverErrorsCarryTheirPayload(statusCode: Int) async throws {
            let client = await IntegrationHarness.makeClient()

            do {
                let _: EchoedRequest = try await client.get("/api/status/\(statusCode)")
                Issue.record("Expected the request to fail")
            } catch let error as LaravelError {
                #expect(error.statusCode == statusCode)
                #expect(error.isServerError)
                #expect(error.httpError?.bodyText?.contains("Status \(statusCode)") == true)
            }
        }

        // MARK: - Headers and middleware

        @Test("Default, provider, and per-request headers all arrive")
        func headersReachTheServer() async throws {
            let client = LaravelClient(
                configuration: LaravelClientConfiguration(
                    baseURL: IntegrationEnvironment.url,
                    defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders
                        .merging(["X-Client": "integration-suite"]) { _, new in new },
                    retryPolicy: .none
                )
            )

            let echo: EchoedRequest = try await client.get(
                "/api/echo",
                query: ["page": "2"],
                options: RequestOptions(headers: ["X-Request-Scope": "single-call"])
            )

            #expect(echo.header("Accept") == "application/json")
            #expect(echo.header("X-Client") == "integration-suite")
            #expect(echo.header("X-Request-Scope") == "single-call")
            #expect(echo.query["page"] == "2")
        }

        @Test("A middleware can rewrite a request and observe the response")
        func middlewareSeesBothDirections() async throws {
            let client = await IntegrationHarness.makeClient()
            let observer = ResponseObserver()
            await client.use(observer)

            let echo: EchoedRequest = try await client.get("/api/echo")

            #expect(echo.header("X-Middleware") == "applied")
            #expect(observer.statusCodes == [200])
        }

        // MARK: - Retries

        @Test("A transient 503 is retried until the endpoint recovers")
        func transientFailuresAreRetried() async throws {
            let key = IntegrationEnvironment.flakyKey("retry")
            let client = await IntegrationHarness.makeClient(
                retryPolicy: RetryPolicy(maxRetries: 3, backoffStrategy: .constant(delay: 0.05))
            )

            let result: FlakyResult = try await client.get(
                "/api/flaky/\(key)",
                query: ["failures": "2"]
            )

            #expect(result.attempts == 3)
        }

        @Test("A POST is not retried, however transient the failure")
        func postsAreNotRetried() async throws {
            let key = IntegrationEnvironment.flakyKey("no-retry")
            let client = await IntegrationHarness.makeClient(
                retryPolicy: RetryPolicy(maxRetries: 3, backoffStrategy: .constant(delay: 0.05))
            )

            do {
                let _: FlakyResult = try await client.post(
                    "/api/flaky/\(key)",
                    body: Optional<String>.none,
                    query: ["failures": "2"]
                )
                Issue.record("Expected the request to fail")
            } catch let error as LaravelError {
                #expect(error.statusCode == 503)
            }

            let counter: FlakyCounter = try await client.delete("/api/flaky/\(key)")
            #expect(counter.attempts == 1)
        }

        @Test("Retries stop once the policy runs out")
        func retriesAreBounded() async throws {
            let key = IntegrationEnvironment.flakyKey("bounded")
            let client = await IntegrationHarness.makeClient(
                retryPolicy: RetryPolicy(maxRetries: 1, backoffStrategy: .constant(delay: 0.05))
            )

            do {
                let _: FlakyResult = try await client.get(
                    "/api/flaky/\(key)",
                    query: ["failures": "5"]
                )
                Issue.record("Expected the request to fail")
            } catch let error as LaravelError {
                #expect(error.statusCode == 503)
            }

            let counter: FlakyCounter = try await client.delete("/api/flaky/\(key)")
            #expect(counter.attempts == 2)
        }

        // MARK: - Cancellation and timeouts

        @Test("A slow endpoint is cut off by the per-request timeout")
        func perRequestTimeoutApplies() async throws {
            let client = await IntegrationHarness.makeClient(timeout: 30)

            do {
                let _: EchoedRequest = try await client.get(
                    "/api/slow",
                    query: ["seconds": "3"],
                    options: RequestOptions(timeout: 0.6)
                )
                Issue.record("Expected the request to time out")
            } catch let error as LaravelError {
                #expect(error.isTimeout)
            }
        }

        @Test("Cancelling the surrounding task cancels the request")
        func cancellationPropagates() async throws {
            let client = await IntegrationHarness.makeClient(timeout: 30)

            let task = Task { () async throws -> EchoedRequest in
                try await client.get("/api/slow", query: ["seconds": "3"])
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            task.cancel()

            do {
                _ = try await task.value
                Issue.record("Expected the request to be cancelled")
            } catch let error as LaravelError {
                #expect(error.isCancelled)
            }
        }
    }
}

/// Adds a header on the way out and records the status on the way back.
private final class ResponseObserver: Middleware, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    var statusCodes: [Int] { lock.withLock { storage } }

    func process(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("applied", forHTTPHeaderField: "X-Middleware")
        return request
    }

    func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        lock.withLock { storage.append(response.statusCode) }
    }
}
