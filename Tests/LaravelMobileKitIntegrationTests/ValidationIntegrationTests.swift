import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    @MainActor
    @Suite("Validation errors")
    struct ValidationIntegrationTests {
        private struct NewEvent: Encodable {
            let title: String
            let startsAt: Date?
        }

        @Test("A 422 arrives as a structured error, field by field")
        func validationFailureIsStructured() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            do {
                let _: Envelope<APIEvent> = try await stack.client.post(
                    "/api/events",
                    body: NewEvent(title: "ab", startsAt: nil)
                )
                Issue.record("Expected the request to fail validation")
            } catch let error as LaravelValidationError {
                #expect(error.statusCode == 422)
                #expect(error.hasError(for: "title"))
                #expect(error.hasError(for: "starts_at"))
                #expect(error.firstError(for: "title")?.isEmpty == false)
                #expect(Set(error.fields) == ["title", "starts_at"])
                #expect(!error.message.isEmpty)
            }
        }

        @Test("A valid payload is accepted and comes back as a model")
        func validPayloadIsAccepted() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            let startsAt = Date(timeIntervalSince1970: 1_800_000_000)

            let created: Envelope<APIEvent> = try await stack.client.post(
                "/api/events",
                body: NewEvent(title: "Integration event", startsAt: startsAt)
            )

            #expect(created.data.title == "Integration event")
            #expect(created.data.startsAt == startsAt)

            let _: EmptyResponse = try await stack.client.delete("/api/events/\(created.data.id)")
        }

        @Test("Validation errors are also reachable through the HTTP error")
        func validationErrorIsReachableFromTheHTTPError() async throws {
            let client = await IntegrationHarness.makeClient(version: .none)

            do {
                let _: APIUser = try await client.post(
                    "/api/register",
                    body: ["email": "not-an-email", "name": "", "password": "short"]
                )
                Issue.record("Expected the request to fail validation")
            } catch let error as LaravelValidationError {
                #expect(error.fields.contains("email"))
                #expect(error.fields.contains("password"))
            }
        }

        @Test("Without the validation middleware a 422 stays an HTTP error with its payload")
        func rawClientKeepsTheValidationPayload() async throws {
            let client = LaravelClient(
                configuration: LaravelClientConfiguration(
                    baseURL: IntegrationEnvironment.url,
                    retryPolicy: .none
                )
            )

            do {
                let _: APIUser = try await client.post(
                    "/api/login",
                    body: ["email": IntegrationEnvironment.seededEmail, "password": "wrong"]
                )
                Issue.record("Expected the sign-in to fail")
            } catch let error as LaravelError {
                #expect(error.isValidationError)
                let validation = try #require(error.validationError)
                #expect(validation.hasError(for: "email"))
            }
        }
    }
}
