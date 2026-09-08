import LaravelMobileKitCore

/// Laravel conventions layered on top of the generic Core transport.
///
/// Covers validation errors, pagination, API resources, and API versioning.
public enum LaravelMobileKitLaravel {
    /// Semantic version of the Laravel module.
    public static let version = LaravelMobileKitCore.version
}
