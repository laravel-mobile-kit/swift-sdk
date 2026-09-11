# Compatibility

## Versions

| Mobile Kit SDK | Laravel API contract | Laravel framework | Swift | iOS | macOS | tvOS | watchOS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0.2.x | unversioned, `/v1` | 12 (verified); 10, 11 and 13 expected | 6.0+ | 15+ | 12+ | 15+ | 8+ |

The three version axes move independently: the SDK version, the version of your
API (`/api/v1`), and the Laravel release the server runs. Shipping Mobile Kit 1.0
does not imply API v1, and upgrading Laravel does not require a new SDK.

The integration suite runs against a Laravel application generated from the
official skeleton — see [Testing](TESTING.md). Laravel 12 is what CI builds and
what every release has been tested on. `LARAVEL_VERSION` selects a different
release for a local run:

```sh
rm -rf TestApp/.laravel
LARAVEL_VERSION='^13.0' TestApp/scripts/serve.sh
```

The `rm` is not optional: the fixture is created once, and with `TestApp/.laravel`
already on disk the variable is read by nothing and the old application is served
instead — a run that looks like it proved something about another release.

Laravel 10, 11 and 13 are expected to work — the kit uses only conventions that
have been stable since Laravel 8 — but no run here covers them, so treat them as
unverified rather than guaranteed. Verifying one means adding it to the CI
matrix, not remembering a local run.

## Supported Laravel conventions

| Convention | Status |
| --- | --- |
| Standard JSON responses | Supported |
| API Resources (`data` envelopes) | Supported through your `Codable` models |
| Validation errors (`message` + `errors`) | Supported as `LaravelValidationError` |
| `paginate()` | Supported |
| `simplePaginate()` | Supported |
| `cursorPaginate()` | Supported |
| Resource collections with `meta`/`links` | Supported |
| Standard HTTP status handling | Supported by Core |
| Streamed responses (`text/event-stream`, chunked bodies) | Supported by `LaravelClient.stream` — see [Streaming](STREAMING.md) |
| `multipart/form-data` | Supported by the Uploads module |
| Presigned direct uploads (Vapor-style and hand-written) | Supported |
| Sanctum personal access tokens | Supported |
| Official starter kit (`breeze:install api`) | Verified end to end against unmodified Breeze scaffolding |
| Sanctum SPA cookie sessions | Supported by `LaravelClient.sanctumSPA`, `SanctumSPAAuth`, and `SanctumSPASession` |
| Bearer-token sessions (`AuthManager`, `AuthSession`) | Token APIs; a cookie API uses the Sanctum SPA types instead |
| Passport / OAuth payloads | Supported through `AuthResponseMapper` |
| Non-standard JSON | Supported through the generic Core client |
| Generated models | Never required |

The kit does not invent a response envelope or a pagination format. Where an API
deviates from Laravel's conventions, the generic Core client and a custom
`Codable` model always work — that is the escape hatch, and it is a first-class
one.

## Date formats

Laravel serializes dates as ISO8601 with microsecond precision. All of these
decode:

| Format | Example |
| --- | --- |
| ISO8601 with fractional seconds | `2026-01-15T10:30:00.000000Z` |
| ISO8601 | `2026-01-15T10:30:00Z` |
| SQL date-time (`Y-m-d H:i:s`) | `2026-01-15 10:30:00` |
| Date only | `2026-01-15` (decodes at midnight UTC) |

Encoding always uses the ISO8601 form Laravel expects.

## What is not covered

- Background uploads and downloads (`URLSessionConfiguration.background`).
- OpenAPI-generated models.
- Any transport other than HTTP/JSON — no WebSockets, no GraphQL.

These are deliberate omissions for this release, not gaps to work around.
