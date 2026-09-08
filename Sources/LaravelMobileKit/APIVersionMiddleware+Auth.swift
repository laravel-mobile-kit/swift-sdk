import LaravelMobileKitAuth
import LaravelMobileKitCore
import LaravelMobileKitLaravel

extension APIVersionMiddleware {
    /// Versions the API while leaving the configured authentication routes alone.
    ///
    /// ```swift
    /// await client.use(APIVersionMiddleware(version: .v1, excluding: authConfiguration))
    /// ```
    ///
    /// This lives in the umbrella module because it is the one place that sees
    /// both the Laravel and Auth capabilities.
    public init(
        version: APIVersion,
        pathPrefix: String = "/api",
        excluding authConfiguration: AuthConfiguration
    ) {
        self.init(
            version: version,
            pathPrefix: pathPrefix,
            excludedPaths: authConfiguration.allEndpoints
        )
    }
}
