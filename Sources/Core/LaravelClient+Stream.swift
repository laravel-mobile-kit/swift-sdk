import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LaravelClient {
    /// Sends a request and returns its body as it arrives.
    ///
    /// ```swift
    /// for try await chunk in try await client.stream(.post, "/api/chat", body: prompt) {
    ///     transcript += String(decoding: chunk, as: UTF8.self)
    /// }
    /// ```
    ///
    /// ## What is guaranteed before the first chunk
    ///
    /// The status code is validated, and retries are exhausted, before this
    /// method returns. A caller that receives a stream has already received a
    /// successful response head, so an error body can never reach them looking
    /// like content.
    ///
    /// ## Retries
    ///
    /// Everything the buffered path retries, this retries too — transient
    /// statuses, network failures, a `401` that a ``RetryDecider`` recovers
    /// from — because all of it happens while validating the head, before any
    /// chunk exists. Once the stream is returned, nothing is retried: the
    /// caller has seen part of the answer, and repeating the request would
    /// duplicate it rather than repair it.
    ///
    /// ## Response middleware
    ///
    /// On failure the body is drained and every middleware sees it, which is
    /// what lets `.validationErrors` turn a streamed `422` into a typed error.
    ///
    /// On success middleware is **not** notified. It would have to be handed
    /// either an empty body, which is a lie, or a buffered one, which defeats
    /// the streaming it was asked for. Request middleware — authentication,
    /// versioning, tracing — runs normally in both cases.
    ///
    /// - Throws: ``LaravelError/streamingUnsupported`` when the configured
    ///   transport cannot stream.
    public func stream(
        _ method: HTTPMethod,
        _ path: String,
        body: Data? = nil,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) async throws -> AsyncThrowingStream<Data, any Error> {
        let request = makeRequest(method, path, query: query, options: options, body: body)
        return try await openStreamWithRetry(request)
    }

    /// Opens a stream, repeating the request while the failure is one the policy
    /// or a decider can do something about.
    ///
    /// This mirrors `executeWithRetry`, and deliberately shares its shape: the
    /// only difference is that success yields a stream rather than a payload.
    /// Because the head is validated here, every retry in this loop happens
    /// before the caller has seen a single byte.
    private func openStreamWithRetry(
        _ request: Request
    ) async throws -> AsyncThrowingStream<Data, any Error> {
        let policy = configuration.retryPolicy
        var policyAttempt = 0
        var recoveryAttempt = 0

        while true {
            try checkCancellation()
            do {
                return try await openStream(request)
            } catch let error as LaravelError {
                if policyAttempt < policy.maxRetries,
                   policy.shouldRetry(error, request: request),
                   let wait = policy.wait(forAttempt: policyAttempt, after: error) {
                    try await backOffBeforeStreamRetry(wait)
                    policyAttempt += 1
                    continue
                }

                guard recoveryAttempt < Self.maxRecoveryRetries,
                      try await shouldRecoverStream(
                          from: error,
                          request: request,
                          attempt: recoveryAttempt
                      )
                else {
                    throw error
                }
                recoveryAttempt += 1
            }
        }
    }

    /// One attempt: build the request, send it, validate the head.
    private func openStream(
        _ request: Request
    ) async throws -> AsyncThrowingStream<Data, any Error> {
        guard let transport = transport as? any StreamingTransport else {
            throw LaravelError.streamingUnsupported
        }

        let urlRequest = try await applyRequestMiddlewares(
            to: buildURLRequest(from: request, headers: await resolveHeaders(for: request))
        )
        try checkCancellation()

        let opened: HTTPResponseStream
        do {
            opened = try await transport.stream(urlRequest)
        } catch is CancellationError {
            throw LaravelError.cancelled
        }

        guard (200 ..< 300).contains(opened.response.statusCode) else {
            // The caller never sees this body as content: it is drained here,
            // handed to the middleware that may recognise it, and then thrown.
            let data = try await drain(opened.body)
            try await notifyResponseMiddlewares(opened.response, data: data)
            throw LaravelError.httpError(
                HTTPError(
                    statusCode: opened.response.statusCode,
                    data: data.isEmpty ? nil : data,
                    response: opened.response
                )
            )
        }

        return opened.body
    }

    /// Collects a body that is not going to be streamed to anyone.
    ///
    /// A truncated read is not worth failing over — the status code is the
    /// error, and a partial body still makes a better message than none.
    private func drain(_ body: AsyncThrowingStream<Data, any Error>) async -> Data {
        var data = Data()
        do {
            for try await chunk in body { data.append(chunk) }
        } catch {}
        return data
    }

    /// Asks each decider, in order, whether the request can be sent again.
    private func shouldRecoverStream(
        from error: LaravelError,
        request: Request,
        attempt: Int
    ) async throws -> Bool {
        for decider in retryDeciders {
            if try await decider.shouldRetry(error, request: request, attempt: attempt) {
                return true
            }
        }
        return false
    }

    /// Waits between attempts, reporting cancellation as ``LaravelError/cancelled``.
    private func backOffBeforeStreamRetry(_ delay: TimeInterval) async throws {
        guard delay > 0 else { return }
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            throw LaravelError.cancelled
        }
    }
}
