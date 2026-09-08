import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    @MainActor
    @Suite("Uploads")
    struct UploadIntegrationTests {
        @Test("A multipart upload reaches Laravel's file validation intact")
        func multipartUpload() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            let upload: AvatarUpload = try await stack.client.upload(
                IntegrationHarness.pixelPNG,
                to: "/api/avatar",
                fieldName: "file",
                fileName: "pixel.png",
                mimeType: "image/png",
                fields: ["caption": "From the integration suite"]
            )

            #expect(upload.size == IntegrationHarness.pixelPNG.count)
            #expect(upload.originalName == "pixel.png")
            #expect(upload.mime == "image/png")
            #expect(upload.caption == "From the integration suite")
            #expect(upload.fields["caption"] == "From the integration suite")
        }

        @Test("Upload progress is reported and finishes complete")
        func multipartUploadReportsProgress() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            let progress = ProgressRecorder()
            let _: AvatarUpload = try await stack.client.upload(
                IntegrationHarness.pixelPNG,
                to: "/api/avatar",
                fileName: "pixel.png",
                mimeType: "image/png",
                onProgress: { progress.record($0) }
            )

            #expect(progress.updates.last?.fractionCompleted == 1)
        }

        @Test("A file the API refuses surfaces as a validation error")
        func rejectedUploadIsAValidationError() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()

            do {
                let _: AvatarUpload = try await stack.client.upload(
                    IntegrationHarness.pixelPNG,
                    to: "/api/avatar",
                    fieldName: "not_the_field",
                    fileName: "pixel.png",
                    mimeType: "image/png"
                )
                Issue.record("Expected the upload to fail validation")
            } catch let error as LaravelValidationError {
                #expect(error.hasError(for: "file"))
            }
        }

        @Test("A presigned upload goes straight to storage and is then recorded")
        func presignedDirectUpload() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            let uploader = stack.client.directUploader()

            let receipt: DirectUploadReceipt = try await uploader.upload(
                IntegrationHarness.pixelPNG,
                authorizingAt: "/api/uploads/authorize",
                notifyingAt: "/api/uploads/complete",
                fileName: "pixel.png",
                mimeType: "image/png"
            )

            #expect(receipt.filename == "pixel.png")
            #expect(receipt.size == IntegrationHarness.pixelPNG.count)
            #expect(receipt.key.hasSuffix("pixel.png"))
        }

        @Test("The bytes are sent without the app's Authorization header")
        func presignedUploadIsUnauthenticated() async throws {
            let stack = await IntegrationHarness.makeAuthStack()
            try await stack.login()
            let uploader = stack.client.directUploader()

            let presigned = try await uploader.authorize(
                at: "/api/uploads/authorize",
                fields: ["filename": "pixel.png", "content_type": "image/png"],
                size: IntegrationHarness.pixelPNG.count
            )
            try await uploader.send(IntegrationHarness.pixelPNG, to: presigned)

            // The storage stand-in reports what it received; a bearer token there
            // would mean the client leaked its credential to object storage.
            let storage = LaravelClient(baseURL: IntegrationEnvironment.url)
            let response = try await storage.raw(
                .put,
                presigned.url.absoluteString,
                body: IntegrationHarness.pixelPNG,
                options: RequestOptions(headers: presigned.headers)
            )
            let payload = try JSONSerialization.jsonObject(with: response.rawData) as? [String: Any]
            #expect(payload?["authorization"] as? String == nil)
        }
    }
}

/// Collects progress updates from the upload callback.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UploadProgress] = []

    var updates: [UploadProgress] { lock.withLock { storage } }

    func record(_ progress: UploadProgress) {
        lock.withLock { storage.append(progress) }
    }
}
