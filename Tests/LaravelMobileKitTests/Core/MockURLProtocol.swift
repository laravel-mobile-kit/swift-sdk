import Foundation

/// Intercepts `URLSession` traffic so transport tests never touch the network.
final class MockURLProtocol: URLProtocol {
    /// Produces a response for an intercepted request, or throws to simulate a
    /// transport failure.
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    /// Produces a response that is not necessarily an `HTTPURLResponse`, so the
    /// transport's own metadata checks can be exercised.
    typealias RawHandler = @Sendable (URLRequest) throws -> (URLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _rawHandler: RawHandler?

    static var handler: Handler? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    /// Takes precedence over ``handler`` while it is set.
    static var rawHandler: RawHandler? {
        get { lock.withLock { _rawHandler } }
        set { lock.withLock { _rawHandler = newValue } }
    }

    /// A session configuration whose requests are served by `handler`.
    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let rawHandler = MockURLProtocol.rawHandler {
            respond(using: { try rawHandler($0) })
            return
        }
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        respond(using: { try handler($0) })
    }

    private func respond(using handler: (URLRequest) throws -> (URLResponse, Data)) {
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
