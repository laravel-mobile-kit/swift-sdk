# Compatibility

## Versions

| Mobile Kit SDK | Laravel API contract | Laravel framework | Swift | iOS | macOS | tvOS | watchOS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0.1.x | unversioned, `/v1` | 12, 13 (verified); 10 and 11 expected | 6.0+ | 15+ | 12+ | 15+ | 8+ |

The three version axes move independently: the SDK version, the version of your
API (`/api/v1`), and the Laravel release the server runs. Shipping Mobile Kit 1.0
does not imply API v1, and upgrading Laravel does not require a new SDK.

The integration suite runs against a Laravel application generated from the
official skeleton — see [Testing](TESTING.md). The whole suite has been run
against Laravel 12 and Laravel 13; `LARAVEL_VERSION` selects which release the
fixture is built from:

```sh
LARAVEL_VERSION='^13.0' TestApp/scripts/serve.sh
```

Laravel 10 and 11 are expected to work — the kit uses only conventions that have
been stable since Laravel 8 — but they are not covered by a run here, so treat
them as unverified rather than guaranteed.

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
