import Foundation
import Testing

import LaravelMobileKitCore

private struct Author: Codable, Hashable, Sendable {
    let displayName: String
}

private struct Article: Codable, Hashable, Sendable {
    let id: Int
    let publishedTitle: String
    let createdAt: Date
    let deletedAt: Date?
    let author: Author
    let tagNames: [String]
}

/// Wraps an ``EmptyResponse`` so it is decoded through its own initialiser
/// rather than through the client's empty-body shortcut.
private struct Envelope: Decodable, Hashable {
    let data: EmptyResponse
}

@Suite("Laravel JSON coding")
struct SerializationTests {
    let decoder = LaravelJSONDecoder.makeDefault()
    let encoder = LaravelJSONEncoder.makeDefault()

    @Test("snake_case keys decode into camelCase properties, including nested values")
    func snakeCaseDecoding() throws {
        let json = """
        {
          "id": 1,
          "published_title": "Launch",
          "created_at": "2024-01-15T10:30:00.000000Z",
          "deleted_at": null,
          "author": { "display_name": "Ada" },
          "tag_names": ["swift", "laravel"]
        }
        """

        let article = try decoder.decode(Article.self, from: Data(json.utf8))

        #expect(article.id == 1)
        #expect(article.publishedTitle == "Launch")
        #expect(article.deletedAt == nil)
        #expect(article.author == Author(displayName: "Ada"))
        #expect(article.tagNames == ["swift", "laravel"])
        #expect(article.createdAt == Date(timeIntervalSince1970: 1_705_314_600))
    }

    @Test(
        "Supported date formats all decode to the same instant",
        arguments: [
            "2024-01-15T10:30:00.000000Z",
            "2024-01-15T10:30:00.000Z",
            "2024-01-15T10:30:00Z",
            "2024-01-15T12:30:00+02:00",
            "2024-01-15 10:30:00",
        ]
    )
    func supportedDateFormats(string: String) throws {
        let date = try #require(LaravelDateFormat.date(from: string))

        #expect(date == Date(timeIntervalSince1970: 1_705_314_600))
    }

    @Test("A date-only value decodes at midnight UTC")
    func dateOnlyFormat() throws {
        let date = try #require(LaravelDateFormat.date(from: "2024-01-15"))

        #expect(date == Date(timeIntervalSince1970: 1_705_276_800))
    }

    @Test("An unsupported date string fails with a decoding error")
    func unsupportedDateFormatThrows() {
        #expect(LaravelDateFormat.date(from: "15/01/2024") == nil)

        let json = Data(#"{"created_at":"15/01/2024"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try decoder.decode([String: Date].self, from: json)
        }
    }

    @Test("camelCase properties encode as snake_case with ISO8601 dates")
    func snakeCaseEncoding() throws {
        let article = Article(
            id: 1,
            publishedTitle: "Launch",
            createdAt: Date(timeIntervalSince1970: 1_705_314_600),
            deletedAt: nil,
            author: Author(displayName: "Ada"),
            tagNames: ["swift"]
        )

        let data = try encoder.encode(article)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["published_title"] as? String == "Launch")
        #expect(object["created_at"] as? String == "2024-01-15T10:30:00.000Z")
        #expect((object["author"] as? [String: Any])?["display_name"] as? String == "Ada")
        #expect(object["tag_names"] as? [String] == ["swift"])
        #expect(object["deleted_at"] == nil)
    }

    @Test("Encoding then decoding round-trips a model")
    func roundTrip() throws {
        let article = Article(
            id: 3,
            publishedTitle: "Launch",
            createdAt: Date(timeIntervalSince1970: 1_705_314_600),
            deletedAt: Date(timeIntervalSince1970: 1_705_318_200),
            author: Author(displayName: "Ada"),
            tagNames: []
        )

        let decoded = try decoder.decode(Article.self, from: try encoder.encode(article))

        #expect(decoded == article)
    }
}

@Suite("Client serialization")
struct ClientSerializationTests {
    let baseURL = URL(string: "https://api.example.com")!

    @Test("The client decodes snake_case payloads by default")
    func clientUsesLaravelDecoder() async throws {
        let transport = MockTransport(json: #"{"display_name":"Ada"}"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let author: Author = try await client.get("/api/user")

        #expect(author == Author(displayName: "Ada"))
    }

    @Test("The client encodes request bodies as snake_case by default")
    func clientUsesLaravelEncoder() async throws {
        let transport = MockTransport(json: #"{"display_name":"Ada"}"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let _: Author = try await client.post("/api/users", body: Author(displayName: "Ada"))

        let body = try #require(await transport.lastRequest?.httpBody)
        #expect(String(decoding: body, as: UTF8.self).contains("display_name"))
    }

    @Test("A custom decoder replaces the Laravel conventions")
    func customDecoderIsUsed() async throws {
        let transport = MockTransport(json: #"{"displayName":"Ada"}"#)
        let client = LaravelClient(
            baseURL: baseURL,
            transport: transport,
            decoder: JSONDecoder()
        )

        let author: Author = try await client.get("/api/user")

        #expect(author == Author(displayName: "Ada"))
    }

    @Test("EmptyResponse decodes from a payload without reading it")
    func emptyResponseIgnoresItsPayload() async throws {
        let transport = MockTransport(json: #"{"data":{"id":1,"unexpected":true}}"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let envelope: Envelope = try await client.get("/api/ping")

        #expect(envelope.data == EmptyResponse())
    }
}
