import Foundation
import Testing

import LaravelMobileKitCore

@Suite("HTTP transport")
struct HTTPTransportTests {
    let baseURL = URL(string: "https://api.example.com")!

    // MARK: - Request construction

    @Test("A GET request resolves the path and decodes the response")
    func getDecodesResponse() async throws {
        let transport = MockTransport(json: #"[{"id":1,"title":"Launch"}]"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let events: [Event] = try await client.get("/api/events")

        #expect(events == [Event(id: 1, title: "Launch")])
        let request = try #require(await transport.lastRequest)
        #expect(request.url?.absoluteString == "https://api.example.com/api/events")
        #expect(request.httpMethod == "GET")
    }

    @Test("Query parameters are appended to the URL")
    func queryParametersAreAppended() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let _: [Event] = try await client.get("/api/events", query: ["page": "2", "per_page": "50"])

        let request = try #require(await transport.lastRequest)
        #expect(request.url?.absoluteString == "https://api.example.com/api/events?page=2&per_page=50")
    }

    @Test("A trailing slash on the base URL does not double up with the path")
    func baseURLTrailingSlashIsNormalized() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(
            baseURL: URL(string: "https://api.example.com/")!,
            transport: transport
        )

        let _: [Event] = try await client.get("api/events")

        let request = try #require(await transport.lastRequest)
        #expect(request.url?.absoluteString == "https://api.example.com/api/events")
    }

    @Test("A path that is already an absolute URL is used unchanged")
    func absolutePathIsUsedAsIs() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let _: [Event] = try await client.get("https://files.example.com/uploads")

        let request = try #require(await transport.lastRequest)
        #expect(request.url?.absoluteString == "https://files.example.com/uploads")
    }

    @Test("Default headers and the configured timeout are applied")
    func defaultHeadersAndTimeoutAreApplied() async throws {
        let transport = MockTransport(json: "[]")
        let configuration = LaravelClientConfiguration(
            baseURL: baseURL,
            defaultHeaders: ["Accept": "application/json", "X-App": "demo"],
            timeoutInterval: 7
        )
        let client = LaravelClient(configuration: configuration, transport: transport)

        let _: [Event] = try await client.get("/api/events")

        let request = try #require(await transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-App") == "demo")
        #expect(request.timeoutInterval == 7)
    }

    @Test("Per-request headers override the client defaults")
    func perRequestHeadersWin() async throws {
        let transport = MockTransport(json: "[]")
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let _: [Event] = try await client.get("/api/events", options: .headers(["Accept": "text/plain"]))

        let request = try #require(await transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/plain")
    }

    @Test("POST encodes the body and sends it", arguments: [HTTPMethod.post, .put, .patch])
    func bodyMethodsEncodeTheirBody(method: HTTPMethod) async throws {
        let transport = MockTransport(statusCode: 201, json: #"{"id":7,"title":"Launch"}"#)
        let client = LaravelClient(baseURL: baseURL, transport: transport)
        let body = CreateEvent(title: "Launch")

        let event: Event
        switch method {
        case .post: event = try await client.post("/api/events", body: body)
        case .put: event = try await client.put("/api/events/7", body: body)
        case .patch: event = try await client.patch("/api/events/7", body: body)
        default: fatalError("unreachable")
        }

        #expect(event == Event(id: 7, title: "Launch"))
        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == method.rawValue)
        let sentBody = try #require(request.httpBody)
        #expect(try JSONDecoder().decode(CreateEvent.self, from: sentBody) == body)
    }

    @Test("DELETE sends no body")
    func deleteSendsNoBody() async throws {
        let transport = MockTransport(statusCode: 204)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let _: EmptyResponse = try await client.delete("/api/events/7")

        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.httpBody == nil)
    }

    // MARK: - Status handling

    @Test("A 2xx response with an empty body decodes as EmptyResponse")
    func emptyBodyDecodesAsEmptyResponse() async throws {
        let transport = MockTransport(statusCode: 204)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        let response: EmptyResponse = try await client.post("/api/logout", body: Optional<CreateEvent>.none)

        #expect(response == EmptyResponse())
    }

    @Test("Client errors throw an HTTPError that keeps the payload", arguments: [400, 401, 403, 404, 422])
    func clientErrorsPreservePayload(statusCode: Int) async throws {
        let payload = #"{"message":"Nope"}"#
        let transport = MockTransport(statusCode: statusCode, json: payload)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        await #expect(throws: LaravelError.self) {
            let _: Event = try await client.get("/api/events/1")
        }

        do {
            let _: Event = try await client.get("/api/events/1")
            Issue.record("Expected the request to throw")
        } catch let LaravelError.httpError(error) {
            #expect(error.statusCode == statusCode)
            #expect(error.isClientError)
            #expect(!error.isServerError)
            #expect(error.data == Data(payload.utf8))
        }
    }

    @Test("Server errors are reported as server errors", arguments: [500, 503])
    func serverErrorsAreFlagged(statusCode: Int) async throws {
        let transport = MockTransport(statusCode: statusCode)
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)

        do {
            let _: Event = try await client.get("/api/events/1")
            Issue.record("Expected the request to throw")
        } catch let LaravelError.httpError(error) {
            #expect(error.statusCode == statusCode)
            #expect(error.isServerError)
            #expect(error.data == nil)
        }
    }

    @Test("A malformed payload throws a decoding error that keeps the raw data")
    func malformedPayloadThrowsDecodingError() async throws {
        let payload = #"{"id":"not-an-int"}"#
        let transport = MockTransport(json: payload)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        do {
            let _: Event = try await client.get("/api/events/1")
            Issue.record("Expected the request to throw")
        } catch let LaravelError.decodingError(_, data) {
            #expect(data == Data(payload.utf8))
        }
    }

    @Test("A transport failure propagates as a network error")
    func transportFailurePropagates() async throws {
        let underlying = URLError(.notConnectedToInternet)
        let transport = MockTransport(result: .failure(LaravelError.networkError(underlying: underlying)))
        let client = LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)

        do {
            let _: Event = try await client.get("/api/events")
            Issue.record("Expected the request to throw")
        } catch let LaravelError.networkError(error) {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }
}
