# Testing

## The suites

| Suite | What it proves | Needs |
| --- | --- | --- |
| `LaravelMobileKitTests` | Request construction, serialization, error mapping, retries, cancellation, auth state, refresh coordination, middleware — against a mocked transport | Nothing |
| `LaravelMobileKitIntegrationTests` | The same contracts against a real Laravel application | A running fixture |

```sh
swift test                                            # unit suite only
TestApp/scripts/serve.sh                              # in another terminal
LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test     # both suites
```

Without `LARAVEL_TEST_URL` every integration suite skips itself, so `swift test`
stays useful on a machine with no fixture.

## The fixture

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
rather than the network: `signIn(with:)` takes a credential you construct.
