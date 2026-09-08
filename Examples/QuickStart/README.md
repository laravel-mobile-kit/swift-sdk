# Quick Start

A small SwiftUI application that walks the whole integration path: point the SDK
at a Laravel API, sign in, restore the session on the next launch, read a
paginated collection, upload a file both ways, and render Laravel's validation
errors in a form.

It is a package of its own that depends on this repository through a path
dependency, so it compiles exactly as your app would — and `swift build` proves
the documented integration still works.

## Running it

The defaults point at the compatibility fixture in [`TestApp/`](../../TestApp),
so nothing else is needed:

```sh
TestApp/scripts/serve.sh                    # in one terminal
swift run --package-path Examples/QuickStart
```

Sign in with `test@example.com` / `password` — the form is pre-filled.

Point it at your own API instead:

```sh
LARAVEL_TEST_URL=https://api.example.com swift run --package-path Examples/QuickStart
```

Your API needs the endpoints in [`AppConfiguration`](Sources/QuickStart/AppConfiguration.swift)
and [`AppEnvironment`](Sources/QuickStart/AppEnvironment.swift): `/api/login`,
`/api/user`, `/api/logout`, `/api/auth/refresh`, and the `/api/v1` business
routes. Every path is configurable — the kit never dictates an API contract.

## Where each flow lives

| Flow | File |
| --- | --- |
| Configuration — base URL, API version, Keychain service | `AppConfiguration.swift` |
| The whole wiring: Keychain → token provider → middleware → refresh → session | `AppEnvironment.swift` |
| Session restoration at launch | `QuickStartApp.swift`, `ContentView.swift` |
| Sign in, with per-field validation errors from a 422 | `LoginView.swift` |
| Codable requests and Laravel pagination, page by page | `EventsListView.swift` |
| Cancelling a request that is no longer needed | `EventsModel.loadFirstPage` |
| `multipart/form-data` upload with progress | `UploadView.swift` |
| Presigned direct-to-storage upload | `UploadView.swift` |
| Sign out | `AccountView` in `HomeView.swift` |

401 handling and token refresh have no screen of their own on purpose: they are
wired once in `AppEnvironment` and every screen inherits them. Expire the token
from the fixture to watch it work:

```sh
curl -X POST http://127.0.0.1:8000/api/auth/revoke-access-token \
  -H "Authorization: Bearer <token>" -H "Accept: application/json"
```

The next screen refresh recovers without signing the user out.

## Platforms

iOS 16+ / macOS 13+. The sample avoids platform-specific SwiftUI so the same
sources build for both; the kit itself supports iOS 15+, macOS 12+, tvOS 15+,
and watchOS 8+.
