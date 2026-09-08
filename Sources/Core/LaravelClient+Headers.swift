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
        return headers
    }
}
