import Foundation

/// Describes which failures are retried, for which methods, and how long the
/// client waits in between.
///
/// `POST` is deliberately absent from ``default``: it is not idempotent, so a
/// retried create can produce a duplicate record. Add it explicitly only for
/// endpoints that are safe to repeat.
public struct RetryPolicy: Sendable, Hashable {
    /// Number of additional attempts after the initial one. `0` disables retries.
    public var maxRetries: Int
    /// HTTP status codes that are considered transient.
    public var retryableStatusCodes: Set<Int>
    /// Methods that may be retried.
    public var retryableMethods: Set<HTTPMethod>
    /// Delay applied between attempts.
    public var backoffStrategy: BackoffStrategy
    /// Whether timeouts and connection failures are retried as well.
    public var retriesNetworkFailures: Bool

    public init(
        maxRetries: Int,
        retryableStatusCodes: Set<Int> = RetryPolicy.defaultRetryableStatusCodes,
        retryableMethods: Set<HTTPMethod> = RetryPolicy.idempotentMethods,
        backoffStrategy: BackoffStrategy = .exponential(base: 0.5, maxDelay: 30),
        retriesNetworkFailures: Bool = true
    ) {
        self.maxRetries = max(0, maxRetries)
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableMethods = retryableMethods
        self.backoffStrategy = backoffStrategy
        self.retriesNetworkFailures = retriesNetworkFailures
    }

    /// Status codes retried by default: request timeout, rate limiting, and
    /// transient server failures.
    public static let defaultRetryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]

    /// Methods that can be repeated without changing the result twice.
    public static let idempotentMethods: Set<HTTPMethod> = [.get, .put, .delete]

    /// Three retries of idempotent requests, with exponential backoff.
    public static let `default` = RetryPolicy(maxRetries: 3)

    /// No retries: every request is attempted exactly once.
    public static let none = RetryPolicy(
        maxRetries: 0,
        retryableStatusCodes: [],
        retryableMethods: [],
        backoffStrategy: .none,
        retriesNetworkFailures: false
    )

    /// Whether `error` is worth repeating for a request using `method`.
    public func shouldRetry(_ error: LaravelError, method: HTTPMethod) -> Bool {
        guard maxRetries > 0, retryableMethods.contains(method) else { return false }

        if let statusCode = error.statusCode {
            return retryableStatusCodes.contains(statusCode)
        }
        switch error {
        case .timeout, .networkError:
            return retriesNetworkFailures
        default:
            // Decoding, encoding, and malformed-URL failures repeat identically.
            return false
        }
    }
}
