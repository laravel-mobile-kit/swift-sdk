import Foundation
import Testing

import LaravelMobileKit

/// Replays a scripted streamed response, one script per attempt.
///
/// The body is left open until ``release()`` is called, which is what makes the
/// "the head arrives before the body finishes" assertions deterministic rather
/// than timing-dependent.
actor MockStreamingTransport: StreamingTransport {
    struct Script: Sendable {
        var statusCode: Int = 200
        var headers: [String: String] = [:]
        var chunks: [String] = []
        /// Fails the body after the chunks, as a mid-stream disconnect would.
        var failure: (any Error)?
        /// Holds the body open until `release()`.
        var waitsForRelease: Bool = false
    }

    private var scripts: [Script]
    private let fallback: Script
    private var pendingRelease: [AsyncThrowingStream<Data, any Error>.Continuation] = []
    private(set) var attemptCount = 0
    private(set) var executedRequests: [URLRequest] = []

    init(scripts: [Script], fallback: Script = Script()) {
        self.scripts = scripts
        self.fallback = fallback
    }

    init(chunks: [String], statusCode: Int = 200, waitsForRelease: Bool = false) {
        self.init(
            scripts: [],
            fallback: Script(statusCode: statusCode, chunks: chunks, waitsForRelease: waitsForRelease)
        )
    }

    /// Finishes every body currently held open.
    func release() {
        for continuation in pendingRelease { continuation.finish() }
        pendingRelease.removeAll()
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let opened = try await stream(request)
        var data = Data()
        for try await chunk in opened.body { data.append(chunk) }
        return (data, opened.response)
    }

    func stream(_ request: URLRequest) async throws -> HTTPResponseStream {
        attemptCount += 1
        executedRequests.append(request)
        let script = scripts.isEmpty ? fallback : scripts.removeFirst()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: script.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: script.headers
        )!

        let (body, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        for chunk in script.chunks { continuation.yield(Data(chunk.utf8)) }

        if let failure = script.failure {
            continuation.finish(throwing: failure)
        } else if script.waitsForRelease {
            pendingRelease.append(continuation)
        } else {
            continuation.finish()
        }

        return HTTPResponseStream(response: response, body: body)
    }
}

