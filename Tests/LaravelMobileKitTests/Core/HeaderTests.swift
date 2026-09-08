import Foundation
import Testing

import LaravelMobileKitCore

@Suite("Header resolution")
struct HeaderTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func sentHeaders(
        defaultHeaders: [String: String] = LaravelClientConfiguration.defaultJSONHeaders,
        providers: [any HeaderProvider] = [],
        options: RequestOptions = .none
    ) async throws -> [String: String] {
        let transport = MockTransport(json: "[]")
        let configuration = LaravelClientConfiguration(
            baseURL: baseURL,
            defaultHeaders: defaultHeaders,
            headerProviders: providers,
            retryPolicy: .none
        )
        let client = LaravelClient(configuration: configuration, transport: transport)

        let _: [Event] = try await client.get("/api/events", options: options)

        return try #require(await transport.lastRequest?.allHTTPHeaderFields)
    }

    @Test("Default headers are sent on every request")
    func defaultHeadersAreSent() async throws {
        let headers = try await sentHeaders(defaultHeaders: ["X-App": "demo"])

        #expect(headers["X-App"] == "demo")
    }

    @Test("Header providers are consulted per request")
    func providerHeadersAreSent() async throws {
        let headers = try await sentHeaders(
            defaultHeaders: [:],
            providers: [StaticHeaders(["X-Device": "iPhone"])]
        )

        #expect(headers["X-Device"] == "iPhone")
    }

    @Test("A dynamic provider computes its value at send time")
    func dynamicProviderIsCalled() async throws {
        let counter = Counter()
        let provider = DynamicHeaders { ["X-Nonce": "\(await counter.next())"] }

        let first = try await sentHeaders(defaultHeaders: [:], providers: [provider])
        let second = try await sentHeaders(defaultHeaders: [:], providers: [provider])

        #expect(first["X-Nonce"] == "1")
        #expect(second["X-Nonce"] == "2")
    }

    @Test("Providers override defaults, and later providers override earlier ones")
    func providerPrecedence() async throws {
        let headers = try await sentHeaders(
            defaultHeaders: ["X-Source": "default"],
            providers: [
                StaticHeaders(["X-Source": "first"]),
                StaticHeaders(["X-Source": "second"]),
            ]
        )

        #expect(headers["X-Source"] == "second")
    }

    @Test("Per-request headers override every other source")
    func requestHeadersWin() async throws {
        let headers = try await sentHeaders(
            defaultHeaders: ["X-Source": "default"],
            providers: [StaticHeaders(["X-Source": "provider"])],
            options: .headers(["X-Source": "request"])
        )

        #expect(headers["X-Source"] == "request")
    }

    @Test("Sources that do not collide are all applied")
    func sourcesAreMerged() async throws {
        let headers = try await sentHeaders(
            defaultHeaders: ["Accept": "application/json"],
            providers: [StaticHeaders(["X-Device": "iPhone"])],
            options: .headers(["X-Trace": "abc"])
        )

        #expect(headers["Accept"] == "application/json")
        #expect(headers["X-Device"] == "iPhone")
        #expect(headers["X-Trace"] == "abc")
    }
}

private actor Counter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
