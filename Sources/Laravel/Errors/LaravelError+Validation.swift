import Foundation

import LaravelMobileKitCore

extension LaravelError {
    /// The Laravel validation failure this error carries, if it is one.
    ///
    /// Use this when reading validation errors from a client that has no
    /// ``ValidationErrorMiddleware`` registered:
    ///
    /// ```swift
    /// catch let error as LaravelError {
    ///     if let validation = error.validationError { ... }
    /// }
    /// ```
    public var validationError: LaravelValidationError? {
        guard let httpError, httpError.isValidationError else { return nil }
        return LaravelValidationError(httpError: httpError)
    }
}
