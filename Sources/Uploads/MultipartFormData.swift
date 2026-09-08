import Foundation

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A file to send as part of a multipart request.
public struct UploadFile: Sendable, Hashable {
    /// The bytes to upload.
    public var data: Data
    /// The form field the server reads it from — Laravel's `$request->file(...)`.
    public var fieldName: String
    /// The name the server records for the file.
    public var fileName: String
    /// The declared content type; inferred from the file extension when omitted.
    public var mimeType: String

    public init(
        data: Data,
        fieldName: String = "file",
        fileName: String = "file",
        mimeType: String? = nil
    ) {
        self.data = data
        self.fieldName = fieldName
        self.fileName = fileName
        self.mimeType = mimeType ?? MIMEType.inferred(fromFileName: fileName)
    }

    /// Reads a file from disk.
    public init(
        contentsOf url: URL,
        fieldName: String = "file",
        fileName: String? = nil,
        mimeType: String? = nil
    ) throws {
        let name = fileName ?? url.lastPathComponent
        self.init(
            data: try Data(contentsOf: url),
            fieldName: fieldName,
            fileName: name,
            mimeType: mimeType ?? MIMEType.inferred(fromFileName: name)
        )
    }
}

/// Guesses a content type from a file name.
public enum MIMEType {
    /// The type matching the file's extension, or `application/octet-stream`.
    public static func inferred(fromFileName fileName: String) -> String {
        let fallback = "application/octet-stream"
        let ext = (fileName as NSString).pathExtension
        guard !ext.isEmpty else { return fallback }

        #if canImport(UniformTypeIdentifiers)
        if let type = UTType(filenameExtension: ext)?.preferredMIMEType {
            return type
        }
        #endif
        return fallback
    }
}

/// A `multipart/form-data` body.
///
/// Laravel reads files with `$request->file('avatar')` and text fields with
/// `$request->input('caption')`; both travel in the same body, which is what
/// this builds.
///
/// ```swift
/// var form = MultipartFormData()
/// form.append(UploadFile(data: jpeg, fieldName: "avatar", fileName: "avatar.jpg"))
/// form.append(value: "Holiday", name: "caption")
/// ```
public struct MultipartFormData: Sendable, Hashable {
    /// The boundary separating the parts.
    public let boundary: String

    private var parts: [Part] = []

    /// - Parameter boundary: Overriding it is for tests that assert on the body.
    public init(boundary: String = "LaravelMobileKit-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// The value for the request's `Content-Type` header.
    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Whether anything has been added.
    public var isEmpty: Bool { parts.isEmpty }

    // MARK: - Building

    /// Adds a file part.
    public mutating func append(_ file: UploadFile) {
        parts.append(
            Part(
                name: file.fieldName,
                fileName: file.fileName,
                mimeType: file.mimeType,
                data: file.data
            )
        )
    }

    /// Adds a file part from raw bytes.
    public mutating func append(
        data: Data,
        name: String,
        fileName: String? = nil,
        mimeType: String? = nil
    ) {
        parts.append(
            Part(
                name: name,
                fileName: fileName,
                mimeType: mimeType ?? fileName.map(MIMEType.inferred(fromFileName:)),
                data: data
            )
        )
    }

    /// Adds a plain text field.
    public mutating func append(value: String, name: String) {
        parts.append(Part(name: name, fileName: nil, mimeType: nil, data: Data(value.utf8)))
    }

    /// Adds several text fields, in a stable order.
    public mutating func append(fields: [String: String]) {
        for name in fields.keys.sorted() {
            append(value: fields[name]!, name: name)
        }
    }

    // MARK: - Encoding

    /// The encoded body.
    public func encode() -> Data {
        var body = Data()
        for part in parts {
            body.append(line("--\(boundary)"))
            body.append(part.headerData())
            body.append(part.data)
            body.append(line(""))
        }
        body.append(line("--\(boundary)--"))
        return body
    }

    private func line(_ text: String) -> Data {
        Data("\(text)\r\n".utf8)
    }

    /// One part of the body.
    private struct Part: Sendable, Hashable {
        let name: String
        let fileName: String?
        let mimeType: String?
        let data: Data

        func headerData() -> Data {
            var disposition = "Content-Disposition: form-data; name=\"\(escaped(name))\""
            if let fileName {
                disposition += "; filename=\"\(escaped(fileName))\""
            }

            var header = "\(disposition)\r\n"
            if let mimeType {
                header += "Content-Type: \(mimeType)\r\n"
            }
            header += "\r\n"
            return Data(header.utf8)
        }

        /// Quotes inside a field name would end the attribute early.
        private func escaped(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\r\n", with: "")
                .replacingOccurrences(of: "\n", with: "")
        }
    }
}
