import Foundation

import LaravelMobileKit

/// Examples from `Documentation/VERSIONING.md`.
enum VersioningSnippets {
    static func prefixing(client: LaravelClient) async throws {
        await client.use(.apiVersion(.v1))

        let events: [Event] = try await client.get("/api/events")   // → /api/v1/events
        _ = events
    }

    static func excludingAuthRoutes(
        client: LaravelClient,
        authConfiguration: AuthConfiguration
    ) async {
        await client.use(APIVersionMiddleware(version: .v1, excluding: authConfiguration))

        await client.use(
            .apiVersion(
                .v1,
                excludedPaths: APIVersionMiddleware.defaultExcludedPaths.union(["/api/auth"])
            )
        )
    }

    static func anotherPrefix(client: LaravelClient) async throws {
        await client.use(.apiVersion(.v1, pathPrefix: "/rest"))

        let events: [Event] = try await client.get("/rest/events")  // → /rest/v1/events
        _ = events
    }

    static var headerVersioning: LaravelClientConfiguration {
        LaravelClientConfiguration(
            baseURL: baseURL,
            defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders
                .merging(["Accept-Version": "2024-01-01"]) { _, new in new }
        )
    }

    static func twoVersionsAtOnce(
        configuration: LaravelClientConfiguration,
        provider: any TokenProvider
    ) async -> (LaravelClient, LaravelClient) {
        let v1 = LaravelClient(configuration: configuration)
        await v1.use([.auth(provider), .apiVersion(.v1)])

        let v2 = LaravelClient(configuration: configuration)
        await v2.use([.auth(provider), .apiVersion(.v2)])

        return (v1, v2)
    }
}
