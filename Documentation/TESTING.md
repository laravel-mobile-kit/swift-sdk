# Testing

## The suites

| Suite | What it proves | Needs |
| --- | --- | --- |
| `LaravelMobileKitTests` | Request construction, serialization, error mapping, retries, cancellation, auth state, refresh coordination, middleware — against a mocked transport | Nothing |
| `LaravelMobileKitIntegrationTests` | The same contracts against a real Laravel application | `LARAVEL_TEST_URL` |
| `Laravel starter kit (Breeze API)` | The kit against scaffolding Laravel generated, not ours | `LARAVEL_BREEZE_URL` |

```sh
swift test                                            # unit suite only
TestApp/scripts/serve.sh                              # in another terminal
LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test     # + the integration suite

TestApp/scripts/serve-breeze.sh                       # the starter-kit fixture
LARAVEL_BREEZE_URL=http://127.0.0.1:8200 swift test   # + the starter-kit suite
```

Each suite skips itself when its variable is unset, so `swift test` stays useful
on a machine with no fixture running.

## The fixtures

[`TestApp/`](../TestApp) holds a Laravel application generated from the official
skeleton with this repository's routes, controllers, models, and seed data
applied on top. It is a real Laravel install, deliberately: mocked responses can
only prove the kit against our idea of Laravel.

```sh
docker compose -f TestApp/docker-compose.yml up --build    # or
TestApp/scripts/serve.sh                                   # PHP 8.2+ and Composer
```

Seed data: `test@example.com` / `password`, and 45 events titled `Event 01`…
`Event 45`. The endpoint list is in [`TestApp/README.md`](../TestApp/README.md).

The second fixture, `TestApp/.breeze`, is `laravel/laravel` plus
`php artisan breeze:install api` and nothing else — no overlay, no routes of
ours. It proves the kit against the contract Laravel's own starter kit
generates, which is a cookie session rather than a bearer token:

```sh
TestApp/scripts/serve-breeze.sh    # builds and serves on :8200
```

## Testing your own app against the kit

Swap the transport rather than the network:

```swift
struct StubTransport: HTTPTransport {
    let result: Result<(Data, HTTPURLResponse), any Error>

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try result.get()
    }
}

let client = LaravelClient(
    configuration: .init(baseURL: baseURL, retryPolicy: .none),
    transport: StubTransport(result: .success((fixture, response)))
)
```

Two details make these tests predictable:

- Use `retryPolicy: .none` unless the retry behaviour is what you are testing;
  otherwise a stubbed failure is attempted four times.
- Use `InMemoryCredentialStore` instead of the Keychain, which an unsigned test
  binary cannot always reach.

For view models built on `AuthSession`, drive the state through the session
rather than the network: `signIn(with:)` takes a credential you construct. The
cookie-session equivalent is `SanctumSPASession.adopt(user:)`.

A cookie-session client needs a jar of its own per test, or one test signs
another one in:

```swift
let jar = URLSessionConfiguration.ephemeral.httpCookieStorage!
let client = await LaravelClient.sanctumSPA(baseURL: baseURL, cookieStorage: jar)
```
