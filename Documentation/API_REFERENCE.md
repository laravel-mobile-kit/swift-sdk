# API reference

Every public type, by module. The guides explain how they fit together; this is
the index.

## LaravelMobileKitCore

### Client

| Type | Purpose |
| --- | --- |
| `actor LaravelClient` | The root client. One per API. |
| `struct LaravelClientConfiguration` | `baseURL`, `defaultHeaders`, `headerProviders`, `timeoutInterval`, `retryPolicy` |
| `struct RequestOptions` | Per-request `timeout` and `headers`. `.none`, `.timeout(_)`, `.headers(_)` |
| `struct Request` | A transport-agnostic request: method, path, query, headers, body, timeout |
| `struct Response<Value>` | A decoded value plus `httpResponse`, `rawData`, `statusCode`, `headers` |
| `enum HTTPMethod` | `.get`, `.post`, `.put`, `.patch`, `.delete` |
| `struct EmptyResponse` | Stand-in for a body-less response, such as `204` |

```swift
// Decoded verbs
func get<T: Decodable>(_ path: String, query: [String: String]?, options: RequestOptions) async throws -> T
func post<T: Decodable, B: Encodable>(_ path: String, body: B?, query: [String: String]?, options: RequestOptions) async throws -> T
func put<T: Decodable, B: Encodable>(_ path: String, body: B?, query: [String: String]?, options: RequestOptions) async throws -> T
func patch<T: Decodable, B: Encodable>(_ path: String, body: B?, query: [String: String]?, options: RequestOptions) async throws -> T
func delete<T: Decodable>(_ path: String, query: [String: String]?, options: RequestOptions) async throws -> T

// Metadata and raw payloads
func response<T: Decodable>(_ method: HTTPMethod, _ path: String, query: [String: String]?, body: Data?, options: RequestOptions, onProgress: (@Sendable (UploadProgress) -> Void)?) async throws -> Response<T>
func raw(_ method: HTTPMethod, _ path: String, query: [String: String]?, body: Data?, options: RequestOptions, onProgress: (@Sendable (UploadProgress) -> Void)?) async throws -> Response<Data>

// Pipeline
func use(_ middleware: any Middleware)
func use(_ middlewares: [any Middleware])
func use(retryDecider: any RetryDecider)
```

A path that already carries a scheme is used as-is, so a fully-qualified URL —
a presigned upload endpoint, say — goes through the same client.

### Errors

| Type | Purpose |
| --- | --- |
| `enum LaravelError` | Every transport-level failure. `statusCode`, `httpError`, `isUnauthorized`, `isForbidden`, `isNotFound`, `isValidationError`, `isServerError`, `isTimeout`, `isCancelled` |
| `struct HTTPError` | `statusCode`, `data`, `response`, `bodyText`, plus the same status predicates |

### Serialization

| Type | Purpose |
| --- | --- |
| `enum LaravelJSONDecoder` | `makeDefault()` — `snake_case` keys, Laravel date formats |
| `enum LaravelJSONEncoder` | `makeDefault()` — `snake_case` keys, ISO8601 dates |
| `enum LaravelDateFormat` | `date(from:)`, `string(from:)` for Laravel's date shapes |

### Retries

| Type | Purpose |
| --- | --- |
| `struct RetryPolicy` | `maxRetries`, `retryableStatusCodes`, `retryableMethods`, `backoffStrategy`, `retriesNetworkFailures`, `jitter`, `maximumRetryAfter`. `wait(forAttempt:after:now:)` honours `Retry-After`. `.default`, `.none`, `idempotentMethods` |
| `enum RetryPolicy.Jitter` | `.none`, `.full` |
| `enum BackoffStrategy` | `.none`, `.constant(delay:)`, `.exponential(base:maxDelay:)` |
| `protocol RetryDecider` | `shouldRetry(_:request:attempt:)` — recovery that changes something first |

### Middleware, headers, transport

