import Foundation

import LaravelMobileKitCore

/// A Laravel validation failure, parsed from a `422` response.
///
/// Laravel answers a failed `Validator` with
/// `{"message": "...", "errors": {"email": ["The email has already been taken."]}}`.
/// This type turns that payload into something a form can bind to directly:
///
/// ```swift
/// catch let error as LaravelValidationError {
///     emailError = error.firstError(for: "email")
/// }
/// ```
///
/// Field names are kept exactly as the API sent them — `first_name` stays
/// `first_name` — because they identify form fields rather than Swift
/// properties.
public struct LaravelValidationError: Error, LocalizedError, Hashable, Sendable {
    /// Laravel's summary message, for example "The given data was invalid.".
    public let message: String
    /// Field-level messages, keyed by the field name Laravel validated.
    public let errors: [String: [String]]
    /// Status code of the response that produced this error.
    public let statusCode: Int
    /// The untouched response payload.
    public let rawData: Data

    public init(
        message: String,
        errors: [String: [String]],
        statusCode: Int = 422,
        rawData: Data = Data()
    ) {
        self.message = message
        self.errors = errors
        self.statusCode = statusCode
        self.rawData = rawData
    }

    /// Laravel's default summary, used when a response omits `message`.
    public static let defaultMessage = "The given data was invalid."

    // MARK: - Field access

    /// Every message for `field`, or `nil` when the field validated cleanly.
    public subscript(field: String) -> [String]? {
        errors[field]
    }

    /// The first message for `field` — what a form shows under an input.
    public func firstError(for field: String) -> String? {
        errors[field]?.first
    }

    /// Whether `field` failed validation.
    public func hasError(for field: String) -> Bool {
        !(errors[field]?.isEmpty ?? true)
    }

    /// The fields that failed, sorted for stable display.
    public var fields: [String] {
        errors.keys.sorted()
    }

    /// The first message of every failing field, keyed by field name.
    public var firstErrors: [String: String] {
        errors.compactMapValues(\.first)
    }

    /// Every message, ordered by field name.
    public var allErrors: [String] {
        fields.flatMap { errors[$0] ?? [] }
    }

    /// Messages that belong to the form as a whole rather than to one field.
    ///
    /// Laravel places these under an empty key when a rule fails outside a
    /// specific attribute.
    public var globalErrors: [String] {
        errors[""] ?? []
    }

    /// Whether any field-level message was returned.
    public var hasErrors: Bool {
        !errors.isEmpty
    }

    public var errorDescription: String? { message }

    public var failureReason: String? {
        allErrors.isEmpty ? nil : allErrors.joined(separator: " ")
    }
}
