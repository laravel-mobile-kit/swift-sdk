# Migrating from a hand-written networking layer

The kit is designed to be adopted in pieces. Nothing below has to happen in one
release, and Core works with any REST API, so an app can move one screen at a
time.

## 1. Replace the request builder

Before:

```swift
var request = URLRequest(url: baseURL.appendingPathComponent("api/events"))
request.setValue("application/json", forHTTPHeaderField: "Accept")
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

let (data, response) = try await session.data(for: request)
guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
    throw APIError.badStatus
}
let events = try decoder.decode([Event].self, from: data)
```

After:

```swift
let events: [Event] = try await client.get("/api/events")
```

Status validation, decoding, timeouts, retries, and cancellation come with it.

## 2. Keep your models

`Codable` models carry over unchanged. If you were writing `CodingKeys` blocks
only to map `snake_case`, delete them — `LaravelJSONDecoder.makeDefault()` does
that conversion, and understands Laravel's date formats.

Custom coders still work:

```swift
LaravelClient(baseURL: baseURL, encoder: myEncoder, decoder: myDecoder)
```

## 3. Move the token out of `UserDefaults`

```swift
let store = KeychainCredentialStore(service: Bundle.main.bundleIdentifier!)

// One-time migration on launch:
if let legacy = UserDefaults.standard.string(forKey: "api_token") {
    try await store.store(AuthCredential(accessToken: legacy))
    UserDefaults.standard.removeObject(forKey: "api_token")
}
```

Then let the middleware attach it, and delete the code that copied the token
into every request:

```swift
await client.use(.auth(CredentialTokenProvider(store: store)))
```

## 4. Replace the 401 handler

A hand-written refresh usually has two problems: several concurrent 401s start
several refreshes, and a failed refresh leaves the app in an ambiguous state.
`TokenRefreshCoordinator` plus `AuthRefreshRetryDecider` fixes both — see
[Authentication](AUTHENTICATION.md).

## 4b. Coming from a cookie-based client instead

If your app talks to a Sanctum SPA — the contract Laravel's API starter kit
generates — there is no token to move and no 401 handler to replace. What you
delete is the CSRF plumbing:

```swift
// Before: fetch /sanctum/csrf-cookie, dig the XSRF-TOKEN cookie out of
// HTTPCookieStorage, re-read it after every sign-in, remember the Referer.
// After:
let client = await LaravelClient.sanctumSPA(baseURL: baseURL)
let auth = SanctumSPAAuth<AppUser>(client: client, session: session)
try await auth.login(email: email, password: password)
```

Keep using the shared cookie jar and your session survives a relaunch exactly as
it did before. See [Authentication](AUTHENTICATION.md#cookie-sessions-sanctum-spa-breeze-api).

## 5. Delete the pagination bookkeeping

```swift
// Before: page counters, per_page bookkeeping, "is this the last page" guesses.
// After:
let page: Page<Event> = try await client.page("/api/events")
let next = try await client.nextPage(after: page)
```

## 6. Adopt what is left when it suits you

Validation errors, uploads, and versioning are independent middlewares and
methods: adopt them per screen. The generic client keeps working for endpoints
that do not fit any Laravel convention — that path is supported, not a fallback
to apologise for.

## Keeping your own transport

Certificate pinning, a shared session, or a proxy already in place stay in
place:

```swift
LaravelClient(configuration: configuration, transport: URLSessionTransport(session: pinnedSession))
```

Or conform your existing networking layer to `HTTPTransport` and let the kit sit
on top of it while you migrate.

## What not to port

- Manual `URLRequest` construction, status checks, and JSON decoding.
- A bespoke error enum wrapping status codes — `LaravelError` and
  `LaravelValidationError` carry the payload.
- Retry loops written per call site — the policy is configuration.
- Token plumbing in every request — that is one middleware.
