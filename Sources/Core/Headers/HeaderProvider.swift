import Foundation

/// Supplies headers that are computed when a request is sent.
///
/// Static values belong in ``LaravelClientConfiguration/defaultHeaders``. A
/// provider is for values that change between requests — a device identifier
/// loaded lazily, a locale that follows the user's settings, a token read from
/// storage.
public protocol HeaderProvider: Sendable {
    /// Headers to apply to the request being built.
    func headers() async -> [String: String]
}

/// A provider returning a fixed set of headers.
public struct StaticHeaders: HeaderProvider {
    private let values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public func headers() async -> [String: String] { values }
}

/// A provider computing its headers on every request.
public struct DynamicHeaders: HeaderProvider {
    private let build: @Sendable () async -> [String: String]

    public init(_ build: @escaping @Sendable () async -> [String: String]) {
        self.build = build
    }

    public func headers() async -> [String: String] { await build() }
}
