import Foundation

/// Failures specific to uploading.
public enum UploadError: Error, LocalizedError, Hashable {
    /// The authorization response carried no usable upload URL.
    case invalidAuthorization
    /// The storage service rejected the upload.
    case directUploadFailed(statusCode: Int, body: Data?)

    public var errorDescription: String? {
        switch self {
        case .invalidAuthorization:
            "The upload authorization response contained no upload URL"
        case let .directUploadFailed(statusCode, _):
            "The storage service rejected the upload with HTTP \(statusCode)"
        }
    }
}
