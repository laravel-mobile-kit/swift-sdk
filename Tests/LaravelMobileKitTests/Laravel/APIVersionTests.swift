import Foundation
import Testing

import LaravelMobileKitCore
import LaravelMobileKitLaravel

@Suite("API versions")
struct APIVersionTests {
    @Test("Each version names its path segment")
    func pathSegments() {
        #expect(APIVersion.none.pathSegment == nil)
        #expect(APIVersion.v1.pathSegment == "v1")
        #expect(APIVersion.v2.pathSegment == "v2")
        #expect(APIVersion.v3.pathSegment == "v3")
        #expect(APIVersion.custom("beta").pathSegment == "beta")
    }
}

@Suite("Version prefixing")
struct APIVersionMiddlewareTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func sentURL(
        path: String,
        version: APIVersion,
        pathPrefix: String = "/api",
        excludedPaths: Set<String> = APIVersionMiddleware.defaultExcludedPaths,
        baseURL: URL? = nil
    ) async throws -> String {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(
            configuration: .withoutRetries(baseURL ?? self.baseURL),
            transport: transport
        )
        await client.use(
            .apiVersion(version, pathPrefix: pathPrefix, excludedPaths: excludedPaths)
        )

        let _: [Event] = try await client.get(path)

        return try #require(await transport.lastRequest?.url?.absoluteString)
    }

    @Test("An unversioned client sends the path unchanged")
    func noVersion() async throws {
        #expect(
            try await sentURL(path: "/api/events", version: .none)
                == "https://api.example.com/api/events"
        )
    }

    @Test("A version is inserted after the prefix", arguments: [
        (APIVersion.v1, "https://api.example.com/api/v1/events"),
        (APIVersion.v2, "https://api.example.com/api/v2/events"),
        (APIVersion.custom("beta"), "https://api.example.com/api/beta/events"),
    ])
    func versionIsInserted(version: APIVersion, expected: String) async throws {
        #expect(try await sentURL(path: "/api/events", version: version) == expected)
    }

    @Test("Query parameters survive the rewrite")
    func queryIsPreserved() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
        await client.use(.apiVersion(.v1))

        let _: [Event] = try await client.get("/api/events", query: ["page": "2"])

        #expect(
            await transport.lastRequest?.url?.absoluteString
                == "https://api.example.com/api/v1/events?page=2"
        )
    }

    @Test("A path that already names the version is untouched")
    func alreadyVersioned() async throws {
        #expect(
            try await sentURL(path: "/api/v1/events", version: .v1)
                == "https://api.example.com/api/v1/events"
        )
    }

    @Test("A path naming another version is respected")
    func explicitOtherVersionWins() async throws {
        #expect(
            try await sentURL(path: "/api/v2/events", version: .v1)
                == "https://api.example.com/api/v2/events"
        )
    }

    @Test("Auth routes stay unversioned", arguments: [
        "/api/login", "/api/logout", "/api/register", "/api/user", "/api/auth/refresh",
    ])
    func authRoutesAreExcluded(path: String) async throws {
        #expect(
            try await sentURL(path: path, version: .v1) == "https://api.example.com\(path)"
        )
    }

    @Test("A custom exclusion list replaces the default")
    func customExclusions() async throws {
        #expect(
            try await sentURL(path: "/api/health", version: .v1, excludedPaths: ["/api/health"])
                == "https://api.example.com/api/health"
        )
        // The defaults no longer apply once the list is replaced.
        #expect(
            try await sentURL(path: "/api/login", version: .v1, excludedPaths: ["/api/health"])
                == "https://api.example.com/api/v1/login"
        )
    }

    @Test("Paths outside the versioned prefix are left alone")
    func pathsOutsidePrefix() async throws {
        #expect(
            try await sentURL(path: "/webhooks/stripe", version: .v1)
                == "https://api.example.com/webhooks/stripe"
        )
    }

    @Test("A custom prefix is honoured")
    func customPrefix() async throws {
        #expect(
            try await sentURL(path: "/rest/events", version: .v1, pathPrefix: "/rest")
                == "https://api.example.com/rest/v1/events"
        )
    }

    @Test("A version already in the base URL is not doubled")
    func versionInBaseURL() async throws {
        #expect(
            try await sentURL(
                path: "/events",
                version: .v1,
                baseURL: URL(string: "https://api.example.com/api/v1")!
            ) == "https://api.example.com/api/v1/events"
        )
    }

    @Test("Absolute URLs, such as pagination links, keep their own version")
    func absoluteURLsAreUntouched() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
        await client.use(.apiVersion(.v2))

        let _: [Event] = try await client.get("https://api.example.com/api/v1/events?page=3")

        #expect(
            await transport.lastRequest?.url?.absoluteString
                == "https://api.example.com/api/v1/events?page=3"
        )
    }
}
