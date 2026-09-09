# Changelog

## 0.2.0

The first release with a version anyone can resolve: `0.1.0` was described in
the README but never tagged, so `from: "0.1.0"` could not be satisfied.

### Security

- **`LoggingMiddleware` no longer prints credentials.** `Authorization`,
  `Cookie`, `Set-Cookie` and the other credential-bearing headers are replaced
  with `<redacted>` at every level, and the set is configurable via
  `redactedHeaders:`.
- **Bodies are no longer printed by raising a log level.** `.body` reports
  `<123 bytes>`; printing content now takes a separate `bodies: .unredacted`
  argument, so the dangerous choice is visible at the call site.

### Added

- **Streaming.** `client.stream(_:_:body:query:options:)` returns the response
  body as `AsyncThrowingStream<Data, any Error>`. The status is validated and
  retries are exhausted before the first chunk, so an error body can never
  arrive looking like content. `StreamingTransport` is the capability;
  `URLSessionTransport` conforms, and a transport that cannot stream reports
  `LaravelError.streamingUnsupported` rather than quietly buffering. See
  [Streaming](Documentation/STREAMING.md).
- **Idempotency keys.** `RequestOptions.idempotencyKey` sends
  `Idempotency-Key` — the header name is configurable via
  `LaravelClientConfiguration.idempotencyKeyHeader` — and makes that one request
  retryable whatever its method, which is the trade `POST` is excluded from
  `idempotentMethods` for.
- **Sign in with Apple.** `SignInWithAppleNonce` holds the raw and hashed forms
  and names them after where each one goes.
  `AuthManager.login(identityToken:nonce:provider:extraFields:fieldNames:)`
  performs the exchange. `AuthConfiguration.identityTokenEndpoint` gives it its
  own route when the API has one. Nothing is Apple-specific but the defaults.
- **`Retry-After`.** Honoured in both wire forms, delay-seconds and HTTP-date,
  replacing the backoff schedule when present.
- **Jitter.** `RetryPolicy.jitter` defaults to `.full`, so clients that fail
  together no longer retry together.

### Changed

- `RetryPolicy` gained `jitter` and `maximumRetryAfter`; a server asking for a
  longer wait than `maximumRetryAfter` (60s) ends the retries rather than being
  ignored or obeyed without bound.
- `RetryPolicy.shouldRetry(_:request:)` is the overload the client now uses;
  `shouldRetry(_:method:)` remains.
- `LaravelError` gained `.streamingUnsupported`.

### Fixed

- **`KeychainCredentialStore` was not safe to use concurrently**, which its
  protocol promises. It shared a `JSONEncoder` and `JSONDecoder` across callers;
  coders are now created per call.
- **`KeychainCredentialStore.store()` could lose a write.** It did
  `SecItemDelete` then `SecItemAdd`, two steps that are not atomic, so two
  writers could both delete, both add, and leave one failing with
  `errSecDuplicateItem` having stored nothing. No lock could fix it — an app and
  its extensions share one access-group item, so the racing writer is usually in
  another process. It now adds first and updates on collision.

### Notes

`CredentialTokenProvider` reads the store on every call and holds no copy; that
behaviour is now covered by tests, because caching there would strand an app's
extensions on a token the server has stopped accepting.
