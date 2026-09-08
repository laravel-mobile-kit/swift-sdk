import Foundation

import LaravelMobileKitCore

/// Inserts an API version segment into request paths.
///
/// ```swift
/// await client.use(.apiVersion(.v1))
///
/// let events: [Event] = try await client.get("/api/events")   // → /api/v1/events
/// ```
///
/// Version prefixing is a convenience, never a requirement: writing
/// `/api/v1/events` directly always works, and a path that already carries a
/// version is left alone. Authentication routes are excluded by default,
/// because Laravel apps routinely expose `/api/login` next to `/api/v1/events`.
public struct APIVersionMiddleware: Middleware {
    /// The version to insert.
    public let version: APIVersion
    /// The prefix a versioned path starts with, normally `/api`.
    public let pathPrefix: String
    /// Paths that keep their shape — auth routes and anything else unversioned.
    public let excludedPaths: Set<String>

    public init(
        version: APIVersion,
        pathPrefix: String = "/api",
        excludedPaths: Set<String> = APIVersionMiddleware.defaultExcludedPaths
    ) {
        self.version = version
        self.pathPrefix = pathPrefix
        self.excludedPaths = excludedPaths
    }

    /// The authentication routes a stock Laravel application exposes.
    ///
    /// Pass `AuthConfiguration.allEndpoints` instead when the app configures
    /// its own auth routes.
    public static let defaultExcludedPaths: Set<String> = [
        "/api/login",
        "/api/logout",
        "/api/register",
        "/api/user",
        "/api/auth/refresh",
        "/api/forgot-password",
        "/api/reset-password",
        "/api/email/verification-notification",
    ]

    public func process(_ request: URLRequest) async throws -> URLRequest {
        guard let url = request.url,
              let segment = version.pathSegment,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return request
        }

        let versioned = versionedPath(components.path, segment: segment)
        guard versioned != components.path else { return request }

        components.path = versioned
        var request = request
        request.url = components.url
        return request
    }

    /// The path to send, given the configured version.
    func versionedPath(_ path: String, segment: String) -> String {
        guard !isExcluded(path), !isVersioned(path, segment: segment) else { return path }
        guard path == pathPrefix || path.hasPrefix("\(pathPrefix)/") else {
            // Outside the versioned area of the API — a webhook or a signed
            // storage callback, say.
            return path
        }

        return "\(pathPrefix)/\(segment)\(path.dropFirst(pathPrefix.count))"
    }

    private func isExcluded(_ path: String) -> Bool {
        excludedPaths.contains { path == $0 || path.hasPrefix("\($0)/") }
    }

    /// Whether the path already names a version.
    ///
    /// Both the configured segment and any `v<number>` segment count, so a
    /// deliberate `/api/v2/events` is never rewritten to v1.
    private func isVersioned(_ path: String, segment: String) -> Bool {
        path.split(separator: "/").contains { part in
            part == segment || (part.hasPrefix("v") && part.dropFirst().allSatisfy(\.isNumber) && part.count > 1)
        }
    }
}

extension Middleware where Self == APIVersionMiddleware {
    /// Prefixes request paths with an API version.
    public static func apiVersion(
        _ version: APIVersion,
        pathPrefix: String = "/api",
        excludedPaths: Set<String> = APIVersionMiddleware.defaultExcludedPaths
    ) -> APIVersionMiddleware {
        APIVersionMiddleware(
            version: version,
            pathPrefix: pathPrefix,
            excludedPaths: excludedPaths
        )
    }
}
