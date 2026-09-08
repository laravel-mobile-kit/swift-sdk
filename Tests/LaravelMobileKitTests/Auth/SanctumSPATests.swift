import Foundation
import Testing

import LaravelMobileKitAuth
import LaravelMobileKitCore

/// A cookie jar of its own, so these tests never touch the shared one.
private func makeCookieJar() -> HTTPCookieStorage {
    URLSessionConfiguration.ephemeral.httpCookieStorage ?? .shared
}

private func storeCSRFCookie(
    _ value: String,
    in jar: HTTPCookieStorage,
    named name: String = "XSRF-TOKEN",
    for url: URL
) {
    let cookie = HTTPCookie(properties: [
        .name: name,
        .value: value,
        .domain: url.host ?? "api.example.com",
        .path: "/",
    ])!
    jar.setCookie(cookie)
}

@Suite("Sanctum CSRF middleware")
struct SanctumCSRFMiddlewareTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func request(_ method: String, path: String = "/login") -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        return request
    }

    @Test("An unsafe request carries the token from the cookie")
    func unsafeRequestsCarryTheToken() async throws {
        let jar = makeCookieJar()
        storeCSRFCookie("token-value", in: jar, for: baseURL)
        let middleware = SanctumCSRFMiddleware(baseURL: baseURL, cookieStorage: jar)

        let processed = try await middleware.process(request("POST"))

        #expect(processed.value(forHTTPHeaderField: "X-XSRF-TOKEN") == "token-value")
    }

    @Test("Safe methods are left alone", arguments: ["GET", "HEAD", "OPTIONS"])
    func safeMethodsAreUntouched(method: String) async throws {
        let jar = makeCookieJar()
        storeCSRFCookie("token-value", in: jar, for: baseURL)
        let middleware = SanctumCSRFMiddleware(baseURL: baseURL, cookieStorage: jar)

        let processed = try await middleware.process(request(method))

        #expect(processed.value(forHTTPHeaderField: "X-XSRF-TOKEN") == nil)
    }

    @Test("The token is percent-decoded, as Laravel writes it encoded")
    func tokenIsDecoded() async throws {
        let jar = makeCookieJar()
        storeCSRFCookie("abc%3D%3D", in: jar, for: baseURL)
        let middleware = SanctumCSRFMiddleware(baseURL: baseURL, cookieStorage: jar)

        let processed = try await middleware.process(request("POST"))

        #expect(processed.value(forHTTPHeaderField: "X-XSRF-TOKEN") == "abc==")
    }

    @Test("Without the cookie the request is sent unchanged")
    func missingCookieIsNotAnError() async throws {
        let middleware = SanctumCSRFMiddleware(baseURL: baseURL, cookieStorage: makeCookieJar())

        let processed = try await middleware.process(request("POST"))

        #expect(processed.value(forHTTPHeaderField: "X-XSRF-TOKEN") == nil)
    }

    @Test("A header the caller set is not overwritten")
    func callerSuppliedHeaderWins() async throws {
        let jar = makeCookieJar()
        storeCSRFCookie("from-the-jar", in: jar, for: baseURL)
        let middleware = SanctumCSRFMiddleware(baseURL: baseURL, cookieStorage: jar)

        var outgoing = request("POST")
        outgoing.setValue("chosen-by-the-caller", forHTTPHeaderField: "X-XSRF-TOKEN")
        let processed = try await middleware.process(outgoing)

        #expect(processed.value(forHTTPHeaderField: "X-XSRF-TOKEN") == "chosen-by-the-caller")
    }

    @Test("The cookie and header names are configurable")
    func namesAreConfigurable() async throws {
        let jar = makeCookieJar()
        storeCSRFCookie("token-value", in: jar, named: "CSRF-COOKIE", for: baseURL)
        let middleware = SanctumCSRFMiddleware(
            baseURL: baseURL,
            cookieStorage: jar,
            cookieName: "CSRF-COOKIE",
            headerField: "X-CSRF-TOKEN"
        )

        let processed = try await middleware.process(request("POST"))

        #expect(processed.value(forHTTPHeaderField: "X-CSRF-TOKEN") == "token-value")
    }
}

