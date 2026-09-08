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

@MainActor
@Suite(
    "Laravel starter kit (Breeze API)",
    .enabled(if: StarterKitEnvironment.isConfigured),
    .serialized
)
struct StarterKitIntegrationTests {
    /// One app's worth of wiring, against a cookie jar of its own so tests do
    /// not share a session.
    private struct SPAStack {
        let client: LaravelClient
        let auth: SanctumSPAAuth<BreezeUser>
        let session: SanctumSPASession<BreezeUser>
        let cookies: HTTPCookieStorage
    }

    private func makeStack(
        cookies: HTTPCookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage ?? .shared
    ) async -> SPAStack {
        let client = await LaravelClient.sanctumSPA(
            baseURL: StarterKitEnvironment.url,
            cookieStorage: cookies,
            retryPolicy: .none
        )
        await client.use(.validationErrors)

        let session = SanctumSPASession<BreezeUser>(client: client)
        let auth = SanctumSPAAuth<BreezeUser>(client: client, session: session)

        return SPAStack(client: client, auth: auth, session: session, cookies: cookies)
    }

    @Test("Signing in against Breeze's own controller establishes a session")
    func cookieSessionSignIn() async throws {
        let stack = await makeStack()

        let user = try await stack.auth.login(
            email: StarterKitEnvironment.seededEmail,
            password: StarterKitEnvironment.seededPassword
        )

        #expect(user.email == StarterKitEnvironment.seededEmail)
        #expect(user.createdAt != nil)
        #expect(stack.session.state.isAuthenticated)
        // The starter kit issues no token at all: the session is the cookie.
        // Laravel names it after the app — `laravel-session` by default — so
        // the assertion is on the kind of cookie, not on an exact name.
        let cookies = stack.cookies.cookies(for: StarterKitEnvironment.url) ?? []
        #expect(cookies.contains { $0.name.lowercased().contains("session") })
        #expect(cookies.contains { $0.name == "XSRF-TOKEN" })
    }

    @Test("Without a session the API refuses the request")
    func unauthenticatedRequestIsRefused() async throws {
        let stack = await makeStack()

        await stack.session.restore()

        #expect(stack.session.state == .unauthenticated)
    }

    @Test("A session cookie is restored on the next launch")
    func sessionSurvivesARelaunch() async throws {
        // A jar shared between two clients is what a persistent cookie store
        // looks like from the app's point of view.
        let jar = URLSessionConfiguration.ephemeral.httpCookieStorage ?? .shared
        let firstLaunch = await makeStack(cookies: jar)
        try await firstLaunch.auth.login(
            email: StarterKitEnvironment.seededEmail,
            password: StarterKitEnvironment.seededPassword
        )

        let relaunch = await makeStack(cookies: jar)
        await relaunch.session.restore()

        #expect(relaunch.session.state.isAuthenticated)
        #expect(relaunch.session.user?.email == StarterKitEnvironment.seededEmail)
    }

    @Test("Breeze's login failure arrives as a structured validation error")
    func wrongPasswordIsAValidationError() async throws {
        let stack = await makeStack()

        do {
            _ = try await stack.auth.login(
                email: StarterKitEnvironment.seededEmail,
                password: "not-the-password"
            )
            Issue.record("Expected the sign-in to fail")
        } catch let error as LaravelValidationError {
            #expect(error.statusCode == 422)
            #expect(error.hasError(for: "email"))
        }
    }

    @Test("Registration through the starter kit's controller signs the account in")
    func registrationEstablishesASession() async throws {
        let stack = await makeStack()
        let email = StarterKitEnvironment.unusedEmail("breeze")

        let user = try await stack.auth.register(fields: [
            "name": "Starter Kit Registrant",
            "email": email,
            "password": "password-1234",
            "password_confirmation": "password-1234",
        ])

        #expect(user.email == email)
        #expect(stack.session.user?.email == email)
    }

    @Test("The starter kit's own validation rules surface field by field")
    func registrationValidationIsStructured() async throws {
        let stack = await makeStack()

        do {
            _ = try await stack.auth.register(fields: [
                "name": "",
                "email": "not-an-email",
                "password": "short",
                "password_confirmation": "different",
            ])
            Issue.record("Expected the registration to fail validation")
        } catch let error as LaravelValidationError {
            #expect(error.hasError(for: "name"))
            #expect(error.hasError(for: "email"))
            #expect(error.hasError(for: "password"))
        }
    }

    @Test("Signing out ends the session")
    func signOutEndsTheSession() async throws {
        let stack = await makeStack()
        try await stack.auth.login(
            email: StarterKitEnvironment.seededEmail,
            password: StarterKitEnvironment.seededPassword
        )

        await stack.auth.logout()

        #expect(stack.session.state == .unauthenticated)
        await stack.session.restore()
        #expect(stack.session.state == .unauthenticated)
    }

    @Test("A password reset request reaches the starter kit's endpoint")
    func passwordResetIsRequested() async throws {
        // Laravel throttles reset links per account, so this runs against an
        // account created for this test rather than the seeded one.
        let email = StarterKitEnvironment.unusedEmail("reset")
        let registrar = await makeStack()
        _ = try await registrar.auth.register(fields: [
            "name": "Reset Requester",
            "email": email,
            "password": "password-1234",
            "password_confirmation": "password-1234",
        ])

        // The endpoint is for guests, so the request comes from a signed-out
        // client with a cookie jar of its own.
        let guest = await makeStack()
        try await guest.auth.requestPasswordReset(email: email)
    }

    @Test("The raw client still works for anything the flows do not cover")
    func rawRequestsRemainAvailable() async throws {
        let stack = await makeStack()
        try await stack.auth.login(
            email: StarterKitEnvironment.seededEmail,
            password: StarterKitEnvironment.seededPassword
        )

        let response = try await stack.client.raw(.get, "/api/user")
        let payload = try JSONSerialization.jsonObject(with: response.rawData) as? [String: Any]

        #expect(response.statusCode == 200)
        #expect(payload?["email"] as? String == StarterKitEnvironment.seededEmail)
    }
}
