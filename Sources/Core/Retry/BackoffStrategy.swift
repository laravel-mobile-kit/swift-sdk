import Foundation

/// How long to wait between retry attempts.
public enum BackoffStrategy: Sendable, Hashable {
    /// Retry immediately.
    case none
    /// Wait the same amount of time before every retry.
    case constant(delay: TimeInterval)
    /// Double the wait after each attempt, up to `maxDelay`.
    case exponential(base: TimeInterval, maxDelay: TimeInterval)

    /// Delay before the retry following `attempt`, counted from zero.
    public func delay(for attempt: Int) -> TimeInterval {
        switch self {
        case .none:
            0
        case let .constant(delay):
            max(0, delay)
        case let .exponential(base, maxDelay):
            min(max(0, base) * pow(2, Double(max(0, attempt))), maxDelay)
        }
    }
}