@Suite("Sanctum SPA flows")
struct SanctumSPAAuthTests {
    let baseURL = URL(string: "https://api.example.com")!
    let userJSON = #"{"id":1,"name":"Ada"}"#

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("Signing in handshakes, posts the credentials, and loads the user")
    func loginPerformsTheWholeFlow() async throws {
        let transport = MockTransport(bodies: ["", "", userJSON])
        let auth = SanctumSPAAuth<AppUser>(client: makeClient(transport))

        let user = try await auth.login(email: "ada@example.com", password: "secret")

        #expect(user == AppUser(id: 1, name: "Ada"))
        let requests = await transport.executedRequests
        #expect(requests.count == 3)
        #expect(requests[0].url?.path == "/sanctum/csrf-cookie")
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[1].url?.path == "/login")
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[2].url?.path == "/api/user")

        let body = try #require(requests[1].httpBody)
        let fields = try JSONDecoder().decode([String: String].self, from: body)
        #expect(fields["email"] == "ada@example.com")
        #expect(fields["password"] == "secret")
    }

    @Test("Registration sends the fields exactly as written")
    func registrationSendsItsFields() async throws {
        let transport = MockTransport(bodies: ["", "", userJSON])
        let auth = SanctumSPAAuth<AppUser>(client: makeClient(transport))

        _ = try await auth.register(fields: [
            "name": "Ada",
            "email": "ada@example.com",
            "password": "secret-1234",
            "password_confirmation": "secret-1234",
        ])

        let requests = await transport.executedRequests
        #expect(requests[1].url?.path == "/register")
        let body = try #require(requests[1].httpBody)
        let fields = try JSONDecoder().decode([String: String].self, from: body)
        #expect(fields["password_confirmation"] == "secret-1234")
    }

    @Test("A rejected sign-in surfaces the server's error")
    func rejectedSignInThrows() async throws {
        let transport = MockTransport(statusCodes: [204, 422], json: #"{"message":"invalid"}"#)
        let auth = SanctumSPAAuth<AppUser>(client: makeClient(transport))

        do {
            _ = try await auth.login(email: "ada@example.com", password: "wrong")
            Issue.record("Expected the sign-in to fail")
        } catch let error as LaravelError {
            #expect(error.isValidationError)
        }
    }

    @Test("Endpoints are configurable")
    func endpointsAreConfigurable() async throws {
        let transport = MockTransport(bodies: ["", "", userJSON])
        let auth = SanctumSPAAuth<AppUser>(
            client: makeClient(transport),
            configuration: SanctumSPAConfiguration(
                csrfCookieEndpoint: "/csrf",
                loginEndpoint: "/api/session",
                userEndpoint: "/api/me"
            )
        )

        _ = try await auth.login(email: "ada@example.com", password: "secret")

        let requests = await transport.executedRequests
        #expect(requests.map { $0.url?.path } == ["/csrf", "/api/session", "/api/me"])
    }

    @Test("Signing out tells the server and settles the session")
    func logoutEndsTheSession() async throws {
        let transport = MockTransport(statusCode: 204)
        let client = makeClient(transport)
        let session = await SanctumSPASession<AppUser>(client: client)
        let auth = SanctumSPAAuth<AppUser>(client: client, session: session)
        await session.adopt(user: AppUser(id: 1, name: "Ada"))

        await auth.logout()

        #expect(await transport.executedRequests.contains { $0.url?.path == "/logout" })
        #expect(await session.state == .unauthenticated)
    }

    @Test("Signing out locally succeeds even when the server cannot be reached")
    func logoutSurvivesAnOfflineServer() async throws {
        let transport = MockTransport.alwaysFailing(with: LaravelError.timeout)
        let client = makeClient(transport)
        let session = await SanctumSPASession<AppUser>(client: client)
        let auth = SanctumSPAAuth<AppUser>(client: client, session: session)
        await session.adopt(user: AppUser(id: 1, name: "Ada"))

        await auth.logout()

        #expect(await session.state == .unauthenticated)
    }

    @Test("A password reset needs a configured endpoint")
    func passwordResetRequiresAnEndpoint() async throws {
        let transport = MockTransport(statusCode: 204)
        let auth = SanctumSPAAuth<AppUser>(
            client: makeClient(transport),
            configuration: SanctumSPAConfiguration(passwordResetEndpoint: nil)
        )

        await #expect(throws: AuthError.endpointNotConfigured("password reset")) {
            try await auth.requestPasswordReset(email: "ada@example.com")
        }
    }
}

@MainActor
@Suite("Sanctum SPA session")
struct SanctumSPASessionTests {
    let baseURL = URL(string: "https://api.example.com")!
    let userJSON = #"{"id":1,"name":"Ada"}"#

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("A cookie the server still honours restores the user")
    func restoreWithALiveCookie() async {
        let session = SanctumSPASession<AppUser>(client: makeClient(MockTransport(json: userJSON)))

        await session.restore()

        #expect(session.state == .authenticated(AppUser(id: 1, name: "Ada")))
        #expect(session.user?.name == "Ada")
    }

    @Test("A 401 means signed out")
    func restoreWithAnExpiredCookie() async {
        let session = SanctumSPASession<AppUser>(
            client: makeClient(MockTransport(statusCode: 401, json: #"{"message":"Unauthenticated."}"#))
        )

        await session.restore()

        #expect(session.state == .unauthenticated)
    }

    @Test("A server that cannot be reached leaves the session unverified")
    func restoreWhileOffline() async {
        let session = SanctumSPASession<AppUser>(
            client: makeClient(MockTransport.alwaysFailing(with: LaravelError.timeout))
        )

        await session.restore()

        #expect(session.state == .unverified)
        #expect(session.lastError != nil)
    }

    @Test("A wrapped user payload is read by a custom loader")
    func customUserLoader() async {
        let transport = MockTransport(json: #"{"data":{"id":2,"name":"Grace"}}"#)
        let session = SanctumSPASession<AppUser>(client: makeClient(transport)) { client in
            struct Envelope: Decodable { let data: AppUser }
            let envelope: Envelope = try await client.get("/api/me")
            return envelope.data
        }

        await session.restore()

        #expect(session.user == AppUser(id: 2, name: "Grace"))
    }

    @Test("Reloading keeps the state in step")
    func reloadUpdatesTheState() async throws {
        let transport = MockTransport(bodies: [userJSON, #"{"id":1,"name":"Ada Lovelace"}"#])
        let session = SanctumSPASession<AppUser>(client: makeClient(transport))

        await session.restore()
        let reloaded = try await session.reloadUser()

        #expect(reloaded.name == "Ada Lovelace")
        #expect(session.user?.name == "Ada Lovelace")
    }
}