@Suite("Streaming")
struct StreamingTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func makeClient(
        transport: any HTTPTransport,
        policy: RetryPolicy = .none
    ) -> LaravelClient {
        LaravelClient(
            configuration: LaravelClientConfiguration(baseURL: baseURL, retryPolicy: policy),
            transport: transport
        )
    }

    private func collect(_ stream: AsyncThrowingStream<Data, any Error>) async throws -> [String] {
        var chunks: [String] = []
        for try await chunk in stream { chunks.append(String(decoding: chunk, as: UTF8.self)) }
        return chunks
    }

    // MARK: - Delivery

    @Test("Chunks arrive as chunks, not as one concatenated body")
    func chunkBoundariesSurvive() async throws {
        let transport = MockStreamingTransport(chunks: ["Hel", "lo, ", "world"])
        let client = makeClient(transport: transport)

        let chunks = try await collect(try await client.stream(.post, "/api/chat"))

        #expect(chunks == ["Hel", "lo, ", "world"])
    }

    /// The property that makes this streaming rather than a late `Data`: the
    /// call returns while the body is still open. If the client buffered, it
    /// could not have returned yet.
    @Test("The head is delivered before the body finishes")
    func headArrivesBeforeBodyCompletes() async throws {
        let transport = MockStreamingTransport(chunks: ["first"], waitsForRelease: true)
        let client = makeClient(transport: transport)

        let stream = try await client.stream(.post, "/api/chat")

        // We are here, holding a stream, while the response is still in flight.
        await transport.release()

        #expect(try await collect(stream) == ["first"])
    }

    // MARK: - Failures before the first byte

    @Test("A failing status throws instead of yielding an error body as content")
    func errorStatusThrowsBeforeAnyChunk() async throws {
        let transport = MockStreamingTransport(
            chunks: [#"{"message":"Server Error"}"#],
            statusCode: 500
        )
        let client = makeClient(transport: transport)

        do {
            _ = try await client.stream(.post, "/api/chat")
            Issue.record("Expected the stream to throw")
        } catch let error as LaravelError {
            #expect(error.statusCode == 500)
            // The body travels with the error, not to the caller as content.
            #expect(error.httpError?.bodyText == #"{"message":"Server Error"}"#)
        }
    }

    @Test("A streamed validation error reaches the middleware that understands it")
    func validationErrorsAreParsedFromAStream() async throws {
        let payload = #"{"message":"Invalid","errors":{"prompt":["required"]}}"#
        let transport = MockStreamingTransport(chunks: [payload], statusCode: 422)
        let client = makeClient(transport: transport)
        await client.use(.validationErrors)

        do {
            _ = try await client.stream(.post, "/api/chat")
            Issue.record("Expected the stream to throw")
        } catch let error as LaravelValidationError {
            #expect(error.firstError(for: "prompt") == "required")
        }
    }

    @Test("A transport that cannot stream says so")
    func nonStreamingTransportIsReported() async throws {
        let client = makeClient(transport: MockTransport(statusCode: 200, json: "{}"))

        do {
            _ = try await client.stream(.post, "/api/chat")
            Issue.record("Expected the stream to throw")
        } catch let error as LaravelError {
            guard case .streamingUnsupported = error else {
                Issue.record("Expected .streamingUnsupported, got \(error)")
                return
            }
        }
    }

    // MARK: - Retries

    @Test("A transient status is retried, and the caller sees only the attempt that worked")
    func transientFailuresAreRetriedBeforeStreaming() async throws {
        let transport = MockStreamingTransport(
            scripts: [
                .init(statusCode: 503),
                .init(statusCode: 503),
                .init(statusCode: 200, chunks: ["ok"]),
            ],
            fallback: .init(statusCode: 200, chunks: ["ok"])
        )
        let client = makeClient(
            transport: transport,
            policy: RetryPolicy(maxRetries: 3, retryableMethods: [.post], backoffStrategy: .none)
        )

        let chunks = try await collect(try await client.stream(.post, "/api/chat"))

        #expect(chunks == ["ok"])
        #expect(await transport.attemptCount == 3)
    }

    @Test("A 401 is recovered before the first byte, and the retry carries the new token")
    func unauthorizedIsRecoveredBeforeStreaming() async throws {
        let store = InMemoryCredentialStore(
            credential: AuthCredential(accessToken: "stale", refreshToken: "renewable")
        )
        let transport = MockStreamingTransport(
            scripts: [.init(statusCode: 401), .init(statusCode: 200, chunks: ["ok"])],
            fallback: .init(statusCode: 200, chunks: ["ok"])
        )
        let client = makeClient(transport: transport)
        let coordinator = TokenRefreshCoordinator(credentialStore: store) { _ in
            AuthCredential(accessToken: "fresh", refreshToken: "r")
        }
        await client.use(.auth(CredentialTokenProvider(store: store)))
        await client.use(retryDecider: AuthRefreshRetryDecider(coordinator: coordinator))

        let chunks = try await collect(try await client.stream(.post, "/api/chat"))

        #expect(chunks == ["ok"])
        let sent = await transport.executedRequests.map {
            $0.value(forHTTPHeaderField: "Authorization")
        }
        #expect(sent == ["Bearer stale", "Bearer fresh"])
    }

    /// Once a chunk has been handed over, repeating the request would duplicate
    /// the answer rather than repair it — so a mid-stream failure is reported to
    /// the caller instead of being retried.
    @Test("A failure after the first chunk is reported, not retried")
    func midStreamFailureIsNotRetried() async throws {
        struct Disconnected: Error {}
        let transport = MockStreamingTransport(
            scripts: [.init(statusCode: 200, chunks: ["partial"], failure: Disconnected())],
            fallback: .init(statusCode: 200, chunks: ["whole"])
        )
        let client = makeClient(
            transport: transport,
            policy: RetryPolicy(maxRetries: 3, retryableMethods: [.post], backoffStrategy: .none)
        )

        var received: [String] = []
        do {
            for try await chunk in try await client.stream(.post, "/api/chat") {
                received.append(String(decoding: chunk, as: UTF8.self))
            }
            Issue.record("Expected the stream to fail")
        } catch {
            #expect(received == ["partial"])
        }

        // One attempt: the retry engine never saw this, by construction.
        #expect(await transport.attemptCount == 1)
    }

    // MARK: - Pipeline

    @Test("Request middleware runs for streamed requests too")
    func requestMiddlewareApplies() async throws {
        let transport = MockStreamingTransport(chunks: ["ok"])
        let client = makeClient(transport: transport)
        await client.use(.apiVersion(.v1))
        await client.use(.auth(StaticTokenProvider("secret")))

        _ = try await collect(try await client.stream(.post, "/api/chat"))

        let request = await transport.executedRequests.first
        #expect(request?.url?.path == "/api/v1/chat")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }
}
