import Foundation

import LaravelMobileKitCore

/// Attaches the current token to every outgoing request.
///
/// ```swift
/// let provider = CredentialTokenProvider(store: keychain)
/// await client.use(.auth(provider))
/// ```
///
/// A request that already carries the header this transport writes is left
/// alone, so a caller can override the token for one call.
public struct AuthMiddleware: Middleware {
    private let tokenProvider: any TokenProvider
    private let transport: AuthTransport

    public init(tokenProvider: any TokenProvider, transport: AuthTransport = .bearer) {
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    public func process(_ request: URLRequest) async throws -> URLRequest {
        if let headerField = transport.headerField,
           request.value(forHTTPHeaderField: headerField) != nil {
            return request
        }
        guard let token = try await tokenProvider.currentToken() else {
            // Signed out, or the token expired: send the request unauthenticated
            // and let the API answer 401.
            return request
        }
        return try await transport.apply(token, to: request)
    }
}

extension Middleware where Self == AuthMiddleware {
    /// Authenticates requests with the token `provider` supplies.
    public static func auth(
        _ provider: any TokenProvider,
        transport: AuthTransport = .bearer
    ) -> AuthMiddleware {
        AuthMiddleware(tokenProvider: provider, transport: transport)
    }
}
