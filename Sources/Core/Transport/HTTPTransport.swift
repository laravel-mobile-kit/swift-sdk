import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Executes fully-formed `URLRequest`s.
///
/// The client owns request construction, status validation, and decoding; a
/// transport only moves bytes. Substituting a transport is how tests avoid the
/// network and how apps plug in a custom `URLSession`.
public protocol HTTPTransport: Sendable {
    /// Sends `request` and returns its payload and HTTP metadata.
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The default `URLSession`-backed transport.
public final class URLSessionTransport: HTTPTransport, ProgressReportingTransport {
    private let session: URLSession

    /// Creates a transport owning a session built from `configuration`.
    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    /// Creates a transport that uses an existing session.
    public init(session: URLSession) {
        self.session = session
    }

    public func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await perform(request, delegate: nil)
    }

    public func execute(
        _ request: URLRequest,
        uploadProgress: @escaping @Sendable (UploadProgress) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        try await perform(request, delegate: UploadProgressDelegate(handler: uploadProgress))
    }

    private func perform(
        _ request: URLRequest,
        delegate: (any URLSessionTaskDelegate)?
    ) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            if let body = request.httpBody, delegate != nil {
                // An upload task is what reports body progress; the body moves
                // from the request into the task for that to work.
                var request = request
                request.httpBody = nil
                (data, response) = try await session.upload(
                    for: request,
                    from: body,
                    delegate: delegate
                )
            } else {
                (data, response) = try await session.data(for: request, delegate: delegate)
            }
        } catch {
            throw LaravelError(transportFailure: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LaravelError.invalidResponse
        }
        return (data, httpResponse)
    }
}

/// Forwards `URLSession`'s body-progress callbacks to a handler.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let handler: @Sendable (UploadProgress) -> Void

    init(handler: @escaping @Sendable (UploadProgress) -> Void) {
        self.handler = handler
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        handler(UploadProgress(bytesSent: totalBytesSent, totalBytes: totalBytesExpectedToSend))
    }
}
