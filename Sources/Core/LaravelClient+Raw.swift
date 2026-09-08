import Foundation

extension LaravelClient {
    /// Performs a request and returns the decoded value together with the
    /// response metadata.
    ///
    /// Use this when the status code or a response header matters — a
    /// `Location` header after a create, or an `X-RateLimit-Remaining` budget.
    ///
    /// ```swift
    /// let response: Response<Event> = try await client.response(.post, "/api/events", body: data)
    /// print(response.statusCode, response.headers["Location"] ?? "")
    /// ```
    public func response<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String]? = nil,
        body: Data? = nil,
        options: RequestOptions = .none,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> Response<T> {
        let (data, httpResponse) = try await executeWithRetry(
            makeRequest(method, path, query: query, options: options, body: body),
            uploadProgress: onProgress
        )
        return Response(
            value: try decode(T.self, from: data),
            httpResponse: httpResponse,
            rawData: data
        )
    }

    /// Performs a request and returns the untouched payload.
    ///
    /// This is the escape hatch for responses the Codable path cannot express —
    /// a CSV export, an image, a payload whose shape is only known at runtime.
    /// Status validation, retries, middleware, and cancellation still apply.
    ///
    /// `onProgress` reports how much of the body has been sent, when the
    /// transport can tell.
    public func raw(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String]? = nil,
        body: Data? = nil,
        options: RequestOptions = .none,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> Response<Data> {
        let (data, httpResponse) = try await executeWithRetry(
            makeRequest(method, path, query: query, options: options, body: body),
            uploadProgress: onProgress
        )
        return Response(value: data, httpResponse: httpResponse, rawData: data)
    }
}
