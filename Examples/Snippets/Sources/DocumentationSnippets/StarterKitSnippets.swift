import Foundation

import LaravelMobileKit

/// Examples from the "Cookie sessions" section of `AUTHENTICATION.md`.
enum StarterKitSnippets {
    @MainActor
    static func wireUp() async -> (LaravelClient, SanctumSPAAuth<AppUser>, SanctumSPASession<AppUser>) {
        let client = await LaravelClient.sanctumSPA(baseURL: baseURL)
        await client.use(.validationErrors)

        let session = SanctumSPASession<AppUser>(client: client)
        let auth = SanctumSPAAuth<AppUser>(client: client, session: session)

        return (client, auth, session)
    }

    @MainActor
    static func flows(email: String, password: String, name: String) async throws {
        let (_, auth, session) = await wireUp()

        try await auth.login(email: email, password: password)
        _ = try await auth.register(fields: [
            "name": name,
            "email": email,
            "password": password,
            "password_confirmation": password,
        ])
        _ = try await auth.currentUser()
        try await auth.requestPasswordReset(email: email)
        await auth.logout()

        await session.restore()
        _ = session.user
    }

    static func cookieJars() async -> (LaravelClient, LaravelClient) {
        // Persistent — a returning user is still signed in.
        let client = await LaravelClient.sanctumSPA(baseURL: baseURL)

        // Private and in-memory — what tests and previews want.
        let jar = URLSessionConfiguration.ephemeral.httpCookieStorage!
        let isolated = await LaravelClient.sanctumSPA(baseURL: baseURL, cookieStorage: jar)

        return (client, isolated)
    }

    static func customRoutes(client: LaravelClient) -> SanctumSPAAuth<AppUser> {
        SanctumSPAAuth<AppUser>(
            client: client,
            configuration: SanctumSPAConfiguration(
                csrfCookieEndpoint: "/sanctum/csrf-cookie",
                loginEndpoint: "/api/session",
                registerEndpoint: "/api/accounts",
                logoutEndpoint: "/api/session/end",
                userEndpoint: "/api/me"
            )
        )
    }

    static func middlewareOnItsOwn(client: LaravelClient) async {
        await client.use(.sanctumCSRF(baseURL: baseURL, cookieStorage: .shared))
    }
}
