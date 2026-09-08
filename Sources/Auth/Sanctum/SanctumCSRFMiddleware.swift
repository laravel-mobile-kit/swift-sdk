import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import LaravelMobileKitCore

/// Sends the CSRF token a Sanctum SPA session expects.
///
/// Laravel writes the token into an `XSRF-TOKEN` cookie and reads it back from
/// an `X-XSRF-TOKEN` header. The value is re-read from the cookie jar on every
/// request, because Laravel regenerates the session — and the token with it —
/// on sign-in and sign-out.
///
/// ```swift
/// await client.use(.sanctumCSRF(baseURL: baseURL))
/// ```
///
/// Only unsafe methods carry the header; `GET` and `HEAD` never need it, and
/// the CSRF-cookie handshake itself is a `GET`.
public struct SanctumCSRFMiddleware: Middleware {
    /// The API's root, used to look the cookie up.
    public let baseURL: URL
    /// Where the cookie is read from. Defaults to the shared jar, which is what
    /// `URLSession` writes to unless told otherwise.
    public let cookieStorage: HTTPCookieStorage
    /// Cookie Laravel writes the token into.
    public let cookieName: String
    /// Header Laravel reads the token back from.
    public let headerField: String

    /// Methods that never carry a CSRF token.
    private static let safeMethods: Set<String> = ["GET", "HEAD", "OPTIONS", "TRACE"]

    public init(
        baseURL: URL,
        cookieStorage: HTTPCookieStorage = .shared,
        cookieName: String = "XSRF-TOKEN",
        headerField: String = "X-XSRF-TOKEN"
    ) {
        self.baseURL = baseURL
        self.cookieStorage = cookieStorage
        self.cookieName = cookieName
        self.headerField = headerField
    }

    public func process(_ request: URLRequest) async throws -> URLRequest {
        let method = request.httpMethod ?? "GET"
        guard !SanctumCSRFMiddleware.safeMethods.contains(method) else { return request }
        // A caller that set the header itself keeps it.
        guard request.value(forHTTPHeaderField: headerField) == nil else { return request }
        guard let token = currentToken() else { return request }

        var request = request
        request.setValue(token, forHTTPHeaderField: headerField)
        return request
    }

    /// The token currently in the jar, percent-decoded as Laravel expects.
    func currentToken() -> String? {
        guard let cookies = cookieStorage.cookies(for: baseURL),
              let value = cookies.first(where: { $0.name == cookieName })?.value,
              !value.isEmpty
        else {
            return nil
        }
        return value.removingPercentEncoding ?? value
    }
}

extension Middleware where Self == SanctumCSRFMiddleware {
    /// Attaches Sanctum's CSRF token to every unsafe request.
    public static func sanctumCSRF(
        baseURL: URL,
        cookieStorage: HTTPCookieStorage = .shared
    ) -> SanctumCSRFMiddleware {
        SanctumCSRFMiddleware(baseURL: baseURL, cookieStorage: cookieStorage)
    }
}