| Type | Purpose |
| --- | --- |
| `protocol Middleware` | `process(_:)`, `didReceive(_:data:)` |
| `struct LoggingMiddleware` | `.none`, `.basic`, `.headers`, `.body`; `bodies:` and `redactedHeaders:` control what is withheld; custom `sink` |
| `protocol HeaderProvider` | `headers()` computed per request |
| `struct StaticHeaders`, `struct DynamicHeaders` | The two ready-made providers |
| `protocol HTTPTransport` | `execute(_:)` — swap for pinning, stubs, a shared session |
| `final class URLSessionTransport` | The default transport. `init(configuration:)`, `init(session:)` |
| `protocol ProgressReportingTransport` | Transports that report body progress |
| `struct UploadProgress` | `bytesSent`, `totalBytes`, `fractionCompleted` |

## LaravelMobileKitLaravel

| Type | Purpose |
| --- | --- |
| `struct Page<Item>` | One page of any Laravel paginator. `items`, `currentPage`, `lastPage`, `perPage`, `total`, `from`, `to`, `path`, `nextPageURL`, `previousPageURL`, `firstPageURL`, `lastPageURL`, `nextCursor`, `previousCursor`, `kind`, `hasNextPage`, `hasPreviousPage`, `isEmpty` |
| `enum PaginationKind` | `.length`, `.simple`, `.cursor` |
| `struct PageSequence<Item>` | `AsyncSequence` over the pages of one endpoint |
| `struct LaravelValidationError` | `message`, `errors`, `statusCode`, `rawData`, `subscript(field:)`, `firstError(for:)`, `hasError(for:)`, `fields`, `firstErrors`, `allErrors`, `globalErrors`, `hasErrors` |
| `struct ValidationErrorMiddleware` | `.validationErrors`, or `init(statusCodes:)` |
| `enum APIVersion` | `.none`, `.v1`, `.v2`, `.v3`, `.custom(String)` |
| `struct APIVersionMiddleware` | `.apiVersion(_:pathPrefix:excludedPaths:)`, `defaultExcludedPaths` |

```swift
func page<Item>(_ path: String, query: [String: String]?, options: RequestOptions) async throws -> Page<Item>
func nextPage<Item>(after page: Page<Item>, options: RequestOptions) async throws -> Page<Item>?
func previousPage<Item>(before page: Page<Item>, options: RequestOptions) async throws -> Page<Item>?
nonisolated func pages<Item>(of type: Item.Type, at path: String, query: [String: String]?, options: RequestOptions) -> PageSequence<Item>

extension LaravelError {
    var validationError: LaravelValidationError? { get }
}
```

## LaravelMobileKitAuth

The module covers two contracts. Token APIs — Sanctum personal access tokens,
Passport, a hand-written controller — use `AuthManager` and the Keychain.
Cookie APIs, which is what Laravel's own API starter kit generates, use the
Sanctum SPA types. Both publish the same `AuthState`.

### Token APIs

| Type | Purpose |
| --- | --- |
| `actor AuthManager<User>` | `login(email:password:deviceName:extraFields:)`, `login(fields:)`, `register(fields:)`, `logout()`, `currentUser()`, `requestPasswordReset(email:)`, `resendEmailVerification()` |
| `struct AuthResult<User>` | The credential and, when the response carried one, the user |
| `struct AuthConfiguration` | Every endpoint path. `.laravel`, `allEndpoints` |
| `struct AuthResponseMapper<User>` | `makeCredential`, `makeUser`; `.laravel` reads the common shapes |
| `@MainActor final class AuthSession<User>` | `state`, `user`, `lastError`, `restore()`, `signIn(with:)`, `adopt(user:)`, `reloadUser()`, `logout()`, `endSession(reason:)`, `authFailureHandler()` |
| `struct AuthCredential` | `accessToken`, `refreshToken`, `tokenType`, `expiresAt`, `isExpired`, `expires(within:from:)`, `authorizationHeaderValue` |
| `protocol CredentialStore` | `store(_:)`, `retrieve()`, `delete()` |
| `final class KeychainCredentialStore` | `init(service:account:accessGroup:accessibility:usesDataProtectionKeychain:)` |
| `actor InMemoryCredentialStore` | For tests and previews |
| `protocol TokenProvider` | `currentToken()`, `refreshToken()`, `clearToken()` |
| `actor CredentialTokenProvider` | A provider backed by a `CredentialStore`, with an `expiryLeeway` |
| `struct StaticTokenProvider` | A fixed API token |
| `struct AuthMiddleware` | `.auth(_:transport:)` |
| `enum AuthTransport` | `.bearer`, `.scheme(String)`, `.cookie`, `.custom(_)` |
| `actor TokenRefreshCoordinator` | `refreshIfNeeded()`, `invalidate()`, `isRefreshing` — single-flight refresh |
| `struct AuthRefreshRetryDecider` | `init(coordinator:maxAttempts:onAuthFailure:)` |

