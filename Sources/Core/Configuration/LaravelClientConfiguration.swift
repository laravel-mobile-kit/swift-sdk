import Foundation

/// Immutable configuration for a ``LaravelClient``.
///
/// A configuration is captured when the client is created; changing a
/// configuration value afterwards has no effect on an existing client.
public struct LaravelClientConfiguration: Sendable {
    /// Root URL every request path is resolved against.
    public let baseURL: URL
    /// Headers applied to every request, before providers and per-request headers.
    public var defaultHeaders: [String: String]
    /// Providers consulted on every request, in order.
    public var headerProviders: [any HeaderProvider]
    /// Timeout applied to every request, in seconds.
    public var timeoutInterval: TimeInterval
    /// Retry behaviour for transient failures.
    public var retryPolicy: RetryPolicy

    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = LaravelClientConfiguration.defaultJSONHeaders,
        headerProviders: [any HeaderProvider] = [],
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.headerProviders = headerProviders
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
    }

    /// Headers a JSON API is expected to receive.
    ///
    /// `Accept: application/json` matters for Laravel in particular: without it
    /// the framework answers validation failures with an HTML redirect instead
    /// of a JSON error payload.
    public static let defaultJSONHeaders: [String: String] = [
        "Accept": "application/json",
        "Content-Type": "application/json",
    ]
}
