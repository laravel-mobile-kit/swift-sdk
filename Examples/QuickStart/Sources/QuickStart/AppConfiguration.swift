import Foundation

import LaravelMobileKit

/// Everything about this app that depends on the Laravel application behind it.
///
/// The defaults point at the compatibility fixture in `TestApp/`, so the sample
/// runs end to end without a server of your own:
///
/// ```sh
/// TestApp/scripts/serve.sh
/// swift run --package-path Examples/QuickStart
/// ```
struct AppConfiguration: Sendable {
    /// Root of the Laravel API.
    var baseURL: URL
    /// Version prefix business endpoints carry. Authentication endpoints never
    /// inherit it — Laravel apps routinely serve `/api/login` next to
    /// `/api/v1/events`.
    var apiVersion: APIVersion
    /// Keychain service the credential is stored under, usually the bundle id.
    var keychainService: String

    static var `default`: AppConfiguration {
        let urlString = ProcessInfo.processInfo.environment["LARAVEL_TEST_URL"]
            ?? "http://127.0.0.1:8000"

        return AppConfiguration(
            baseURL: URL(string: urlString) ?? URL(string: "http://127.0.0.1:8000")!,
            apiVersion: .v1,
            keychainService: "com.example.quickstart"
        )
    }
}
