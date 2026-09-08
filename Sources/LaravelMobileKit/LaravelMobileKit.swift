@_exported import LaravelMobileKitAuth
@_exported import LaravelMobileKitCore
@_exported import LaravelMobileKitLaravel
@_exported import LaravelMobileKitUploads

/// Umbrella module re-exporting every Laravel Mobile Kit capability.
///
/// Applications that want the full kit depend on `LaravelMobileKit`. Applications
/// that want a smaller dependency surface depend on the individual capability
/// modules instead.
public enum LaravelMobileKit {
    /// Semantic version of the kit.
    public static let version = LaravelMobileKitCore.version
}
