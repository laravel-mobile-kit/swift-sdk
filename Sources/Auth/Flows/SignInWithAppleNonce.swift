import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// A nonce for Sign in with Apple, in the two forms the flow needs.
///
/// Apple's request carries a **hash** of the nonce; the identity token it
/// returns carries that same hash as a claim. Your server compares the claim
/// against the hash of the **raw** value your app sends alongside the token,
/// which is what proves the token was minted for this sign-in rather than
/// replayed from another one.
///
/// Two values, used in two places, one derived from the other — which is
/// precisely why hand-rolling it goes wrong. The usual mistake is sending the
/// hashed form to the server, or hashing twice; both fail server-side with an
/// error that says nothing about nonces.
///
/// ```swift
/// let nonce = SignInWithAppleNonce()
///
/// let request = ASAuthorizationAppleIDProvider().createRequest()
/// request.requestedScopes = [.fullName, .email]
/// request.nonce = nonce.hashed          // Apple gets the hash
///
/// // …and after the controller calls back:
/// try await auth.login(identityToken: token, nonce: nonce.raw)   // the server gets the raw value
/// ```
///
/// Keep the value alive between the two: a nonce regenerated after the callback
/// matches nothing.
public struct SignInWithAppleNonce: Sendable, Hashable {
    /// The value your server receives, alongside the identity token.
    public let raw: String
    /// The SHA-256 of ``raw``, hex-encoded — the value Apple's request carries.
    public let hashed: String

    /// Creates a nonce from a fresh random value.
    public init() {
        self.init(raw: Self.makeRaw())
    }

    /// Creates a nonce from a value you already have.
    ///
    /// Useful when the raw nonce is generated elsewhere — a server-issued one,
    /// or a fixed value in a test.
    public init(raw: String) {
        self.raw = raw
        self.hashed = Self.sha256(raw)
    }

    /// A URL-safe random string.
    ///
    /// Drawn from `SystemRandomNumberGenerator`, which is cryptographically
    /// secure on every platform the kit supports.
    public static func makeRaw(length: Int = 32) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")
        var generator = SystemRandomNumberGenerator()
        return String((0 ..< max(1, length)).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// Hex-encoded SHA-256, which is the encoding Apple expects.
    static func sha256(_ value: String) -> String {
        let bytes = Data(value.utf8)
        #if canImport(CryptoKit)
        return CryptoKit.SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #else
        // Sign in with Apple is an Apple-platform flow; off those platforms the
        // type still compiles so shared code can reference it, but there is no
        // CryptoKit to hash with and no Apple to hash for.
        fatalError("SignInWithAppleNonce requires CryptoKit")
        #endif
    }
}
