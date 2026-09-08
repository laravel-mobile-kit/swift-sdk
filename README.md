# Laravel Mobile Kit (Swift)

> Build native apps against the Laravel API you already have.

Laravel Mobile Kit is the native client layer for Laravel REST APIs. It handles
the integration work every app rewrites — HTTP, Codable models, authentication
and session restoration, secure token storage, Laravel validation errors,
pagination, multipart and direct uploads, API versioning, retries, middleware,
cancellation — without asking the backend to change.

**No server-side package is required.** Point the SDK at an existing API and it
works — whether it authenticates with tokens (Sanctum, Passport, or your own
controller) or with the cookie session Laravel's API starter kit generates.

```swift
let client = LaravelClient(baseURL: URL(string: "https://api.example.com")!)

let events: [Event] = try await client.get("/api/events")
```

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/laravel-mobile-kit/swift-sdk.git", from: "0.1.0")
]
```

Then depend on the umbrella product, or on just the capabilities you use:

```swift
.product(name: "LaravelMobileKit", package: "swift-sdk")
```

See [Installation](Documentation/INSTALLATION.md) for the module map.

## Modules

| Module | What it holds |
| --- | --- |
| `LaravelMobileKitCore` | `LaravelClient`, transport, Codable, errors, retries, middleware, headers |
| `LaravelMobileKitLaravel` | Validation errors, pagination, API versioning |
| `LaravelMobileKitAuth` | Credential storage, token providers, sessions, refresh coordination, Sanctum SPA cookie sessions |
| `LaravelMobileKitUploads` | Multipart and presigned direct uploads |
| `LaravelMobileKit` | Umbrella re-exporting all four |

Core never depends on the Laravel conventions: the same client works against any
REST API, and the Laravel-specific behaviour sits in the modules above it.

## Quick start

```swift
import LaravelMobileKit

// 1. One client for the app.
let client = LaravelClient(
    configuration: LaravelClientConfiguration(baseURL: baseURL)
)

// 2. The pipeline: tokens on the way out, Laravel errors on the way back.
let store = KeychainCredentialStore(service: "com.example.app")
let provider = CredentialTokenProvider(store: store)
await client.use([.auth(provider), .validationErrors])

// 3. Sign in.
let auth = AuthManager<AppUser>(client: client, credentialStore: store)
try await auth.login(email: email, password: password)

// 4. Use the API.
let page: Page<Event> = try await client.page("/api/events")
```

The full walk-through is in [Quick Start](Documentation/QUICK_START.md), and a
runnable SwiftUI application is in [`Examples/QuickStart`](Examples/QuickStart).

## Documentation

- [Installation](Documentation/INSTALLATION.md) — Swift Package Manager, module choices
- [Quick Start](Documentation/QUICK_START.md) — end-to-end integration
- [Authentication](Documentation/AUTHENTICATION.md) — login, sessions, 401s, refresh
- [Pagination](Documentation/PAGINATION.md) — all three Laravel paginators
- [Uploads](Documentation/UPLOADS.md) — multipart and presigned direct uploads
- [Error handling](Documentation/ERROR_HANDLING.md) — error types, validation errors
- [Versioning](Documentation/VERSIONING.md) — `/v1` prefixes, unversioned auth routes
- [Middleware](Documentation/MIDDLEWARE.md) — request/response interception, retry deciders
- [API reference](Documentation/API_REFERENCE.md) — every public type
- [Compatibility](Documentation/COMPATIBILITY.md) — Laravel, Swift, and platform versions
- [Migration](Documentation/MIGRATION.md) — from a hand-written networking layer
- [Testing](Documentation/TESTING.md) — running the suites, including against a real Laravel app
- [Definition of Done](Documentation/DEFINITION_OF_DONE.md) — the MVP checklist and the test that accepts each item

## Requirements

iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, Swift 6.0+. The integration suite is
run against Laravel 12 and 13 — see
[Compatibility](Documentation/COMPATIBILITY.md).

## Tests

```sh
swift test                                            # unit suite

TestApp/scripts/serve.sh                              # a real Laravel app
LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test     # + integration suite

TestApp/scripts/serve-breeze.sh                       # Laravel's API starter kit
LARAVEL_BREEZE_URL=http://127.0.0.1:8200 swift test   # + starter-kit suite
```

Both fixtures in [`TestApp/`](TestApp) are generated from the official skeleton,
so the kit is verified against Laravel's actual responses rather than mocks of
them. The second one is `php artisan breeze:install api` with nothing of ours
added, which is how starter-kit compatibility is kept honest.
