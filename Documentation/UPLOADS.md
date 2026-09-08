# Uploads

Two paths, matching the two ways Laravel apps accept files: `multipart/form-data`
through the app, and a presigned URL the client uploads to directly.

## Multipart

```swift
let response: AvatarResponse = try await client.upload(
    jpegData,
    to: "/api/avatar",
    fieldName: "avatar",        // the name the controller validates
    fileName: "avatar.jpg",
    mimeType: "image/jpeg",     // inferred from the file name when omitted
    fields: ["caption": "On the beach"]
) { progress in
    Task { @MainActor in fraction = progress.fractionCompleted ?? 0 }
}
```

Several files in one request:

```swift
let files = images.enumerated().map { index, data in
    UploadFile(data: data, fieldName: "photos[]", fileName: "photo-\(index).jpg")
}
let response: GalleryResponse = try await client.upload(files, to: "/api/photos")
```

A body you assembled yourself, when the endpoint expects a shape the convenience
methods do not produce:

```swift
var form = MultipartFormData()
form.append(UploadFile(data: pdf, fieldName: "document", fileName: "contract.pdf"))
form.append(fields: ["signed": "true"])

let receipt: Receipt = try await client.upload(form, to: "/api/documents")
```

Uploads are ordinary requests: middleware runs, the token is attached,
cancellation works, and a failed validation arrives as a
`LaravelValidationError` naming the field.

## Progress

`onProgress` reports how much of the body has been sent:

```swift
onProgress: { progress in
    progress.bytesSent
    progress.totalBytes
    progress.fractionCompleted   // nil when the total is unknown
}
```

The callback runs off the main actor — hop before touching UI state, as above.

## Presigned direct uploads

The mobile app never holds storage credentials. It asks Laravel to authorize an
upload, sends the bytes straight to the signed URL, and tells Laravel the object
key:

```
1. POST /api/uploads/authorize   → { url, method, headers, key, uuid }
2. PUT  <signed url>             ← the bytes, no Authorization header
3. POST /api/uploads/complete    → the record Laravel created
```

```swift
let uploader = client.directUploader()

let record: Attachment = try await uploader.upload(
    videoData,
    authorizingAt: "/api/uploads/authorize",
    notifyingAt: "/api/uploads/complete",
    fileName: "clip.mp4",
    mimeType: "video/mp4"
) { progress in … }
```

Or step by step, when the app needs the key before telling the API:

```swift
let presigned = try await uploader.authorize(
    at: "/api/uploads/authorize",
    fields: ["filename": "clip.mp4", "content_type": "video/mp4"],
    size: videoData.count
)
try await uploader.send(videoData, to: presigned)
```

The bytes go through a separate, unauthenticated transport on purpose: a
presigned URL carries its own signature, and sending the app's `Authorization`
header alongside it makes storage services reject the request. Only the headers
the API returned are sent — they are part of what the signature covers.

`PresignedUpload` reads authorization responses tolerantly: `url`, `upload_url`,
`signed_url`, with or without a `data` envelope, plus `method`, `headers`,
`key`, `bucket`, and `uuid`.

## Errors

| `UploadError` | When |
| --- | --- |
| `.invalidAuthorization` | The authorize call returned no usable URL |
| `.directUploadFailed(statusCode:body:)` | Storage rejected the bytes |

Everything else surfaces as a `LaravelError` or `LaravelValidationError`, exactly
as it does for any other request.
