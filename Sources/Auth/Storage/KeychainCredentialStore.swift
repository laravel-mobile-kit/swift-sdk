import Foundation
import Security

/// Stores the credential in the Keychain.
///
/// Tokens must never live in `UserDefaults`: it is unencrypted and included in
/// backups. The Keychain item defaults to
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which lets background
/// refreshes read the token after the first unlock while keeping it off other
/// devices.
///
/// `CredentialStore` promises it is safe to call from several tasks at once, and
/// here that is not free: an app, a share extension and a capture extension can
/// all reach the same access-group item concurrently. Nothing mutable is stored
/// — the coders are created per call rather than held, because `JSONEncoder` and
/// `JSONDecoder` are classes and sharing one across tasks is a data race that
/// only shows up under load.
///
/// `@unchecked` covers exactly one thing: `accessibility` is a `CFString`
/// constant, which the compiler cannot prove `Sendable` and which is immutable
/// in fact.
public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    /// Keychain service the item belongs to, usually the app's bundle id.
    public let service: String
    /// Account within the service, so one app can keep several credentials.
    public let account: String
    /// Keychain sharing group, for sharing a token with app extensions.
    public let accessGroup: String?

    private let accessibility: CFString
    private let usesDataProtectionKeychain: Bool

    /// Creates a store for one credential.
    ///
    /// - Parameters:
    ///   - service: Keychain service, usually the bundle identifier.
    ///   - account: Distinguishes credentials within a service.
    ///   - accessGroup: Keychain access group for sharing with extensions.
    ///   - accessibility: When the item can be read.
    ///   - usesDataProtectionKeychain: Uses the modern, iOS-style Keychain.
    ///     Only turn this off for an unsigned macOS tool, which cannot reach it.
    public init(
        service: String,
        account: String = "credentials",
        accessGroup: String? = nil,
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        usesDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.accessibility = accessibility
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    // MARK: - CredentialStore

    public func store(_ credential: AuthCredential) async throws {
        let data = try JSONEncoder().encode(credential)

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility

        // Add first, update on collision. The obvious alternative — delete then
        // add — is two steps that are not atomic and cannot be made atomic here:
        // the racing writer is often in another process (an app and its
        // extensions share one access-group item), so no lock this type could
        // take would cover it. Losing that race means both writers delete, both
        // add, and one fails with `errSecDuplicateItem` having stored nothing.
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: accessibility,
            ]
            let updateStatus = SecItemUpdate(
                baseQuery() as CFDictionary,
                attributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unableToStore(updateStatus)
            }
        default:
            throw KeychainError.unableToStore(status)
        }
    }

    public func retrieve() async throws -> AuthCredential? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.corruptedCredential
            }
            do {
                return try JSONDecoder().decode(AuthCredential.self, from: data)
            } catch {
                throw KeychainError.corruptedCredential
            }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unableToRetrieve(status)
        }
    }

    public func delete() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }

    // MARK: - Queries

    /// The attributes identifying this store's single item.
    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
