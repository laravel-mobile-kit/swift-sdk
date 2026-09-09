import Foundation
import Testing

import LaravelMobileKitCore

/// Records the pipeline order and can rewrite or abort a request.
private struct RecordingMiddleware: Middleware {
    let name: String
    let recorder: Recorder
    var headerValue: String?
    var requestError: (any Error)?
    var responseError: (any Error)?

    func process(_ request: URLRequest) async throws -> URLRequest {
        await recorder.record("request:\(name)")
        if let requestError { throw requestError }

        var request = request
        if let headerValue {
            request.setValue(headerValue, forHTTPHeaderField: "X-Chain")
        }
        return request
    }

    func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        await recorder.record("response:\(name):\(response.statusCode)")
        if let responseError { throw responseError }
    }
}

private actor Recorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private struct MiddlewareFailure: Error, Equatable {}

@Suite("Middleware pipeline")
struct MiddlewareTests {
    let baseURL = URL(string: "https://api.example.com")!

    @Test("A middleware can add a header to every request")
    func middlewareRewritesRequest() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use(
            RecordingMiddleware(name: "auth", recorder: Recorder(), headerValue: "one")
        )

        let _: [Event] = try await client.get("/api/events")

        #expect(await transport.lastRequest?.value(forHTTPHeaderField: "X-Chain") == "one")
    }

    @Test("Requests run through middlewares in order, responses in reverse")
    func pipelineOrdering() async throws {
        let recorder = Recorder()
        let transport = MockTransport(statusCode: 200, json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use([
            RecordingMiddleware(name: "first", recorder: recorder, headerValue: "first"),
            RecordingMiddleware(name: "second", recorder: recorder, headerValue: "second"),
        ])

        let _: [Event] = try await client.get("/api/events")

        #expect(
            await recorder.events == [
                "request:first",
                "request:second",
                "response:second:200",
                "response:first:200",
            ]
        )
        // The later middleware rewrote the header the earlier one set.
        #expect(await transport.lastRequest?.value(forHTTPHeaderField: "X-Chain") == "second")
    }

    @Test("A middleware that throws aborts the request before it is sent")
    func middlewareAbortsRequest() async throws {
        let recorder = Recorder()
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use([
            RecordingMiddleware(name: "first", recorder: recorder, requestError: MiddlewareFailure()),
            RecordingMiddleware(name: "second", recorder: recorder),
        ])

        await #expect(throws: MiddlewareFailure.self) {
            let _: [Event] = try await client.get("/api/events")
        }
        #expect(await recorder.events == ["request:first"])
        #expect(await transport.executedRequests.isEmpty)
    }

    @Test("A middleware observing a response can reject it")
    func middlewareRejectsResponse() async throws {
        let transport = MockTransport(json: #"[{"id":1,"title":"Launch"}]"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use(
            RecordingMiddleware(name: "audit", recorder: Recorder(), responseError: MiddlewareFailure())
        )

        await #expect(throws: MiddlewareFailure.self) {
            let _: [Event] = try await client.get("/api/events")
        }
    }

    @Test("Response middleware sees failing responses too")
    func middlewareObservesFailures() async throws {
        let recorder = Recorder()
        let transport = MockTransport(statusCode: 500, json: "{}")
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
        await client.use(RecordingMiddleware(name: "audit", recorder: recorder))

        await #expect(throws: LaravelError.self) {
            let _: [Event] = try await client.get("/api/events")
        }
        #expect(await recorder.events == ["request:audit", "response:audit:500"])
    }

    @Test("A client with no middleware still sends the request")
    func emptyPipeline() async throws {
        let transport = MockTransport(json: #"[{"id":1,"title":"Launch"}]"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let events: [Event] = try await client.get("/api/events")

        #expect(events == [Event(id: 1, title: "Launch")])
    }
}

@Suite("Logging middleware")
struct LoggingMiddlewareTests {
    let baseURL = URL(string: "https://api.example.com")!

    /// Collects log lines synchronously, so assertions never race the sink.
    private final class LogSink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        var lines: [String] { lock.withLock { storage } }

