import Foundation
import Testing

import LaravelMobileKitAuth
import LaravelMobileKitCore

@Suite("Sign in with Apple")
struct SignInWithAppleTests {
    let baseURL = URL(string: "https://api.example.com")!

    // MARK: - Nonce

    /// The one place this can silently go wrong: a hash that is not the hash
    /// Apple computes fails server-side with an error that never mentions
    /// nonces. Checked against a known vector rather than against itself.
    @Test("The hashed nonce is the hex SHA-256 of the raw one")
    func hashMatchesAKnownVector() {
        let nonce = SignInWithAppleNonce(raw: "abc")

        #expect(nonce.raw == "abc")
        #expect(
            nonce.hashed == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("The empty string hashes to the documented SHA-256 of nothing")
    func hashOfEmptyString() {
        #expect(
            SignInWithAppleNonce(raw: "").hashed
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test("A generated nonce is random, URL-safe, and the requested length")
    func generatedNoncesAreRandom() {
        let nonces = (0 ..< 50).map { _ in SignInWithAppleNonce() }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")

        #expect(Set(nonces.map(\.raw)).count == 50)
        #expect(nonces.allSatisfy { $0.raw.count == 32 })
        #expect(nonces.allSatisfy { $0.raw.allSatisfy(allowed.contains) })
    }

    @Test("The same raw value always hashes the same way")
    func hashingIsStable() {
        #expect(SignInWithAppleNonce(raw: "same").hashed == SignInWithAppleNonce(raw: "same").hashed)
    }

    // MARK: - Exchange

    private func makeManager(
        transport: MockTransport,
        configuration: AuthConfiguration = .laravel,
        store: any CredentialStore = InMemoryCredentialStore()
    ) -> AuthManager<StubUser> {
        AuthManager<StubUser>(
            client: LaravelClient(baseURL: baseURL, transport: transport),
            configuration: configuration,
            credentialStore: store
        )
    }

    @Test("The exchange posts the token, the raw nonce, and the provider")
    func exchangePostsTheExpectedFields() async throws {
        let transport = MockTransport(statusCode: 200, json: #"{"token":"sanctum-token"}"#)
        let manager = makeManager(transport: transport)
        let nonce = SignInWithAppleNonce(raw: "raw-nonce")

        let result = try await manager.login(identityToken: "apple.jwt", nonce: nonce.raw)

        #expect(result.credential.accessToken == "sanctum-token")

        let body = try #require(await transport.executedRequests.first?.httpBody)
        let sent = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(sent["identity_token"] == "apple.jwt")
        #expect(sent["provider"] == "apple")
        // The raw value, never the hash: the server hashes it to check the claim.
        #expect(sent["nonce"] == "raw-nonce")
        #expect(sent["nonce"] != nonce.hashed)
    }

    @Test("A flow without a nonce sends no nonce field")
    func nonceIsOptional() async throws {
        let transport = MockTransport(statusCode: 200, json: #"{"token":"t"}"#)
        let manager = makeManager(transport: transport)

        _ = try await manager.login(identityToken: "apple.jwt")

        let body = try #require(await transport.executedRequests.first?.httpBody)
        let sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent["nonce"] == nil)
    }

    @Test("Field names bend to the API rather than the other way round")
    func fieldNamesAreConfigurable() async throws {
        let transport = MockTransport(statusCode: 200, json: #"{"token":"t"}"#)
        let manager = makeManager(transport: transport)

        _ = try await manager.login(
            identityToken: "google.jwt",
            provider: "google",
            fieldNames: .oidc
        )

        let body = try #require(await transport.executedRequests.first?.httpBody)
        let sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent["id_token"] == "google.jwt")
        #expect(sent["identity_token"] == nil)
        #expect(sent["provider"] == "google")
    }

    @Test("Extra fields travel alongside, for the name Apple only sends once")
    func extraFieldsAreSent() async throws {
        let transport = MockTransport(statusCode: 200, json: #"{"token":"t"}"#)
        let manager = makeManager(transport: transport)

        _ = try await manager.login(
            identityToken: "apple.jwt",
            extraFields: ["given_name": "Ada", "authorization_code": "code-1"]
        )

        let body = try #require(await transport.executedRequests.first?.httpBody)
        let sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent["given_name"] == "Ada")
        #expect(sent["authorization_code"] == "code-1")
    }

    @Test("The exchange reuses the login route unless given its own")
    func endpointDefaultsToLogin() async throws {
        let transport = MockTransport(statusCode: 200, json: #"{"token":"t"}"#)
        _ = try await makeManager(transport: transport).login(identityToken: "apple.jwt")
        #expect(await transport.executedRequests.first?.url?.path == "/api/login")

        let dedicated = MockTransport(statusCode: 200, json: #"{"token":"t"}"#)
        let configuration = AuthConfiguration(identityTokenEndpoint: "/api/auth/apple")
        _ = try await makeManager(transport: dedicated, configuration: configuration)
            .login(identityToken: "apple.jwt")
        #expect(await dedicated.executedRequests.first?.url?.path == "/api/auth/apple")
    }

    @Test("A dedicated exchange route is exempt from API versioning, like the other auth routes")
    func exchangeRouteIsAnAuthRoute() {
        let configuration = AuthConfiguration(identityTokenEndpoint: "/api/auth/apple")

        #expect(configuration.allEndpoints.contains("/api/auth/apple"))
    }

    @Test("The issued credential is stored, so the session survives a relaunch")
    func credentialIsPersisted() async throws {
        let store = InMemoryCredentialStore()
        let transport = MockTransport(statusCode: 200, json: #"{"token":"sanctum-token"}"#)

        _ = try await makeManager(transport: transport, store: store)
            .login(identityToken: "apple.jwt")

        #expect(try await store.retrieve()?.accessToken == "sanctum-token")
    }
}

private struct StubUser: Decodable, Sendable, Equatable {
    let id: Int
}
