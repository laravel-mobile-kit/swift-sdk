# Middleware and interceptors

Middleware sees every request on the way out and every response on the way back.
It is how the kit adds authentication, validation errors, and versioning — and
how an app adds anything else.

```swift
public protocol Middleware: Sendable {
    func process(_ request: URLRequest) async throws -> URLRequest
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws
}
```

`didReceive` has a default empty implementation, so a middleware that only
rewrites requests implements one method.

## Registering

```swift
await client.use(.auth(provider))
await client.use([.validationErrors, .apiVersion(.v1)])
```

Requests run through middleware in registration order; responses run back
through it in reverse. Order matters when one middleware depends on another's
work — attach the token before anything that signs the finished request.

## Writing one

```swift
struct TracingMiddleware: Middleware {
    let traceID: @Sendable () -> String

    func process(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue(traceID(), forHTTPHeaderField: "X-Trace-Id")
        return request
    }

    func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        metrics.record(status: response.statusCode, bytes: data.count)
    }
}

await client.use(TracingMiddleware { UUID().uuidString })
```

Throwing from `process` fails the request before it is sent. Throwing from
`didReceive` fails it after the response arrived — which is exactly how
`ValidationErrorMiddleware` turns a 422 into a typed error.

## Logging

```swift
await client.use(LoggingMiddleware(level: .headers))
```

| Level | Logs |
| --- | --- |
| `.none` | Nothing |
| `.basic` | Method, URL, status |
| `.headers` | `.basic` plus request and response headers |
| `.body` | `.headers` plus payloads |

Log lines go to `print` unless you redirect them:

```swift
await client.use(LoggingMiddleware(level: .body, sink: { logger.debug("\($0)") }))
```

Bodies and headers contain tokens — keep `.body` out of release builds.

## Headers

Static values belong in the configuration:

```swift
LaravelClientConfiguration(
    baseURL: baseURL,
    defaultHeaders: LaravelClientConfiguration.defaultJSONHeaders
        .merging(["X-App-Version": appVersion]) { _, new in new }
)
```

Values computed per request belong in a provider:

```swift
LaravelClientConfiguration(
    baseURL: baseURL,
    headerProviders: [
        StaticHeaders(["X-Platform": "ios"]),
        DynamicHeaders { ["Accept-Language": await Locale.preferred.identifier] },
    ]
)
```

And a single call can override anything:

```swift
try await client.get("/api/events", options: .headers(["X-Debug": "1"]))
```

Precedence, lowest to highest: default headers → providers → per-request
options → middleware.

## Retry deciders

A `RetryPolicy` repeats failures that pass on their own. A `RetryDecider`
handles failures that need something to change first:

```swift
public protocol RetryDecider: Sendable {
    func shouldRetry(_ error: LaravelError, request: Request, attempt: Int) async throws -> Bool
}
```

```swift
struct RateLimitDecider: RetryDecider {
    func shouldRetry(_ error: LaravelError, request: Request, attempt: Int) async throws -> Bool {
        guard error.statusCode == 429, attempt < 1 else { return false }

        let retryAfter = error.httpError?.response.value(forHTTPHeaderField: "Retry-After")
        try await Task.sleep(nanoseconds: UInt64((Double(retryAfter ?? "1") ?? 1) * 1_000_000_000))
        return true
    }
}

await client.use(retryDecider: RateLimitDecider())
```

Deciders are asked in registration order and the first `true` wins. The retried
request is rebuilt from scratch, so middleware runs again and picks up whatever
the decider changed — which is how a refreshed token reaches the retry.

Throwing from a decider fails the request with a more meaningful error than the
server's: that is how `AuthRefreshRetryDecider` reports
`AuthError.sessionExpired` instead of a bare 401.

## Transports

For everything below the request — certificate pinning, a shared `URLSession`,
a stub in tests — replace the transport:

```swift
let client = LaravelClient(
    configuration: configuration,
    transport: URLSessionTransport(session: pinnedSession)
)
```

```swift
struct StubTransport: HTTPTransport {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (fixture, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
```

Conform to `ProgressReportingTransport` as well when the transport can report
upload progress.
