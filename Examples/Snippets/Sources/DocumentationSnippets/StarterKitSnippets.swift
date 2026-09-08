import Foundation

import LaravelMobileKit

/// The cookie-session middleware printed in `Documentation/AUTHENTICATION.md`.
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
        request.setValue(token.removingPercentEncoding ?? token, forHTTPHeaderField: "X-XSRF-TOKEN")
        return request
    }
}

/// Examples from the "Cookie sessions" section of `AUTHENTICATION.md`.
enum StarterKitSnippets {
    static func makeCookieClient() -> (LaravelClient, HTTPCookieStorage) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpShouldSetCookies = true
        let cookies = sessionConfiguration.httpCookieStorage ?? .shared

        let client = LaravelClient(
            configuration: LaravelClientConfiguration(
                baseURL: baseURL,
                defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders
                    .merging(["Referer": baseURL.absoluteString]) { _, new in new }
            ),
            transport: URLSessionTransport(configuration: sessionConfiguration)
        )

        return (client, cookies)
    }

    static func signIn(email: String, password: String) async throws -> AppUser {
        let (client, cookies) = makeCookieClient()
        await client.use(SanctumCSRFMiddleware(cookieStorage: cookies, baseURL: baseURL))

        _ = try await client.raw(.get, "/sanctum/csrf-cookie")
        let _: EmptyResponse = try await client.post(
            "/login",
            body: ["email": email, "password": password]
        )
        let user: AppUser = try await client.get("/api/user")
        let _: EmptyResponse = try await client.post("/logout", body: Optional<String>.none)

        return user
    }
}
