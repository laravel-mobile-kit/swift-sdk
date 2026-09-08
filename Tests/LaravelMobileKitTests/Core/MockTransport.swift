import Foundation

import LaravelMobileKitCore

/// Records the requests it receives and replays a canned result.
actor MockTransport: HTTPTransport {
    private(set) var executedRequests: [URLRequest] = []
    private var result: Result<(Data, HTTPURLResponse), any Error>
    /// Results answered before falling back to `result`, oldest first.
    private var queuedResults: [Result<(Data, HTTPURLResponse), any Error>] = []
    /// How long `execute` stalls before answering, used to exercise timeouts.
    var delayNanoseconds: UInt64 = 0

    init(result: Result<(Data, HTTPURLResponse), any Error>) {
        self.result = result
    }

    init(statusCode: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        self.result = .success((body, response))
    }

    init(statusCode: Int = 200, json: String) {
        self.init(statusCode: statusCode, body: Data(json.utf8))
    }

    /// Answers with each body in turn, repeating the last one afterwards.
    init(bodies: [String], statusCode: Int = 200) {
        precondition(!bodies.isEmpty)
        let responses = bodies.map { body in
            Result<(Data, HTTPURLResponse), any Error>.success(
                (
                    Data(body.utf8),
                    HTTPURLResponse(
                        url: URL(string: "https://api.example.com")!,
                        statusCode: statusCode,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )!
                )
            )
        }
        self.result = responses[responses.count - 1]
        self.queuedResults = Array(responses.dropLast())
    }

    /// Answers with each status code in turn, repeating the last one afterwards.
    init(statusCodes: [Int], json: String = "{}") {
        precondition(!statusCodes.isEmpty)
        let responses = statusCodes.map { statusCode in
            Result<(Data, HTTPURLResponse), any Error>.success(
                (
                    Data(json.utf8),
                    HTTPURLResponse(
                        url: URL(string: "https://api.example.com")!,
                        statusCode: statusCode,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )!
                )
            )
        }
        self.result = responses[responses.count - 1]
        self.queuedResults = Array(responses.dropLast())
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        executedRequests.append(request)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if !queuedResults.isEmpty {
            return try queuedResults.removeFirst().get()
        }
        return try result.get()
    }

    /// Makes `execute` stall for `seconds` before answering.
    func stall(seconds: Double) {
        delayNanoseconds = UInt64(seconds * 1_000_000_000)
    }

    var lastRequest: URLRequest? { executedRequests.last }

    var attemptCount: Int { executedRequests.count }

    /// Fails every attempt with `error`.
    static func alwaysFailing(with error: any Error) -> MockTransport {
        MockTransport(result: .failure(error))
    }
}

struct Event: Codable, Hashable, Sendable {
    let id: Int
    let title: String
}

struct CreateEvent: Codable, Hashable, Sendable {
    let title: String
}

extension LaravelClientConfiguration {
    /// A configuration with retries disabled, so a test observes exactly one attempt.
    static func withoutRetries(_ baseURL: URL, timeoutInterval: TimeInterval = 30) -> Self {
        LaravelClientConfiguration(
            baseURL: baseURL,
            timeoutInterval: timeoutInterval,
            retryPolicy: .none
        )
    }
}
