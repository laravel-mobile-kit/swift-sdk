import Foundation
import Testing

import LaravelMobileKitCore
import LaravelMobileKitUploads

private struct StoredFile: Codable, Hashable, Sendable {
    let id: Int
    let key: String
}

/// Stands in for object storage: records what it received and answers a status.
private actor StorageTransport: HTTPTransport {
    private let statusCode: Int
    private let body: Data
    private(set) var executedRequests: [URLRequest] = []

    init(statusCode: Int = 200, body: Data = Data()) {
        self.statusCode = statusCode
        self.body = body
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        executedRequests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (body, response)
    }

    var lastRequest: URLRequest? { executedRequests.last }
}

@Suite("Presigned authorization payloads")
struct PresignedUploadTests {
    @Test("A Vapor-style response is understood")
    func vaporShape() throws {
        let json = """
        {
          "uuid": "abc-123",
          "bucket": "app-uploads",
          "key": "tmp/abc-123",
          "url": "https://bucket.s3.amazonaws.com/tmp/abc-123?X-Amz-Signature=xyz",
          "headers": {"Content-Type": "image/jpeg", "x-amz-acl": "private"}
        }
        """

        let presigned = try #require(PresignedUpload(data: Data(json.utf8)))

        #expect(presigned.url.host == "bucket.s3.amazonaws.com")
        #expect(presigned.method == "PUT")
        #expect(presigned.key == "tmp/abc-123")
        #expect(presigned.bucket == "app-uploads")
        #expect(presigned.uuid == "abc-123")
        #expect(presigned.headers["x-amz-acl"] == "private")
    }

    @Test("Alternative URL field names are accepted", arguments: [
        "upload_url", "uploadUrl", "signed_url", "signedUrl",
    ])
    func alternativeURLKeys(key: String) throws {
        let json = #"{"\#(key)":"https://storage.example.com/x","key":"x"}"#

        let presigned = try #require(PresignedUpload(data: Data(json.utf8)))

        #expect(presigned.url.absoluteString == "https://storage.example.com/x")
    }

    @Test("A wrapped authorization is unwrapped")
    func wrappedPayload() throws {
        let json = #"{"data":{"upload_url":"https://storage.example.com/x","key":"x","method":"post"}}"#

        let presigned = try #require(PresignedUpload(data: Data(json.utf8)))

        #expect(presigned.key == "x")
        #expect(presigned.method == "POST")
    }

    @Test("A payload without a URL is rejected")
    func missingURL() {
        #expect(PresignedUpload(data: Data(#"{"key":"x"}"#.utf8)) == nil)
        #expect(PresignedUpload(data: Data("not json".utf8)) == nil)
    }
}

@Suite("Direct uploads")
struct DirectUploadTests {
    let baseURL = URL(string: "https://api.example.com")!
    let authorizationJSON = """
    {
      "uuid": "abc-123",
      "bucket": "app-uploads",
      "key": "tmp/abc-123",
      "url": "https://bucket.s3.amazonaws.com/tmp/abc-123?X-Amz-Signature=xyz",
      "headers": {"Content-Type": "image/jpeg"}
    }
    """

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("Authorization is requested with the file's type and size")
    func authorizationRequest() async throws {
        let api = MockTransport(json: authorizationJSON)
        let storage = StorageTransport()
        let uploader = DirectUploader(client: makeClient(api), storageTransport: storage)

        _ = try await uploader.upload(
            Data(repeating: 0, count: 2_048),
            authorizingAt: "/api/uploads/authorize",
            fileName: "avatar.jpg"
        )

        let request = try #require(await api.lastRequest)
        #expect(request.url?.path == "/api/uploads/authorize")
        let body = try #require(request.httpBody)
        let fields = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(fields["content_type"] as? String == "image/jpeg")
        #expect(fields["filename"] as? String == "avatar.jpg")
        #expect(fields["size"] as? Int == 2_048)
    }

    @Test("The bytes go to the signed URL with the signed headers")
    func bytesGoToStorage() async throws {
        let api = MockTransport(json: authorizationJSON)
        let storage = StorageTransport()
        let uploader = DirectUploader(client: makeClient(api), storageTransport: storage)

        let presigned = try await uploader.upload(
            Data("BYTES".utf8),
            authorizingAt: "/api/uploads/authorize",
            fileName: "avatar.jpg"
        )

        #expect(presigned.key == "tmp/abc-123")
        let request = try #require(await storage.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.host == "bucket.s3.amazonaws.com")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(request.httpBody == Data("BYTES".utf8))
    }

