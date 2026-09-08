import Foundation
import Testing

import LaravelMobileKitAuth

@Suite("Auth credential")
struct AuthCredentialTests {
    @Test("A credential without an expiry never expires")
    func credentialWithoutExpiryNeverExpires() {
        let credential = AuthCredential(accessToken: "abc")

        #expect(!credential.isExpired)
        #expect(!credential.isExpired(at: Date(timeIntervalSince1970: 4_000_000_000)))
        #expect(!credential.expires(within: 3600))
    }

    @Test("A credential expires at its expiry date")
    func expiryIsHonoured() {
        let expiry = Date(timeIntervalSince1970: 1_000)
        let credential = AuthCredential(accessToken: "abc", expiresAt: expiry)

        #expect(!credential.isExpired(at: expiry.addingTimeInterval(-1)))
        #expect(credential.isExpired(at: expiry))
        #expect(credential.isExpired(at: expiry.addingTimeInterval(1)))
    }

    @Test("A credential can report that it expires soon")
    func expiresWithinWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let credential = AuthCredential(
            accessToken: "abc",
            expiresAt: now.addingTimeInterval(30)
        )

        #expect(credential.expires(within: 60, from: now))
        #expect(!credential.expires(within: 10, from: now))
    }

    @Test("The authorization header uses the token type")
    func authorizationHeaderValue() {
        #expect(AuthCredential(accessToken: "abc").authorizationHeaderValue == "Bearer abc")
        #expect(
            AuthCredential(accessToken: "abc", tokenType: "Token").authorizationHeaderValue
                == "Token abc"
        )
        #expect(
            AuthCredential(accessToken: "abc", tokenType: "").authorizationHeaderValue == "abc"
        )
    }

    @Test("A credential round-trips through Codable")
    func codableRoundTrip() throws {
        let credential = AuthCredential(
            accessToken: "abc",
            refreshToken: "def",
            tokenType: "Bearer",
            expiresAt: Date(timeIntervalSince1970: 1_705_314_600)
        )

        let data = try JSONEncoder().encode(credential)
        let decoded = try JSONDecoder().decode(AuthCredential.self, from: data)

        #expect(decoded == credential)
    }
}

@Suite("In-memory credential store")
struct InMemoryCredentialStoreTests {
    @Test("A stored credential is returned")
    func storeThenRetrieve() async throws {
        let store = InMemoryCredentialStore()
        let credential = AuthCredential(accessToken: "abc")

        try await store.store(credential)

        #expect(try await store.retrieve() == credential)
    }

    @Test("An empty store returns nothing")
    func emptyStore() async throws {
        let store = InMemoryCredentialStore()

        #expect(try await store.retrieve() == nil)
    }

    @Test("Storing again replaces the previous credential")
    func storeReplaces() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "old"))

        try await store.store(AuthCredential(accessToken: "new"))

        #expect(try await store.retrieve()?.accessToken == "new")
    }

    @Test("Deleting empties the store, and deleting nothing is not an error")
    func deleteIsIdempotent() async throws {
        let store = InMemoryCredentialStore(credential: AuthCredential(accessToken: "abc"))

        try await store.delete()
        try await store.delete()

        #expect(try await store.retrieve() == nil)
    }
}
