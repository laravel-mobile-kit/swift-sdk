# Laravel compatibility fixture

A real Laravel application the Swift integration suite runs against. It exists
because mocked responses can only prove the kit against our idea of Laravel;
these tests prove it against Laravel itself — Sanctum tokens, `ValidationException`
payloads, all three paginators, `UploadedFile` handling, and signed URLs.

## What is version-controlled

Only `overlay/` and the scripts. The application itself is generated from the
official `laravel/laravel` skeleton into `TestApp/.laravel` (git-ignored) and the
overlay is copied over it, so the fixture stays an unmodified Laravel install
plus this repository's routes, controllers, models, and seed data.

## Running it

With Docker:

```sh
docker compose -f TestApp/docker-compose.yml up --build
LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test
```

Without Docker (needs PHP 8.2+ and Composer on the machine):

```sh
TestApp/scripts/serve.sh
LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test
```

`swift test` skips every integration suite when `LARAVEL_TEST_URL` is unset, so
the unit tests stay runnable on a machine with no fixture.

Set `LARAVEL_VERSION` to build against another framework release:

```sh
LARAVEL_VERSION='^13.0' TestApp/scripts/serve.sh
```

Delete `TestApp/.laravel` to rebuild from scratch. Each start re-applies the
overlay and re-runs `migrate:fresh --seed`, so the data is identical every time.

## Seed data

- User `test@example.com` / `password`.
- 45 events titled `Event 01` … `Event 45`, ordered by id.

## Endpoints

Authentication deliberately sits outside the version prefix, and the business
API is published twice — unversioned and under `/v1` — so the SDK's versioning
middleware can be exercised against both.

| Endpoint | Purpose |
| --- | --- |
| `POST /api/register`, `POST /api/login` | Issue an access token, a rotating refresh token, and the user |
| `POST /api/logout`, `GET /api/user` | Revoke the token; return the authenticated user |
| `POST /api/auth/refresh` | Exchange a refresh token for a new access token |
| `POST /api/auth/revoke-access-token` | Test hook: expires the access token, leaving the refresh token usable |
| `POST /api/forgot-password` | Password-reset request |
| `GET /api/[v1/]events` | `paginate()` — length-aware |
| `GET /api/[v1/]events/resource` | The same page through an API Resource collection |
| `GET /api/[v1/]events/simple` | `simplePaginate()` |
| `GET /api/[v1/]events/cursor` | `cursorPaginate()` |
| `GET /api/[v1/]events/{id}` | One record, or 404 |
| `POST /api/[v1/]events` | Validated create (422 on failure) |
| `DELETE /api/[v1/]events/{id}` | 204 with no body |
| `POST /api/[v1/]avatar` | `multipart/form-data` upload |
| `POST /api/[v1/]uploads/authorize` | Issues a signed direct-upload URL |
| `PUT /api/uploads/storage/{uuid}` | Object-storage stand-in, reached only through the signed URL |
| `POST /api/[v1/]uploads/complete` | Records an upload that landed in storage |
| `GET /api/[v1/]version` | Which version prefix served the request |
| `GET /api/[v1/]echo` | Reflects method, path, query, and headers |
| `GET /api/[v1/]slow?seconds=` | Answers after a delay — timeouts and cancellation |
| `GET|POST /api/[v1/]flaky/{key}?failures=` | Fails N times, then succeeds — retries |
| `DELETE /api/[v1/]flaky/{key}` | Reports and clears that counter |
| `GET /api/[v1/]status/{code}` | Answers with the requested status |
