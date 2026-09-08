import Foundation

/// A decoded response together with the raw transport metadata that produced it.
///
/// Callers that only need the decoded model use the generic `LaravelClient`
/// methods directly. `Response` is returned by the raw-response API for callers
/// that also need status codes, headers, or the untouched payload.
public struct Response<Value> {
    /// The decoded response body.
    public let value: Value
    /// The underlying HTTP response, including status code and headers.
    public let httpResponse: HTTPURLResponse
    /// The untouched response payload.
    public let rawData: Data

    public init(value: Value, httpResponse: HTTPURLResponse, rawData: Data) {
        self.value = value
        self.httpResponse = httpResponse
        self.rawData = rawData
    }

    /// Status code of the underlying HTTP response.
    public var statusCode: Int { httpResponse.statusCode }

    /// Header fields of the underlying HTTP response, keyed by field name.
    public var headers: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            guard let name = key as? String, let value = value as? String else { continue }
            result[name] = value
        }
        return result
    }
}

extension Response: Sendable where Value: Sendable {}
