import Foundation

/// Where the authentication flows send their requests.
///
/// Every path is configurable because the kit refuses to dictate an application
/// contract: an existing Laravel API keeps its own routes, and the app points
/// the kit at them.
///
/// Auth endpoints are used exactly as written and never inherit an API version
/// prefix — Laravel apps routinely expose `/api/login` next to `/api/v1/events`.
public struct AuthConfiguration: Sendable, Hashable {
    /// Exchanges credentials for a token.
    public var loginEndpoint: String
    /// Creates an account.
    public var registerEndpoint: String
    /// Revokes the current token server-side.
    public var logoutEndpoint: String
    /// Returns the authenticated user.
    public var userEndpoint: String
    /// Exchanges a refresh token for a new access token.
    public var refreshEndpoint: String
    /// Starts a password reset, when the API offers one.
    public var passwordResetEndpoint: String?
    /// Re-sends an email verification link, when the API offers one.
    public var emailVerificationEndpoint: String?

    public init(
        loginEndpoint: String = "/api/login",
        registerEndpoint: String = "/api/register",
        logoutEndpoint: String = "/api/logout",
        userEndpoint: String = "/api/user",
        refreshEndpoint: String = "/api/auth/refresh",
        passwordResetEndpoint: String? = "/api/forgot-password",
        emailVerificationEndpoint: String? = "/api/email/verification-notification"
    ) {
        self.loginEndpoint = loginEndpoint
        self.registerEndpoint = registerEndpoint
        self.logoutEndpoint = logoutEndpoint
        self.userEndpoint = userEndpoint
        self.refreshEndpoint = refreshEndpoint
        self.passwordResetEndpoint = passwordResetEndpoint
        self.emailVerificationEndpoint = emailVerificationEndpoint
    }

    /// The routes a stock Laravel application exposes.
    public static let laravel = AuthConfiguration()

    /// Every configured path.
    ///
    /// API versioning uses this to leave authentication routes alone.
    public var allEndpoints: Set<String> {
        var endpoints: Set<String> = [
            loginEndpoint,
            registerEndpoint,
            logoutEndpoint,
            userEndpoint,
            refreshEndpoint,
        ]
        if let passwordResetEndpoint { endpoints.insert(passwordResetEndpoint) }
        if let emailVerificationEndpoint { endpoints.insert(emailVerificationEndpoint) }
        return endpoints
    }
}
