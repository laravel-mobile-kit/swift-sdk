# Definition of Done

The MVP is done when a developer can take an existing Laravel REST API and,
using Swift Package Manager, complete this flow without a server-side package:

```
Existing Laravel API → install the package → configure the base URL →
authenticate → restore the session → Codable requests → validation errors →
pagination → multipart upload → 401 and token refresh → cancel and retry
```

Every item below is accepted by a named test. Nothing here is signed off by
reading the code.

## The checklist

| # | Item | Accepted by |
| --- | --- | --- |
| 1 | A developer can point the SDK at an existing Laravel REST API | `DefinitionOfDoneTests.pointAtAnExistingAPI` |
| 2 | No backend package is required for Core functionality | `DefinitionOfDoneTests.noBackendPackageRequired` |
| 3 | Unversioned and `/v1` path-versioned APIs work | `DefinitionOfDoneTests.versionedAndUnversionedAPIs` |
| 4 | Auth endpoints can have a different URL structure from business endpoints | `DefinitionOfDoneTests.authEndpointsKeepTheirStructure` |
| 5 | Credentials are securely stored in the Keychain | `DefinitionOfDoneTests.credentialsAreStoredInTheKeychain` |
| 6 | Login, logout, current-user retrieval, and session restoration work | `DefinitionOfDoneTests.theFullSessionLifecycle` |
| 7 | 401/token-expiration handling is deterministic **and documented** | `DefinitionOfDoneTests.unauthorizedHandlingIsDeterministic` + `DefinitionOfDoneDocumentationTests.unauthorizedHandlingIsDocumented` |
| 8 | Token refresh is deterministic, including concurrent 401s | `DefinitionOfDoneTests.concurrentRefreshIsSingleFlight` |
| 9 | Laravel validation errors are structured Swift errors | `DefinitionOfDoneTests.validationErrorsAreStructured` |
| 10 | Standard Laravel pagination formats are supported | `DefinitionOfDoneTests.everyPaginationFormatIsSupported` |
| 11 | Multipart uploads work with existing Laravel endpoints | `DefinitionOfDoneTests.multipartUploadWorks` |
| 12 | Presigned direct uploads work against a Laravel-issued authorization | `DefinitionOfDoneTests.presignedUploadWorks` |
| 13 | Requests support cancellation and configurable timeouts | `DefinitionOfDoneTests.cancellationAndTimeouts` |
| 14 | Retry behaviour is explicit and configurable; retries do not blindly apply to every method | `DefinitionOfDoneTests.retriesAreExplicitAndMethodAware` |
| 15 | Codable serialization works for standard Laravel JSON | `DefinitionOfDoneTests.codableSerializationWorks` |
| 16 | Non-standard responses remain usable through the generic Core client | `DefinitionOfDoneTests.nonStandardResponsesRemainUsable` |
| 17 | Middleware can modify requests and observe responses | `DefinitionOfDoneTests.middlewareWorksBothWays` |
| 18 | The Core API is usable without OpenAPI or generated models | `DefinitionOfDoneTests.noGeneratedModelsRequired` |
| 19 | Unit and integration tests cover the supported contracts | `DefinitionOfDoneDocumentationTests.bothSuitesExist`, `.theFixtureIsARealLaravelApp` |
| 20 | The compatibility matrix is documented | `DefinitionOfDoneDocumentationTests.compatibilityMatrixIsDocumented` |
| 21 | Documentation contains a complete quick-start application example | `DefinitionOfDoneDocumentationTests.quickStartExampleExists`, `.documentedExamplesAreCompiled` |

## Where the tests live

| Suite | Target | Needs a fixture |
| --- | --- | --- |
| `Definition of Done` | `LaravelMobileKitIntegrationTests` | Yes — items 1–18 run against a real Laravel app |
| `Definition of Done — repository` | `LaravelMobileKitTests` | No — items about documentation and coverage |

Items 1–18 are accepted against the Laravel application in
[`TestApp/`](../TestApp), not against mocks: "works with Laravel" is not
something a stubbed transport can attest to.

## Running the acceptance suite

```sh
TestApp/scripts/serve.sh
LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test --filter DefinitionOfDone
```

Without a fixture, `swift test --filter DefinitionOfDone` still runs the
repository items and skips the rest.

## Depth versus acceptance

This suite answers one question — is the MVP done? — with one test per item. The
capability suites next to it go deeper: refresh failure modes, every pagination
edge, upload progress, header precedence, transport failure classification. An
item passing here means the flow works end to end; the capability suite is where
its corners are covered.
