import Foundation

/// A transport-agnostic description of an outgoing HTTP request.
///
/// A `Request` is relative to ``LaravelClientConfiguration/baseURL``: `path` is
/// appended to the base URL when the request is turned into a `URLRequest`.
/// Headers declared here are merged on top of the client's default headers.
public struct Request: Sendable, Hashable {
    /// HTTP verb used for the request.
    public var method: HTTPMethod
    /// Path relative to the client's base URL, for example `/api/events`.
    public var path: String
    /// Query parameters appended to the URL, if any.
    public var query: [String: String]?
    /// Per-request headers, merged over the client's default headers.
    public var headers: [String: String]
    /// Already-encoded request body, if any.
    public var body: Data?
    /// Timeout for this request, overriding the client-wide timeout.
    public var timeout: TimeInterval?
    /// Idempotency key, when the caller supplied one.
    ///
    /// Carried on the request rather than folded into ``headers`` because the
    /// retry engine has to read it: a keyed request is safe to repeat whatever
    /// its method, and that decision is made from a ``Request``.
    public var idempotencyKey: String?

    public init(
        method: HTTPMethod,
        path: String,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        idempotencyKey: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.idempotencyKey = idempotencyKey
    }
}
