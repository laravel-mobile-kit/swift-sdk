import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Logs requests and responses passing through the client.
///
/// ```swift
/// await client.use(LoggingMiddleware(level: .headers))
/// ```
///
/// ## What is redacted
///
/// Credential-bearing headers are replaced with `<redacted>` at every level,
/// and bodies are logged as a byte count unless the caller asks for their
/// content. Both defaults exist because a log level is the easiest thing in a
/// codebase to raise in a hurry and the easiest to forget to lower: an SDK that
/// prints a bearer token the moment someone debugs a 401 has handed out that
/// token to every log sink the app has.
///
/// Logging a body verbatim is therefore a separate, deliberate argument rather
/// than a higher level:
///
/// ```swift
/// await client.use(LoggingMiddleware(level: .body, bodies: .unredacted))
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

    /// Whether body content is written out, or only its size.
    public enum BodyLogging: Sendable, Hashable {
        /// Log the byte count only. The default.
        case sizeOnly
        /// Log the body verbatim.
        ///
        /// Request and response payloads routinely carry credentials, personal
        /// data, and whatever the user typed. Choose this for a local debugging
        /// session, not for a build you ship.
        case unredacted
    }

    /// Headers whose values are replaced with `<redacted>`, matched
    /// case-insensitively.
    public static let defaultRedactedHeaders: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "x-csrf-token",
        "x-xsrf-token",
    ]

    /// The configured verbosity.
    public let level: Level
    /// Whether body content is written out.
    public let bodies: BodyLogging
    /// Header names whose values are withheld, stored lowercased.
    public let redactedHeaders: Set<String>
    /// Where log lines are written. Defaults to standard output.
    private let sink: @Sendable (String) -> Void

    public init(
        level: Level = .basic,
        bodies: BodyLogging = .sizeOnly,
        redactedHeaders: Set<String> = LoggingMiddleware.defaultRedactedHeaders,
        sink: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.level = level
        self.bodies = bodies
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.sink = sink
    }

    public func process(_ request: URLRequest) async throws -> URLRequest {
        guard level > .none else { return request }

        sink("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        if level >= .headers {
            for (field, value) in request.allHTTPHeaderFields ?? [:] {
                sink(headerLine(field, value))
            }
        }
        if level >= .body, let body = request.httpBody {
            sink(bodyLine(body))
        }
        return request
    }

    public func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        guard level > .none else { return }

        sink("← \(response.statusCode) \(response.url?.absoluteString ?? "?")")
        if level >= .headers {
            for (field, value) in response.allHeaderFields {
                sink(headerLine("\(field)", "\(value)"))
            }
        }
        if level >= .body, !data.isEmpty {
            sink(bodyLine(data))
        }
    }

    // MARK: - Formatting

    /// One header line, with the value withheld when the name is redacted.
    private func headerLine(_ field: String, _ value: String) -> String {
        redactedHeaders.contains(field.lowercased())
            ? "  \(field): <redacted>"
            : "  \(field): \(value)"
    }

    /// One body line: the payload, or its size when content is not requested.
    private func bodyLine(_ data: Data) -> String {
        switch bodies {
        case .unredacted:
            "  \(String(decoding: data, as: UTF8.self))"
        case .sizeOnly:
            "  <\(data.count) bytes>"
        }
    }
}
