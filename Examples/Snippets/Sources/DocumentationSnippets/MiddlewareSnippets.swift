import Foundation

import LaravelMobileKit

/// The tracing middleware from `Documentation/MIDDLEWARE.md`.
struct TracingMiddleware: Middleware {
    let traceID: @Sendable () -> String

    func process(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue(traceID(), forHTTPHeaderField: "X-Trace-Id")
        return request
    }

    func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        Metrics.record(status: response.statusCode, bytes: data.count)
    }
}

enum Metrics {
    static func record(status: Int, bytes: Int) {}
}

/// The rate-limit decider from the guide.
struct RateLimitDecider: RetryDecider {
    func shouldRetry(_ error: LaravelError, request: Request, attempt: Int) async throws -> Bool {
        guard error.statusCode == 429, attempt < 1 else { return false }

        let retryAfter = error.httpError?.response.value(forHTTPHeaderField: "Retry-After")
        try await Task.sleep(nanoseconds: UInt64((Double(retryAfter ?? "1") ?? 1) * 1_000_000_000))
        return true
    }
}

/// A transport stub, as documented for tests.
struct StubTransport: HTTPTransport {
    let fixture: Data

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (
            fixture,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

/// Examples from `Documentation/MIDDLEWARE.md`.
enum MiddlewareSnippets {
    static func registering(client: LaravelClient, provider: any TokenProvider) async {
        await client.use(.auth(provider))
        await client.use([.validationErrors, .apiVersion(.v1)])
        await client.use(TracingMiddleware { UUID().uuidString })
        await client.use(retryDecider: RateLimitDecider())
    }

    static func logging(client: LaravelClient) async {
        await client.use(LoggingMiddleware(level: .headers))
        await client.use(LoggingMiddleware(level: .body, sink: { line in print(line) }))
    }

    static var staticHeaders: LaravelClientConfiguration {
        LaravelClientConfiguration(
            baseURL: baseURL,
            defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders
                .merging(["X-App-Version": appVersion]) { _, new in new }
        )
    }

    static var headerProviders: LaravelClientConfiguration {
        LaravelClientConfiguration(
            baseURL: baseURL,
            headerProviders: [
                StaticHeaders(["X-Platform": "ios"]),
                DynamicHeaders { ["Accept-Language": Locale.current.identifier] },
            ]
        )
    }

    static func perRequestHeaders(client: LaravelClient) async throws {
        let events: [Event] = try await client.get(
            "/api/events",
            options: .headers(["X-Debug": "1"])
        )
        _ = events
    }

    static func customTransport(
        configuration: LaravelClientConfiguration,
        pinnedSession: URLSession
    ) -> LaravelClient {
        LaravelClient(
            configuration: configuration,
            transport: URLSessionTransport(session: pinnedSession)
        )
    }
}
