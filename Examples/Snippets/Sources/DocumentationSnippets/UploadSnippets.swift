import Foundation

import LaravelMobileKit

/// Examples from `Documentation/UPLOADS.md`.
enum UploadSnippets {
    static func multipart(client: LaravelClient, jpegData: Data) async throws {
        let response: AvatarResponse = try await client.upload(
            jpegData,
            to: "/api/avatar",
            fieldName: "avatar",
            fileName: "avatar.jpg",
            mimeType: "image/jpeg",
            fields: ["caption": "On the beach"]
        ) { progress in
            _ = progress.fractionCompleted ?? 0
        }
        _ = response
    }

    static func severalFiles(client: LaravelClient, images: [Data]) async throws {
        let files = images.enumerated().map { index, data in
            UploadFile(data: data, fieldName: "photos[]", fileName: "photo-\(index).jpg")
        }
        let response: GalleryResponse = try await client.upload(files, to: "/api/photos")
        _ = response
    }

    static func handBuiltForm(client: LaravelClient, pdf: Data) async throws {
        var form = MultipartFormData()
        form.append(UploadFile(data: pdf, fieldName: "document", fileName: "contract.pdf"))
        form.append(fields: ["signed": "true"])

        let receipt: Receipt = try await client.upload(form, to: "/api/documents")
        _ = receipt
    }

    static func progressFields(_ progress: UploadProgress) {
        _ = progress.bytesSent
        _ = progress.totalBytes
        _ = progress.fractionCompleted
    }

    static func directUpload(client: LaravelClient, videoData: Data) async throws {
        let uploader = client.directUploader()

        let record: Attachment = try await uploader.upload(
            videoData,
            authorizingAt: "/api/uploads/authorize",
            notifyingAt: "/api/uploads/complete",
            fileName: "clip.mp4",
            mimeType: "video/mp4"
        ) { progress in
            _ = progress.fractionCompleted
        }
        _ = record
    }

    static func directUploadStepByStep(client: LaravelClient, videoData: Data) async throws {
        let uploader = client.directUploader()

        let presigned = try await uploader.authorize(
            at: "/api/uploads/authorize",
            fields: ["filename": "clip.mp4", "content_type": "video/mp4"],
            size: videoData.count
        )
        try await uploader.send(videoData, to: presigned)
    }
}
