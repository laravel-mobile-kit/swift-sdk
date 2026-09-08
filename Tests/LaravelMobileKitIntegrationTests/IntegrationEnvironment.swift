import Foundation

import LaravelMobileKit

/// Where the integration suite finds the Laravel fixture.
///
/// The suite runs against the application in `TestApp/`, which is a real
/// Laravel installation rather than a stub: the point of these tests is to prove
/// the kit against Laravel's actual responses, not against our idea of them.
///
/// ```sh
/// TestApp/scripts/serve.sh                       # or: docker compose -f TestApp/docker-compose.yml up
/// LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test
/// ```
///
/// Without `LARAVEL_TEST_URL` every suite here is skipped, so `swift test` stays
/// useful on a machine with no fixture running.
enum IntegrationEnvironment {
    /// Environment variable naming the fixture's base URL.
    static let variableName = "LARAVEL_TEST_URL"

    static let baseURL: URL? = ProcessInfo.processInfo.environment[variableName]
        .flatMap(URL.init(string:))

    /// Whether a fixture was pointed at.
    static var isConfigured: Bool { baseURL != nil }

    /// The configured base URL. Only read from suites gated on ``isConfigured``.
    static var url: URL {
        guard let baseURL else {
            preconditionFailure("Set \(variableName) to run the integration suite")
        }
        return baseURL
    }

    /// The account `DatabaseSeeder` creates.
    static let seededEmail = "test@example.com"
    static let seededPassword = "password"

    /// How many events the seeder inserts.
    static let seededEventCount = 45

    /// An email nobody has registered yet.
    static func unusedEmail(_ label: String) -> String {
        "\(label)-\(UUID().uuidString.prefix(8).lowercased())@example.com"
    }

    /// A key that keeps one test's flaky-endpoint counter to itself.
    static func flakyKey(_ label: String) -> String {
        "\(label)-\(UUID().uuidString.prefix(8).lowercased())"
    }
}
