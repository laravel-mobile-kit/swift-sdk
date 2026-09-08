import Foundation
import Testing

import LaravelMobileKitCore

private struct UnencodableBody: Encodable {
    func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(
            self,
            EncodingError.Context(codingPath: [], debugDescription: "nope")
        )
    }
}

private struct DescribedFailure: LocalizedError {
    var errorDescription: String? { "boom" }
}

@Suite("Error handling")
struct ErrorHandlingTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func makeHTTPError(statusCode: Int, body: String = "") -> HTTPError {
        HTTPError(
            statusCode: statusCode,
            data: body.isEmpty ? nil : Data(body.utf8),
            response: HTTPURLResponse(
                url: baseURL,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }

    @Test("Status codes classify into client, server, and named failures")
    func statusClassification() {
        #expect(makeHTTPError(statusCode: 401).isUnauthorized)
        #expect(makeHTTPError(statusCode: 403).isForbidden)
        #expect(makeHTTPError(statusCode: 404).isNotFound)
        #expect(makeHTTPError(statusCode: 422).isValidationError)
        #expect(makeHTTPError(statusCode: 422).isClientError)
        #expect(makeHTTPError(statusCode: 503).isServerError)
        #expect(!makeHTTPError(statusCode: 503).isClientError)
    }

    @Test("A wrapped HTTP failure exposes its status through the error")
    func laravelErrorExposesStatus() {
        let error = LaravelError.httpError(makeHTTPError(statusCode: 401, body: "{}"))

        #expect(error.statusCode == 401)
        #expect(error.isUnauthorized)
        #expect(!error.isNotFound)
        #expect(error.httpError?.bodyText == "{}")
    }

    @Test("Non-HTTP errors report no status")
    func nonHTTPErrorsHaveNoStatus() {
        #expect(LaravelError.timeout.statusCode == nil)
        #expect(!LaravelError.cancelled.isUnauthorized)
        #expect(LaravelError.invalidResponse.httpError == nil)
    }

    @Test("Every case has a human-readable description")
    func errorDescriptions() {
        #expect(LaravelError.invalidURL("//bad").errorDescription == "Invalid URL: //bad")
        #expect(LaravelError.timeout.errorDescription == "The request timed out")
        #expect(LaravelError.cancelled.errorDescription == "The request was cancelled")
        #expect(
            LaravelError.httpError(makeHTTPError(statusCode: 500)).errorDescription
                == "HTTP 500 for https://api.example.com"
        )
        #expect(LaravelError.networkError(underlying: URLError(.notConnectedToInternet))
            .errorDescription?.hasPrefix("Network error:") == true)
    }

    @Test("Coding and metadata failures describe themselves")
    func codingFailureDescriptions() {
        #expect(
            LaravelError.invalidResponse.errorDescription
                == "The server returned a response that was not an HTTP response"
        )
        #expect(
            LaravelError.decodingError(DescribedFailure(), data: Data("{}".utf8)).errorDescription
                == "Failed to decode the response: boom"
        )
        #expect(
            LaravelError.encodingError(DescribedFailure()).errorDescription
                == "Failed to encode the request body: boom"
        )
    }

    @Test("Predicates answer false for the cases they do not describe")
    func predicatesRejectUnrelatedCases() {
        #expect(LaravelError.httpError(makeHTTPError(statusCode: 503)).isServerError)
        #expect(!LaravelError.invalidResponse.isServerError)
        #expect(LaravelError.timeout.isTimeout)
        #expect(!LaravelError.cancelled.isTimeout)
        #expect(LaravelError.cancelled.isCancelled)
        #expect(!LaravelError.timeout.isCancelled)
    }

    @Test("A 422 keeps its payload for the Laravel layer to parse")
    func validationPayloadIsPreserved() async throws {
        let payload = #"{"message":"The given data was invalid.","errors":{"email":["Required"]}}"#
        let transport = MockTransport(statusCode: 422, json: payload)
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        do {
            let _: Event = try await client.post("/api/events", body: CreateEvent(title: ""))
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            #expect(error.isValidationError)
            #expect(error.httpError?.data == Data(payload.utf8))
        }
    }

    @Test("An unencodable body fails before the request is sent")
    func encodingFailureIsReported() async throws {
        let transport = MockTransport(json: "{}")
        let client = LaravelClient(baseURL: baseURL, transport: transport)

        do {
            let _: Event = try await client.post("/api/events", body: UnencodableBody())
            Issue.record("Expected the request to throw")
        } catch let LaravelError.encodingError(underlying) {
            #expect(underlying is EncodingError)
        }
        #expect(await transport.executedRequests.isEmpty)
    }
}
