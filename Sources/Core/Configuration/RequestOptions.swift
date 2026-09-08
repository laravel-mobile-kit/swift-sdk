import Foundation

/// Per-request overrides applied on top of the client configuration.
///
/// ```swift
/// let events: [Event] = try await client.get("/api/events", options: .timeout(5))
/// ```
public struct RequestOptions: Sendable, Hashable {
    /// Timeout for this request, overriding ``LaravelClientConfiguration/timeoutInterval``.
    public var timeout: TimeInterval?
    /// Headers for this request, applied over the client's default headers.
    public var headers: [String: String]

    public init(timeout: TimeInterval? = nil, headers: [String: String] = [:]) {
        self.timeout = timeout
        self.headers = headers
    }

    /// No overrides: the client configuration is used as-is.
    public static let none = RequestOptions()

    /// Options carrying only a timeout override.
    public static func timeout(_ timeout: TimeInterval) -> RequestOptions {
        RequestOptions(timeout: timeout)
    }

    /// Options carrying only header overrides.
    public static func headers(_ headers: [String: String]) -> RequestOptions {
        RequestOptions(headers: headers)
    }
}
