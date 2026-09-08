import Foundation

/// Decides whether a failed request is worth repeating, after doing whatever
/// makes the repeat meaningful.
///
/// ``RetryPolicy`` handles failures that pass on their own — a 503, a dropped
/// connection. A decider handles failures that need something to *change*
/// first: refreshing an expired token is the case the kit ships, but re-signing
/// a request or waiting out a rate limit fit the same shape.
///
/// Core stays generic: it knows only that something may have been fixed and the
/// request can be sent again. The retried request is rebuilt from scratch, so
/// middleware runs again and picks up whatever the decider changed.
public protocol RetryDecider: Sendable {
    /// Whether to send `request` again.
    ///
    /// - Parameters:
    ///   - error: Why the attempt failed.
    ///   - request: The request that failed.
    ///   - attempt: How many times a decider has already retried this request,
    ///     starting at zero. Use it to allow exactly one recovery attempt.
    /// - Returns: `true` to send the request again.
    /// - Throws: To fail the request with a more meaningful error than the one
    ///   the server returned — a session that cannot be renewed, say.
    func shouldRetry(_ error: LaravelError, request: Request, attempt: Int) async throws -> Bool
}
