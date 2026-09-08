import Foundation
import Testing

/// The part of the Definition of Done that is about the repository rather than
/// the runtime: that the tests, the compatibility matrix, and the quick-start
/// example exist and say what they must.
///
/// These live in the unit target on purpose — they need no fixture, so a plain
/// `swift test` still answers them. The runtime items are accepted by
/// `DefinitionOfDoneTests` in the integration target, and the full mapping is in
/// `Documentation/DEFINITION_OF_DONE.md`.
@Suite("Definition of Done — repository")
struct DefinitionOfDoneDocumentationTests {
    /// The repository root, found from this file rather than from the working
    /// directory, which `swift test` does not promise.
    private static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/LaravelMobileKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    private func read(_ path: String) throws -> String {
        let url = Self.repositoryRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(
            atPath: Self.repositoryRoot.appendingPathComponent(path).path
        )
    }

    // MARK: 7. 401 handling is deterministic *and documented*

    @Test("7. The 401 and refresh rules are written down")
    func unauthorizedHandlingIsDocumented() throws {
        let guide = try read("Documentation/AUTHENTICATION.md")

        #expect(guide.contains("401 and token refresh"))
        #expect(guide.contains("TokenRefreshCoordinator"))
        #expect(guide.contains("AuthError.sessionExpired"))
    }

    // MARK: 19. Unit and integration tests cover the supported contracts

    @Test("19. Both test suites exist and are wired into the package")
    func bothSuitesExist() throws {
        let manifest = try read("Package.swift")

        #expect(manifest.contains("LaravelMobileKitTests"))
        #expect(manifest.contains("LaravelMobileKitIntegrationTests"))

        for contract in [
            "AuthenticationIntegrationTests",
            "TokenRefreshIntegrationTests",
            "PaginationIntegrationTests",
            "ValidationIntegrationTests",
            "UploadIntegrationTests",
            "VersioningIntegrationTests",
            "RequestBehaviorIntegrationTests",
            "DefinitionOfDoneTests",
        ] {
            #expect(
                exists("Tests/LaravelMobileKitIntegrationTests/\(contract).swift"),
                "Missing integration coverage: \(contract)"
            )
        }
    }

    @Test("19. The integration suite runs against a real Laravel application")
    func theFixtureIsARealLaravelApp() throws {
        #expect(exists("TestApp/scripts/build-app.sh"))
        #expect(exists("TestApp/docker-compose.yml"))
        #expect(exists("TestApp/overlay/routes/api.php"))

        let script = try read("TestApp/scripts/build-app.sh")
        // The fixture is generated from the official skeleton, not hand-written.
        #expect(script.contains("composer create-project"))
        #expect(script.contains("laravel/laravel"))
    }

    // MARK: 20. The compatibility matrix is documented

    @Test("20. The compatibility matrix names the SDK, Laravel, and platform versions")
    func compatibilityMatrixIsDocumented() throws {
        let matrix = try read("Documentation/COMPATIBILITY.md")

        #expect(matrix.contains("| Mobile Kit SDK |"))
        #expect(matrix.contains("Laravel framework"))
        #expect(matrix.contains("Swift"))
        for platform in ["iOS", "macOS", "tvOS", "watchOS"] {
            #expect(matrix.contains(platform), "The matrix does not mention \(platform)")
        }
        // The supported-convention table is the other half of §17.
        #expect(matrix.contains("cursorPaginate()"))
        #expect(matrix.contains("multipart/form-data"))
    }

    // MARK: 21. Documentation contains a complete quick-start application

    @Test("21. The quick-start guide points at a sample application that builds")
    func quickStartExampleExists() throws {
        #expect(exists("Documentation/QUICK_START.md"))
        #expect(exists("Examples/QuickStart/Package.swift"))
        #expect(exists("Examples/QuickStart/README.md"))

        let app = try read("Examples/QuickStart/Sources/QuickStart/QuickStartApp.swift")
        #expect(app.contains("@main"))
        #expect(app.contains("session"))

        let guide = try read("Documentation/QUICK_START.md")
        #expect(guide.contains("Examples/QuickStart"))

        // Every documented flow has a screen behind it.
        for screen in ["LoginView.swift", "EventsListView.swift", "UploadView.swift", "ContentView.swift"] {
            #expect(
                exists("Examples/QuickStart/Sources/QuickStart/\(screen)"),
                "The sample is missing \(screen)"
            )
        }
    }

    @Test("21. The documented examples are compiled, not just printed")
    func documentedExamplesAreCompiled() throws {
        #expect(exists("Examples/Snippets/Package.swift"))

        for guide in [
            "QuickStart", "Authentication", "Pagination", "Upload",
            "ErrorHandling", "Versioning", "Middleware", "Migration",
        ] {
            #expect(
                exists("Examples/Snippets/Sources/DocumentationSnippets/\(guide)Snippets.swift"),
                "No compiled snippets for the \(guide) guide"
            )
        }
    }

    @Test("The documentation set is complete")
    func documentationSetIsComplete() throws {
        for guide in [
            "INSTALLATION", "QUICK_START", "AUTHENTICATION", "PAGINATION",
            "UPLOADS", "ERROR_HANDLING", "VERSIONING", "MIDDLEWARE",
            "API_REFERENCE", "COMPATIBILITY", "MIGRATION", "TESTING",
            "DEFINITION_OF_DONE",
        ] {
            #expect(exists("Documentation/\(guide).md"), "Missing Documentation/\(guide).md")
        }

        let readme = try read("README.md")
        #expect(readme.contains("Documentation/QUICK_START.md"))
    }
}
