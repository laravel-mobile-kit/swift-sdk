import Foundation
import Testing

import LaravelMobileKit

/// Where the Breeze starter-kit fixture is served from.
///
/// This is a second fixture on purpose: `TestApp/` exercises endpoints we wrote,
/// while `TestApp/.breeze` runs the routes, controllers, and form requests that
/// `php artisan breeze:install api` generates. Nothing in it is ours, and its
/// authentication contract is a different one — Sanctum's cookie-based SPA
/// session rather than bearer tokens.
enum StarterKitEnvironment {
    static let variableName = "LARAVEL_BREEZE_URL"

    static let baseURL: URL? = ProcessInfo.processInfo.environment[variableName]
        .flatMap(URL.init(string:))

    static var isConfigured: Bool { baseURL != nil }

    static var url: URL {
        guard let baseURL else {
            preconditionFailure("Set \(variableName) to run the starter-kit suite")
        }
        return baseURL
    }

    /// The account the stock `DatabaseSeeder` creates.
    static let seededEmail = "test@example.com"
    static let seededPassword = "password"

    static func unusedEmail(_ label: String) -> String {
        "\(label)-\(UUID().uuidString.prefix(8).lowercased())@example.com"
    }
}

/// Sends the CSRF token Sanctum's SPA guard expects.
///
/// Laravel writes the token into an `XSRF-TOKEN` cookie and reads it back from
/// an `X-XSRF-TOKEN` header. The value is re-read from the cookie jar on every
/// request because the session — and with it the token — is regenerated on
/// sign-in and sign-out.
///
/// This lives in the test suite rather than in the kit: the SDK's middleware
/// seam is what is being tested here, and this is the whole of what an app has
/// to write to talk to a stock Breeze API.
struct SanctumCSRFMiddleware: Middleware {
    let cookieStorage: HTTPCookieStorage
    let baseURL: URL

    func process(_ request: URLRequest) async throws -> URLRequest {
        guard request.httpMethod != "GET", request.httpMethod != "HEAD" else { return request }

        guard let cookies = cookieStorage.cookies(for: baseURL),
              let token = cookies.first(where: { $0.name == "XSRF-TOKEN" })?.value
        else {
            return request
        }

        var request = request
        request.setValue(
            token.removingPercentEncoding ?? token,
            forHTTPHeaderField: "X-XSRF-TOKEN"
        )
        return request
    }
}

/// The user Breeze's `/api/user` route returns.
struct BreezeUser: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let email: String
    let emailVerifiedAt: Date?
    let createdAt: Date?
}

struct PasswordResetStatus: Codable, Sendable {
    let status: String
}

@Suite(
    "Laravel starter kit (Breeze API)",
    .enabled(if: StarterKitEnvironment.isConfigured),
    .serialized
)
struct StarterKitIntegrationTests {
    /// A client with its own cookie jar, so each test gets its own session.
    private func makeClient() -> (client: LaravelClient, cookies: HTTPCookieStorage) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieAcceptPolicy = .always
        sessionConfiguration.httpShouldSetCookies = true
        let cookies = sessionConfiguration.httpCookieStorage ?? .shared

        let client = LaravelClient(
            configuration: LaravelClientConfiguration(
                baseURL: StarterKitEnvironment.url,
                defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders.merging([
                    // Sanctum only treats a request as stateful when it comes
                    // from a domain it was told about.
                    "Referer": StarterKitEnvironment.url.absoluteString
                ]) { _, new in new },
                retryPolicy: .none
            ),
            transport: URLSessionTransport(configuration: sessionConfiguration)
        )

