import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LaravelClient {
    /// Registers a middleware at the end of the pipeline.
    public func use(_ middleware: any Middleware) {
        middlewares.append(middleware)
    }

    /// Registers several middlewares, preserving their order.
    public func use(_ middlewares: [any Middleware]) {
        self.middlewares.append(contentsOf: middlewares)
    }

    /// Registers a decider consulted when a request fails.
    ///
    /// Deciders are asked in registration order and the first `true` wins.
    public func use(retryDecider: any RetryDecider) {
        retryDeciders.append(retryDecider)
    }

    /// Runs the request through every middleware, in registration order.
    func applyRequestMiddlewares(to request: URLRequest) async throws -> URLRequest {
        var request = request
        for middleware in middlewares {
            request = try await middleware.process(request)
        }
        return request
    }

    /// Notifies every middleware of a response, in reverse registration order.
    func notifyResponseMiddlewares(_ response: HTTPURLResponse, data: Data) async throws {
        for middleware in middlewares.reversed() {
            try await middleware.didReceive(response, data: data)
        }
    }
}
