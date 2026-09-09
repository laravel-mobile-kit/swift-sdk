import Foundation

/// The field names an identity-token exchange is sent under.
///
/// There is no convention here — `identity_token`, `id_token` and `token` are
/// all in the wild, and an existing API is not going to rename its parameters
/// because a client arrived. These are the API's contract, so they are sent
/// exactly as written.
public struct IdentityTokenFieldNames: Sendable, Hashable {
    /// Carries the signed JWT from the provider.
    public var identityToken: String
    /// Carries the raw nonce.
    public var nonce: String
    /// Carries which provider issued the token.
    public var provider: String

    public init(
        identityToken: String = "identity_token",
        nonce: String = "nonce",
        provider: String = "provider"
    ) {
        self.identityToken = identityToken
        self.nonce = nonce
        self.provider = provider
    }

    /// `identity_token`, `nonce`, `provider`.
    public static let `default` = IdentityTokenFieldNames()

    /// `id_token`, `nonce`, `provider` — the OIDC spelling, which Socialite's
    /// stateless helpers and most Google integrations use.
    public static let oidc = IdentityTokenFieldNames(identityToken: "id_token")
}
