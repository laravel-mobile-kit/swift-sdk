# Error handling

## The taxonomy

Everything the transport layer produces is a `LaravelError`:

| Case | Meaning |
| --- | --- |
| `.invalidURL(String)` | A path could not be resolved against the base URL |
| `.networkError(underlying:)` | The transport failed before an HTTP response existed |
| `.timeout` | The request exceeded its timeout |
| `.cancelled` | The request was cancelled |
| `.invalidResponse` | The transport returned something that was not an HTTP response |
| `.httpError(HTTPError)` | The server answered with a non-2xx status |
| `.decodingError(_, data:)` | The body could not be decoded — the payload is kept |
| `.encodingError(_)` | The request body could not be encoded |

Every non-successful response arrives as `.httpError` carrying the untouched
payload, rather than as a status-specific case: the body of a 401, 404, or 422
is exactly what a good error message is made of.

```swift
do {
    let event: Event = try await client.get("/api/events/1")
} catch let error as LaravelError {
    error.statusCode          // 404
    error.isNotFound          // true
    error.httpError?.bodyText // what the server actually said
}
```

Convenience checks, all `false` for errors that never reached the server:
`isUnauthorized`, `isForbidden`, `isNotFound`, `isValidationError`,
`isServerError`, `isTimeout`, `isCancelled`.

## Validation errors

Register the middleware once:

```swift
await client.use(.validationErrors)
```

A 422 then arrives as a `LaravelValidationError` instead of a generic HTTP
failure:

```swift
do {
    let created: Event = try await client.post("/api/events", body: draft)
} catch let error as LaravelValidationError {
    error.message                  // "The given data was invalid."
    error["title"]                 // ["The title field is required."]
    error.firstError(for: "title")
    error.hasError(for: "starts_at")
    error.fields                   // ["title", "starts_at"]
    error.firstErrors              // ["title": "…", "starts_at": "…"]
    error.allErrors                // every message, flattened
    error.globalErrors             // messages not tied to a field
}
```

Which is what a form wants:

```swift
Section {
    TextField("Title", text: $title)
    ForEach(validation?["title"] ?? [], id: \.self) { message in
        Text(message).font(.caption).foregroundStyle(.red)
    }
}
```

Without the middleware nothing is lost — the payload is still there:

```swift
catch let error as LaravelError {
    if let validation = error.validationError { … }
}
```

By default only 422 is treated as validation. APIs that use another status say
so: `ValidationErrorMiddleware(statusCodes: [400, 422])`.

## Errors that are not failures

A cancelled request is not an error worth showing:

```swift
catch let error as LaravelError where error.isCancelled {
    // The user moved on. Say nothing.
}
```

Neither is being offline while a session is restoring — that is what
`AuthState.unverified` is for, rather than signing the user out. See
[Authentication](AUTHENTICATION.md).

## Retries

`RetryPolicy` decides what is worth repeating:

```swift
LaravelClientConfiguration(
    baseURL: baseURL,
    retryPolicy: RetryPolicy(
        maxRetries: 3,
        // Defaults to RetryPolicy.defaultRetryableStatusCodes:
        // [408, 429, 500, 502, 503, 504]
        retryableStatusCodes: [408, 429, 500, 502, 503, 504],
        retryableMethods: RetryPolicy.idempotentMethods,   // GET, PUT, DELETE
        backoffStrategy: .exponential(base: 0.5, maxDelay: 30),
        retriesNetworkFailures: true
    )
)
```

`.default` is three retries of idempotent requests with exponential backoff;
`.none` attempts every request exactly once. POST is deliberately absent from
`idempotentMethods`: retrying a payment because a proxy timed out is not a
convenience. Decoding, encoding, and malformed-URL failures are never retried —
they would fail identically.

For failures that need something to *change* before a retry means anything —
refreshing a token, waiting out a rate limit — use a `RetryDecider`. See
[Middleware](MIDDLEWARE.md).

## Timeouts

```swift
// Client-wide:
LaravelClientConfiguration(baseURL: baseURL, timeoutInterval: 30)

// Per request:
try await client.get("/api/report", options: .timeout(120))
```

The per-request timeout wins where both apply, and surfaces as
`LaravelError.timeout`.
