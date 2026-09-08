import Foundation

/// Runs `operation`, failing with ``LaravelError/timeout`` if it takes longer
/// than `seconds`.
///
/// The timeout is enforced here rather than left to `URLRequest.timeoutInterval`
/// alone, so it applies to every transport — including the ones tests and apps
/// substitute for `URLSession`.
func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    guard seconds > 0 else { return try await operation() }

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw LaravelError.timeout
        }

        defer { group.cancelAll() }
        // The group always has two children, so `next()` cannot return nil here.
        return try await group.next()!
    }
}

/// Throws ``LaravelError/cancelled`` if the surrounding task was cancelled.
func checkCancellation() throws {
    if Task.isCancelled { throw LaravelError.cancelled }
}
