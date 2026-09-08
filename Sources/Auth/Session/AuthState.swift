import Foundation

/// What the app knows about the current session.
///
/// The state is deliberately explicit about "not known yet" and "could not be
/// checked": an app that is merely offline must not be told the user is signed
/// out, because that would discard a perfectly valid credential.
public enum AuthState<User: Sendable>: Sendable {
    /// Nothing has been checked yet — the state before ``AuthSession/restore()``.
    case unknown
    /// A stored credential is being restored or refreshed.
    case restoring
    /// No usable credential: the user must sign in.
    case unauthenticated
    /// A credential was verified and belongs to `user`.
    case authenticated(User)
    /// A credential exists but could not be verified — the network failed, or
    /// the server did not answer. The credential is kept so a retry can succeed.
    case unverified

    /// The signed-in user, when there is one.
    public var user: User? {
        guard case let .authenticated(user) = self else { return nil }
        return user
    }

    /// Whether a verified credential is in place.
    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    /// Whether the session is still working out where it stands.
    public var isSettled: Bool {
        switch self {
        case .unknown, .restoring: false
        case .unauthenticated, .authenticated, .unverified: true
        }
    }
}

extension AuthState: Equatable where User: Equatable {}
