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
    /// Idempotency key for this request.
    ///
    /// Setting one does two things: it sends the key as a header, and it makes
    /// this request retryable regardless of its method. That pairing is the
    /// point — a `POST` is excluded from retries because repeating it may
    /// create a second record, and a key the server honours is exactly the
    /// promise that it will not.
    ///
    /// The key must be stable across the retries of one logical operation and
    /// different between operations: generate it once, where the operation
    /// starts, not inside the call that sends it.
    public var idempotencyKey: String?

    public init(
        timeout: TimeInterval? = nil,
        headers: [String: String] = [:],
        idempotencyKey: String? = nil
    ) {
        self.timeout = timeout
        self.headers = headers
        self.idempotencyKey = idempotencyKey
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

    /// Options carrying only an idempotency key.
    public static func idempotent(_ key: String) -> RequestOptions {
        RequestOptions(idempotencyKey: key)
    }
}
