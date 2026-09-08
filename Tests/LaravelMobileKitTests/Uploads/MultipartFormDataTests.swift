import Foundation
import Testing

import LaravelMobileKitUploads

@Suite("Multipart bodies")
struct MultipartFormDataTests {
    private func encoded(_ form: MultipartFormData) -> String {
        String(decoding: form.encode(), as: UTF8.self)
    }

    @Test("A file and a field encode into the documented wire format")
    func encodesFileAndField() {
        var form = MultipartFormData(boundary: "TEST")
        form.append(
            UploadFile(data: Data("BYTES".utf8), fieldName: "avatar", fileName: "avatar.jpg")
        )
        form.append(value: "Holiday", name: "caption")

        #expect(encoded(form) == """
        --TEST\r
        Content-Disposition: form-data; name="avatar"; filename="avatar.jpg"\r
        Content-Type: image/jpeg\r
        \r
        BYTES\r
        --TEST\r
        Content-Disposition: form-data; name="caption"\r
        \r
        Holiday\r
        --TEST--\r\n
        """)
    }

    @Test("The content type carries the boundary")
    func contentTypeCarriesBoundary() {
        let form = MultipartFormData(boundary: "TEST")

        #expect(form.contentType == "multipart/form-data; boundary=TEST")
        #expect(form.isEmpty)
    }

    @Test("Generated boundaries differ between bodies")
    func generatedBoundariesAreUnique() {
        #expect(MultipartFormData().boundary != MultipartFormData().boundary)
    }

    @Test("Several files travel in one body")
    func multipleFiles() {
        var form = MultipartFormData(boundary: "TEST")
        form.append(UploadFile(data: Data("A".utf8), fieldName: "files[]", fileName: "a.txt"))
        form.append(UploadFile(data: Data("B".utf8), fieldName: "files[]", fileName: "b.txt"))

        let body = encoded(form)

        #expect(body.components(separatedBy: "--TEST\r\n").count == 3)
        #expect(body.contains(#"filename="a.txt""#))
        #expect(body.contains(#"filename="b.txt""#))
        #expect(body.hasSuffix("--TEST--\r\n"))
    }

    @Test("Text fields are written in a stable order")
    func fieldsAreOrdered() {
        var form = MultipartFormData(boundary: "TEST")
        form.append(fields: ["zulu": "1", "alpha": "2"])

        let body = encoded(form)
        let alphaIndex = try! #require(body.range(of: "alpha")).lowerBound
        let zuluIndex = try! #require(body.range(of: "zulu")).lowerBound

        #expect(alphaIndex < zuluIndex)
    }

    @Test("A quote in a name cannot break out of the header")
    func namesAreEscaped() {
        var form = MultipartFormData(boundary: "TEST")
        form.append(data: Data("X".utf8), name: #"we"ird"#, fileName: "a\"b.txt")

        let body = encoded(form)

        #expect(body.contains(#"name="we\"ird""#))
        #expect(body.contains(#"filename="a\"b.txt""#))
    }

    @Test("A part with no file name carries no content type")
    func plainFieldHasNoContentType() {
        var form = MultipartFormData(boundary: "TEST")
        form.append(data: Data("X".utf8), name: "note")

        #expect(!encoded(form).contains("Content-Type:"))
    }

    @Test("Content types are inferred from the file extension", arguments: [
        ("avatar.jpg", "image/jpeg"),
        ("report.pdf", "application/pdf"),
        ("notes.txt", "text/plain"),
        ("archive.unknownext", "application/octet-stream"),
        ("noextension", "application/octet-stream"),
    ])
    func mimeInference(fileName: String, expected: String) {
        #expect(MIMEType.inferred(fromFileName: fileName) == expected)
        #expect(UploadFile(data: Data(), fileName: fileName).mimeType == expected)
    }

    @Test("An explicit content type wins over inference")
    func explicitMimeTypeWins() {
        let file = UploadFile(data: Data(), fileName: "avatar.jpg", mimeType: "image/heic")

        #expect(file.mimeType == "image/heic")
    }

    @Test("A file is read from disk with its own name")
    func fileFromDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).txt")
        try Data("ON DISK".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try UploadFile(contentsOf: url, fieldName: "document")

        #expect(file.data == Data("ON DISK".utf8))
        #expect(file.fieldName == "document")
        #expect(file.fileName == url.lastPathComponent)
        #expect(file.mimeType == "text/plain")
    }
}
