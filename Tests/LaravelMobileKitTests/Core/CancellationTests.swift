import Foundation
import Testing

import LaravelMobileKitCore

@Suite("Cancellation and timeouts")
struct CancellationTests {
    let baseURL = URL(string: "https://api.example.com")!

    @Test("The client-wide timeout bounds a slow request")
    func clientTimeoutFires() async throws {
        let transport = MockTransport(json: "[]")
        await transport.stall(seconds: 5)
        let configuration = LaravelClientConfiguration(
            baseURL: baseURL,
            timeoutInterval: 0.05,
            retryPolicy: .none
        )
        let client = LaravelClient(configuration: configuration, transport: transport)

        do {
            let _: [Event] = try await client.get("/api/events")
            Issue.record("Expected the request to time out")
        } catch let error as LaravelError {
            #expect(error.isTimeout)
        }
    }

    @Test("A per-request timeout overrides the client default")
    func perRequestTimeoutWins() async throws {
        let transport = MockTransport(json: "[]")
        await transport.stall(seconds: 5)
        let configuration = LaravelClientConfiguration(
            baseURL: baseURL,
            timeoutInterval: 60,
            retryPolicy: .none
        )
        let client = LaravelClient(configuration: configuration, transport: transport)

        do {
            let _: [Event] = try await client.get("/api/events", options: .timeout(0.05))
            Issue.record("Expected the request to time out")
        } catch let error as LaravelError {
            #expect(error.isTimeout)
        }
    }

    @Test("A request that answers in time is not affected by the timeout")
    func fastRequestSucceeds() async throws {
        let transport = MockTransport(json: #"[{"id":1,"title":"Launch"}]"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let events: [Event] = try await client.get("/api/events", options: .timeout(5))

        #expect(events == [Event(id: 1, title: "Launch")])
    }

    @Test("The effective timeout is carried on the URLRequest")
    func timeoutReachesTheURLRequest() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let _: [Event] = try await client.get("/api/events", options: .timeout(3))

        #expect(await transport.lastRequest?.timeoutInterval == 3)
    }

    @Test("Cancelling in flight fails the request as cancelled")
    func cancellationInFlight() async throws {
        let transport = MockTransport(json: "[]")
        await transport.stall(seconds: 5)
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)

        let task = Task { () async throws -> [Event] in
            try await client.get("/api/events")
        }
        // Wait until the transport has actually received the request.
        while await transport.executedRequests.isEmpty {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the request to be cancelled")
        } catch let error as LaravelError {
            #expect(error.isCancelled)
        }
    }

    @Test("A request issued from a cancelled task never reaches the transport")
    func cancellationBeforeSending() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let task = Task { () async throws -> [Event] in
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await client.get("/api/events")
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the request to be cancelled")
        } catch let error as LaravelError {
            #expect(error.isCancelled)
        }
        #expect(await transport.executedRequests.isEmpty)
    }
}
