import Foundation

/// Errors raised by the authentication layer.
public enum AuthError: Error, LocalizedError, Hashable {
    /// No credential is stored, so the operation has nothing to work with.
    case notAuthenticated
    /// The provider cannot obtain a fresh token — it has no refresh token, or
    /// the API issues none.
    case refreshNotSupported
    /// The stored credential carries no refresh token, so it cannot be renewed.
    case noRefreshToken
    /// The credential was rejected and could not be renewed: the user has to
    /// sign in again.
    case sessionExpired
    /// The flow needs an endpoint the configuration leaves unset.
    case endpointNotConfigured(String)
    /// The API answered with something that carries no usable token.
    case invalidAuthResponse

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "No stored credential: the user is signed out"
        case .refreshNotSupported:
            "This token provider cannot refresh its token"
        case .noRefreshToken:
            "The stored credential has no refresh token"
        case .sessionExpired:
            "The session expired and could not be renewed"
        case let .endpointNotConfigured(name):
            "No \(name) endpoint is configured"
        case .invalidAuthResponse:
            "The authentication response contained no token"
        }
    }
}
