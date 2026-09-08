# Documentation snippets

Every non-trivial example printed in [`Documentation/`](../../Documentation) has
a counterpart here, so the guides cannot quietly go stale: when a public API
changes, this package stops compiling.

```sh
swift build --package-path Examples/Snippets
```

It is a library, not an app — nothing here runs, and nothing here is meant to be
copied wholesale. Read the guides; this exists to keep them honest.

| File | Guide |
| --- | --- |
| `QuickStartSnippets.swift` | `README.md`, `QUICK_START.md` |
| `AuthenticationSnippets.swift` | `AUTHENTICATION.md` |
| `PaginationSnippets.swift` | `PAGINATION.md` |
| `UploadSnippets.swift` | `UPLOADS.md` |
| `ErrorHandlingSnippets.swift` | `ERROR_HANDLING.md` |
| `VersioningSnippets.swift` | `VERSIONING.md` |
| `MiddlewareSnippets.swift` | `MIDDLEWARE.md` |
| `MigrationSnippets.swift` | `MIGRATION.md`, `TESTING.md` |
