import Foundation
import Testing

import LaravelMobileKitCore

@Suite("Client configuration")
struct ConfigurationTests {
    let baseURL = URL(string: "https://api.example.com")!

    @Test("Defaults cover JSON headers, a 30s timeout, and the default retry policy")
    func defaults() {
        let configuration = LaravelClientConfiguration(baseURL: baseURL)

        #expect(configuration.baseURL == baseURL)
        #expect(configuration.defaultHeaders["Accept"] == "application/json")
        #expect(configuration.defaultHeaders["Content-Type"] == "application/json")
        #expect(configuration.timeoutInterval == 30)
        #expect(configuration.retryPolicy == .default)
    }

    @Test("Explicit values override every default")
    func explicitValues() {
        let configuration = LaravelClientConfiguration(
            baseURL: baseURL,
            defaultHeaders: ["X-App": "demo"],
            timeoutInterval: 5,
            retryPolicy: .none
        )

        #expect(configuration.defaultHeaders == ["X-App": "demo"])
        #expect(configuration.timeoutInterval == 5)
        #expect(configuration.retryPolicy.maxRetries == 0)
    }

    @Test("A client created from a base URL stores the derived configuration")
    func clientStoresConfiguration() async {
        let client = LaravelClient(baseURL: baseURL)
        let configuration = await client.configuration

        #expect(configuration.baseURL == baseURL)
        #expect(configuration.defaultHeaders == LaravelClientConfiguration.defaultJSONHeaders)
        #expect(configuration.timeoutInterval == 30)
    }

    @Test("A client created from a configuration stores it unchanged")
    func clientStoresExplicitConfiguration() async {
        let expected = LaravelClientConfiguration(
            baseURL: baseURL,
            defaultHeaders: [:],
            timeoutInterval: 12,
            retryPolicy: .none
        )
        let client = LaravelClient(configuration: expected)
        let configuration = await client.configuration

        #expect(configuration.baseURL == expected.baseURL)
        #expect(configuration.defaultHeaders.isEmpty)
        #expect(configuration.timeoutInterval == 12)
        #expect(configuration.retryPolicy == .none)
    }
}

@Suite("Retry policy")
struct RetryPolicyTests {
    @Test("The default policy retries transient failures three times")
    func defaultPolicy() {
        #expect(RetryPolicy.default.maxRetries == 3)
        #expect(RetryPolicy.default.retryableStatusCodes == RetryPolicy.defaultRetryableStatusCodes)
        #expect(RetryPolicy.default.retryableStatusCodes.contains(429))
        #expect(RetryPolicy.default.retryableStatusCodes.contains(503))
        #expect(!RetryPolicy.default.retryableStatusCodes.contains(404))
    }

    @Test("The default policy retries idempotent methods only")
    func defaultPolicyMethods() {
        #expect(RetryPolicy.default.retryableMethods == [.get, .put, .delete])
        #expect(!RetryPolicy.default.retryableMethods.contains(.post))
        #expect(!RetryPolicy.default.retryableMethods.contains(.patch))
    }

    @Test("The none policy never retries")
    func nonePolicy() {
        #expect(RetryPolicy.none.maxRetries == 0)
        #expect(RetryPolicy.none.retryableStatusCodes.isEmpty)
        #expect(RetryPolicy.none.retryableMethods.isEmpty)
    }

    @Test("A negative retry count is clamped to zero")
    func negativeRetryCountIsClamped() {
        #expect(RetryPolicy(maxRetries: -3).maxRetries == 0)
    }
}
