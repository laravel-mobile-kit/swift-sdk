import Foundation
import SwiftUI

import LaravelMobileKit

/// Examples from `Documentation/ERROR_HANDLING.md`.
enum ErrorHandlingSnippets {
    static func inspecting(client: LaravelClient) async {
        do {
            let event: Event = try await client.get("/api/events/1")
            _ = event
        } catch let error as LaravelError {
            _ = error.statusCode
            _ = error.isNotFound
            _ = error.httpError?.bodyText
        } catch {}
    }

    static func validation(client: LaravelClient, draft: EventDraft) async {
        do {
            let created: Event = try await client.post("/api/events", body: draft)
            _ = created
        } catch let error as LaravelValidationError {
            _ = error.message
            _ = error["title"]
            _ = error.firstError(for: "title")
            _ = error.hasError(for: "starts_at")
            _ = error.fields
            _ = error.firstErrors
            _ = error.allErrors
            _ = error.globalErrors
        } catch {}
    }

    static func validationWithoutMiddleware(client: LaravelClient, draft: EventDraft) async {
        do {
            let created: Event = try await client.post("/api/events", body: draft)
            _ = created
        } catch let error as LaravelError {
            if let validation = error.validationError { _ = validation }
        } catch {}
    }

    static func otherStatusCodes(client: LaravelClient) async {
        await client.use(ValidationErrorMiddleware(statusCodes: [400, 422]))
    }

    static func ignoringCancellation(client: LaravelClient) async {
        do {
            let events: [Event] = try await client.get("/api/events")
            _ = events
        } catch let error as LaravelError where error.isCancelled {
            // The user moved on. Say nothing.
        } catch {}
    }

    static var configuredRetries: LaravelClientConfiguration {
        LaravelClientConfiguration(
            baseURL: baseURL,
            retryPolicy: RetryPolicy(
                maxRetries: 3,
                retryableStatusCodes: [408, 429, 500, 502, 503, 504],
                retryableMethods: RetryPolicy.idempotentMethods,
                backoffStrategy: .exponential(base: 0.5, maxDelay: 30),
                retriesNetworkFailures: true,
                jitter: .full,
                maximumRetryAfter: 60
            )
        )
    }

    static func timeouts(client: LaravelClient) async throws {
        _ = LaravelClientConfiguration(baseURL: baseURL, timeoutInterval: 30)

        let report: Event = try await client.get("/api/report", options: .timeout(120))
        _ = report
    }
}

/// The form-field rendering from the guide.
struct ValidatedTitleField: View {
    @Binding var title: String
    let validation: LaravelValidationError?

    var body: some View {
        Section {
            TextField("Title", text: $title)
            ForEach(validation?["title"] ?? [], id: \.self) { message in
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
