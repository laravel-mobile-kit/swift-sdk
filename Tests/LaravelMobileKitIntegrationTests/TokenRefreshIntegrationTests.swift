import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    @MainActor
    @Suite("Token refresh")
    struct TokenRefreshIntegrationTests {
        /// Makes the server reject the access token the client is holding, while
        /// leaving the refresh token usable — a real expiry, on demand.
        private func expireAccessToken(_ stack: IntegrationHarness.AuthStack) async throws {
            _ = try await stack.client.raw(.post, "/api/auth/revoke-access-token")
        }

        @Test("A 401 triggers a refresh and the request then succeeds")
        func refreshRecoversFromA401() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            let original = try #require(try await stack.store.retrieve())

            try await expireAccessToken(stack)
            let user = try await stack.auth.currentUser()

            #expect(user.email == IntegrationEnvironment.seededEmail)
            let renewed = try #require(try await stack.store.retrieve())
            #expect(renewed.accessToken != original.accessToken)
        }

        @Test("Concurrent 401s share a single refresh")
        func concurrentFailuresRefreshOnce() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            try await expireAccessToken(stack)

            let users = try await withThrowingTaskGroup(of: APIUser.self) { group in
                for _ in 0..<4 {
                    group.addTask { try await stack.auth.currentUser() }
                }
                var users: [APIUser] = []
                for try await user in group {
                    users.append(user)
                }
                return users
            }

            #expect(users.count == 4)
            #expect(users.allSatisfy { $0.email == IntegrationEnvironment.seededEmail })
            // A second refresh would have spent a refresh token that no longer
            // exists, so a usable credential proves the refresh was single-flight.
            #expect(try await stack.store.retrieve() != nil)
            #expect(try await stack.auth.currentUser().email == IntegrationEnvironment.seededEmail)
        }

        @Test("A refresh token the server rejects ends the session")
        func unusableRefreshTokenEndsTheSession() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            try await expireAccessToken(stack)

            // Both tokens are now worthless: the access token was revoked, and the
            // refresh token is replaced with one the server never issued.
            let credential = try #require(try await stack.store.retrieve())
            try await stack.store.store(
                AuthCredential(
                    accessToken: credential.accessToken,
                    refreshToken: "not-a-refresh-token",
                    tokenType: credential.tokenType,
                    expiresAt: credential.expiresAt
                )
            )
            await stack.session.restore()

            do {
                _ = try await stack.auth.currentUser()
                Issue.record("Expected the session to be over")
            } catch let error as AuthError {
                #expect(error == .sessionExpired)
            } catch let error as LaravelError {
                #expect(error.isUnauthorized)
            }
        }

        @Test("A refreshed token is used by the requests that follow")
        func refreshedTokenIsReused() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            try await expireAccessToken(stack)

            _ = try await stack.auth.currentUser()
            let refreshed = try #require(try await stack.store.retrieve())

            let echo: EchoedRequest = try await stack.client.get("/api/echo")
            #expect(echo.header("Authorization") == "Bearer \(refreshed.accessToken)")
        }
    }
}
