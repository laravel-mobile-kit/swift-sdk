import Foundation

import LaravelMobileKitCore

/// Turns Laravel's `422` responses into ``LaravelValidationError`` before the
/// client reports a generic HTTP failure.
///
/// ```swift
/// await client.use(.validationErrors)
///
/// do {
///     let user: User = try await client.post("/api/register", body: form)
/// } catch let error as LaravelValidationError {
///     emailError = error.firstError(for: "email")
/// }
/// ```
///
/// Core stays generic: it reports `422` like any other status, and this
/// middleware — living in the Laravel module — is what understands the payload.
public struct ValidationErrorMiddleware: Middleware {
    /// Status codes whose bodies are read as validation payloads.
    public let statusCodes: Set<Int>

    public init(statusCodes: Set<Int> = [422]) {
        self.statusCodes = statusCodes
    }

    public func process(_ request: URLRequest) async throws -> URLRequest { request }

    public func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        guard statusCodes.contains(response.statusCode),
              let error = LaravelValidationError(data: data, response: response)
        else {
            // Not a validation payload: leave it to Core's HTTP error handling.
            return
        }
        throw error
    }
}

extension Middleware where Self == ValidationErrorMiddleware {
    /// Parses Laravel validation payloads out of `422` responses.
    public static var validationErrors: ValidationErrorMiddleware {
        ValidationErrorMiddleware()
    }
}
