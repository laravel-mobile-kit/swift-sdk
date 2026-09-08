import Foundation

/// A non-successful HTTP response, with its payload preserved.
///
/// The raw `data` is kept so higher layers — Laravel validation parsing, for
/// example — can interpret the body without the transport having to understand
/// it.
public struct HTTPError: Error, LocalizedError {
    /// Status code of the failing response.
    public let statusCode: Int
    /// Untouched response payload, if the response had one.
    public let data: Data?
    /// The underlying HTTP response.
    public let response: HTTPURLResponse

    public init(statusCode: Int, data: Data?, response: HTTPURLResponse) {
        self.statusCode = statusCode
        self.data = data
        self.response = response
    }

    /// Whether the status code is in the 4xx range.
    public var isClientError: Bool { (400 ..< 500).contains(statusCode) }
    /// Whether the status code is in the 5xx range.
    public var isServerError: Bool { (500 ..< 600).contains(statusCode) }
    /// Whether the request lacked valid credentials (401).
    public var isUnauthorized: Bool { statusCode == 401 }
    /// Whether the credentials were valid but insufficient (403).
    public var isForbidden: Bool { statusCode == 403 }
    /// Whether the resource does not exist (404).
    public var isNotFound: Bool { statusCode == 404 }
    /// Whether the payload failed Laravel validation (422).
    ///
    /// The body is parsed into typed validation errors by the Laravel module.
    public var isValidationError: Bool { statusCode == 422 }

    /// The response payload interpreted as UTF-8 text, when it has one.
    public var bodyText: String? {
        data.map { String(decoding: $0, as: UTF8.self) }
    }

    public var errorDescription: String? {
        "HTTP \(statusCode) for \(response.url?.absoluteString ?? "the request")"
    }
}
