import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A response whose head has arrived and whose body is still coming.
///
/// The split is the point: the status code and headers are available before the
/// first byte of the body, which is what lets the client validate — and retry —
/// while nothing has been handed to the caller yet.
public struct HTTPResponseStream: Sendable {
    /// Status code and headers, already received.
    public let response: HTTPURLResponse
    /// Body chunks, in arrival order, finishing when the response completes.
    public let body: AsyncThrowingStream<Data, any Error>

    public init(response: HTTPURLResponse, body: AsyncThrowingStream<Data, any Error>) {
        self.response = response
        self.body = body
    }
}

/// Transports that can deliver a response body incrementally.
///
/// Conformance is what makes ``LaravelClient/stream(_:_:body:query:options:)``
/// available. A transport that only buffers — most test doubles — simply does
/// not conform, and the client reports
/// ``LaravelError/streamingUnsupported`` rather than silently buffering a
/// response the caller asked to receive as it arrives.
public protocol StreamingTransport: HTTPTransport {
    /// Sends `request` and returns its head as soon as it arrives, with the
    /// body following as chunks.
    func stream(_ request: URLRequest) async throws -> HTTPResponseStream
}

extension URLSessionTransport: StreamingTransport {
    public func stream(_ request: URLRequest) async throws -> HTTPResponseStream {
        let delegate = StreamingTaskDelegate()
        let (body, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        delegate.adopt(continuation)

        let task = session.dataTask(with: request)
        task.delegate = delegate

        // A caller that stops iterating — or is cancelled — must not leave the
        // request running.
        continuation.onTermination = { _ in task.cancel() }

        do {
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { head in
                    delegate.adopt(head)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
            return HTTPResponseStream(response: response, body: body)
        } catch {
            continuation.finish()
            throw error
        }
    }
}

/// Bridges `URLSession`'s delegate callbacks onto the two continuations a
/// streamed response needs: one for the head, one for every chunk after it.
private final class StreamingTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var head: CheckedContinuation<HTTPURLResponse, any Error>?
    private var headSettled = false
    private var body: AsyncThrowingStream<Data, any Error>.Continuation?

    func adopt(_ continuation: CheckedContinuation<HTTPURLResponse, any Error>) {
        lock.withLock { head = continuation }
    }

    func adopt(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        lock.withLock { body = continuation }
    }

    /// Settles the head exactly once. Returns whether this call was the one that
    /// did it, so a later failure knows whether it belongs to the head or to the
    /// body.
    @discardableResult
    private func settleHead(_ result: Result<HTTPURLResponse, any Error>) -> Bool {
        let continuation: CheckedContinuation<HTTPURLResponse, any Error>? = lock.withLock {
            guard !headSettled else { return nil }
            headSettled = true
            defer { head = nil }
            return head
        }
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else {
            settleHead(.failure(LaravelError.invalidResponse))
            return .cancel
        }
        settleHead(.success(http))
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { body }?.yield(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let bodyContinuation = lock.withLock { body }

        guard let error else {
            settleHead(.failure(LaravelError.invalidResponse))  // no-op if already settled
            bodyContinuation?.finish()
            return
        }

        let failure = LaravelError(transportFailure: error)
        // A failure before the head arrived is the caller's to catch from
        // `stream()`; after it, the stream is the only place left to report.
        if !settleHead(.failure(failure)) {
            bodyContinuation?.finish(throwing: failure)
        } else {
            bodyContinuation?.finish()
        }
    }
}
