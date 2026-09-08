/// Generic REST transport layer for Laravel Mobile Kit.
///
/// `LaravelMobileKitCore` owns HTTP transport, requests and responses, Codable
/// serialization, middleware, errors, configuration, and cancellation. It stays
/// deliberately free of Laravel-specific conventions so it remains usable with
/// any REST API.
public enum LaravelMobileKitCore {
    /// Semantic version of the Core module.
    public static let version = "0.1.0"
}
