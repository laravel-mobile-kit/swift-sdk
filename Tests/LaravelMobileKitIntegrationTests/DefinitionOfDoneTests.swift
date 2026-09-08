import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    /// The MVP acceptance suite.
    ///
    /// One test per item of the Definition of Done checklist (§25 of the
    /// specification), named after the item it accepts. The other integration
    /// suites test each capability in depth; this one answers a single
    /// question — is the MVP done? — and the mapping from checklist item to
    /// test is in `Documentation/DEFINITION_OF_DONE.md`.
    ///
    /// Checklist items about the repository itself — that the tests, the
    /// compatibility matrix, and the quick-start example exist — are accepted
    /// by `DefinitionOfDoneDocumentationTests` in the unit target, so they run
    /// without a fixture.
    @MainActor
    @Suite("Definition of Done")
    struct DefinitionOfDoneTests {
        // MARK: 1. A developer can point the SDK at an existing Laravel REST API

        @Test("1. The SDK works against an existing Laravel API given only its base URL")
        func pointAtAnExistingAPI() async throws {
            let client = LaravelClient(baseURL: IntegrationEnvironment.url)

            let page: Page<APIEvent> = try await client.page("/api/events")

            #expect(!page.items.isEmpty)
        }

        // MARK: 2. No backend package is required for Core functionality

        @Test("2. No server-side package is involved: the fixture is a stock Laravel app")
        func noBackendPackageRequired() async throws {
            // Nothing in the request identifies the kit, and the fixture runs
            // an unmodified Laravel install with ordinary routes.
            let client = await IntegrationHarness.makeClient(version: .none)

            let echo: EchoedRequest = try await client.get("/api/echo")

            #expect(echo.header("Accept") == "application/json")
            #expect(echo.headers.keys.allSatisfy { !$0.lowercased().contains("mobile-kit") })
        }

        // MARK: 3. Unversioned and /v1 path-versioned APIs work

        @Test("3. Both an unversioned and a /v1 API are reachable")
        func versionedAndUnversionedAPIs() async throws {
            let unversioned = await IntegrationHarness.makeClient(version: .none)
            let versioned = await IntegrationHarness.makeClient(version: .v1)

            let fromRoot: ServedVersion = try await unversioned.get("/api/version")
            let fromV1: ServedVersion = try await versioned.get("/api/version")

            #expect(fromRoot.version == "none")
            #expect(fromV1.version == "v1")
        }

        // MARK: 4. Auth endpoints can have a different URL structure

        @Test("4. Authentication keeps its own URL structure under a versioned client")
        func authEndpointsKeepTheirStructure() async throws {
            let stack = await IntegrationHarness.makeAuthStack(version: .v1)

            // /api/login is never rewritten to /api/v1/login …
            try await stack.login()
            // … while business endpoints are.
            let page: Page<APIEvent> = try await stack.client.page("/api/events")

            #expect(try await stack.auth.currentUser().email == IntegrationEnvironment.seededEmail)
            #expect(!page.items.isEmpty)
        }

        // MARK: 5. Credentials are securely stored in the Keychain

        @Test(
            "5. The issued credential is stored in the Keychain",
            .enabled(if: KeychainAvailability.isAvailable)
        )
        func credentialsAreStoredInTheKeychain() async throws {
            let service = "com.laravelmobilekit.dod"
            let account = "credentials-\(UUID().uuidString)"
            let keychain = KeychainCredentialStore(
                service: service,
                account: account,
                usesDataProtectionKeychain: KeychainAvailability.usesDataProtection
            )
            let stack = await IntegrationHarness.makeAuthStack(store: keychain)

            let result = try await stack.login()

            // Read through a second store object: what is asserted is that the
            // token is in the Keychain, not in this process's memory.
            let reader = KeychainCredentialStore(
                service: service,
                account: account,
                usesDataProtectionKeychain: KeychainAvailability.usesDataProtection
            )
            #expect(try await reader.retrieve()?.accessToken == result.credential.accessToken)

            try await keychain.delete()
        }

        // MARK: 6. Login, logout, current user, session restoration

        @Test("6. Login, current user, session restoration, and logout all work")
        func theFullSessionLifecycle() async throws {
            let store = InMemoryCredentialStore()
            let stack = await IntegrationHarness.makeAuthStack(store: store)

            try await stack.login()
            #expect(try await stack.auth.currentUser().email == IntegrationEnvironment.seededEmail)

            let relaunch = await IntegrationHarness.makeAuthStack(store: store)
            await relaunch.session.restore()
            #expect(relaunch.session.state.isAuthenticated)

            await relaunch.auth.logout()
            #expect(try await store.retrieve() == nil)
            #expect(relaunch.session.state == .unauthenticated)
        }

        // MARK: 7. 401 handling is deterministic

        @Test("7. A 401 refreshes the token once and the request then succeeds")
        func unauthorizedHandlingIsDeterministic() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            let before = try #require(try await stack.store.retrieve())

            _ = try await stack.client.raw(.post, "/api/auth/revoke-access-token")
            let user = try await stack.auth.currentUser()

            #expect(user.email == IntegrationEnvironment.seededEmail)
            #expect(try await stack.store.retrieve()?.accessToken != before.accessToken)
        }

        // MARK: 8. Token refresh is deterministic, including concurrent 401s

        @Test("8. Concurrent 401s share one refresh and all succeed")
        func concurrentRefreshIsSingleFlight() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            _ = try await stack.client.raw(.post, "/api/auth/revoke-access-token")

            let emails = try await withThrowingTaskGroup(of: String.self) { group in
                for _ in 0 ..< 5 {
                    group.addTask { try await stack.auth.currentUser().email }
                }
                var emails: [String] = []
                for try await email in group { emails.append(email) }
                return emails
            }

            // The fixture rotates refresh tokens, so a second refresh would
            // have spent a token the server no longer knows: five successes
            // mean exactly one refresh happened.
            #expect(emails.count == 5)
            #expect(emails.allSatisfy { $0 == IntegrationEnvironment.seededEmail })
        }

        // MARK: 9. Validation errors are structured Swift errors

        @Test("9. A 422 arrives as a structured error naming its fields")
        func validationErrorsAreStructured() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            do {
                let _: Envelope<APIEvent> = try await stack.client.post(
                    "/api/events",
                    body: ["title": "ab"]
                )
                Issue.record("Expected the request to fail validation")
            } catch let error as LaravelValidationError {
                #expect(error.statusCode == 422)
                #expect(error.hasError(for: "title"))
                #expect(error.firstError(for: "title")?.isEmpty == false)
            }
        }

        // MARK: 10. Standard Laravel pagination formats

        @Test("10. paginate, simplePaginate, cursorPaginate, and resource collections all decode")
        func everyPaginationFormatIsSupported() async throws {
            let client = await IntegrationHarness.makeClient()

            let length: Page<APIEvent> = try await client.page("/api/events", query: ["per_page": "10"])
            let resource: Page<APIEvent> = try await client.page("/api/events/resource", query: ["per_page": "10"])
            let simple: Page<APIEvent> = try await client.page("/api/events/simple", query: ["per_page": "10"])
            let cursor: Page<APIEvent> = try await client.page("/api/events/cursor", query: ["per_page": "10"])

            #expect(length.kind == .length)
            #expect(resource.total == IntegrationEnvironment.seededEventCount)
            #expect(simple.kind == .simple)
            #expect(cursor.kind == .cursor)
            #expect(try await client.nextPage(after: cursor)?.items.first?.title == "Event 11")
        }

        // MARK: 11. Multipart uploads

        @Test("11. A multipart upload reaches an ordinary Laravel endpoint")
        func multipartUploadWorks() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            let upload: AvatarUpload = try await stack.client.upload(
                IntegrationHarness.pixelPNG,
                to: "/api/avatar",
                fileName: "avatar.png",
                mimeType: "image/png"
            )

            #expect(upload.size == IntegrationHarness.pixelPNG.count)
        }

        // MARK: 12. Presigned direct uploads

        @Test("12. A Laravel-issued authorization uploads straight to storage")
        func presignedUploadWorks() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            let receipt: DirectUploadReceipt = try await stack.client.directUploader().upload(
                IntegrationHarness.pixelPNG,
                authorizingAt: "/api/uploads/authorize",
                notifyingAt: "/api/uploads/complete",
                fileName: "direct.png",
                mimeType: "image/png"
            )

            #expect(receipt.size == IntegrationHarness.pixelPNG.count)
        }

        // MARK: 13. Cancellation and configurable timeouts

        @Test("13. Requests can be cancelled and carry a configurable timeout")
        func cancellationAndTimeouts() async throws {
            let client = await IntegrationHarness.makeClient(timeout: 30)

            do {
                let _: EchoedRequest = try await client.get(
                    "/api/slow",
                    query: ["seconds": "3"],
                    options: RequestOptions(timeout: 0.6)
                )
                Issue.record("Expected the request to time out")
            } catch let error as LaravelError {
                #expect(error.isTimeout)
            }

            let task = Task { () async throws -> EchoedRequest in
                try await client.get("/api/slow", query: ["seconds": "3"])
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            task.cancel()

            do {
                _ = try await task.value
                Issue.record("Expected the request to be cancelled")
            } catch let error as LaravelError {
                #expect(error.isCancelled)
            }
        }

        // MARK: 14. Retries are explicit and not applied to every method

        @Test("14. A transient GET is retried; the same failure on POST is not")
        func retriesAreExplicitAndMethodAware() async throws {
            let policy = RetryPolicy(maxRetries: 3, backoffStrategy: .constant(delay: 0.05))
            let client = await IntegrationHarness.makeClient(retryPolicy: policy)

            let getKey = IntegrationEnvironment.flakyKey("dod-get")
            let recovered: FlakyResult = try await client.get(
                "/api/flaky/\(getKey)",
                query: ["failures": "2"]
            )
            #expect(recovered.attempts == 3)

            let postKey = IntegrationEnvironment.flakyKey("dod-post")
            do {
                let _: FlakyResult = try await client.post(
                    "/api/flaky/\(postKey)",
                    body: Optional<String>.none,
                    query: ["failures": "2"]
                )
                Issue.record("Expected the POST to fail")
            } catch let error as LaravelError {
                #expect(error.statusCode == 503)
            }
            let counter: FlakyCounter = try await client.delete("/api/flaky/\(postKey)")
            #expect(counter.attempts == 1)
        }

        // MARK: 15. Codable serialization of standard Laravel JSON

        @Test("15. Standard Laravel JSON decodes into plain Codable models")
        func codableSerializationWorks() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            let startsAt = Date(timeIntervalSince1970: 1_900_000_000)

            let created: Envelope<APIEvent> = try await stack.client.post(
                "/api/events",
                body: ["title": "Acceptance event", "starts_at": ISO8601DateFormatter().string(from: startsAt)]
            )

            #expect(created.data.title == "Acceptance event")
            // snake_case keys and Laravel's date format, with no CodingKeys.
            #expect(created.data.startsAt == startsAt)
            #expect(created.data.createdAt != nil)

            let _: EmptyResponse = try await stack.client.delete("/api/events/\(created.data.id)")
        }

        // MARK: 16. Non-standard responses through the generic Core client

        @Test("16. A payload that fits no Laravel convention stays reachable")
        func nonStandardResponsesRemainUsable() async throws {
            let client = await IntegrationHarness.makeClient()

            let response = try await client.raw(.get, "/api/events", query: ["per_page": "2"])
            let payload = try JSONSerialization.jsonObject(with: response.rawData) as? [String: Any]

            #expect(response.statusCode == 200)
            #expect((payload?["data"] as? [Any])?.count == 2)
        }

        // MARK: 17. Middleware can modify requests and observe responses

        @Test("17. Middleware rewrites the request and sees the response")
        func middlewareWorksBothWays() async throws {
            let client = await IntegrationHarness.makeClient()
            let observer = AcceptanceObserver()
            await client.use(observer)

            let echo: EchoedRequest = try await client.get("/api/echo")

            #expect(echo.header("X-Acceptance") == "yes")
            #expect(observer.statusCodes == [200])
        }

        // MARK: 18. No OpenAPI or generated models

        @Test("18. Nothing in the flow needs generated models")
        func noGeneratedModelsRequired() async throws {
            // A struct declared by hand, decoded straight from the API.
            struct HandWritten: Decodable, Sendable {
                let currentPage: Int
                let total: Int
            }

            let client = await IntegrationHarness.makeClient()
            let page: HandWritten = try await client.get("/api/events", query: ["per_page": "5"])

            #expect(page.currentPage == 1)
            #expect(page.total == IntegrationEnvironment.seededEventCount)
        }
    }
}

/// Adds a header on the way out and records the status on the way back.
private final class AcceptanceObserver: Middleware, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    var statusCodes: [Int] { lock.withLock { storage } }

    func process(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("yes", forHTTPHeaderField: "X-Acceptance")
        return request
    }

    func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        lock.withLock { storage.append(response.statusCode) }
    }
}
