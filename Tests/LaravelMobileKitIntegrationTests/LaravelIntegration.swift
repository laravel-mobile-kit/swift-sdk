import Foundation
import Security
import Testing

/// Parent of every integration suite.
///
/// All suites share one fixture database, so they run one at a time: a test
/// that creates an event must not be able to shift the pages another test is
/// walking. Serializing here rather than per suite is what makes the results
/// reproducible.
@Suite(
    "Laravel integration",
    .enabled(if: IntegrationEnvironment.isConfigured),
    .serialized
)
struct LaravelIntegration {}

/// Whether Keychain Services answer this process, and in which mode.
///
/// An unsigned binary — which is what the SPM test bundle is — cannot reach the
/// data protection Keychain, but macOS's file-based Keychain does answer it.
enum KeychainAvailability {
    private static func answers(dataProtection: Bool) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.laravelmobilekit.integration-tests.probe",
            kSecAttrAccount as String: UUID().uuidString,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        var addQuery = query
        addQuery[kSecValueData as String] = Data("probe".utf8)

        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else { return false }
        SecItemDelete(query as CFDictionary)
        return true
    }

    /// Whether the data protection Keychain is reachable here.
    static let usesDataProtection = answers(dataProtection: true)
    /// Whether any Keychain is reachable, in either mode.
    static let isAvailable = usesDataProtection || answers(dataProtection: false)
}
