import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LaravelClient {
    /// How many times deciders may retry one request.
    ///
    /// A safety net: recovery is meant to fix something once — refresh a token,
    /// wait out a limit — so a decider that keeps saying "try again" is a bug,
    /// not a workload.
    static let maxRecoveryRetries = 3

    /// Sends a request, repeating it while the configured policy says the
    /// failure is transient, or a decider says it has fixed the cause.
    ///
    /// Retries wrap transport and status validation only: a payload that fails
    /// to decode would fail identically on the next attempt. Each attempt is
    /// rebuilt from the original ``Request``, so headers and middleware run
    /// again — that is how a retry after a token refresh carries the new token.
    /// A retried upload reports its progress from zero again, because the body
    /// really is sent again.
    func executeWithRetry(
        _ request: Request,
        uploadProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let policy = configuration.retryPolicy
        var policyAttempt = 0
        var recoveryAttempt = 0

        while true {
            try checkCancellation()
            do {
                let (data, response) = try await send(request, uploadProgress: uploadProgress)
                try validateHTTPStatus(response, data: data)
                return (data, response)
            } catch let error as LaravelError {
                // A nil wait is the policy declining the retry outright — the
                // server asked to be left alone for longer than this client
                // will wait, and shortening that is not ours to decide.
                if policyAttempt < policy.maxRetries,
                   policy.shouldRetry(error, method: request.method),
                   let wait = policy.wait(forAttempt: policyAttempt, after: error) {
                    try await backOff(wait)
                    policyAttempt += 1
                    continue
                }

                guard recoveryAttempt < Self.maxRecoveryRetries,
                      try await shouldRecover(from: error, request: request, attempt: recoveryAttempt)
                else {
                    throw error
                }
                recoveryAttempt += 1
            }
        }
    }

    /// Asks each decider, in order, whether the request can be sent again.
    private func shouldRecover(
        from error: LaravelError,
        request: Request,
        attempt: Int
    ) async throws -> Bool {
        for decider in retryDeciders {
            if try await decider.shouldRetry(error, request: request, attempt: attempt) {
                return true
            }
        }
        return false
    }

    /// Waits between attempts, reporting cancellation as ``LaravelError/cancelled``.
    private func backOff(_ delay: TimeInterval) async throws {
        guard delay > 0 else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            throw LaravelError.cancelled
        }
    }
}
