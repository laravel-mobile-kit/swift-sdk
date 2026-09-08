# Authentication

The kit integrates with the authentication your Laravel app already has. It does
not define a protocol, require a package on the server, or assume Sanctum: every
endpoint, request field, and response shape is configurable.

## The pieces

```
CredentialStore            where the token lives (Keychain in production)
      ↓
TokenProvider              reads it for each request
      ↓
AuthMiddleware             writes `Authorization: Bearer …`
      ↓
TokenRefreshCoordinator    one refresh at a time, no matter how many 401s
      ↓
AuthRefreshRetryDecider    turns a 401 into one refresh and one retry
      ↓
AuthSession                the state SwiftUI switches on
      ↓
AuthManager                login, register, logout, current user
```

Each is usable on its own. An app with a static API token needs only
`StaticTokenProvider` and `AuthMiddleware`.

## Storing credentials

```swift
let store = KeychainCredentialStore(
    service: "com.example.app",        // usually the bundle identifier
    account: "credentials",            // distinguishes credentials in one service
    accessGroup: nil,                  // set to share with an extension
    accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
)
```

`InMemoryCredentialStore` exists for tests and previews. Anything else — a
shared container, a mock — conforms to `CredentialStore`.

A stored `AuthCredential` carries the access token, an optional refresh token,
the token type, and an optional expiry:

```swift
credential.isExpired
credential.expires(within: 60)          // "will expire in the next minute"
credential.authorizationHeaderValue     // "Bearer abc…"
```

## Signing in

```swift
let auth = AuthManager<AppUser>(
    client: client,
    configuration: .laravel,
    credentialStore: store,
    session: session,
    refreshCoordinator: coordinator
)

try await auth.login(email: email, password: password, deviceName: "iPhone")
try await auth.register(fields: ["name": name, "email": email, "password": password])
try await auth.currentUser()
await auth.logout()
```

Field names are sent exactly as written — `device_name` stays `device_name` —
because they are the API's contract, not Swift property names.

`logout()` tells the server first, but a failure there never blocks the local
sign-out: an app must be able to sign out on a plane.

## Pointing at your own endpoints

```swift
let configuration = AuthConfiguration(
    loginEndpoint: "/api/auth/token",
    registerEndpoint: "/api/auth/register",
    logoutEndpoint: "/api/auth/revoke",
    userEndpoint: "/api/me",
    refreshEndpoint: "/api/auth/refresh",
    passwordResetEndpoint: "/api/auth/forgot",
    emailVerificationEndpoint: nil          // the API does not offer one
)
```

Authentication endpoints are used exactly as written and never inherit an API
version prefix — Laravel apps routinely expose `/api/login` next to
`/api/v1/events`. See [Versioning](VERSIONING.md).

## Reading a login response

There is no single Laravel login response: Sanctum's documented example returns
a bare token, Passport returns an OAuth payload, and hand-written controllers
return whatever the team chose. `AuthResponseMapper.laravel` reads the common
shapes — a payload at the top level or nested under `data`, a token under
`token`, `access_token`, or `plain_text_token`, plus `refresh_token`,
`token_type`, `expires_at`, and `expires_in`.

When your API does something else, write the mapper:

```swift
let mapper = AuthResponseMapper<AppUser>(
    makeCredential: { data in
        let payload = try JSONDecoder().decode(TokenPayload.self, from: data)
        return AuthCredential(
            accessToken: payload.jwt,
            refreshToken: payload.renewal,
            expiresAt: payload.validUntil
        )
    },
    makeUser: { data, decoder in
        try decoder.decode(TokenPayload.self, from: data).profile
    }
)

let auth = AuthManager<AppUser>(client: client, credentialStore: store, mapper: mapper)
```

## Sending the token differently

```swift
await client.use(.auth(provider, transport: .bearer))            // Authorization: Bearer …
await client.use(.auth(provider, transport: .scheme("Token")))   // Authorization: Token …
await client.use(.auth(provider, transport: .cookie))            // Cookie: <session>
await client.use(.auth(provider, transport: .custom { request, token in
    var request = request
    request.setValue(token, forHTTPHeaderField: "X-API-Key")
    return request
}))
```

A request that already carries the header the transport writes is left alone, so
a single call can override the token.

