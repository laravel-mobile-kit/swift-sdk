import Foundation
import Testing

import LaravelMobileKitCore
import LaravelMobileKitUploads

private struct UploadReceipt: Codable, Hashable, Sendable {
    let id: Int
    let url: String
}

/// A transport that reports body progress, the way `URLSession` does.
private actor ProgressMockTransport: ProgressReportingTransport {
    private let body: Data
    private let steps: Int
    private(set) var executedRequests: [URLRequest] = []

    init(json: String, steps: Int = 4) {
        self.body = Data(json.utf8)
        self.steps = steps
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        executedRequests.append(request)
        return (body, response(for: request))
    }

    func execute(
        _ request: URLRequest,
        uploadProgress: @escaping @Sendable (UploadProgress) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        executedRequests.append(request)

        let total = Int64(request.httpBody?.count ?? 0)
        for step in 1 ... steps {
            uploadProgress(
                UploadProgress(bytesSent: total * Int64(step) / Int64(steps), totalBytes: total)
            )
        }
        return (body, response(for: request))
    }

    private func response(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    var lastRequest: URLRequest? { executedRequests.last }
}

/// Collects progress callbacks from any thread.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UploadProgress] = []

    var values: [UploadProgress] { lock.withLock { storage } }

    func makeHandler() -> @Sendable (UploadProgress) -> Void {
        { [self] progress in lock.withLock { storage.append(progress) } }
    }
}

@Suite("Uploads")
struct UploadTests {
    let baseURL = URL(string: "https://api.example.com")!
    let receiptJSON = #"{"id":1,"url":"https://cdn.example.com/a.jpg"}"#

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("Uploading one file posts a multipart body and decodes the response")
    func uploadSingleFile() async throws {
        let transport = MockTransport(statusCode: 201, json: receiptJSON)
        let client = makeClient(transport)

        let receipt: UploadReceipt = try await client.upload(
            Data("BYTES".utf8),
            to: "/api/avatar",
            fieldName: "avatar",
            fileName: "avatar.jpg"
        )

        #expect(receipt == UploadReceipt(id: 1, url: "https://cdn.example.com/a.jpg"))

        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/avatar")

        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains(#"name="avatar"; filename="avatar.jpg""#))
        #expect(body.contains("Content-Type: image/jpeg"))
        #expect(body.contains("BYTES"))
    }

    @Test("The multipart content type replaces the client's JSON default")
    func contentTypeIsReplaced() async throws {
        let transport = MockTransport(statusCode: 201, json: receiptJSON)
        let client = makeClient(transport)

        let _: UploadReceipt = try await client.upload(Data("X".utf8), to: "/api/avatar")

        let contentType = try #require(
            await transport.lastRequest?.value(forHTTPHeaderField: "Content-Type")
        )
        #expect(!contentType.contains("application/json"))
    }

    @Test("Several files and extra fields travel in one request")
    func uploadMultipleFilesWithFields() async throws {
        let transport = MockTransport(statusCode: 201, json: receiptJSON)
        let client = makeClient(transport)

        let _: UploadReceipt = try await client.upload(
            [
                UploadFile(data: Data("A".utf8), fieldName: "files[]", fileName: "a.txt"),
                UploadFile(data: Data("B".utf8), fieldName: "files[]", fileName: "b.txt"),
            ],
            to: "/api/documents",
            fields: ["album": "Holiday"]
        )

        let body = String(decoding: try #require(await transport.lastRequest?.httpBody), as: UTF8.self)
        #expect(body.contains(#"filename="a.txt""#))
        #expect(body.contains(#"filename="b.txt""#))
        #expect(body.contains(#"name="album""#))
        #expect(body.contains("Holiday"))
    }

    @Test("A hand-built body is sent as assembled")
    func uploadPreparedForm() async throws {
        let transport = MockTransport(statusCode: 201, json: receiptJSON)
        let client = makeClient(transport)
        var form = MultipartFormData(boundary: "TEST")
        form.append(value: "1", name: "public")

        let _: UploadReceipt = try await client.upload(form, to: "/api/documents", method: .put)

        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=TEST")
        #expect(request.httpBody == form.encode())
    }

    @Test("Progress is reported while the body is sent")
    func progressIsReported() async throws {
        let transport = ProgressMockTransport(json: receiptJSON)
        let client = makeClient(transport)
        let recorder = ProgressRecorder()

        let _: UploadReceipt = try await client.upload(
            Data(repeating: 0, count: 1_000),
            to: "/api/avatar",
            onProgress: recorder.makeHandler()
        )

        let values = recorder.values
        #expect(values.count == 4)
        #expect(values.last?.fractionCompleted == 1)
        #expect(values.first?.fractionCompleted ?? 0 > 0)
        #expect(values.map(\.bytesSent) == values.map(\.bytesSent).sorted())
    }

    @Test("An upload without a progress handler still works")
    func uploadWithoutProgressHandler() async throws {
        let transport = ProgressMockTransport(json: receiptJSON)
        let client = makeClient(transport)

        let receipt: UploadReceipt = try await client.upload(Data("X".utf8), to: "/api/avatar")

        #expect(receipt.id == 1)
    }

    @Test("A transport that cannot report progress still uploads")
    func progressIsOptionalForTransports() async throws {
        let transport = MockTransport(statusCode: 201, json: receiptJSON)
        let client = makeClient(transport)
        let recorder = ProgressRecorder()

        let receipt: UploadReceipt = try await client.upload(
            Data("X".utf8),
            to: "/api/avatar",
            onProgress: recorder.makeHandler()
        )

        #expect(receipt.id == 1)
        #expect(recorder.values.isEmpty)
    }

    @Test("An upload fails with the server's error")
    func uploadFailure() async throws {
        let transport = MockTransport(statusCode: 422, json: #"{"message":"The file is too large."}"#)
        let client = makeClient(transport)

        do {
            let _: UploadReceipt = try await client.upload(Data("X".utf8), to: "/api/avatar")
            Issue.record("Expected the upload to throw")
        } catch let error as LaravelError {
            #expect(error.isValidationError)
        }
    }

    @Test("Cancelling the task cancels the upload")
    func uploadCancellation() async throws {
        let transport = MockTransport(statusCode: 201, json: receiptJSON)
        await transport.stall(seconds: 5)
        let client = makeClient(transport)

        let task = Task { () async throws -> UploadReceipt in
            try await client.upload(Data("X".utf8), to: "/api/avatar")
        }
        while await transport.executedRequests.isEmpty {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the upload to be cancelled")
        } catch let error as LaravelError {
            #expect(error.isCancelled)
        }
    }
}
