import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    @MainActor
    @Suite("API versioning")
    struct VersioningIntegrationTests {
        @Test("A versioned client reaches the /v1 routes")
        func versionedClientHitsV1() async throws {
            let client = await IntegrationHarness.makeClient(version: .v1)

            let served: ServedVersion = try await client.get("/api/version")

            #expect(served.version == "v1")
        }

        @Test("An unversioned client reaches the unprefixed routes")
        func unversionedClientHitsTheRoot() async throws {
            let client = await IntegrationHarness.makeClient(version: .none)

            let served: ServedVersion = try await client.get("/api/version")

            #expect(served.version == "none")
        }

        @Test("Authentication endpoints keep their own URL structure")
        func authEndpointsAreNotVersioned() async throws {
            // The fixture only publishes /api/login, never /api/v1/login: a client
            // configured for v1 must still find it.
            let stack = await IntegrationHarness.makeAuthStack(version: .v1)

            try await stack.login()
            let user = try await stack.auth.currentUser()

            #expect(user.email == IntegrationEnvironment.seededEmail)
        }

        @Test("A path that already names a version is left alone")
        func explicitVersionWins() async throws {
            let client = await IntegrationHarness.makeClient(version: .v1)

            let echo: EchoedRequest = try await client.get("/api/v1/echo")

            #expect(echo.path == "/api/v1/echo")
        }

        @Test("Both versions of the same collection are reachable")
        func bothVersionsServeTheSameCollection() async throws {
            let versioned = await IntegrationHarness.makeClient(version: .v1)
            let unversioned = await IntegrationHarness.makeClient(version: .none)

            let fromV1: Page<APIEvent> = try await versioned.page(
                "/api/events", query: ["per_page": "5"])
            let fromRoot: Page<APIEvent> = try await unversioned.page(
                "/api/events", query: ["per_page": "5"])

            #expect(fromV1.items == fromRoot.items)
        }
    }
}
