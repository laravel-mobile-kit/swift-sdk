# Quick start

This is the whole integration, from an empty app to authenticated, paginated,
error-handled requests. A runnable version of it is in
[`Examples/QuickStart`](../Examples/QuickStart).

## 1. Model your API in Swift

Plain `Codable` types. No base class, no generated code:

```swift
struct Event: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String
    let startsAt: Date?
}
```

Laravel's `snake_case` keys and ISO8601 dates are handled by the default coders,
so `starts_at` arrives as `startsAt` without a `CodingKeys` block.

## 2. Create one client

```swift
import LaravelMobileKit

let client = LaravelClient(
    configuration: LaravelClientConfiguration(
        baseURL: URL(string: "https://api.example.com")!,
        timeoutInterval: 30,
        retryPolicy: .default
    )
)
```

`LaravelClient` is an actor: create it once and share it. `Accept` and
`Content-Type` default to `application/json`, which is what makes Laravel answer
validation failures with JSON instead of an HTML redirect.

## 3. Register the pipeline

```swift
let store = KeychainCredentialStore(service: "com.example.app")
let provider = CredentialTokenProvider(store: store)

await client.use([
    .auth(provider),        // attaches `Authorization: Bearer …`
    .validationErrors,      // turns a 422 into a LaravelValidationError
    .apiVersion(.v1),       // rewrites /api/events to /api/v1/events
])
```

Middleware runs in registration order on the way out and in reverse on the way
back.

## 4. Sign in

```swift
let auth = AuthManager<AppUser>(
    client: client,
    credentialStore: store,
    session: session          // optional, see below
)

let result = try await auth.login(
    email: "ada@example.com",
    password: "secret",
    deviceName: "iPhone"      // Sanctum's token endpoint wants one
)
```

The issued credential is stored in the Keychain, and every later request carries
it.

> **Does your API issue no token?** Laravel's own API starter kit
> (`breeze:install api`) authenticates with a session cookie instead. Steps 4
> to 6 then look different — `LaravelClient.sanctumSPA`, `SanctumSPAAuth`, and
> `SanctumSPASession` replace the Keychain, `AuthManager`, and the refresh
> coordinator. Everything else on this page is unchanged. See
> [Authentication](AUTHENTICATION.md#cookie-sessions-sanctum-spa-breeze-api).

## 5. Restore the session at launch

```swift
@MainActor
final class AppModel: ObservableObject {
    let session: AuthSession<AppUser>

    init(client: LaravelClient, store: any CredentialStore, provider: CredentialTokenProvider) {
        session = AuthSession(client: client, credentialStore: store, tokenProvider: provider)
    }
}
```

```swift
struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.session.state {
            case .unknown, .restoring: ProgressView()
            case .unauthenticated: LoginView()
            case let .authenticated(user): HomeView(user: user)
            case .unverified: OfflineRetryView()
            }
        }
        .task { await model.session.restore() }
    }
}
```

`.unverified` is the state that matters most: a credential exists but the server
could not be reached. The credential is kept, so a retry signs the user straight
back in instead of dumping them on a login screen because the train went into a
tunnel.

## 6. Handle 401s once

```swift
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
```

Any request that comes back 401 now refreshes the token once and retries itself.
Ten concurrent 401s produce one refresh, not ten. If the refresh fails, the
session ends and the UI follows.

Use a second client for the refresh call: it must not carry the token being
replaced, and it must not be able to trigger a refresh of its own.

## 7. Read data

```swift
let events: [Event] = try await client.get("/api/events")
let event: Event = try await client.get("/api/events/\(id)")
let page: Page<Event> = try await client.page("/api/events", query: ["per_page": "20"])
let next = try await client.nextPage(after: page)
```

## 8. Write data, and show what Laravel says about it

```swift
do {
    let created: Event = try await client.post("/api/events", body: draft)
} catch let error as LaravelValidationError {
    titleErrors = error["title"] ?? []
    startsAtErrors = error["starts_at"] ?? []
}
```

## 9. Upload a file

```swift
let uploaded: AvatarResponse = try await client.upload(
    jpeg,
    to: "/api/avatar",
    fieldName: "avatar",
    fileName: "avatar.jpg",
    mimeType: "image/jpeg"
) { progress in
    Task { @MainActor in fraction = progress.fractionCompleted ?? 0 }
}
```

## 10. Cancel what is no longer needed

```swift
let task = Task { try await client.get("/api/events") as [Event] }
task.cancel()   // surfaces as LaravelError.cancelled
```

Cancellation is checked before the request is built, again before it is sent,
and honoured by the transport, so a cancelled screen stops costing bandwidth.

## Where to go next

- [Authentication](AUTHENTICATION.md) for endpoints that differ from Laravel's defaults, and for cookie sessions
- [Pagination](PAGINATION.md) for cursor and simple paginators
- [Error handling](ERROR_HANDLING.md) for the full error taxonomy
- [Middleware](MIDDLEWARE.md) to add logging, tracing, or your own headers
