import Foundation

/// How much of a request body has reached the server.
public struct UploadProgress: Sendable, Hashable {
    /// Bytes sent so far.
    public let bytesSent: Int64
    /// Bytes the body holds in total, or `nil` when the size is unknown.
    public let totalBytes: Int64?

    public init(bytesSent: Int64, totalBytes: Int64?) {
        self.bytesSent = bytesSent
        self.totalBytes = totalBytes.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Completion between `0` and `1`, or `nil` when the total is unknown.
    public var fractionCompleted: Double? {
        guard let totalBytes else { return nil }
        return min(1, Double(bytesSent) / Double(totalBytes))
    }
}

/// A transport that can report how much of the body it has sent.
///
/// Progress is optional so the plain ``HTTPTransport`` stays a two-line
/// protocol; a transport that cannot report progress simply does not conform,
/// and uploads through it still work.
public protocol ProgressReportingTransport: HTTPTransport {
    /// Sends `request`, calling `uploadProgress` as the body goes out.
    func execute(
        _ request: URLRequest,
        uploadProgress: @escaping @Sendable (UploadProgress) -> Void
    ) async throws -> (Data, HTTPURLResponse)
}
