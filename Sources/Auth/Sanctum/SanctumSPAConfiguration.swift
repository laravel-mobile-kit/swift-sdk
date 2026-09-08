import Foundation

/// Where a Sanctum SPA session sends its requests.
///
/// The defaults are the routes `php artisan breeze:install api` publishes.
/// Unlike a token API, these endpoints usually sit outside `/api`: Laravel's
/// starter kit puts `/login` next to `/api/user`.
public struct SanctumSPAConfiguration: Sendable, Hashable {
    /// Issues the CSRF cookie the session starts with.
    public var csrfCookieEndpoint: String
    /// Exchanges credentials for a session cookie.
    public var loginEndpoint: String
    /// Creates an account and signs it in.
    public var registerEndpoint: String
    /// Ends the session server-side.
    public var logoutEndpoint: String
    /// Returns the authenticated user.
    public var userEndpoint: String
    /// Starts a password reset, when the API offers one.
    public var passwordResetEndpoint: String?
    /// Re-sends an email verification link, when the API offers one.
    public var emailVerificationEndpoint: String?

    public init(
        csrfCookieEndpoint: String = "/sanctum/csrf-cookie",
        loginEndpoint: String = "/login",
        registerEndpoint: String = "/register",
        logoutEndpoint: String = "/logout",
        userEndpoint: String = "/api/user",
        passwordResetEndpoint: String? = "/forgot-password",
        emailVerificationEndpoint: String? = "/email/verification-notification"
    ) {
        self.csrfCookieEndpoint = csrfCookieEndpoint
        self.loginEndpoint = loginEndpoint
        self.registerEndpoint = registerEndpoint
        self.logoutEndpoint = logoutEndpoint
        self.userEndpoint = userEndpoint
        self.passwordResetEndpoint = passwordResetEndpoint
        self.emailVerificationEndpoint = emailVerificationEndpoint
    }

    /// The routes Laravel's API starter kit publishes.
    public static let breeze = SanctumSPAConfiguration()
}
