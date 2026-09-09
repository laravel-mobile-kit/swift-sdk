import Foundation

/// Describes which failures are retried, for which methods, and how long the
/// client waits in between.
///
/// `POST` is deliberately absent from ``default``: it is not idempotent, so a
/// retried create can produce a duplicate record.
///
/// There are two ways to retry one anyway, and they are not equivalent. Adding
/// `.post` to ``retryableMethods`` asserts that every `POST` this client sends
/// is safe to repeat, which is rarely true. Setting
/// ``RequestOptions/idempotencyKey`` asserts it for one request, and gives the
/// server what it needs to make it true. Prefer the second.
public struct RetryPolicy: Sendable, Hashable {
    /// How a computed wait is randomised.
    public enum Jitter: Sendable, Hashable {
        /// Wait exactly what the backoff strategy computed.
        case none
        /// Wait a random duration in `0 ... delay`.
        ///
        /// Clients that fail together retry together: a server that drops
        /// requests for a second gets every one of them back at the same
        /// instant, having done nothing to reduce the load that caused it.
        /// Spreading the waits is what stops a recovery from re-creating the
        /// outage.
        case full
    }

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
    /// How the computed delay is randomised.
    public var jitter: Jitter
    /// The longest `Retry-After` this client is willing to honour.
    ///
    /// A server asking for longer than this ends the retries rather than being
    /// quietly ignored: waiting less than asked is what the header exists to
    /// prevent, and sleeping for an unbounded interval hands a broken or
    /// hostile server control of the client.
    public var maximumRetryAfter: TimeInterval

    public init(
        maxRetries: Int,
        retryableStatusCodes: Set<Int> = RetryPolicy.defaultRetryableStatusCodes,
        retryableMethods: Set<HTTPMethod> = RetryPolicy.idempotentMethods,
        backoffStrategy: BackoffStrategy = .exponential(base: 0.5, maxDelay: 30),
        retriesNetworkFailures: Bool = true,
        jitter: Jitter = .full,
        maximumRetryAfter: TimeInterval = 60
    ) {
        self.maxRetries = max(0, maxRetries)
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableMethods = retryableMethods
        self.backoffStrategy = backoffStrategy
        self.retriesNetworkFailures = retriesNetworkFailures
        self.jitter = jitter
        self.maximumRetryAfter = max(0, maximumRetryAfter)
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

    /// How long to wait before the retry following `attempt`.
    ///
    /// A `Retry-After` header wins over the backoff schedule, and is honoured
    /// exactly rather than jittered — jitter can only shorten a wait, and
    /// waiting less than the server asked for is the failure this header exists
    /// to prevent.
    ///
    /// - Returns: The wait, or `nil` when the server asked for longer than
    ///   ``maximumRetryAfter`` and the request should therefore fail now.
    public func wait(
        forAttempt attempt: Int,
        after error: LaravelError,
        now: Date = Date()
    ) -> TimeInterval? {
        if let response = error.httpError?.response,
           let requested = RetryAfter.seconds(from: response, now: now) {
            return requested <= maximumRetryAfter ? requested : nil
        }
        return jittered(backoffStrategy.delay(for: attempt))
    }

    /// Applies ``jitter`` to a computed delay.
    private func jittered(_ delay: TimeInterval) -> TimeInterval {
        switch jitter {
        case .none:
            delay
        case .full:
            delay > 0 ? TimeInterval.random(in: 0 ... delay) : 0
        }
    }

    /// Whether `error` is worth repeating for `request`.
    ///
    /// A request carrying an idempotency key is retryable whatever its method.
    /// That is the entire trade `POST` is excluded from ``idempotentMethods``
    /// for: repeating a create may make a second record, unless the caller has
    /// told the server how to recognise the repeat.
    public func shouldRetry(_ error: LaravelError, request: Request) -> Bool {
        guard maxRetries > 0 else { return false }
        guard request.idempotencyKey != nil || retryableMethods.contains(request.method) else {
            return false
        }
        return isTransient(error)
    }

    /// Whether `error` is worth repeating for a request using `method`.
    public func shouldRetry(_ error: LaravelError, method: HTTPMethod) -> Bool {
        guard maxRetries > 0, retryableMethods.contains(method) else { return false }
        return isTransient(error)
    }

    /// Whether the failure itself is one that repeating could fix.
    private func isTransient(_ error: LaravelError) -> Bool {
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
