import Foundation
import Testing

import LaravelMobileKitCore

@Suite("Raw response access")
struct RawResponseTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("A decoded response carries the status code and headers")
    func decodedResponseCarriesMetadata() async throws {
        let transport = MockTransport(
            statusCode: 201,
            body: Data(#"{"id":1,"title":"Launch"}"#.utf8),
            headers: ["Location": "/api/events/1"]
        )
        let client = makeClient(transport)

        let response: Response<Event> = try await client.response(.post, "/api/events")

        #expect(response.value == Event(id: 1, title: "Launch"))
        #expect(response.statusCode == 201)
        #expect(response.headers["Location"] == "/api/events/1")
        #expect(response.rawData == Data(#"{"id":1,"title":"Launch"}"#.utf8))
    }

    @Test("A raw response returns bytes without decoding them")
    func rawResponseSkipsDecoding() async throws {
        let payload = Data("id,title\n1,Launch\n".utf8)
        let transport = MockTransport(statusCode: 200, body: payload)
        let client = makeClient(transport)

        let response = try await client.raw(.get, "/api/events/export")

        #expect(response.value == payload)
        #expect(response.rawData == payload)
        #expect(response.statusCode == 200)
    }

    @Test("A raw request sends the method, query, body, and headers it is given")
    func rawRequestIsSentAsGiven() async throws {
        let transport = MockTransport(json: "{}")
        let client = makeClient(transport)
        let body = Data(#"{"title":"Launch"}"#.utf8)

        _ = try await client.raw(
            .put,
            "/api/events/1",
            query: ["notify": "true"],
            body: body,
            options: .headers(["Content-Type": "application/vnd.api+json"])
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.example.com/api/events/1?notify=true")
        #expect(request.httpBody == body)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
    }

    @Test("Raw access still fails on a non-successful status")
    func rawAccessValidatesStatus() async throws {
        let transport = MockTransport(statusCode: 404, json: #"{"message":"Not Found"}"#)
        let client = makeClient(transport)

        do {
            _ = try await client.raw(.get, "/api/events/9")
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            #expect(error.isNotFound)
            #expect(error.httpError?.bodyText == #"{"message":"Not Found"}"#)
        }
    }
}
