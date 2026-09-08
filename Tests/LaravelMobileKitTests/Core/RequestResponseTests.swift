import Foundation
import Testing

import LaravelMobileKitCore

@Suite("Request and response types")
struct RequestResponseTests {
    @Test("HTTP methods use uppercase wire names")
    func httpMethodRawValues() {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.patch.rawValue == "PATCH")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
        #expect(HTTPMethod.allCases.count == 5)
    }

    @Test("A request keeps its path, query, headers, and body")
    func requestStoresItsParts() {
        let body = Data("{}".utf8)
        let request = Request(
            method: .post,
            path: "/api/events",
            query: ["page": "2"],
            headers: ["X-Trace": "abc"],
            body: body
        )

        #expect(request.method == .post)
        #expect(request.path == "/api/events")
        #expect(request.query == ["page": "2"])
        #expect(request.headers == ["X-Trace": "abc"])
        #expect(request.body == body)
    }

    @Test("A request defaults to no query, no headers, and no body")
    func requestDefaults() {
        let request = Request(method: .get, path: "/api/events")

        #expect(request.query == nil)
        #expect(request.headers.isEmpty)
        #expect(request.body == nil)
    }

    @Test("A response exposes the decoded value alongside status and headers")
    func responseExposesTransportMetadata() throws {
        let url = URL(string: "https://api.example.com/api/events")!
        let httpResponse = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: ["X-Request-Id": "42"]
            )
        )
        let rawData = Data(#"{"id":1}"#.utf8)
        let response = Response(value: 1, httpResponse: httpResponse, rawData: rawData)

        #expect(response.value == 1)
        #expect(response.statusCode == 201)
        #expect(response.headers["X-Request-Id"] == "42")
        #expect(response.rawData == rawData)
    }
}
