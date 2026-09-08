# Laravel Mobile Kit

> **Status:** product specification, ready for MVP development handoff.
>
> **Editorial rules for this document:**
> - One authoritative location per requirement. If a requirement appears twice, one of the occurrences is a bug.
> - Heading scheme: `#` document title, `##` numbered sections, `###` subsections. Numbering is continuous and unique.
> - The architecture decisions adopted in September 2026 are normative and are merged into the relevant sections below. See [Appendix A](#appendix-a--decision-provenance) for provenance.

---

## 1. Product

**Name:** Laravel Mobile Kit

**Tagline:** Build native mobile apps with Laravel.

**Positioning:**

> **Laravel Mobile Kit is the native client layer for Laravel APIs.**

Open-source SDK and tooling that make Laravel a first-class backend for native iOS and Android applications.

Mobile Kit provides a native client-side layer that works with existing Laravel REST APIs. It **does not** replace Laravel, introduce a new backend protocol, or require a BaaS.

---

## 2. Vision

**Make Laravel a first-class backend for native applications.**

A developer with an existing Laravel REST API should be able to build a native mobile application without rewriting the backend, installing a mandatory Mobile Kit server package, or adopting a proprietary protocol.

Target experience:

```
Existing Laravel API
        │
        ▼
Laravel Mobile Kit
        │
   ┌────┴────┐
   ▼         ▼
  iOS     Android
 Swift     Kotlin
```

The first implementation targets **Swift/iOS**. Kotlin/Android is a future SDK that must use the same backend contract and architectural principles.

---

## 3. Problem

Laravel is an excellent backend framework, but native developers repeatedly implement the same integration layer:

- HTTP networking;
- authentication and session restoration;
- secure token handling;
- Laravel validation errors;
- pagination;
- multipart uploads;
- API models and serialization;
- API versioning;
- request cancellation, retries, and middleware.

The result is duplicated boilerplate in every native application.

Mobile Kit standardizes this **client layer** while leaving the Laravel backend in control of routes, authentication, API contracts, and business logic.

---

## 4. What Mobile Kit Is / Is Not

### 4.1 Mobile Kit IS

- a native SDK for Laravel REST APIs;
- Laravel-convention-aware client infrastructure;
- a Swift-first library;
- modular and extensible;
- compatible with existing Laravel APIs;
- optional tooling for OpenAPI and code generation.

### 4.2 Mobile Kit IS NOT

- a BaaS;
- a replacement for Laravel;
- a database abstraction;
- a new authentication protocol;
- a cross-platform UI framework;
- a mandatory Laravel backend package;
- a replacement for API design;
- a requirement to modify an existing Laravel API.

The binding, testable form of this list is [§8.4 Permanent non-goals](#84-permanent-non-goals).

---

## 5. Core Principles

### 5.1 Laravel-first

Mobile Kit follows Laravel conventions instead of creating a proprietary backend protocol.

If Laravel provides a standard mechanism, Mobile Kit should integrate with that mechanism.

### 5.2 Invisible to the Laravel developer

**Mobile Kit must never require a Laravel developer to know that a Mobile Kit client exists.**

A Laravel developer must be able to build a completely ordinary Laravel API using routes, controllers, Form Requests, API Resources, Eloquent, policies, and standard Laravel authentication. Mobile Kit is a consumer of that API, not a required part of its server-side architecture.

For example, this remains a normal Laravel endpoint:

```php
Route::get('/events', [EventController::class, 'index']);

public function index()
{
    return EventResource::collection(
        Event::latest()->paginate()
    );
}
```

The iOS client can consume it without any Mobile Kit-specific server abstraction:

```swift
let events: Paginated<Event> = try await client.get("/api/events")
```

The Laravel backend must remain independently usable by web clients, third-party clients, Postman, curl, and other native applications.

### 5.3 Zero backend modification

**Core SDK functionality must never require a special Laravel package.**

If an existing Laravel API already exposes the required endpoint, Mobile Kit must be able to consume it.

```swift
let events: [Event] = try await client.get("/api/events")
```

This must work without installing a Mobile Kit package on the server.

This principle applies to the foundational SDK and its standard capabilities. Optional future server-side integrations may exist for convenience, but they must never become a prerequisite for consuming an ordinary Laravel API — see [§24 Optional Laravel Server Extensions](#24-optional-laravel-server-extensions).

### 5.4 Laravel-native, not Laravel-only

The underlying HTTP client remains generic and useful with any REST endpoint.

Laravel-specific capabilities provide conventions around that generic transport:

```
Generic HTTP client
        +
Laravel conventions
        =
Laravel Mobile Kit
```

The SDK must not hard-code assumptions that every endpoint is Laravel-specific.

#### Escape hatch: arbitrary HTTP

Every important capability must retain a generic escape hatch. A developer must always be able to call an arbitrary endpoint directly and provide their own Codable request/response types and configuration.

The SDK must never force developers into resource-specific APIs such as `client.events.list()` or `client.posts.create()` as the only way to access their backend. Typed convenience APIs and generated clients may be layered on top later, but generic HTTP remains the foundational contract.

### 5.5 Native experience

The SDK must feel like a native Swift library rather than a PHP client translated into Swift.

For iOS:

- Swift concurrency;
- `async/await`;
- `Codable`;
- `URLSession`;
- Keychain for credentials;
- SwiftUI-friendly APIs;
- structured errors;
- cancellation support.

### 5.6 Modular architecture

Optional capabilities must not unnecessarily increase the dependency surface of the Core SDK. Applications must be able to depend only on the capabilities they use.

---

## 6. Design Goals

The project must optimize for a small set of explicit goals:

- Existing Laravel REST APIs must work without backend modification for Core functionality.
- The Swift API must feel native to iOS developers rather than like a PHP client translated into Swift.
- Laravel-specific behavior must be isolated from generic HTTP transport where practical.
- The SDK must expose predictable behavior and avoid hidden networking/authentication magic.
- Optional capabilities must remain modular and must not unnecessarily expand the Core dependency surface.

---

## 7. Product Architecture

### 7.1 Module map

This tree is the authoritative module layout. Pagination, uploads, authentication, and Laravel-specific error handling are **capabilities**, not responsibilities of the Core transport layer.

```
LaravelMobileKit
│
├── Core                          — generic REST transport
│   ├── HTTP
│   ├── Request / Response
│   ├── Middleware
│   ├── Serialization (Codable)
│   ├── Errors
│   ├── Configuration
│   └── Cancellation
│
├── Laravel                       — Laravel conventions
│   ├── Validation errors
│   ├── Pagination
│   ├── API Resources
│   └── API versioning
│
├── Auth
│   ├── Credentials
│   ├── CredentialStore (Keychain)
│   ├── TokenProvider
│   ├── Authenticator
│   └── Session / auth state
│
├── Uploads
│   └── Multipart (+ presigned upload flow)
│
├── Future Extensions             — outside MVP, see §23
│   ├── Realtime
│   ├── Push
│   ├── Devices
│   ├── Storage
│   ├── Deep Links
│   ├── Offline
│   └── Sync
│
└── Tooling                       — P1, see §22
    └── OpenAPI / code generation
```

Future extensions must be modular and must not make Core depend on functionality that most applications do not need.

### 7.2 Core boundary

`LaravelMobileKitCore` must remain a small, generic REST client. Core owns HTTP transport, requests/responses, Codable serialization, middleware, errors, configuration, and cancellation.

Laravel-specific conventions and higher-level capabilities must not be forced into Core. The Core must remain useful with generic, non-Laravel REST APIs.

### 7.3 Pagination boundary

Pagination parsing belongs to the Laravel capability, not to generic Core. Core provides only generic HTTP and Codable functionality; the Laravel module understands Laravel pagination formats and exposes an idiomatic Swift API for fetching subsequent pages. See [§14](#14-pagination).

### 7.4 Upload boundary

Multipart construction is an HTTP capability. Laravel-specific upload conventions belong outside Core where practical. See [§15](#15-file-uploads).

### 7.5 Authentication boundary

Authentication is a capability module with its own separation between transport, credential storage, and auth flows. Auth must not leak Laravel-package-specific assumptions into Core. See [§13](#13-authentication).

---

## 8. Scope

The MVP is intentionally narrow. It prioritizes a production-ready Core, the essential Laravel conventions, and authentication infrastructure over breadth.

This section is the single authoritative location for scope. No other section may add or remove MVP features.

### 8.1 MVP — P0

- Swift SDK;
- Core HTTP client;
- native Swift `async/await` API;
- Codable serialization;
- authentication primitives;
- secure credential storage (Keychain);
- session restoration;
- deterministic 401 handling;
- configurable token refresh;
- structured Laravel errors;
- pagination;
- multipart uploads;
- direct file uploads using Laravel-generated presigned URLs;
- request cancellation;
- timeout configuration;
- retries;
- middleware/interceptors;
- custom headers;
- API versioning support;
- test suite;
- documentation and integration examples.

### 8.2 P1 — after the production-ready Core release

These must not block MVP:

- OpenAPI code generation;
- advanced authentication flows;
- background uploads/downloads;
- additional pagination convenience APIs.

### 8.3 P2 / P3 — deferred

These must not influence Core architecture and must not block the first production-ready release:

- push notifications;
- device management;
- realtime/WebSockets;
- deep links;
- offline-first data layer;
- synchronization/conflict resolution;
- background sync;
- generic storage-provider abstraction;
- Kotlin SDK;
- CLI.

They may be implemented later as separate modules or tooling. See [§23 Future Extensions](#23-future-extensions).

### 8.4 Permanent non-goals

Unlike §8.2 and §8.3, these are not deferrals. Mobile Kit must never:

- require a special Laravel server package for Core functionality;
- introduce a proprietary backend protocol;
- become a BaaS;
- replace or reimplement Laravel authentication as a new auth protocol;
- dictate API architecture or replace API design;
- become an ORM or database abstraction;
- provide a cross-platform UI framework;
- require generated models for normal usage;
- generate an API client without an explicit OpenAPI contract;
- turn the root client into a monolithic service container;
- make offline synchronization a hidden HTTP cache;
- require direct uploads to use a Mobile Kit-specific storage protocol;
- require a proprietary response envelope or pagination format.

### 8.5 Scope rule

> **Do not add a feature to the MVP merely because it is useful for mobile applications. Add it only if it is necessary to make Laravel a first-class backend for native clients.**

When in doubt, prefer the smallest Core API that solves the problem without introducing backend coupling or proprietary conventions.

The success criterion is not the number of features. It is the quality of this experience:

```
I have a Laravel API.

I install Laravel Mobile Kit.

I point it at my API.

I authenticate.

I call my API.

I get a native Swift experience.
```

### 8.6 Priority table

| Feature | Priority |
| --- | --- |
| Swift Core SDK | P0 |
| HTTP Client | P0 |
| Authentication | P0 |
| Secure Credential Storage | P0 |
| Structured Errors | P0 |
| Serialization | P0 |
| Pagination | P0 |
| Uploads | P0 |
| API Versioning | P0 |
| Testing / Documentation | P0 |
| OpenAPI | P1 |
| Code Generation | P1 |
| Realtime | P2 |
| Push / Devices | P2 |
| Storage | P2 |
| Offline / Sync | P3 |
| Kotlin SDK | P3 |

---

## 9. Public API Design — SDK #1, Swift / iOS

The first SDK is Swift. The SDK must define and document a stable, idiomatic Swift public API before implementation is considered complete.

### 9.1 Required coverage

The public API must explicitly cover:

- GET, POST, PUT, PATCH, DELETE;
- query parameters;
- custom headers;
- Codable request bodies;
- Codable response decoding;
- raw response metadata when explicitly requested;
- structured errors;
- cancellation;
- timeout configuration;
- retry policy;
- middleware/interceptors.

### 9.2 Shape of the root client

The root client must remain small and predictable. It must not become a collection of unrelated services. Additional capabilities are exposed through dedicated modules.

Illustrative target:

```swift
let client = LaravelClient(
    baseURL: URL(string: "https://api.example.com")!
)

let events: [Event] = try await client.get("/api/events")

let event: Event = try await client.post(
    "/api/events",
    body: CreateEventRequest(...)
)
```

These examples are design targets. The final API must be selected for idiomatic Swift usage and then treated as a documented contract.

---

## 10. Core HTTP Client

The HTTP client must support:

- GET;
- POST;
- PUT;
- PATCH;
- DELETE;
- multipart requests;
- uploads;
- downloads;
- request cancellation;
- configurable timeout;
- retries;
- middleware/interceptors;
- custom headers;
- Codable request/response serialization;
- HTTP status handling;
- access to raw response metadata when required.

The client must use `URLSession` and Swift concurrency on iOS.

Retry behavior must be explicit and configurable. Automatic retries must not blindly apply to every HTTP method.

---

## 11. Serialization / API Resources

The SDK must use `Codable` for normal Swift model serialization.

It must work naturally with Laravel API Resources and standard JSON responses.

Handwritten Codable models are the first-class workflow. The SDK must not require generated models for basic usage; code generation is optional tooling and must never become a runtime dependency (see [§22](#22-openapi-and-code-generation--p1)).

---

## 12. Errors and Validation

Laravel validation responses must be exposed as structured native errors.

```swift
catch let error as LaravelValidationError {
    let emailError = error.errors["email"]
}
```

The error model must preserve:

- HTTP status;
- Laravel message;
- field-level errors;
- global errors;
- raw response information when explicitly requested.

The API must be suitable for direct integration with SwiftUI forms.

Generic HTTP status handling belongs to Core; Laravel validation parsing belongs to the Laravel module (see [§7.2](#72-core-boundary)).

---

## 13. Authentication

Authentication is the first major feature after Core HTTP. The goal is to integrate with Laravel authentication mechanisms, **not to create a new auth protocol**.

### 13.1 Architecture

Authentication must be protocol-oriented and must not assume a single Laravel authentication implementation.

```
Authentication
│
├── Transport
│   ├── Bearer Token
│   ├── Cookie / Session
│   └── Custom
│
├── Credential Storage
│   └── Keychain
│
├── Primitives
│   ├── CredentialStore
│   ├── TokenProvider
│   ├── Authenticator
│   └── Session
│
└── Auth Flows (configurable endpoints)
    ├── Login
    ├── Register
    ├── Logout
    ├── Current User
    ├── Session Restoration
    ├── Password Reset
    ├── Email Verification
    ├── 2FA
    └── Social / Apple
```

Supported transport strategies must include Bearer token, cookie/session authentication where required by an existing API, and custom authentication through extensible interfaces.

Laravel Sanctum may be documented as a recommended Laravel use case, but Mobile Kit must not require Sanctum or any specific server-side authentication package.

Core operations should support a developer experience such as:

```swift
try await client.auth.login(...)
try await client.auth.logout()
let user = try await client.auth.currentUser()
```

### 13.2 MVP boundary

The SDK provides authentication primitives, not a fixed Laravel auth application contract. Login, register, logout, current-user, password reset, email verification, 2FA, and social login endpoints must remain configurable rather than hard-coded into the SDK.

MVP focuses on:

- Bearer token authentication;
- cookie/session authentication where required by an existing API;
- Keychain-backed credential storage;
- session restoration;
- 401 handling;
- configurable token refresh.

Authentication endpoints must not automatically inherit business API versioning — see [§16.3](#163-auth-exception).

### 13.3 Credential storage

Credential storage must use Keychain on iOS. Tokens must never be stored in `UserDefaults`.

The implementation must correctly handle token expiration, 401 responses, session restoration, and logout.

### 13.4 Token refresh state machine

Token refresh behaviour must be deterministic and concurrency-safe. A refresh operation must be coordinated so that concurrent `401` responses do not trigger independent refresh requests.

```
Request A ──┐
Request B ──┼── 401
Request C ──┘
       ↓
  ONE refresh
       ↓
Retry eligible requests or transition to unauthenticated
```

The implementation must define and document:

- which requests are eligible for retry;
- maximum retry count;
- how refresh requests themselves are protected from retry loops;
- what happens when refresh fails;
- how waiting requests are released;
- how auth state changes after refresh failure;
- what happens if logout occurs while refresh is in progress.

---

## 14. Pagination

The SDK must support standard Laravel pagination mechanisms:

- `paginate`;
- `simplePaginate`;
- cursor pagination.

The implementation must consume Laravel's existing response formats. No proprietary pagination envelope may be required.

The native API must make fetching subsequent pages straightforward. The following is illustrative rather than a fixed API contract; the final Swift API should be selected for the most idiomatic developer experience:

```swift
let page = try await client.getPage("/api/events")
let nextPage = try await page.next()
```

The exact API may be refined during implementation, but backend compatibility is mandatory.

---

## 15. File Uploads

### 15.1 Multipart — MVP

The SDK must support existing Laravel multipart endpoints.

```swift
let result = try await client.upload(
    imageData,
    to: "/api/avatar"
)
```

MVP requirements:

- multipart/form-data;
- multiple files;
- arbitrary text fields alongside files;
- configurable field names;
- configurable filename and MIME type metadata;
- upload progress;
- cancellation.

### 15.2 Direct-to-storage uploads — MVP

Laravel supports direct client-to-object-storage uploads through temporary/presigned upload URLs. Mobile Kit treats this as an existing Laravel-supported flow rather than inventing its own storage protocol.

Where an existing Laravel API exposes a compatible temporary/presigned upload endpoint, the SDK may provide a thin client-side flow:

```
1. Request upload authorization from Laravel
2. Upload the file directly to object storage
3. Optionally notify Laravel with the object key and metadata
```

The mobile application must never receive permanent storage credentials. Laravel remains responsible for authorization and storage integration.

### 15.3 Deferred

Background transfers and provider-specific storage abstractions are future extensions (see [§8.3](#83-p2--p3--deferred)) and must not complicate the Core API.

---

## 16. API Versioning

**API versioning belongs to the Laravel application, not to Mobile Kit.**

### 16.1 Independent version axes

The following versions remain independent:

- Mobile Kit SDK version — e.g. `1.4.0`;
- Laravel API version — e.g. `v1`, `v2`;
- Laravel framework version — e.g. Laravel 12, 13.

Changing one must not imply changing another. The SDK must never assume `Mobile Kit 2.0 == API v2`.

### 16.2 MVP strategies

Support:

- unversioned APIs: `/api/events`;
- path-versioned APIs: `/api/v1/events`, `/api/v2/events`.

Architecture should leave room for header, query-parameter, and `Accept` header strategies later.

```swift
let client = LaravelClient(
    baseURL: apiURL,
    apiVersion: .v1
)
```

The SDK must also work when the version is already part of `baseURL`.

Automatic API-version prefixing is a convenience feature, not a Core requirement. Direct paths such as `/api/v1/events` must always work without SDK-managed version state.

### 16.3 Auth exception

Auth endpoints must not automatically inherit API versioning. This layout must be supported without backend changes:

```
/api/login
/api/logout
/api/user

/api/v1/events
/api/v1/orders
```

### 16.4 Multiple API versions

One SDK release may communicate with multiple API versions simultaneously.

When contracts differ materially, version-specific decoding/models must be used rather than silently normalizing incompatible responses.

---

## 17. Laravel API Contract & Compatibility

Mobile Kit does not guarantee compatibility with arbitrary Laravel responses. It guarantees compatibility with documented Laravel HTTP conventions supported by the SDK.

### 17.1 Convention support classification

| Convention | Status |
| --- | --- |
| Standard JSON responses | supported |
| Laravel API Resources | supported through Codable models |
| Laravel validation errors | supported as structured native errors |
| `paginate`, `simplePaginate`, cursor pagination | supported by the Laravel module |
| Standard HTTP status handling | supported by Core |
| multipart/form-data | supported by the Uploads capability |
| Non-standard JSON | supported through generic Core HTTP + custom Codable types |
| Generated models | optional, never required for basic usage |

The SDK must not invent a proprietary response envelope or pagination format.

Compatibility with official Laravel APIs and starter-kit conventions takes priority over custom conventions.

### 17.2 Compatibility matrix

Before the first stable release, the project must document and test a compatibility matrix covering Mobile Kit SDK versions, supported Laravel API contract versions, supported Laravel framework versions, and minimum supported iOS/Swift versions.

| Mobile Kit SDK | Laravel API | Laravel Framework |
| --- | --- | --- |
| 1.x | v1 | supported versions |
| 1.x | v2 | supported versions |
| 2.x | v2 | supported versions |

The exact supported Laravel and iOS/Swift versions are implementation decisions and must be documented before the first stable release.

Compatibility must be validated with integration tests against representative Laravel APIs, not only mocked unit tests (see [§20](#20-testing-strategy)).

---

## 18. Developer Experience Requirements

Developer experience is a primary product requirement, not secondary documentation work.

The SDK must hide repetitive infrastructure while keeping important behaviour explicit and configurable. A developer must not need to manually implement `URLRequest` construction, JSON encoding/decoding, Keychain persistence, token-refresh coordination, or Laravel validation parsing for common use cases.

### 18.1 Primary integration scenario

```
1. Existing Laravel API
2. Install Mobile Kit
3. Configure base URL
4. Configure authentication
5. Call API
6. Decode native Swift models
```

### 18.2 A developer must not be required to

- install a backend package;
- modify existing routes;
- change the database;
- adopt a proprietary authentication protocol;
- introduce a new API envelope;
- generate code before using the SDK.

### 18.3 Target example

```swift
import LaravelMobileKit

let client = LaravelClient(
    baseURL: URL(string: "https://api.example.com")!
)

try await client.auth.login(...)

let events: [Event] = try await client.get("/api/events")
```

The SDK must make this experience feel unsurprising to both Laravel and Swift developers.

---

## 19. Canonical Quick-Start Example

The documentation must contain one complete example that can be followed end-to-end:

```
Existing Laravel API
        ↓
Install Mobile Kit
        ↓
Configure base URL
        ↓
Authenticate
        ↓
Restore session
        ↓
Fetch Codable models
        ↓
Fetch paginated resources
        ↓
Upload a file
        ↓
Display Laravel validation errors in SwiftUI
```

The canonical example must require no backend package, database changes, proprietary API envelope, generated code, or OpenAPI document.

---

## 20. Testing Strategy

The project must maintain both unit tests and integration tests against a real Laravel test application.

### 20.1 Unit tests

- request construction;
- Codable serialization;
- HTTP status/error mapping;
- Laravel validation errors;
- pagination parsing;
- retry policy;
- authentication state;
- token refresh coordination;
- middleware/interceptors.

### 20.2 Integration tests

- authentication and session restoration;
- 401/token refresh;
- Laravel validation responses;
- Laravel pagination formats;
- multipart uploads;
- API versioning;
- cancellation and timeout behavior.

The test Laravel application acts as a compatibility fixture for the supported Laravel API contracts of [§17](#17-laravel-api-contract--compatibility).

Every flow in the [Definition of Done](#25-definition-of-done--mvp) must have automated tests and at least one documented integration example.

---

## 21. Distribution

The first SDK is distributed through Swift Package Manager.

Package boundaries must preserve modularity so applications can depend only on the capabilities they need:

```
LaravelMobileKit
├── Core
├── Laravel
├── Auth
└── Uploads
```

---

## 22. OpenAPI and Code Generation — P1

OpenAPI is a **strategic P1 feature**, not an MVP dependency.

```
Laravel API
     │
     ▼
 OpenAPI
     │
     ▼
Mobile Kit Generator
     │
     ▼
 Swift Models / API Client
```

The generator may produce models, enums, request types, response types, API clients, and pagination types.

Constraints:

- a Laravel project must be able to use Mobile Kit without OpenAPI or generated code;
- the generator must consume a standard OpenAPI document rather than inventing a Mobile Kit-specific schema;
- code generation must never become a runtime dependency;
- work on the generator starts only after MVP stabilization.

---

## 23. Future Extensions

These capabilities are intentionally outside the MVP (see [§8.3](#83-p2--p3--deferred)).

**Realtime** — future module for Laravel broadcasting/WebSockets.

**Push / Devices** — future optional server extension and native client module for device registration and push notification infrastructure.

**Deep Links** — future module for universal links/app links and Laravel-aware routing.

**Offline / Sync** — a separate product-level problem that must not be implemented as a simple HTTP cache. It requires explicit decisions around local persistence, synchronization, conflict resolution, retry queues, and server authority.

**Storage** — future abstraction for Laravel Filesystem and S3-compatible storage. Direct-to-storage uploads remain optional.

**Kotlin** — future Android SDK using the same backend contract and product principles as Swift.

---

## 24. Optional Laravel Server Extensions

Core SDK functionality must work without a Laravel package.

Optional server extensions may be introduced only when a feature genuinely requires server-side support.

```
Laravel
   │
   ├── Existing API ─────────► Mobile Kit Core
   │
   └── Optional package
          ├── Devices
          ├── Push
          ├── Realtime
          └── Sync extensions
```

The optional package must never become a prerequisite for basic HTTP, authentication, pagination, uploads, or serialization.

---

## 25. Definition of Done — MVP

The MVP is production-ready when a developer can take an existing Laravel REST API and, using Swift Package Manager, configure Mobile Kit and complete this flow without a Mobile Kit server package:

```
Existing Laravel API
        ↓
Install Swift package
        ↓
Configure base URL
        ↓
Authenticate
        ↓
Restore session
        ↓
Perform Codable requests
        ↓
Handle Laravel validation errors
        ↓
Paginate Laravel responses
        ↓
Upload multipart data
        ↓
Handle 401 + token refresh
        ↓
Cancel / retry requests
```

### Checklist

- [ ] A developer can point the SDK at an existing Laravel REST API.
- [ ] No backend package is required for Core functionality.
- [ ] Unversioned and `/v1` path-versioned APIs work.
- [ ] Auth endpoints can have a different URL structure from business endpoints.
- [ ] Credentials are securely stored in Keychain.
- [ ] Login, logout, current-user retrieval, and session restoration work.
- [ ] 401/token-expiration handling is deterministic and documented.
- [ ] Token refresh behavior is deterministic, including concurrent 401 responses.
- [ ] Laravel validation errors are represented as structured Swift errors.
- [ ] Standard Laravel pagination formats are supported.
- [ ] Multipart uploads work with existing Laravel endpoints.
- [ ] Presigned direct uploads work against a Laravel-issued upload authorization.
- [ ] Requests support cancellation and configurable timeouts.
- [ ] Retry behavior is explicit and configurable; automatic retries do not blindly apply to every HTTP method.
- [ ] Codable serialization works for standard Laravel JSON responses.
- [ ] Non-standard API responses remain usable through the generic Core client.
- [ ] Middleware/interceptors can modify requests and observe responses.
- [ ] The Core API remains usable without OpenAPI or generated models.
- [ ] Unit and integration tests cover the supported contracts.
- [ ] The compatibility matrix (§17.2) is documented.
- [ ] Documentation contains a complete quick-start application example.

---

## 26. Implementation Guidance

The implementation should proceed in this order:

1. Define public Core interfaces and configuration.
2. Implement HTTP transport on top of `URLSession` and `async/await`.
3. Implement Codable request/response serialization.
4. Implement structured HTTP and Laravel validation errors.
5. Implement middleware/interceptors.
6. Implement authentication transport and Keychain storage.
7. Implement session restoration and 401 handling.
8. Implement Laravel pagination adapters.
9. Implement multipart uploads.
10. Implement API versioning.
11. Build comprehensive unit/integration tests against representative Laravel API responses.
12. Build the quick-start sample application.
13. Document the public API and compatibility matrix.
14. Only after MVP stabilization, begin P1 OpenAPI/code-generation work.

The implementation should favor stable, boring, well-tested primitives over abstraction for its own sake.

---

## 27. Final Product Principle

**Laravel remains the backend. Swift remains native. Mobile Kit connects the two.**

```
         Laravel
            │
      Existing REST API
            │
            ▼
┌──────────────────────┐
│  Laravel Mobile Kit  │
│                      │
│  Native SDK          │
│  Laravel conventions │
│  Optional tooling    │
└──────────┬───────────┘
           │
      ┌────┴────┐
      ▼         ▼
     iOS     Android
    Swift     Kotlin
```

The product must remain focused on this relationship and resist becoming a second backend platform.

---

## Appendix A — Decision provenance

The "Architecture Decisions — September 2026" block that previously opened this document has been merged into the sections it governs. Nothing was dropped; the mapping is:

| Decision (Sept 2026) | Now lives in |
| --- | --- |
| 1. Core boundary | §7.1, §7.2 |
| 2. Public API design | §9 |
| 3. Laravel API Contract | §17.1 |
| 4. Authentication architecture | §13.1, §13.2 |
| 5. Token refresh state machine | §13.4 |
| 6. Pagination boundary | §7.3, §14 |
| 7. Upload boundary | §7.4, §15 |
| 8. API versioning policy | §16 |
| 9. Compatibility matrix | §17.2 |
| 10. Non-goals | §8.4 |
| 11. Definition of Done — MVP | §25 |
| 12. Developer Experience | §18 |
| 13. Distribution | §21 |
| 14. MVP scope clarification | §8 |

### Editorial pass log

Performed to satisfy the former "Specification Cleanup" note, which is now resolved and removed.

1. **Numbering.** Renumbered to a single continuous `1..27` scheme. Resolved duplicate numbers `7`, `11`, `13`, `17`, `24`, `25`, `26` and the gaps at `10`, `12`, `14`, `22`.
2. **Heading levels.** One `#` title, `##` sections, `###` subsections.
3. **Scope consolidation.** MVP / P1 / P2 / P3 / non-goals were previously stated in five places (decisions §7, §10, §14; body §7 "Included in MVP", §7 "Explicitly out of MVP", §21, §26). They are now consolidated in §8 alone.
4. **Non-goals split.** The former "Non-Goals for MVP" mixed permanent constraints (BaaS, new auth protocol, new API protocol) with deferrals (Android, CLI, realtime, offline). Permanent constraints are now §8.4; deferrals are §8.2/§8.3.
5. **Architecture tree conflict resolved.** The old "Product Architecture" tree placed Pagination and Uploads inside Core, contradicting the Sept 2026 core-boundary decision. The decision wins: §7.1 places them as capability modules.
6. **Definition of Done merged.** The flow diagram (decisions §11) and the checklist (body §25) are now one section, §25. Two DoD items were added to cover MVP features that had no checklist entry: presigned direct uploads and the documented compatibility matrix.
7. **Deduplication.** "Codable serialization" appeared twice in the MVP list; the duplicate Auth/Refresh diagrams and the duplicated compatibility text were collapsed to one authoritative occurrence each.
