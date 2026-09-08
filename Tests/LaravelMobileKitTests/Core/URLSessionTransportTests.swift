import Foundation
import Testing

import LaravelMobileKitCore

@Suite("URLSession transport", .serialized)
struct URLSessionTransportTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func makeTransport() -> URLSessionTransport {
        URLSessionTransport(configuration: MockURLProtocol.makeSessionConfiguration())
    }

    @Test("A successful response is returned with its HTTP metadata")
    func successfulResponse() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"id":1,"title":"Launch"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let (data, response) = try await makeTransport()
            .execute(URLRequest(url: baseURL.appendingPathComponent("api/events/1")))

        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode(Event.self, from: data) == Event(id: 1, title: "Launch"))
    }

    @Test("A network failure is wrapped in a network error")
    func networkFailureIsWrapped() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { MockURLProtocol.handler = nil }

        do {
            _ = try await makeTransport().execute(URLRequest(url: baseURL))
            Issue.record("Expected the request to throw")
        } catch let LaravelError.networkError(underlying) {
            #expect((underlying as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @Test("A client driven by the real transport decodes an end-to-end response")
    func endToEndThroughTheClient() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.example.com/api/events?page=2")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(#"[{"id":1,"title":"Launch"}]"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let client = LaravelClient(baseURL: baseURL, transport: makeTransport())
        let events: [Event] = try await client.get("/api/events", query: ["page": "2"])

        #expect(events == [Event(id: 1, title: "Launch")])
    }

    @Test("A 500 from the network surfaces as an HTTP error")
    func serverErrorSurfacesThroughTheClient() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(#"{"message":"Server Error"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let client = LaravelClient(
            configuration: .withoutRetries(baseURL),
            transport: makeTransport()
        )

        do {
            let _: Event = try await client.get("/api/events/1")
            Issue.record("Expected the request to throw")
        } catch let LaravelError.httpError(error) {
            #expect(error.statusCode == 500)
            #expect(error.isServerError)
        }
    }

    @Test("A request with a body is sent through the upload path when progress is asked for")
    func uploadPathDeliversTheBody() async throws {
        MockURLProtocol.handler = { request in
            // `URLSession.upload(for:from:)` hands the body to the protocol as a
            // stream rather than as `httpBody`.
            #expect(request.httpMethod == "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(#"{"id":1,"title":"Launch"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/events"))
        request.httpMethod = "POST"
        request.httpBody = Data("BYTES".utf8)

        let (data, response) = try await makeTransport().execute(request) { _ in }

        #expect(response.statusCode == 201)
        #expect(try JSONDecoder().decode(Event.self, from: data) == Event(id: 1, title: "Launch"))
    }

    @Test("A transport can be built on a session the app already owns")
    func injectedSessionIsUsed() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(#"{"id":2,"title":"Owned"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let session = URLSession(configuration: MockURLProtocol.makeSessionConfiguration())
        let transport = URLSessionTransport(session: session)

        let (data, response) = try await transport.execute(URLRequest(url: baseURL))

        #expect(response.statusCode == 200)
        #expect(try JSONDecoder().decode(Event.self, from: data) == Event(id: 2, title: "Owned"))
    }

    @Test("A response that carries no HTTP metadata is rejected")
    func nonHTTPResponseIsRejected() async throws {
        MockURLProtocol.rawHandler = { request in
            let response = URLResponse(
                url: request.url!,
                mimeType: "text/plain",
                expectedContentLength: 0,
                textEncodingName: nil
            )
            return (response, Data())
        }
        defer { MockURLProtocol.rawHandler = nil }

        do {
            _ = try await makeTransport().execute(URLRequest(url: baseURL))
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            guard case .invalidResponse = error else {
                Issue.record("Expected an invalid response, got \(error)")
                return
            }
        }
    }

    @Suite("Transport failure classification")
    struct TransportFailureTests {
        let baseURL = URL(string: "https://api.example.com")!

        private func execute(failingWith error: any Error) async throws -> LaravelError? {
            MockURLProtocol.handler = { _ in throw error }
            defer { MockURLProtocol.handler = nil }

            let transport = URLSessionTransport(
                configuration: MockURLProtocol.makeSessionConfiguration()
            )
            do {
                _ = try await transport.execute(URLRequest(url: baseURL))
                return nil
            } catch let error as LaravelError {
                return error
            }
        }

        @Test("A timeout is reported as a timeout")
        func timeoutIsClassified() async throws {
            let error = try await execute(failingWith: URLError(.timedOut))

            guard case .timeout = try #require(error) else {
                Issue.record("Expected a timeout, got \(String(describing: error))")
                return
            }
        }

        @Test("Cancellation is reported as cancellation")
        func cancellationIsClassified() async throws {
            let error = try await execute(failingWith: URLError(.cancelled))

            guard case .cancelled = try #require(error) else {
                Issue.record("Expected cancellation, got \(String(describing: error))")
                return
            }
        }

        @Test("A failure that is not a URLError is still reported as a network error")
        func nonURLErrorsAreWrapped() async throws {
            struct Offline: Error, Equatable {}

            let error = try await execute(failingWith: Offline())

            guard case let .networkError(underlying) = try #require(error) else {
                Issue.record("Expected a network error, got \(String(describing: error))")
                return
            }
            // `URLSession` bridges a non-`URLError` failure into an `NSError`
            // whose domain names the original type; what matters is that the
            // classification did not mistake it for a URL loading failure.
            #expect(!(underlying is URLError))
            #expect((underlying as NSError).domain.contains("Offline"))
        }

        @Test("Any other transport failure keeps the underlying error")
        func otherFailuresAreWrapped() async throws {
            let error = try await execute(failingWith: URLError(.cannotFindHost))

            guard case let .networkError(underlying) = try #require(error) else {
                Issue.record("Expected a network error, got \(String(describing: error))")
                return
            }
            #expect((underlying as? URLError)?.code == .cannotFindHost)
        }
    }
}
