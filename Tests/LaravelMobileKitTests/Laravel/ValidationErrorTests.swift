import Foundation
import Testing

import LaravelMobileKitCore
import LaravelMobileKitLaravel

@Suite("Laravel validation payloads")
struct ValidationPayloadTests {
    let standardPayload = """
    {
      "message": "The given data was invalid.",
      "errors": {
        "email": ["The email has already been taken.", "The email must be valid."],
        "first_name": ["The first name field is required."]
      }
    }
    """

    @Test("A standard Laravel payload parses into field errors")
    func standardPayload_parses() throws {
        let error = try #require(LaravelValidationError(data: Data(standardPayload.utf8)))

        #expect(error.message == "The given data was invalid.")
        #expect(error.statusCode == 422)
        #expect(error.hasErrors)
        #expect(error.fields == ["email", "first_name"])
        #expect(error["email"]?.count == 2)
        #expect(error.firstError(for: "email") == "The email has already been taken.")
        #expect(error.hasError(for: "first_name"))
    }

    @Test("Field names keep the casing the API sent")
    func fieldNamesAreNotRewritten() throws {
        let error = try #require(LaravelValidationError(data: Data(standardPayload.utf8)))

        #expect(error["first_name"] != nil)
        #expect(error["firstName"] == nil)
    }

    @Test("A clean field reports no error")
    func missingFieldHasNoError() throws {
        let error = try #require(LaravelValidationError(data: Data(standardPayload.utf8)))

        #expect(error["password"] == nil)
        #expect(error.firstError(for: "password") == nil)
        #expect(!error.hasError(for: "password"))
    }

    @Test("Convenience views suit form binding")
    func formFriendlyViews() throws {
        let error = try #require(LaravelValidationError(data: Data(standardPayload.utf8)))

        #expect(error.firstErrors == [
            "email": "The email has already been taken.",
            "first_name": "The first name field is required.",
        ])
        #expect(error.allErrors == [
            "The email has already been taken.",
            "The email must be valid.",
            "The first name field is required.",
        ])
        #expect(error.errorDescription == "The given data was invalid.")
    }

    @Test("A single string instead of an array is accepted")
    func singleStringErrorIsAccepted() throws {
        let json = #"{"message":"Invalid","errors":{"email":"Required"}}"#

        let error = try #require(LaravelValidationError(data: Data(json.utf8)))

        #expect(error["email"] == ["Required"])
    }

    @Test("A payload without a message falls back to Laravel's wording")
    func missingMessageFallsBack() throws {
        let json = #"{"errors":{"email":["Required"]}}"#

        let error = try #require(LaravelValidationError(data: Data(json.utf8)))

        #expect(error.message == LaravelValidationError.defaultMessage)
        #expect(error.hasErrors)
    }

    @Test("A payload with only a message parses with no field errors")
    func messageOnlyPayload() throws {
        let json = #"{"message":"Too many attempts."}"#

        let error = try #require(LaravelValidationError(data: Data(json.utf8)))

        #expect(error.message == "Too many attempts.")
        #expect(!error.hasErrors)
        #expect(error.allErrors.isEmpty)
    }

    @Test("Errors under an empty key are global")
    func globalErrors() throws {
        let json = #"{"message":"Invalid","errors":{"":["Something went wrong."],"email":["Required"]}}"#

        let error = try #require(LaravelValidationError(data: Data(json.utf8)))

        #expect(error.globalErrors == ["Something went wrong."])
    }

    @Test("Bodies that are not validation payloads are rejected", arguments: [
        "<html><body>Whoops</body></html>",
        "",
        "not json at all",
        #"{"data":{"id":1}}"#,
        "[1, 2, 3]",
    ])
    func nonValidationBodiesAreRejected(body: String) {
        #expect(LaravelValidationError(data: Data(body.utf8)) == nil)
    }

    @Test("The raw payload and status are preserved")
    func rawPayloadIsPreserved() throws {
        let data = Data(standardPayload.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/api/register")!,
            statusCode: 422,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        let error = try #require(LaravelValidationError(data: data, response: response))

        #expect(error.rawData == data)
        #expect(error.statusCode == 422)
    }
}

@Suite("Validation errors through the client")
struct ValidationIntegrationTests {
    let baseURL = URL(string: "https://api.example.com")!
    let payload = #"{"message":"The given data was invalid.","errors":{"email":["Required"]}}"#

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("A 422 surfaces as a validation error when the middleware is registered")
    func middlewareThrowsValidationError() async throws {
        let transport = MockTransport(statusCode: 422, json: payload)
        let client = makeClient(transport)
        await client.use(.validationErrors)

        do {
            let _: Event = try await client.post("/api/events", body: CreateEvent(title: ""))
            Issue.record("Expected the request to throw")
        } catch let error as LaravelValidationError {
            #expect(error.firstError(for: "email") == "Required")
        }
    }

    @Test("Without the middleware, the validation payload is still reachable")
    func laravelErrorExposesValidation() async throws {
        let transport = MockTransport(statusCode: 422, json: payload)
        let client = makeClient(transport)

        do {
            let _: Event = try await client.post("/api/events", body: CreateEvent(title: ""))
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            let validation = try #require(error.validationError)
            #expect(validation.firstError(for: "email") == "Required")
        }
    }

    @Test("A non-422 failure is left to Core's HTTP handling")
    func otherStatusesAreUntouched() async throws {
        let transport = MockTransport(statusCode: 404, json: #"{"message":"Not Found"}"#)
        let client = makeClient(transport)
        await client.use(.validationErrors)

        do {
            let _: Event = try await client.get("/api/events/9")
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            #expect(error.isNotFound)
            #expect(error.validationError == nil)
        }
    }

    @Test("A 422 whose body is not a validation payload stays an HTTP error")
    func unparseableValidationBodyStaysHTTPError() async throws {
        let transport = MockTransport(statusCode: 422, body: Data("<html>Whoops</html>".utf8))
        let client = makeClient(transport)
        await client.use(.validationErrors)

        do {
            let _: Event = try await client.post("/api/events", body: CreateEvent(title: ""))
            Issue.record("Expected the request to throw")
        } catch let error as LaravelError {
            #expect(error.isValidationError)
            #expect(error.validationError == nil)
        }
    }

    @Test("A successful response is unaffected by the middleware")
    func successIsUnaffected() async throws {
        let transport = MockTransport(statusCode: 201, json: #"{"id":1,"title":"Launch"}"#)
        let client = makeClient(transport)
        await client.use(.validationErrors)

        let event: Event = try await client.post("/api/events", body: CreateEvent(title: "Launch"))

        #expect(event == Event(id: 1, title: "Launch"))
    }
}
