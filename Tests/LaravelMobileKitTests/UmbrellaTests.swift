import Foundation
import Testing

import LaravelMobileKit

@Suite("Umbrella module")
struct UmbrellaTests {
    let baseURL = URL(string: "https://api.example.com")!

    @Test("Versioning can be told to skip an app's own auth routes")
    func versioningExcludesConfiguredAuthRoutes() async throws {
        let configuration = AuthConfiguration(
            loginEndpoint: "/auth/sign-in",
            userEndpoint: "/auth/me"
        )
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
        await client.use(APIVersionMiddleware(version: .v1, excluding: configuration))

        let _: [Event] = try await client.get("/auth/sign-in")
        let _: [Event] = try await client.get("/api/events")

        let urls = await transport.executedRequests.map(\.url?.absoluteString)
        #expect(urls == [
            "https://api.example.com/auth/sign-in",
            "https://api.example.com/api/v1/events",
        ])
    }
}
