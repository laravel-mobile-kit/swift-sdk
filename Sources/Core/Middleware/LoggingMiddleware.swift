import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Logs requests and responses passing through the client.
///
/// ```swift
/// await client.use(LoggingMiddleware(level: .headers))
/// ```
public struct LoggingMiddleware: Middleware {
    /// How much of each exchange is logged.
    public enum Level: Sendable, Hashable, Comparable, CaseIterable {
        /// Log nothing.
        case none
        /// Method, URL, and status code.
        case basic
        /// `basic`, plus headers.
        case headers
        /// `headers`, plus request and response bodies.
        case body
    }

    /// The configured verbosity.
    public let level: Level
    /// Where log lines are written. Defaults to standard output.
    private let sink: @Sendable (String) -> Void

    public init(level: Level = .basic, sink: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.level = level
        self.sink = sink
    }

    public func process(_ request: URLRequest) async throws -> URLRequest {
        guard level > .none else { return request }

        sink("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        if level >= .headers {
            for (field, value) in request.allHTTPHeaderFields ?? [:] {
                sink("  \(field): \(value)")
            }
        }
        if level >= .body, let body = request.httpBody {
            sink("  \(String(decoding: body, as: UTF8.self))")
        }
        return request
    }

    public func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        guard level > .none else { return }

        sink("← \(response.statusCode) \(response.url?.absoluteString ?? "?")")
        if level >= .headers {
            for (field, value) in response.allHeaderFields {
                sink("  \(field): \(value)")
            }
        }
        if level >= .body, !data.isEmpty {
            sink("  \(String(decoding: data, as: UTF8.self))")
        }
    }
}
