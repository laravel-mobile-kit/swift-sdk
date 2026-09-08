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

Laravel's API starter kit issues no tokens at all. `breeze:install api`
generates a session-cookie contract: the client fetches a CSRF cookie, posts
credentials to `/login`, and is authenticated by the session cookie from then
on. `AuthManager`, `AuthCredential`, and the Keychain do not apply — there is
nothing to store and nothing to refresh.

The kit covers that contract with three pieces:

```swift
let client = await LaravelClient.sanctumSPA(baseURL: baseURL)
await client.use(.validationErrors)                 // from LaravelMobileKitLaravel

let session = SanctumSPASession<AppUser>(client: client)
let auth = SanctumSPAAuth<AppUser>(client: client, session: session)

try await auth.login(email: email, password: password)
```

`sanctumSPA(baseURL:)` gets right the three things Laravel needs and that fail
opaquely when they are wrong: the cookie jar is kept across requests, the
request names its origin through `Referer` (Sanctum only accepts a session from
a domain in `SANCTUM_STATEFUL_DOMAINS`), and unsafe requests carry the CSRF
token from the `XSRF-TOKEN` cookie.

### The flows

```swift
try await auth.login(email: email, password: password)
try await auth.register(fields: [
    "name": name,
    "email": email,
    "password": password,
    "password_confirmation": password,
])
try await auth.currentUser()
try await auth.requestPasswordReset(email: email)
await auth.logout()
```

Each performs the CSRF handshake first, so no caller has to remember it. Fields
are sent exactly as written — Breeze expects `password_confirmation`, and that
is what it gets. Sign-in answers `204 No Content`, so the flows load the user
afterwards, which doubles as the check that the cookie really took.

### Session state

```swift
switch session.state {
case .unknown, .restoring: ProgressView()
case .unauthenticated: LoginView()
case let .authenticated(user): HomeView(user: user)
case .unverified: OfflineRetryView()
}
```

`SanctumSPASession` publishes the same ``AuthState`` the token session does, so
a view switches on it identically. `restore()` asks the API who the cookie
belongs to: a 401 means signed out, and anything else — offline, server down —
leaves the session `.unverified` rather than discarding a cookie that may still
be good.

Cookies outlive a launch only if the jar does. The shared storage is persistent,
which is why it is the default:

```swift
// Persistent — a returning user is still signed in.
let client = await LaravelClient.sanctumSPA(baseURL: baseURL)

// Private and in-memory — what tests and previews want.
let jar = URLSessionConfiguration.ephemeral.httpCookieStorage!
let isolated = await LaravelClient.sanctumSPA(baseURL: baseURL, cookieStorage: jar)
```

### Different routes

```swift
let auth = SanctumSPAAuth<AppUser>(
    client: client,
    configuration: SanctumSPAConfiguration(
        csrfCookieEndpoint: "/sanctum/csrf-cookie",
        loginEndpoint: "/api/session",
        registerEndpoint: "/api/accounts",
        logoutEndpoint: "/api/session/end",
        userEndpoint: "/api/me"
    )
)
```

### Doing it by hand

The middleware is usable on its own, for a client you assembled yourself:

```swift
await client.use(.sanctumCSRF(baseURL: baseURL, cookieStorage: .shared))
```

It reads the token from the cookie jar on every unsafe request — not once at
setup — because Laravel regenerates the session, and the token with it, on
sign-in and sign-out. A caller that sets `X-XSRF-TOKEN` itself keeps its value.

`AuthTransport.cookie` is a different thing: it writes a `Cookie` header from a
token you hold yourself, for APIs that authenticate that way. A Sanctum SPA does
not need it — `URLSession` owns the cookie jar.

This whole flow is covered by `StarterKitIntegrationTests`, which runs against an
unmodified `breeze:install api` application — see [Testing](TESTING.md).

## Errors

| `AuthError` | When |
| --- | --- |
| `.notAuthenticated` | An operation needed a credential and none was stored |
| `.refreshNotSupported` | The provider cannot refresh |
| `.noRefreshToken` | The credential has no refresh token |
| `.sessionExpired` | The session could not be renewed — sign the user out |
| `.endpointNotConfigured(name)` | An optional endpoint was called without being configured |
| `.invalidAuthResponse` | The response carried no token the mapper could read |