        func makeSink() -> @Sendable (String) -> Void {
            { [self] line in lock.withLock { storage.append(line) } }
        }
    }

    private func lines(
        at level: LoggingMiddleware.Level,
        bodies: LoggingMiddleware.BodyLogging = .sizeOnly,
        options: RequestOptions = .none
    ) async throws -> [String] {
        let sink = LogSink()
        let transport = MockTransport(statusCode: 201, json: #"{"id":1,"title":"Launch"}"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use(LoggingMiddleware(level: level, bodies: bodies, sink: sink.makeSink()))

        let _: Event = try await client.post(
            "/api/events",
            body: CreateEvent(title: "Launch"),
            options: options
        )

        return sink.lines
    }

    @Test("The none level logs nothing")
    func noneLevelIsSilent() async throws {
        #expect(try await lines(at: .none).isEmpty)
    }

    @Test("The basic level logs the request line and the status")
    func basicLevel() async throws {
        let lines = try await lines(at: .basic)

        #expect(lines.contains("→ POST https://api.example.com/api/events"))
        #expect(lines.contains { $0.hasPrefix("← 201") })
        #expect(!lines.contains { $0.contains("Accept:") })
    }

    @Test("The headers level adds request headers")
    func headersLevel() async throws {
        let lines = try await lines(at: .headers)

        #expect(lines.contains { $0.contains("Accept: application/json") })
        #expect(!lines.contains { $0.contains("\"title\"") })
    }

    @Test("The headers level adds response headers")
    func responseHeadersAreLogged() async throws {
        let sink = LogSink()
        let transport = MockTransport(
            statusCode: 200,
            body: Data(#"{"id":1,"title":"Launch"}"#.utf8),
            headers: ["X-Request-Id": "abc123"]
        )
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use(LoggingMiddleware(level: .headers, sink: sink.makeSink()))

        let _: Event = try await client.get("/api/events/1")

        #expect(sink.lines.contains { $0.lowercased().contains("x-request-id: abc123") })
    }

    @Test("The body level reports payload sizes, not payloads")
    func bodyLevelWithheldByDefault() async throws {
        let lines = try await lines(at: .body)

        // Raising the level is not consent to print what the user typed.
        #expect(!lines.contains { $0.contains(#""title":"Launch""#) })
        #expect(!lines.contains { $0.contains(#""id":1"#) })
        #expect(lines.contains { $0.contains("bytes>") })
    }

    @Test("Payloads are logged only when the caller asks for them")
    func bodyLevelUnredacted() async throws {
        let lines = try await lines(at: .body, bodies: .unredacted)

        #expect(lines.contains { $0.contains(#""title":"Launch""#) })
        #expect(lines.contains { $0.contains(#""id":1"#) })
    }

    @Test("Credential-bearing request headers are redacted")
    func requestCredentialsAreRedacted() async throws {
        let lines = try await lines(
            at: .headers,
            options: .headers(["Authorization": "Bearer super-secret-token"])
        )

        #expect(!lines.contains { $0.contains("super-secret-token") })
        #expect(lines.contains { $0.contains("Authorization: <redacted>") })
        // Redaction is targeted: ordinary headers still come through.
        #expect(lines.contains { $0.contains("Accept: application/json") })
    }

    @Test("Credential-bearing response headers are redacted")
    func responseCredentialsAreRedacted() async throws {
        let sink = LogSink()
        let transport = MockTransport(
            statusCode: 200,
            body: Data(#"{"id":1,"title":"Launch"}"#.utf8),
            headers: ["Set-Cookie": "session=super-secret-session", "X-Request-Id": "abc123"]
        )
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use(LoggingMiddleware(level: .headers, sink: sink.makeSink()))

        let _: Event = try await client.get("/api/events/1")

        #expect(!sink.lines.contains { $0.contains("super-secret-session") })
        #expect(sink.lines.contains { $0.lowercased().contains("set-cookie: <redacted>") })
        #expect(sink.lines.contains { $0.lowercased().contains("x-request-id: abc123") })
    }

    @Test("The redacted header set is caller-configurable and case-insensitive")
    func redactionIsConfigurable() async throws {
        let sink = LogSink()
        let transport = MockTransport(statusCode: 200, json: #"{"id":1,"title":"Launch"}"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        await client.use(
            LoggingMiddleware(
                level: .headers,
                redactedHeaders: ["X-Tenant-Secret"],
                sink: sink.makeSink()
            )
        )

        let _: Event = try await client.get(
            "/api/events/1",
            options: .headers(["x-tenant-secret": "hunter2"])
        )

        #expect(!sink.lines.contains { $0.contains("hunter2") })
    }
}
