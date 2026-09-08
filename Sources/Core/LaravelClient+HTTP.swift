import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LaravelClient {
    /// Executes a prepared request and decodes its body.
    ///
    /// Requests flow through one path: build the `URLRequest`, hand it to the
    /// transport, validate the status code, decode. Anything layered on top —
    /// middleware, retries, authentication — hooks into this path rather than
    /// bypassing it.
    func executeRequest<T: Decodable>(
        _ request: Request,
        uploadProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> T {
        let (data, _) = try await executeWithRetry(request, uploadProgress: uploadProgress)
        return try decode(T.self, from: data)
    }

    /// Executes a prepared request and returns the payload with its metadata.
    ///
    /// Cancellation is honoured before the request leaves the client, and the
    /// effective timeout — per-request if given, client-wide otherwise — bounds
    /// how long the transport may take.
    func send(
        _ request: Request,
        uploadProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        try checkCancellation()

        let transport = self.transport
        do {
            let urlRequest = try await applyRequestMiddlewares(
                to: buildURLRequest(from: request, headers: await resolveHeaders(for: request))
            )
            try checkCancellation()

            let (data, response) = try await withTimeout(
                request.timeout ?? configuration.timeoutInterval
            ) {
                // Progress is reported only by transports that can; anything
                // else sends the same request without it.
                if let uploadProgress, let transport = transport as? any ProgressReportingTransport {
                    return try await transport.execute(urlRequest, uploadProgress: uploadProgress)
                }
                return try await transport.execute(urlRequest)
            }
            try await notifyResponseMiddlewares(response, data: data)
            return (data, response)
        } catch is CancellationError {
            throw LaravelError.cancelled
        }
    }

    /// Turns a transport-agnostic ``Request`` into a `URLRequest`.
    func buildURLRequest(from request: Request, headers: [String: String]) throws -> URLRequest {
        var urlRequest = URLRequest(url: try resolveURL(for: request))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeout ?? configuration.timeoutInterval
        urlRequest.httpBody = request.body

        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        return urlRequest
    }

    /// Resolves a request path against the configured base URL.
    ///
    /// A path that already carries a scheme is used as-is, so callers can hit a
    /// fully-qualified URL — a presigned upload endpoint, for instance — through
    /// the same client.
    func resolveURL(for request: Request) throws -> URL {
        let url: URL
        if let absolute = URL(string: request.path), absolute.scheme != nil {
            url = absolute
        } else {
            var base = configuration.baseURL.absoluteString
            while base.hasSuffix("/") { base.removeLast() }
            var path = request.path
            while path.hasPrefix("/") { path.removeFirst() }

            guard let joined = URL(string: path.isEmpty ? base : "\(base)/\(path)") else {
                throw LaravelError.invalidURL(request.path)
            }
            url = joined
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw LaravelError.invalidURL(request.path)
        }
        if let query = request.query, !query.isEmpty {
            let items = query
                .map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
            components.queryItems = (components.queryItems ?? []) + items
        }
        guard let resolved = components.url else {
            throw LaravelError.invalidURL(request.path)
        }
        return resolved
    }

    /// Throws for any status code outside the 2xx range.
    ///
    /// The payload travels with the error so callers can read a server-provided
    /// error body.
    func validateHTTPStatus(_ response: HTTPURLResponse, data: Data) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw LaravelError.httpError(
                HTTPError(
                    statusCode: response.statusCode,
                    data: data.isEmpty ? nil : data,
                    response: response
                )
            )
        }
    }

    /// Decodes a response payload, treating an empty body as ``EmptyResponse``.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let empty = EmptyResponse() as? T, data.isEmpty || type == EmptyResponse.self {
            return empty
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw LaravelError.decodingError(error, data: data)
        }
    }
}
