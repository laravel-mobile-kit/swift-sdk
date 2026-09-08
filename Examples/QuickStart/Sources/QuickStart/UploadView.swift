import SwiftUI

import LaravelMobileKit

/// Both upload paths a Laravel API offers, side by side.
///
/// - `multipart/form-data` through the app, with progress.
/// - A presigned direct upload: the app asks Laravel to authorize it, sends the
///   bytes straight to storage, and tells Laravel the object key. The device
///   never holds storage credentials.
@MainActor
final class UploadModel: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isUploading = false
    @Published private(set) var result: String?
    @Published private(set) var failure: String?

    func uploadMultipart(using client: LaravelClient) async {
        await run { [self] in
            let upload: AvatarUpload = try await client.upload(
                Self.samplePNG,
                to: "/api/avatar",
                fieldName: "file",
                fileName: "avatar.png",
                mimeType: "image/png",
                fields: ["caption": "Sent from the quick start"],
                onProgress: { [weak self] progress in
                    guard let fraction = progress.fractionCompleted else { return }
                    Task { @MainActor in self?.progress = fraction }
                }
            )
            return "Stored \(upload.originalName) (\(upload.size) bytes) at \(upload.path)"
        }
    }

    func uploadDirectly(using client: LaravelClient) async {
        await run {
            let uploader = client.directUploader()
            let presigned = try await uploader.upload(
                Self.samplePNG,
                authorizingAt: "/api/uploads/authorize",
                fileName: "avatar.png",
                mimeType: "image/png"
            )
            return "Uploaded straight to storage as \(presigned.key ?? "an unnamed object")"
        }
    }

    private func run(_ work: @escaping () async throws -> String) async {
        isUploading = true
        progress = 0
        result = nil
        failure = nil
        defer { isUploading = false }

        do {
            result = try await work()
        } catch let error as LaravelValidationError {
            failure = error.firstErrors.values.first ?? error.message
        } catch let error as LaravelError {
            failure = error.errorDescription ?? "The upload failed"
        } catch {
            failure = error.localizedDescription
        }
    }

    /// A 1×1 PNG, so the sample needs no file picker or asset catalogue.
    static let samplePNG = Data(
        base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
            """
    )!
}

struct UploadView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = UploadModel()

    var body: some View {
        Form {
            Section("Through the app") {
                Button("Upload as multipart/form-data") {
                    Task { await model.uploadMultipart(using: environment.client) }
                }
                .disabled(model.isUploading)

                if model.isUploading {
                    ProgressView(value: model.progress)
                }
            }

            Section("Straight to storage") {
                Button("Upload with a presigned URL") {
                    Task { await model.uploadDirectly(using: environment.client) }
                }
                .disabled(model.isUploading)
            }

            if let result = model.result {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
            if let failure = model.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Upload")
    }
}
