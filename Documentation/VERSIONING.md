# API versioning

**The API's version belongs to the Laravel application, not to the kit.** Mobile
Kit 2.0 does not imply API v2: the two move independently, and the middleware
below is how an app says which API version it talks to.

## Adding a version prefix

```swift
await client.use(.apiVersion(.v1))

try await client.get("/api/events")     // → GET /api/v1/events
```

Call sites stay unversioned, so moving the app to v2 is one line:

```swift
await client.use(.apiVersion(.v2))
```

Available versions: `.none`, `.v1`, `.v2`, `.v3`, and `.custom("beta")`.

## What is left alone

- Paths that already name a version. `/api/v2/events` is never rewritten to v1,
  so a call that deliberately targets another version keeps working.
- Paths outside the versioned area — a webhook, a signed storage callback,
  anything not under the configured prefix.
- The authentication routes.

That last one is the point: Laravel apps routinely serve `/api/login` next to
`/api/v1/events`. The default exclusions cover Laravel's conventional auth
paths:

```
/api/login  /api/logout  /api/register  /api/user
/api/auth/refresh  /api/forgot-password  /api/reset-password
/api/email/verification-notification
```

When your auth routes differ, hand the middleware your `AuthConfiguration` and
it excludes exactly what you configured:

```swift
import LaravelMobileKit   // this initialiser sees both Laravel and Auth

await client.use(APIVersionMiddleware(version: .v1, excluding: authConfiguration))
```

Or list the paths yourself:

```swift
await client.use(
    .apiVersion(
        .v1,
        excludedPaths: APIVersionMiddleware.defaultExcludedPaths.union(["/api/auth"])
    )
)
```

An exclusion matches the path itself and everything under it, so `/api/auth`
covers `/api/auth/refresh`.

## A different prefix

```swift
await client.use(.apiVersion(.v1, pathPrefix: "/rest"))

try await client.get("/rest/events")    // → GET /rest/v1/events
```

## Header-based versioning

Some APIs version through a header rather than a path. That is an ordinary
default header — no middleware needed:

```swift
LaravelClientConfiguration(
    baseURL: baseURL,
    defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders
        .merging(["Accept-Version": "2024-01-01"]) { _, new in new }
)
```

## Talking to two versions at once

During a migration, use one client per version. They can share a credential
store, so both are authenticated by the same token:

```swift
let v1 = LaravelClient(configuration: configuration)
await v1.use([.auth(provider), .apiVersion(.v1)])

let v2 = LaravelClient(configuration: configuration)
await v2.use([.auth(provider), .apiVersion(.v2)])
```
