import Foundation

/// Errors surfaced by the Core transport layer.
///
/// Every non-successful HTTP response arrives as ``httpError(_:)`` carrying the
/// untouched payload, rather than as a status-specific case: the body of a 401,
/// 404, or 422 is exactly what higher layers need to produce a good message.
/// Status inspection is available through ``HTTPError`` and the convenience
/// properties on this type.
public enum LaravelError: Error, LocalizedError {
    /// A request path could not be resolved against the client's base URL.
    case invalidURL(String)
    /// The transport failed before an HTTP response was produced.
    case networkError(underlying: any Error)
    /// The request exceeded the configured timeout.
    case timeout
    /// The request was cancelled before it completed.
    case cancelled
    /// The transport returned a response that was not an HTTP response.
    case invalidResponse
    /// The server answered with a non-successful status code.
    case httpError(HTTPError)
    /// A response body could not be decoded into the requested type.
    case decodingError(any Error, data: Data)
    /// A request body could not be encoded.
    case encodingError(any Error)

    // MARK: - Status inspection

    /// The underlying HTTP failure, when this error came from a response.
    public var httpError: HTTPError? {
        guard case let .httpError(error) = self else { return nil }
        return error
    }

    /// Status code of the failing response, when there was one.
    public var statusCode: Int? { httpError?.statusCode }

    /// Whether the request was rejected for missing or expired credentials.
    ///
    /// This is the signal the authentication layer uses to trigger a refresh.
    public var isUnauthorized: Bool { httpError?.isUnauthorized ?? false }
    /// Whether the request was rejected as forbidden (403).
    public var isForbidden: Bool { httpError?.isForbidden ?? false }
    /// Whether the resource does not exist (404).
    public var isNotFound: Bool { httpError?.isNotFound ?? false }
    /// Whether the payload failed validation (422).
    public var isValidationError: Bool { httpError?.isValidationError ?? false }
    /// Whether the server failed (5xx).
    public var isServerError: Bool { httpError?.isServerError ?? false }
    /// Whether the request exceeded its timeout.
    public var isTimeout: Bool {
        if case .timeout = self { return true }
        return false
    }
    /// Whether the request was cancelled.
    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(path):
            "Invalid URL: \(path)"
        case let .networkError(underlying):
            "Network error: \(underlying.localizedDescription)"
        case .timeout:
            "The request timed out"
        case .cancelled:
            "The request was cancelled"
        case .invalidResponse:
            "The server returned a response that was not an HTTP response"
        case let .httpError(error):
            error.errorDescription
        case let .decodingError(underlying, _):
            "Failed to decode the response: \(underlying.localizedDescription)"
        case let .encodingError(underlying):
            "Failed to encode the request body: \(underlying.localizedDescription)"
        }
    }
}

extension LaravelError {
    /// Classifies a failure raised by a transport before any response arrived.
    ///
    /// Timeouts and cancellation are common enough — and handled differently
    /// enough by callers — to deserve their own cases rather than hiding inside
    /// a generic network error.
    init(transportFailure error: any Error) {
        if error is CancellationError {
            self = .cancelled
            return
        }
        guard let urlError = error as? URLError else {
            self = .networkError(underlying: error)
            return
        }

        switch urlError.code {
        case .timedOut: self = .timeout
        case .cancelled: self = .cancelled
        default: self = .networkError(underlying: urlError)
        }
    }
}
