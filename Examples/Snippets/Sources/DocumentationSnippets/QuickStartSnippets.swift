import Foundation
import SwiftUI

import LaravelMobileKit

/// Examples from `Documentation/QUICK_START.md` and the root `README.md`.
enum QuickStartSnippets {
    static func makeClient() -> LaravelClient {
        LaravelClient(
            configuration: LaravelClientConfiguration(
                baseURL: baseURL,
                timeoutInterval: 30,
                retryPolicy: .default
            )
        )
    }

    static func registerPipeline(client: LaravelClient) async {
        let store = KeychainCredentialStore(service: "com.example.app")
        let provider = CredentialTokenProvider(store: store)

        await client.use([
            .auth(provider),
            .validationErrors,
            .apiVersion(.v1),
        ])
    }

    static func signIn(client: LaravelClient, session: AuthSession<AppUser>) async throws {
        let store = KeychainCredentialStore(service: "com.example.app")
        let auth = AuthManager<AppUser>(
            client: client,
            credentialStore: store,
            session: session
        )

        _ = try await auth.login(
            email: "ada@example.com",
            password: "secret",
            deviceName: "iPhone"
        )
    }

    static func handleUnauthorized(
        client: LaravelClient,
        refreshClient: LaravelClient,
        session: AuthSession<AppUser>
    ) async {
        let store = KeychainCredentialStore(service: "com.example.app")

        let coordinator = TokenRefreshCoordinator(credentialStore: store) { credential in
            guard let refreshToken = credential.refreshToken else { throw AuthError.noRefreshToken }

            let response = try await refreshClient.raw(
                .post,
                "/api/auth/refresh",
                body: try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
            )
            return try AuthResponseMapper<AppUser>.laravel.makeCredential(response.rawData)
        }

        await client.use(
            retryDecider: AuthRefreshRetryDecider(
                coordinator: coordinator,
                onAuthFailure: session.authFailureHandler()
            )
        )
    }

    static func readData(client: LaravelClient, id: Int) async throws {
        let events: [Event] = try await client.get("/api/events")
        let event: Event = try await client.get("/api/events/\(id)")
        let page: Page<Event> = try await client.page("/api/events", query: ["per_page": "20"])
        let next = try await client.nextPage(after: page)

        _ = (events, event, next)
    }

    static func writeData(client: LaravelClient, draft: EventDraft) async -> [String] {
        do {
            let created: Event = try await client.post("/api/events", body: draft)
            _ = created
            return []
        } catch let error as LaravelValidationError {
            return (error["title"] ?? []) + (error["starts_at"] ?? [])
        } catch {
            return []
        }
    }

    static func upload(client: LaravelClient, jpeg: Data) async throws {
        let uploaded: AvatarResponse = try await client.upload(
            jpeg,
            to: "/api/avatar",
            fieldName: "avatar",
            fileName: "avatar.jpg",
            mimeType: "image/jpeg"
        ) { progress in
            _ = progress.fractionCompleted ?? 0
        }
        _ = uploaded
    }

    static func cancel(client: LaravelClient) {
        let task = Task { try await client.get("/api/events") as [Event] }
        task.cancel()
    }
}

/// The SwiftUI wiring from the quick start.
@MainActor
final class AppModel: ObservableObject {
    let session: AuthSession<AppUser>

    init(client: LaravelClient, store: any CredentialStore, provider: CredentialTokenProvider) {
        session = AuthSession(client: client, credentialStore: store, tokenProvider: provider)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.session.state {
            case .unknown, .restoring: ProgressView()
            case .unauthenticated: LoginPlaceholderView()
            case let .authenticated(user): HomePlaceholderView(user: user)
            case .unverified: OfflineRetryView()
            }
        }
        .task { await model.session.restore() }
    }
}

struct LoginPlaceholderView: View { var body: some View { Text("Sign in") } }
struct HomePlaceholderView: View {
    let user: AppUser
    var body: some View { Text(user.name) }
}
struct OfflineRetryView: View { var body: some View { Text("Offline") } }
