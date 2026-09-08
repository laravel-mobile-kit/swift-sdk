import Foundation

import LaravelMobileKit

/// Examples from `Documentation/MIGRATION.md` and `Documentation/TESTING.md`.
enum MigrationSnippets {
    static func afterTheRewrite(client: LaravelClient) async throws {
        let events: [Event] = try await client.get("/api/events")
        _ = events
    }

    static func customCoders() -> LaravelClient {
        LaravelClient(
            baseURL: baseURL,
            encoder: LaravelJSONEncoder.makeDefault(),
            decoder: LaravelJSONDecoder.makeDefault()
        )
    }

    static func migrateLegacyToken() async throws {
        let store = KeychainCredentialStore(service: Bundle.main.bundleIdentifier ?? "com.example.app")

        if let legacy = UserDefaults.standard.string(forKey: "api_token") {
            try await store.store(AuthCredential(accessToken: legacy))
            UserDefaults.standard.removeObject(forKey: "api_token")
        }

        _ = store
    }

    static func attachTheToken(client: LaravelClient, store: any CredentialStore) async {
        await client.use(.auth(CredentialTokenProvider(store: store)))
    }

    static func paginationInsteadOfBookkeeping(client: LaravelClient) async throws {
        let page: Page<Event> = try await client.page("/api/events")
        let next = try await client.nextPage(after: page)
        _ = next
    }

    static func keepYourTransport(
        configuration: LaravelClientConfiguration,
        pinnedSession: URLSession
    ) -> LaravelClient {
        LaravelClient(
            configuration: configuration,
            transport: URLSessionTransport(session: pinnedSession)
        )
    }

    /// From `Documentation/TESTING.md`.
    static func clientUnderTest(fixture: Data, response: HTTPURLResponse) -> LaravelClient {
        LaravelClient(
            configuration: .init(baseURL: baseURL, retryPolicy: .none),
            transport: ResultStubTransport(result: .success((fixture, response)))
        )
    }
}

/// The stub `Documentation/TESTING.md` hands a canned result to.
struct ResultStubTransport: HTTPTransport {
    let result: Result<(Data, HTTPURLResponse), any Error>

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try result.get()
    }
}
