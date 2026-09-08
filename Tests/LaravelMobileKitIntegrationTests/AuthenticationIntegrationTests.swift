import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    @MainActor
    @Suite("Authentication")
    struct AuthenticationIntegrationTests {
        @Test("Signing in returns a credential and the user behind it")
        func loginIssuesCredential() async throws {
            let stack = await IntegrationHarness.makeAuthStack()

            let result = try await stack.login()

            #expect(!result.credential.accessToken.isEmpty)
            #expect(result.credential.refreshToken?.isEmpty == false)
            #expect(result.credential.tokenType == "Bearer")
            #expect(result.credential.expiresAt != nil)
            #expect(result.user?.email == IntegrationEnvironment.seededEmail)
            #expect(try await stack.store.retrieve()?.accessToken == result.credential.accessToken)
        }

        @Test("The stored token authenticates later requests")
        func tokenAuthenticatesRequests() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            let user = try await stack.auth.currentUser()

            #expect(user.email == IntegrationEnvironment.seededEmail)
            #expect(user.createdAt != nil)
        }

        @Test("Signing out revokes the token server-side")
        func logoutRevokesTheToken() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            await stack.auth.logout()

            #expect(try await stack.store.retrieve() == nil)
            // With nothing left to refresh with, the 401 ends the session
            // rather than surfacing as a bare HTTP error.
            await #expect(throws: AuthError.sessionExpired) {
                _ = try await stack.auth.currentUser()
            }
        }

        @Test("A request without a credential is refused with 401")
        func unauthenticatedRequestIsRefused() async throws {
            let client = await IntegrationHarness.makeClient()

            do {
                let _: APIUser = try await client.get("/api/user")
                Issue.record("Expected the request to be refused")
            } catch let error as LaravelError {
                #expect(error.isUnauthorized)
                #expect(error.statusCode == 401)
            }
        }

        @Test("Registering creates an account and signs it in")
        func registrationSignsTheNewAccountIn() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            let email = IntegrationEnvironment.unusedEmail("register")

            let result = try await stack.auth.register(fields: [
                "name": "Integration Registrant",
                "email": email,
                "password": "password-1234",
            ])

            #expect(result.user?.email == email)
            #expect(try await stack.auth.currentUser().email == email)
        }

        @Test("A stored credential is restored at launch")
        func sessionIsRestoredFromStorage() async throws {
            let store = InMemoryCredentialStore()
            let firstLaunch = await IntegrationHarness.makeAuthStack(store: store)
            try await firstLaunch.login()

            // A second stack over the same store is what a relaunch looks like.
            let relaunch = await IntegrationHarness.makeAuthStack(store: store)
            await relaunch.session.restore()

            #expect(relaunch.session.state.isAuthenticated)
            #expect(relaunch.session.user?.email == IntegrationEnvironment.seededEmail)
        }

        @Test("A session with nothing stored settles as signed out")
        func emptyStoreRestoresAsUnauthenticated() async throws {
            let stack = await IntegrationHarness.makeAuthStack()

            await stack.session.restore()

            #expect(stack.session.state == .unauthenticated)
        }

        @Test(
            "Credentials survive a relaunch through the Keychain",
            .enabled(if: KeychainAvailability.isAvailable)
        )
        func credentialsRoundTripThroughTheKeychain() async throws {
            let keychain = KeychainCredentialStore(
                service: "com.laravelmobilekit.integration-tests",
                account: "restore-\(UUID().uuidString)",
                usesDataProtectionKeychain: KeychainAvailability.usesDataProtection
            )
            defer { Task { try? await keychain.delete() } }

            let firstLaunch = await IntegrationHarness.makeAuthStack(store: keychain)
            try await firstLaunch.login()

            let relaunch = await IntegrationHarness.makeAuthStack(store: keychain)
            await relaunch.session.restore()

            #expect(relaunch.session.user?.email == IntegrationEnvironment.seededEmail)
        }

        @Test("Wrong credentials come back as a Laravel validation error")
        func wrongPasswordIsAValidationError() async throws {
            let stack = await IntegrationHarness.makeAuthStack()

            do {
                _ = try await stack.auth.login(
                    email: IntegrationEnvironment.seededEmail,
                    password: "not-the-password"
                )
                Issue.record("Expected the sign-in to fail")
            } catch let error as LaravelValidationError {
                #expect(error.statusCode == 422)
                #expect(error.hasError(for: "email"))
            }
        }

        @Test("A password reset request reaches its own endpoint")
        func passwordResetIsRequested() async throws {
            let stack = await IntegrationHarness.makeAuthStack()

            try await stack.auth.requestPasswordReset(email: IntegrationEnvironment.seededEmail)
        }
    }
}
