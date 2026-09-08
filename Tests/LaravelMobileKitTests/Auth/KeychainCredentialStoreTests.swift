import Foundation
import Security
import Testing

import LaravelMobileKitAuth

/// Whether Keychain Services answer this process at all, and in which mode.
///
/// An unsigned binary — which is what `swift test` and the SPM test bundle
/// build — cannot reach the data protection Keychain (`errSecMissingEntitlement`),
/// but the legacy file-based Keychain on macOS does answer it. The tests below
/// use whichever mode works, and skip when neither does.
private func keychainAnswers(dataProtection: Bool) -> Bool {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.laravelmobilekit.tests.probe",
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

/// Whether the store can use the data protection Keychain here.
let keychainUsesDataProtection = keychainAnswers(dataProtection: true)
/// Whether any Keychain is reachable, in either mode.
let keychainIsAvailable = keychainUsesDataProtection || keychainAnswers(dataProtection: false)

@Suite("Keychain credential store", .enabled(if: keychainIsAvailable))
struct KeychainCredentialStoreTests {
    /// A store isolated to this test, so concurrent runs never collide.
    private func makeStore(
        service: String = "com.laravelmobilekit.tests.\(UUID().uuidString)",
        account: String = "credentials"
    ) -> KeychainCredentialStore {
        KeychainCredentialStore(
            service: service,
            account: account,
            usesDataProtectionKeychain: keychainUsesDataProtection
        )
    }

    /// Runs `body` and removes the stores' items afterwards, pass or fail.
    ///
    /// These tests write to the real Keychain, so cleanup has to happen on the
    /// failure path too rather than in a detached task that may outlive the run.
    private func withCleanup(
        _ stores: [KeychainCredentialStore],
        _ body: () async throws -> Void
    ) async throws {
        do {
            try await body()
        } catch {
            for store in stores { try? await store.delete() }
            throw error
        }
        for store in stores { try? await store.delete() }
    }

    @Test("A stored credential survives a round-trip")
    func storeThenRetrieve() async throws {
        let store = makeStore()
        let credential = AuthCredential(
            accessToken: "abc",
            refreshToken: "def",
            expiresAt: Date(timeIntervalSince1970: 1_705_314_600)
        )

        try await withCleanup([store]) {
            try await store.store(credential)

            #expect(try await store.retrieve() == credential)
        }
    }

    @Test("An empty store returns nothing")
    func emptyStore() async throws {
        let store = makeStore()

        #expect(try await store.retrieve() == nil)
    }

    @Test("Storing again replaces the previous credential")
    func storeReplaces() async throws {
        let store = makeStore()

        try await withCleanup([store]) {
            try await store.store(AuthCredential(accessToken: "old"))
            try await store.store(AuthCredential(accessToken: "new"))

            #expect(try await store.retrieve()?.accessToken == "new")
        }
    }

    @Test("Deleting removes the credential, and deleting nothing succeeds")
    func deleteIsIdempotent() async throws {
        let store = makeStore()

        try await withCleanup([store]) {
            try await store.store(AuthCredential(accessToken: "abc"))
            try await store.delete()
            try await store.delete()

            #expect(try await store.retrieve() == nil)
        }
    }

    @Test("Accounts within one service hold separate credentials")
    func accountsAreIsolated() async throws {
        let service = "com.laravelmobilekit.tests.\(UUID().uuidString)"
        let first = makeStore(service: service, account: "user-1")
        let second = makeStore(service: service, account: "user-2")

        try await withCleanup([first, second]) {
            try await first.store(AuthCredential(accessToken: "one"))
            try await second.store(AuthCredential(accessToken: "two"))

            #expect(try await first.retrieve()?.accessToken == "one")
            #expect(try await second.retrieve()?.accessToken == "two")
        }
    }

    @Test("A credential written by another store is not visible")
    func servicesAreIsolated() async throws {
        let first = makeStore()
        let second = makeStore()

        try await withCleanup([first, second]) {
            try await first.store(AuthCredential(accessToken: "one"))

            #expect(try await second.retrieve() == nil)
        }
    }
}

@Suite("Keychain errors")
struct KeychainErrorTests {
    @Test("Statuses that mean the Keychain is out of reach are recognisable")
    func unavailableStatuses() {
        #expect(KeychainError.unableToStore(errSecMissingEntitlement).isKeychainUnavailable)
        #expect(KeychainError.unableToRetrieve(errSecNotAvailable).isKeychainUnavailable)
        #expect(!KeychainError.unableToStore(errSecDuplicateItem).isKeychainUnavailable)
        #expect(!KeychainError.corruptedCredential.isKeychainUnavailable)
    }

    @Test("Errors describe themselves")
    func errorDescriptions() {
        #expect(KeychainError.unableToStore(errSecDuplicateItem).errorDescription?
            .hasPrefix("Could not store the credential") == true)
        #expect(KeychainError.corruptedCredential.errorDescription != nil)
        #expect(KeychainError.unableToDelete(errSecItemNotFound).status == errSecItemNotFound)
    }
}
