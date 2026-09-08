import Foundation

import LaravelMobileKitCore

extension LaravelClient {
    /// Uploads one file to a Laravel endpoint.
    ///
    /// ```swift
    /// let result: AvatarResponse = try await client.upload(
    ///     jpegData,
    ///     to: "/api/avatar",
    ///     fieldName: "avatar",
    ///     fileName: "avatar.jpg"
    /// ) { progress in
    ///     await MainActor.run { fraction = progress.fractionCompleted ?? 0 }
    /// }
    /// ```
    ///
    /// Cancelling the surrounding task cancels the upload, exactly as it does
    /// for any other request.
    @discardableResult
    public func upload<T: Decodable>(
        _ data: Data,
        to path: String,
        fieldName: String = "file",
        fileName: String = "file",
        mimeType: String? = nil,
        fields: [String: String] = [:],
        method: HTTPMethod = .post,
        options: RequestOptions = .none,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> T {
        let file = UploadFile(
            data: data,
            fieldName: fieldName,
            fileName: fileName,
            mimeType: mimeType
        )
        return try await upload(
            [file],
            to: path,
            fields: fields,
            method: method,
            options: options,
            onProgress: onProgress
        )
    }

    /// Uploads several files in one request.
    @discardableResult
    public func upload<T: Decodable>(
        _ files: [UploadFile],
        to path: String,
        fields: [String: String] = [:],
        method: HTTPMethod = .post,
        options: RequestOptions = .none,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> T {
        var form = MultipartFormData()
        for file in files {
            form.append(file)
        }
        form.append(fields: fields)

        return try await upload(
            form,
            to: path,
            method: method,
            options: options,
            onProgress: onProgress
        )
    }

    /// Sends a body you assembled yourself.
    ///
    /// Use this when the endpoint expects a shape the convenience methods do
    /// not produce — repeated field names, or a specific part order.
    @discardableResult
    public func upload<T: Decodable>(
        _ form: MultipartFormData,
        to path: String,
        method: HTTPMethod = .post,
        options: RequestOptions = .none,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> T {
        var options = options
        // The boundary is part of the header, so it has to come from this body.
        options.headers["Content-Type"] = form.contentType

        let response: Response<T> = try await response(
            method,
            path,
            body: form.encode(),
            options: options,
            onProgress: onProgress
        )
        return response.value
    }
}
