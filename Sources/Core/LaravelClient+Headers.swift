import Foundation

extension LaravelClient {
    /// Merges every header source for one request.
    ///
    /// Precedence runs from general to specific: client defaults first, then
    /// header providers in registration order, then the request's own headers.
    /// The most specific source always wins.
    func resolveHeaders(for request: Request) async -> [String: String] {
        var headers = configuration.defaultHeaders

        for provider in configuration.headerProviders {
            for (field, value) in await provider.headers() {
                headers[field] = value
            }
        }
        for (field, value) in request.headers {
            headers[field] = value
        }
        // Last, and deliberately not overridable by the request's own headers:
        // the key the retry engine acts on and the key the server sees have to
        // be the same one.
        if let key = request.idempotencyKey {
            headers[configuration.idempotencyKeyHeader] = key
        }
        return headers
    }
}