        return (client, cookies)
    }

    /// The handshake every Sanctum SPA performs before its first write.
    private func startSession(_ client: LaravelClient, cookies: HTTPCookieStorage) async throws {
        await client.use(.validationErrors)
        await client.use(
            SanctumCSRFMiddleware(cookieStorage: cookies, baseURL: StarterKitEnvironment.url)
        )
        _ = try await client.raw(.get, "/sanctum/csrf-cookie")
    }

    private func signIn(_ client: LaravelClient) async throws {
        let _: EmptyResponse = try await client.post(
            "/login",
            body: [
                "email": StarterKitEnvironment.seededEmail,
                "password": StarterKitEnvironment.seededPassword,
            ]
        )
    }

    @Test("Signing in against Breeze's own controller establishes a session")
    func cookieSessionSignIn() async throws {
        let (client, cookies) = makeClient()
        try await startSession(client, cookies: cookies)

        try await signIn(client)
        let user: BreezeUser = try await client.get("/api/user")

        #expect(user.email == StarterKitEnvironment.seededEmail)
        #expect(user.createdAt != nil)
        // The starter kit issues no token at all: the session is the cookie.
        #expect(cookies.cookies(for: StarterKitEnvironment.url)?
            .contains { $0.name.hasPrefix("laravel") || $0.name.hasSuffix("_session") } == true)
    }

    @Test("Without a session the API refuses the request")
    func unauthenticatedRequestIsRefused() async throws {
        let (client, cookies) = makeClient()
        try await startSession(client, cookies: cookies)

        do {
            let _: BreezeUser = try await client.get("/api/user")
            Issue.record("Expected the request to be refused")
        } catch let error as LaravelError {
            #expect(error.isUnauthorized)
        }
    }

    @Test("Breeze's login failure arrives as a structured validation error")
    func wrongPasswordIsAValidationError() async throws {
        let (client, cookies) = makeClient()
        try await startSession(client, cookies: cookies)

        do {
            let _: EmptyResponse = try await client.post(
                "/login",
                body: ["email": StarterKitEnvironment.seededEmail, "password": "not-the-password"]
            )
            Issue.record("Expected the sign-in to fail")
        } catch let error as LaravelValidationError {
            #expect(error.statusCode == 422)
            #expect(error.hasError(for: "email"))
        }
    }

    @Test("Registration through the starter kit's controller signs the account in")
    func registrationEstablishesASession() async throws {
        let (client, cookies) = makeClient()
        try await startSession(client, cookies: cookies)
        let email = StarterKitEnvironment.unusedEmail("breeze")

        let _: EmptyResponse = try await client.post(
            "/register",
            body: [
                "name": "Starter Kit Registrant",
                "email": email,
                "password": "password-1234",
                "password_confirmation": "password-1234",
            ]
        )

        let user: BreezeUser = try await client.get("/api/user")
        #expect(user.email == email)
    }

    @Test("The starter kit's own validation rules surface field by field")
    func registrationValidationIsStructured() async throws {
        let (client, cookies) = makeClient()
        try await startSession(client, cookies: cookies)

        do {
            let _: EmptyResponse = try await client.post(
                "/register",
                body: [
                    "name": "",
                    "email": "not-an-email",
                    "password": "short",
                    "password_confirmation": "different",
                ]
            )
            Issue.record("Expected the registration to fail validation")
        } catch let error as LaravelValidationError {
            #expect(error.hasError(for: "name"))
            #expect(error.hasError(for: "email"))
            #expect(error.hasError(for: "password"))
        }
    }

    @Test("Signing out ends the session")
    func signOutEndsTheSession() async throws {
        let (client, cookies) = makeClient()
        try await startSession(client, cookies: cookies)
        try await signIn(client)

        let _: EmptyResponse = try await client.post("/logout", body: Optional<String>.none)

        do {
            let _: BreezeUser = try await client.get("/api/user")
            Issue.record("Expected the session to be over")
        } catch let error as LaravelError {
            #expect(error.isUnauthorized)
        }
    }

    @Test("A password reset request reaches the starter kit's endpoint")
    func passwordResetIsRequested() async throws {
        let (client, cookies) = makeClient()
        try await startSession(client, cookies: cookies)

        let status: PasswordResetStatus = try await client.post(
            "/forgot-password",
            body: ["email": StarterKitEnvironment.seededEmail]
        )

        #expect(!status.status.isEmpty)
    }
}
