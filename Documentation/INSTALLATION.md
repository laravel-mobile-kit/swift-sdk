# Installation

## Swift Package Manager

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/laravel-mobile-kit/swift-sdk.git", from: "0.1.0")
],
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "LaravelMobileKit", package: "swift-sdk")
        ]
    )
]
```

In Xcode: **File → Add Package Dependencies…**, paste the repository URL, and
add the `LaravelMobileKit` product to your app target.

## Choosing modules

`LaravelMobileKit` re-exports everything. An app that wants a smaller dependency
surface depends on the capabilities it actually uses:

| Product | Depends on | Use it for |
| --- | --- | --- |
| `LaravelMobileKitCore` | — | HTTP, Codable, errors, retries, middleware |
| `LaravelMobileKitLaravel` | Core | Validation errors, pagination, versioning |
| `LaravelMobileKitAuth` | Core | Keychain storage, tokens, sessions, refresh |
| `LaravelMobileKitUploads` | Core | Multipart and direct uploads |
| `LaravelMobileKit` | all of the above | Everything, one import |

```swift
// Everything:
import LaravelMobileKit

// Or only what you use:
import LaravelMobileKitCore
import LaravelMobileKitLaravel
```

One combination is worth knowing about: versioning that skips the authentication
routes needs both the Laravel and Auth modules, so
`APIVersionMiddleware(version:excluding:)` lives in the umbrella module. See
[Versioning](VERSIONING.md).

## Platforms

| Platform | Minimum |
| --- | --- |
| iOS | 15.0 |
| macOS | 12.0 |
| tvOS | 15.0 |
| watchOS | 8.0 |
| Swift | 6.0 (the package builds in Swift 6 language mode) |

The kit uses `async`/`await` throughout and is written for strict concurrency:
every public type is `Sendable`, and `LaravelClient` is an actor, so one client
can be shared across the whole app.

## App Transport Security

Requests go through `URLSession`, so the usual rules apply: HTTPS in production,
and an ATS exception if you point a debug build at a plaintext local server.
