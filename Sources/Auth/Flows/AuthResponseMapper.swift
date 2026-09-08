import Foundation

import LaravelMobileKitCore

/// Reads a credential — and the user, when present — out of an authentication
/// response.
///
/// There is no single Laravel login response. Sanctum's documented example
/// returns a bare token string, `laravel/passport` returns an OAuth payload,
/// and hand-written controllers return whatever the team chose. The mapper is
/// the seam that lets the kit work with an existing API instead of asking the
/// backend to change.
public struct AuthResponseMapper<User: Decodable & Sendable>: Sendable {
    /// Extracts the credential from the response payload.
    public let makeCredential: @Sendable (Data) throws -> AuthCredential
    /// Extracts the user from the response payload, when it carries one.
    public let makeUser: @Sendable (Data, JSONDecoder) throws -> User?

    public init(
        makeCredential: @escaping @Sendable (Data) throws -> AuthCredential,
        makeUser: @escaping @Sendable (Data, JSONDecoder) throws -> User?
    ) {
        self.makeCredential = makeCredential
        self.makeUser = makeUser
    }

    /// A mapper covering the response shapes Laravel APIs commonly return.
    ///
    /// It accepts a payload at the top level or nested under `data`, finds the
    /// token under `token`, `access_token`, or `plain_text_token`, reads
    /// `refresh_token` and `token_type` when present, and understands both
    /// `expires_at` (a date) and `expires_in` (seconds from now). A `user`
    /// object is decoded when the response includes one.
    public static var laravel: AuthResponseMapper {
        AuthResponseMapper(
            makeCredential: { data in
                guard let payload = AuthPayload(data: data) else {
                    throw AuthError.invalidAuthResponse
                }
                return try payload.credential()
            },
            makeUser: { data, decoder in
                guard let payload = AuthPayload(data: data) else { return nil }
                return try payload.user(as: User.self, decodedBy: decoder)
            }
        )
    }
}

/// The JSON object of an auth response, unwrapped from any `data` envelope.
private struct AuthPayload {
    private let object: [String: Any]

    init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // An API resource wraps its payload; a plain controller does not.
        if let nested = root["data"] as? [String: Any], AuthPayload.carriesToken(nested) {
            object = nested
        } else {
            object = root
        }
    }

    private static let tokenKeys = ["token", "access_token", "accessToken", "plain_text_token", "plainTextToken"]
    private static let refreshKeys = ["refresh_token", "refreshToken"]
    private static let typeKeys = ["token_type", "tokenType"]
    private static let expiryDateKeys = ["expires_at", "expiresAt"]
    private static let expiryIntervalKeys = ["expires_in", "expiresIn"]

    private static func carriesToken(_ object: [String: Any]) -> Bool {
        tokenKeys.contains { object[$0] is String }
    }

    func credential() throws -> AuthCredential {
        guard let token = string(forAnyOf: AuthPayload.tokenKeys) else {
            throw AuthError.invalidAuthResponse
        }
        return AuthCredential(
            accessToken: token,
            refreshToken: string(forAnyOf: AuthPayload.refreshKeys),
            tokenType: string(forAnyOf: AuthPayload.typeKeys) ?? "Bearer",
            expiresAt: expiry()
        )
    }

    func user<T: Decodable>(as type: T.Type, decodedBy decoder: JSONDecoder) throws -> T? {
        guard let user = object["user"] ?? object["data"] else { return nil }

        let data = try JSONSerialization.data(withJSONObject: user)
        return try decoder.decode(type, from: data)
    }

    private func string(forAnyOf keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func expiry() -> Date? {
        for key in AuthPayload.expiryDateKeys {
            if let raw = object[key] as? String, let date = LaravelDateFormat.date(from: raw) {
                return date
            }
        }
        for key in AuthPayload.expiryIntervalKeys {
            if let seconds = object[key] as? NSNumber {
                return Date().addingTimeInterval(seconds.doubleValue)
            }
        }
        return nil
    }
}
