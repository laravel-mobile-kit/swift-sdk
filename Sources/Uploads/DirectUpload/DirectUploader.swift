import Foundation

import LaravelMobileKitCore

/// Uploads files straight to object storage using a URL the Laravel app signs.
///
/// ```
/// 1. ask Laravel to authorize the upload
/// 2. send the bytes to the signed URL
/// 3. tell Laravel the object key
/// ```
///
/// ```swift
/// let uploader = client.directUploader()
/// let receipt: Receipt = try await uploader.upload(
///     jpeg,
///     authorizingAt: "/api/uploads/authorize",
///     notifyingAt: "/api/uploads/complete",
///     fileName: "avatar.jpg",
///     mimeType: "image/jpeg"
/// )
/// ```
///
/// The bytes go through a separate, unauthenticated transport on purpose: a
/// presigned URL carries its own signature, and sending the app's
/// `Authorization` header alongside it makes storage services reject the
/// request. It also means the file never passes through the Laravel server.
public actor DirectUploader {
    private let client: LaravelClient
    private let storageTransport: any HTTPTransport

    /// - Parameters:
    ///   - client: Used for the authorize and notify calls, with the app's
    ///     usual authentication.
    ///   - storageTransport: Sends the bytes to storage. It deliberately
    ///     carries none of the client's middleware or default headers.
    public init(
        client: LaravelClient,
        storageTransport: any HTTPTransport = URLSessionTransport()
    ) {
        self.client = client
        self.storageTransport = storageTransport
    }

    // MARK: - Steps

    /// Asks the API to authorize an upload.
    ///
    /// - Parameters:
    ///   - fields: Sent as the request body. Endpoints differ in what they
    ///     expect, so pass exactly what yours reads.
    ///   - size: Written as a JSON number, since size limits are validated as
    ///     integers.
    public func authorize(
        at endpoint: String,
        fields: [String: String],
        size: Int? = nil
    ) async throws -> PresignedUpload {
        let response = try await client.raw(
            .post,
            endpoint,
            body: DirectUploader.body(fields: fields, size: size)
        )

        guard let presigned = PresignedUpload(data: response.rawData) else {
            throw UploadError.invalidAuthorization
        }
        return presigned
    }

    /// Sends the bytes to the signed URL.
    ///
    /// Only the headers the API returned are sent: they are part of what the
    /// signature covers.
    public func send(
        _ data: Data,
        to presigned: PresignedUpload,
        timeout: TimeInterval? = nil,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws {
        var request = URLRequest(url: presigned.url)
        request.httpMethod = presigned.method
        request.httpBody = data
        if let timeout {
            request.timeoutInterval = timeout
        }
        for (field, value) in presigned.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (body, response): (Data, HTTPURLResponse)
        if let onProgress, let transport = storageTransport as? any ProgressReportingTransport {
            (body, response) = try await transport.execute(request, uploadProgress: onProgress)
        } else {
            (body, response) = try await storageTransport.execute(request)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw UploadError.directUploadFailed(
                statusCode: response.statusCode,
                body: body.isEmpty ? nil : body
            )
        }
    }

    // MARK: - Whole flow

    /// Authorizes an upload and sends the bytes, without notifying the API.
    ///
    /// - Returns: The authorization, so the caller can record the object key.
    @discardableResult
    public func upload(
        _ data: Data,
        authorizingAt authorizationEndpoint: String,
        fileName: String? = nil,
        mimeType: String? = nil,
        extraFields: [String: String] = [:],
        timeout: TimeInterval? = nil,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> PresignedUpload {
        let presigned = try await authorize(
            at: authorizationEndpoint,
            fields: authorizationFields(
                fileName: fileName,
                mimeType: mimeType,
                extraFields: extraFields
            ),
            size: data.count
        )
        try await send(data, to: presigned, timeout: timeout, onProgress: onProgress)
        return presigned
    }

    /// Authorizes an upload, sends the bytes, and tells the API it landed.
    ///
    /// The notification body carries the object key, bucket, and uuid the
    /// authorization returned, plus anything in `notifyFields`.
    ///
    /// - Returns: The decoded response of the notify call — normally the record
    ///   Laravel created for the file.
    @discardableResult
    public func upload<T: Decodable & Sendable>(
        _ data: Data,
        authorizingAt authorizationEndpoint: String,
        notifyingAt notifyEndpoint: String,
        fileName: String? = nil,
        mimeType: String? = nil,
        extraFields: [String: String] = [:],
        notifyFields: [String: String] = [:],
        timeout: TimeInterval? = nil,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> T {
        let presigned = try await upload(
            data,
            authorizingAt: authorizationEndpoint,
            fileName: fileName,
            mimeType: mimeType,
            extraFields: extraFields,
            timeout: timeout,
            onProgress: onProgress
        )

        var fields = notifyFields
        if let key = presigned.key { fields["key"] = key }
        if let bucket = presigned.bucket { fields["bucket"] = bucket }
        if let uuid = presigned.uuid { fields["uuid"] = uuid }
        if let fileName { fields["filename"] = fileName }

        let response: Response<T> = try await client.response(
            .post,
            notifyEndpoint,
            body: DirectUploader.body(fields: fields, size: nil)
        )
        return response.value
    }

    /// The body of the authorization request.
    private func authorizationFields(
        fileName: String?,
        mimeType: String?,
        extraFields: [String: String]
    ) -> [String: String] {
        var fields = extraFields
        fields["content_type"] = mimeType
            ?? fileName.map(MIMEType.inferred(fromFileName:))
            ?? "application/octet-stream"
        if let fileName {
            fields["filename"] = fileName
        }
        return fields
    }

    /// Encodes field names exactly as given — they are the API's contract.
    private static func body(fields: [String: String], size: Int?) -> Data {
        var object: [String: Any] = fields
        if let size {
            object["size"] = size
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}

extension LaravelClient {
    /// An uploader that sends files straight to storage.
    public nonisolated func directUploader(
        storageTransport: any HTTPTransport = URLSessionTransport()
    ) -> DirectUploader {
        DirectUploader(client: self, storageTransport: storageTransport)
    }
}