## Session state

`AuthSession` is `@MainActor` and `ObservableObject`, so a SwiftUI view can
switch on it directly:

| State | Meaning |
| --- | --- |
| `.unknown` | Nothing checked yet — before `restore()` |
| `.restoring` | A stored credential is being restored or refreshed |
| `.unauthenticated` | No usable credential: show the sign-in screen |
| `.authenticated(user)` | Verified, and this is who it is |
| `.unverified` | A credential exists but could not be checked — offline, not signed out |

```swift
await session.restore()          // never throws: every outcome is a state
try await session.signIn(with: credential)
try await session.reloadUser()
await session.logout()
await session.endSession(reason: error)
```

## 401 and token refresh

The rules are deterministic:

- A 401 triggers **one** refresh, through `TokenRefreshCoordinator`. Concurrent
  401s join the refresh already in flight rather than starting their own.
- Each request gets **one** refresh-driven retry (`maxAttempts`). A second 401
  means the fresh token was rejected too: the request fails with
  `AuthError.sessionExpired` and `onAuthFailure` runs.
- A failed refresh does the same, and hands the underlying error to
  `onAuthFailure` so the app can tell "expired" from "server down".
- `logout()` invalidates the coordinator, so a refresh in flight cannot re-store
  a credential the user just discarded.

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
        maxAttempts: 1,
        onAuthFailure: session.authFailureHandler()
    )
)
```

APIs without refresh tokens skip the coordinator: a 401 then means the session
is over, which is exactly what `AuthSession` reports when there is nothing to
refresh with.

## Cookie sessions (Sanctum SPA, Breeze API)

Laravel's API starter kit does not issue tokens at all. `breeze:install api`
generates a session-cookie contract: the client fetches a CSRF cookie, posts
credentials to `/login`, and is authenticated by the session cookie from then
on. `AuthManager` and `AuthCredential` are token-shaped and do not apply here —
what you need instead is the CSRF header and a cookie jar, both of which
`URLSession` and one middleware cover:

```swift
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
```

The token is re-read from the jar on every request because Laravel regenerates
the session — and the token with it — on sign-in and sign-out.

Two details make Sanctum treat the request as stateful:

```swift
let sessionConfiguration = URLSessionConfiguration.ephemeral   // its own cookie jar
sessionConfiguration.httpShouldSetCookies = true

let client = LaravelClient(
    configuration: LaravelClientConfiguration(
        baseURL: baseURL,
        defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders
            // Sanctum only accepts a session from a domain it was told about.
            .merging(["Referer": baseURL.absoluteString]) { _, new in new }
    ),
    transport: URLSessionTransport(configuration: sessionConfiguration)
)
await client.use(SanctumCSRFMiddleware(cookieStorage: cookies, baseURL: baseURL))
```

Then the flow is ordinary requests:

```swift
_ = try await client.raw(.get, "/sanctum/csrf-cookie")            // the handshake
let _: EmptyResponse = try await client.post("/login", body: ["email": email, "password": password])
let user: User = try await client.get("/api/user")
let _: EmptyResponse = try await client.post("/logout", body: Optional<String>.none)
```

The server must list the app's origin in `SANCTUM_STATEFUL_DOMAINS`. Validation
failures still arrive as `LaravelValidationError`, so a sign-in form behaves the
same as it does against a token API.

This flow is covered by the starter-kit suite in
`Tests/LaravelMobileKitIntegrationTests/StarterKitIntegrationTests.swift`, which
runs against an unmodified `breeze:install api` application — see
[Testing](TESTING.md).

`AuthTransport.cookie` is a different thing: it writes a `Cookie` header from a
token you hold yourself, for APIs that authenticate that way. A Sanctum SPA does
not need it — `URLSession` owns the cookie jar.

## Errors

| `AuthError` | When |
| --- | --- |
| `.notAuthenticated` | An operation needed a credential and none was stored |
| `.refreshNotSupported` | The provider cannot refresh |
| `.noRefreshToken` | The credential has no refresh token |
| `.sessionExpired` | The session could not be renewed — sign the user out |
| `.endpointNotConfigured(name)` | An optional endpoint was called without being configured |
| `.invalidAuthResponse` | The response carried no token the mapper could read |
