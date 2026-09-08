import Foundation

import LaravelMobileKitCore

extension LaravelValidationError {
    /// Parses a Laravel validation payload, returning `nil` when the body is
    /// not one.
    ///
    /// A non-JSON body, an HTML error page, or a JSON object carrying neither
    /// `message` nor `errors` is not a validation failure and is left for the
    /// caller to handle as a plain HTTP error.
    public init?(data: Data, statusCode: Int = 422) {
        guard let payload = try? LaravelValidationError.payloadDecoder
            .decode(ValidationPayload.self, from: data),
            payload.message != nil || payload.errors != nil
        else {
            return nil
        }

        self.init(
            message: payload.message ?? LaravelValidationError.defaultMessage,
            errors: payload.errors ?? [:],
            statusCode: statusCode,
            rawData: data
        )
    }

    /// Parses a validation payload from a response.
    public init?(data: Data, response: HTTPURLResponse) {
        self.init(data: data, statusCode: response.statusCode)
    }

    /// Parses the validation payload carried by an HTTP failure.
    public init?(httpError: HTTPError) {
        guard let data = httpError.data else { return nil }
        self.init(data: data, statusCode: httpError.statusCode)
    }

    /// Validation payloads are read with a plain decoder on purpose: field
    /// names are form identifiers, so `first_name` must not be rewritten to
    /// `firstName` on the way in.
    private static let payloadDecoder = JSONDecoder()
}

/// The wire shape of a Laravel validation response.
private struct ValidationPayload: Decodable {
    let message: String?
    let errors: [String: [String]]?

    private enum CodingKeys: String, CodingKey {
        case message
        case errors
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        errors = try container.decodeIfPresent(FieldErrors.self, forKey: .errors)?.values
    }
}

/// Field errors, tolerating the single-string form some APIs return.
private struct FieldErrors: Decodable {
    let values: [String: [String]]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        var values: [String: [String]] = [:]
        for key in container.allKeys {
            if let messages = try? container.decode([String].self, forKey: key) {
                values[key.stringValue] = messages
            } else if let message = try? container.decode(String.self, forKey: key) {
                values[key.stringValue] = [message]
            }
        }
        self.values = values
    }
}
