import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import LaravelMobileKitCore

extension LaravelClient {
    /// A client wired for a Sanctum SPA session.
    ///
    /// Three things have to be right for Laravel to treat a request as
    /// stateful, and getting any of them wrong fails in a way that is hard to
    /// read from the client side:
    ///
    /// - the cookie jar is kept across requests, so the session cookie sticks;
    /// - the request names its origin, because Sanctum only accepts a session
    ///   from a domain listed in `SANCTUM_STATEFUL_DOMAINS`;
    /// - unsafe requests carry the CSRF token from the `XSRF-TOKEN` cookie.
    ///
    /// ```swift
    /// let client = await LaravelClient.sanctumSPA(baseURL: baseURL)
    /// await client.use(.validationErrors)   // from LaravelMobileKitLaravel
    /// ```
    ///
    /// - Parameters:
    ///   - cookieStorage: Where the session cookie lives. The shared jar is
    ///     persistent, so a session survives a relaunch; pass a private jar —
    ///     `URLSessionConfiguration.ephemeral.httpCookieStorage` — to isolate
    ///     one, as tests do.
    ///   - additionalHeaders: Merged over the defaults, so `Origin` or an app
    ///     header can be added.
    public static func sanctumSPA(
        baseURL: URL,
        cookieStorage: HTTPCookieStorage = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default,
        additionalHeaders: [String: String] = [:]
    ) async -> LaravelClient {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpCookieStorage = cookieStorage
        sessionConfiguration.httpCookieAcceptPolicy = .always
        sessionConfiguration.httpShouldSetCookies = true

        var headers = LaravelClientConfiguration.defaultJSONHeaders
        headers["Referer"] = baseURL.absoluteString
        for (field, value) in additionalHeaders {
            headers[field] = value
        }

        let client = LaravelClient(
            configuration: LaravelClientConfiguration(
                baseURL: baseURL,
                defaultHeaders: headers,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            ),
            transport: URLSessionTransport(configuration: sessionConfiguration)
        )
        await client.use(.sanctumCSRF(baseURL: baseURL, cookieStorage: cookieStorage))
        return client
    }
}