    @Test("The upload to storage carries no app credentials")
    func storageRequestIsUnauthenticated() async throws {
        let api = MockTransport(json: authorizationJSON)
        let storage = StorageTransport()
        let client = makeClient(api)
        // The API client authenticates; the storage transport must not.
        await client.use(.headerStamp(field: "Authorization", value: "Bearer secret"))
        let uploader = DirectUploader(client: client, storageTransport: storage)

        _ = try await uploader.upload(
            Data("BYTES".utf8),
            authorizingAt: "/api/uploads/authorize"
        )

        #expect(await api.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(await storage.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(await storage.lastRequest?.value(forHTTPHeaderField: "Accept") == nil)
    }

    @Test("The API is notified with the object key once the bytes land")
    func notifiesTheAPI() async throws {
        let api = MockTransport(bodies: [
            authorizationJSON,
            #"{"id":7,"key":"tmp/abc-123"}"#,
        ])
        let storage = StorageTransport()
        let uploader = DirectUploader(client: makeClient(api), storageTransport: storage)

        let stored: StoredFile = try await uploader.upload(
            Data("BYTES".utf8),
            authorizingAt: "/api/uploads/authorize",
            notifyingAt: "/api/uploads/complete",
            fileName: "avatar.jpg",
            notifyFields: ["album": "Holiday"]
        )

        #expect(stored == StoredFile(id: 7, key: "tmp/abc-123"))

        let requests = await api.executedRequests
        #expect(requests.map(\.url?.path) == ["/api/uploads/authorize", "/api/uploads/complete"])
        let notifyBody = try #require(requests[1].httpBody)
        let fields = try #require(
            try JSONSerialization.jsonObject(with: notifyBody) as? [String: Any]
        )
        #expect(fields["key"] as? String == "tmp/abc-123")
        #expect(fields["bucket"] as? String == "app-uploads")
        #expect(fields["uuid"] as? String == "abc-123")
        #expect(fields["album"] as? String == "Holiday")
        #expect(fields["filename"] as? String == "avatar.jpg")
    }

    @Test("A storage rejection is reported with its status")
    func storageFailure() async throws {
        let api = MockTransport(json: authorizationJSON)
        let storage = StorageTransport(
            statusCode: 403,
            body: Data("<Error><Code>AccessDenied</Code></Error>".utf8)
        )
        let uploader = DirectUploader(client: makeClient(api), storageTransport: storage)

        do {
            _ = try await uploader.upload(Data("X".utf8), authorizingAt: "/api/uploads/authorize")
            Issue.record("Expected the upload to throw")
        } catch let error as UploadError {
            guard case let .directUploadFailed(statusCode, body) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(statusCode == 403)
            #expect(body != nil)
        }
    }

    @Test("An unusable authorization stops before anything is sent")
    func invalidAuthorization() async throws {
        let api = MockTransport(json: #"{"message":"Not allowed"}"#)
        let storage = StorageTransport()
        let uploader = DirectUploader(client: makeClient(api), storageTransport: storage)

        await #expect(throws: UploadError.invalidAuthorization) {
            _ = try await uploader.upload(Data("X".utf8), authorizingAt: "/api/uploads/authorize")
        }
        #expect(await storage.executedRequests.isEmpty)
    }

    @Test("A failed authorization never reaches storage")
    func authorizationFailure() async throws {
        let api = MockTransport(statusCode: 403, json: #"{"message":"Forbidden"}"#)
        let storage = StorageTransport()
        let uploader = DirectUploader(client: makeClient(api), storageTransport: storage)

        await #expect(throws: LaravelError.self) {
            _ = try await uploader.upload(Data("X".utf8), authorizingAt: "/api/uploads/authorize")
        }
        #expect(await storage.executedRequests.isEmpty)
    }

    @Test("The client exposes an uploader")
    func clientConvenience() async throws {
        let api = MockTransport(json: authorizationJSON)
        let uploader = makeClient(api).directUploader(storageTransport: StorageTransport())

        let presigned = try await uploader.upload(
            Data("X".utf8),
            authorizingAt: "/api/uploads/authorize"
        )

        #expect(presigned.uuid == "abc-123")
    }
}

/// Adds a fixed header, standing in for the app's authentication.
private struct HeaderStampMiddleware: Middleware {
    let field: String
    let value: String

    func process(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue(value, forHTTPHeaderField: field)
        return request
    }
}

extension Middleware where Self == HeaderStampMiddleware {
    fileprivate static func headerStamp(field: String, value: String) -> HeaderStampMiddleware {
        HeaderStampMiddleware(field: field, value: value)
    }
}