### Cookie sessions (Sanctum SPA)

| Type | Purpose |
| --- | --- |
| `LaravelClient.sanctumSPA(baseURL:cookieStorage:timeoutInterval:retryPolicy:additionalHeaders:)` | A client wired for a cookie session: the jar, the stateful-domain `Referer`, and the CSRF middleware |
| `actor SanctumSPAAuth<User>` | `startSession()`, `login(email:password:extraFields:)`, `login(fields:)`, `register(fields:)`, `currentUser()`, `logout()`, `requestPasswordReset(email:)`, `resendEmailVerification()` |
| `struct SanctumSPAConfiguration` | Endpoint paths. `.breeze` matches Laravel's API starter kit |
| `@MainActor final class SanctumSPASession<User>` | `state`, `user`, `lastError`, `restore()`, `adopt(user:)`, `reloadUser()`, `signedOut()`, `endSession(reason:)` |
| `struct SanctumCSRFMiddleware` | `.sanctumCSRF(baseURL:cookieStorage:)`, with configurable cookie and header names |

### Shared

| Type | Purpose |
| --- | --- |
| `enum AuthState<User>` | `.unknown`, `.restoring`, `.unauthenticated`, `.authenticated(User)`, `.unverified`, plus `user`, `isAuthenticated`, `isSettled` |
| `enum AuthError` | `.notAuthenticated`, `.refreshNotSupported`, `.noRefreshToken`, `.sessionExpired`, `.endpointNotConfigured(String)`, `.invalidAuthResponse` |
| `enum KeychainError` | `.unableToStore(OSStatus)`, `.unableToRetrieve(OSStatus)`, `.unableToDelete(OSStatus)`, `.corruptedCredential`, plus `status` and `isKeychainUnavailable` |

## LaravelMobileKitUploads

| Type | Purpose |
| --- | --- |
| `struct UploadFile` | `data`, `fieldName`, `fileName`, `mimeType` |
| `struct MultipartFormData` | `append(_:)`, `append(fields:)`, `contentType`, `boundary`, `isEmpty`, `encode()` |
| `enum MIMEType` | `inferred(fromFileName:)` |
| `actor DirectUploader` | `authorize(at:fields:size:)`, `send(_:to:timeout:onProgress:)`, `upload(…)` |
| `struct PresignedUpload` | `url`, `method`, `headers`, `key`, `bucket`, `uuid`; `init?(data:)` reads the common authorization shapes |
| `enum UploadError` | `.invalidAuthorization`, `.directUploadFailed(statusCode:body:)` |

```swift
func upload<T: Decodable>(_ data: Data, to path: String, fieldName: String, fileName: String, mimeType: String?, fields: [String: String], method: HTTPMethod, options: RequestOptions, onProgress: (@Sendable (UploadProgress) -> Void)?) async throws -> T
func upload<T: Decodable>(_ files: [UploadFile], to path: String, fields: [String: String], method: HTTPMethod, options: RequestOptions, onProgress: (@Sendable (UploadProgress) -> Void)?) async throws -> T
func upload<T: Decodable>(_ form: MultipartFormData, to path: String, method: HTTPMethod, options: RequestOptions, onProgress: (@Sendable (UploadProgress) -> Void)?) async throws -> T
nonisolated func directUploader(storageTransport: any HTTPTransport) -> DirectUploader
```

## LaravelMobileKit

Re-exports all four modules, and adds the one initialiser that needs two of them
at once:

```swift
APIVersionMiddleware(version: .v1, pathPrefix: "/api", excluding: authConfiguration)
```

## Source documentation

Every public declaration carries a doc comment; Xcode's Quick Help shows them,
and `swift package generate-documentation` produces a DocC archive if you add
[swift-docc-plugin](https://github.com/apple/swift-docc-plugin) to your own
package.
