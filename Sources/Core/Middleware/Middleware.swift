import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A hook in the request pipeline.
///
/// Middleware sees every request the client sends and every response it
/// receives. Request middleware runs in registration order and may rewrite the
/// request — adding an `Authorization` header, for example — or throw to abort
/// it. Response middleware runs in reverse order, so a middleware that wrapped
/// the request is also the last to see the response.
public protocol Middleware: Sendable {
    /// Transforms an outgoing request, or throws to abort it.
    func process(_ request: URLRequest) async throws -> URLRequest
    /// Observes an incoming response before it is validated or decoded.
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws
}

extension Middleware {
    /// Observing responses is optional.
    public func didReceive(_ response: HTTPURLResponse, data: Data) async throws {}
}
