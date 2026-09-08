import Foundation

/// Authorization for one direct-to-storage upload, issued by the Laravel app.
///
/// The mobile app never holds storage credentials: it asks the API for a
/// short-lived signed URL, uploads to it, and tells the API the object key.
/// Laravel stays in charge of who may upload what.
public struct PresignedUpload: Sendable, Hashable {
    /// The signed URL the bytes are sent to.
    public let url: URL
    /// HTTP method the signature was issued for.
    public let method: String
    /// Headers the signature covers — they must be sent exactly as given.
    public let headers: [String: String]
    /// The object key the file will live under.
    public let key: String?
    /// The bucket, when the API names one.
    public let bucket: String?
    /// An identifier the API can use to reconcile the upload afterwards.
    public let uuid: String?

    public init(
        url: URL,
        method: String = "PUT",
        headers: [String: String] = [:],
        key: String? = nil,
        bucket: String? = nil,
        uuid: String? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.key = key
        self.bucket = bucket
        self.uuid = uuid
    }

    /// Reads an authorization response.
    ///
    /// The payload is read tolerantly because there is no single shape:
    /// `laravel/vapor-core` answers with `url` and `headers`, hand-written
    /// controllers commonly use `upload_url` or `signed_url`, and either may
    /// arrive wrapped in a `data` envelope.
    public init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let object = (root["data"] as? [String: Any]).flatMap {
            PresignedUpload.containsURL($0) ? $0 : nil
        } ?? root

        guard let urlString = PresignedUpload.string(in: object, keys: PresignedUpload.urlKeys),
              let url = URL(string: urlString)
        else {
            return nil
        }

        self.url = url
        self.method = PresignedUpload.string(in: object, keys: ["method"])?.uppercased() ?? "PUT"
        self.headers = (object["headers"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        self.key = PresignedUpload.string(in: object, keys: ["key", "path", "object_key", "objectKey"])
        self.bucket = PresignedUpload.string(in: object, keys: ["bucket"])
        self.uuid = PresignedUpload.string(in: object, keys: ["uuid", "id"])
    }

    private static let urlKeys = ["url", "upload_url", "uploadUrl", "signed_url", "signedUrl"]

    private static func containsURL(_ object: [String: Any]) -> Bool {
        urlKeys.contains { object[$0] is String }
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
