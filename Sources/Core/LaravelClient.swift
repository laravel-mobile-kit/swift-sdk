import Foundation

/// The root REST client.
///
/// `LaravelClient` is deliberately small: it owns configuration and exposes one
/// generic method per HTTP verb. Higher-level capabilities — authentication,
/// pagination, uploads — live in their own modules and build on this client
/// rather than growing it.
///
/// ```swift
/// let client = LaravelClient(baseURL: URL(string: "https://api.example.com")!)
/// let events: [Event] = try await client.get("/api/events")
/// ```
///
/// The type is an actor so a single client can be shared across tasks while
/// mutable state — middlewares, and later the auth session — stays serialized.
public actor LaravelClient {
    /// Configuration captured when the client was created.
    public let configuration: LaravelClientConfiguration

    /// Transport used to execute requests.
    let transport: any HTTPTransport
    /// Encoder used for `Encodable` request bodies.
    let encoder: JSONEncoder
    /// Decoder used for `Decodable` response bodies.
    let decoder: JSONDecoder
    /// Middlewares applied to every request, in registration order.
    var middlewares: [any Middleware] = []
    /// Deciders consulted when a request fails, in registration order.
    var retryDeciders: [any RetryDecider] = []

    /// Creates a client with default configuration for `baseURL`.
    ///
    /// The encoder and decoder default to Laravel's JSON conventions —
    /// `snake_case` keys and ISO8601 dates — and can be replaced for APIs that
    /// deviate from them.
    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        encoder: JSONEncoder = LaravelJSONEncoder.makeDefault(),
        decoder: JSONDecoder = LaravelJSONDecoder.makeDefault()
    ) {
        self.init(
            configuration: LaravelClientConfiguration(baseURL: baseURL),
            transport: transport,
            encoder: encoder,
            decoder: decoder
        )
    }

    /// Creates a client with an explicit configuration.
    public init(
        configuration: LaravelClientConfiguration,
        transport: any HTTPTransport = URLSessionTransport(),
        encoder: JSONEncoder = LaravelJSONEncoder.makeDefault(),
        decoder: JSONDecoder = LaravelJSONDecoder.makeDefault()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - HTTP verbs

    /// Performs a `GET` request and decodes the response body.
    @discardableResult
    public func get<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) async throws -> T {
        try await executeRequest(makeRequest(.get, path, query: query, options: options))
    }

    /// Performs a `POST` request with an encoded body and decodes the response.
    @discardableResult
    public func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B?,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) async throws -> T {
        try await execute(.post, path, body: body, query: query, options: options)
    }

    /// Performs a `PUT` request with an encoded body and decodes the response.
    @discardableResult
    public func put<T: Decodable, B: Encodable>(
        _ path: String,
        body: B?,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) async throws -> T {
        try await execute(.put, path, body: body, query: query, options: options)
    }

    /// Performs a `PATCH` request with an encoded body and decodes the response.
    @discardableResult
    public func patch<T: Decodable, B: Encodable>(
        _ path: String,
        body: B?,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) async throws -> T {
        try await execute(.patch, path, body: body, query: query, options: options)
    }

    /// Performs a `DELETE` request and decodes the response body.
    @discardableResult
    public func delete<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) async throws -> T {
        try await executeRequest(makeRequest(.delete, path, query: query, options: options))
    }

    // MARK: - Request construction

    /// Builds a request from a path and per-request options.
    func makeRequest(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String]?,
        options: RequestOptions,
        body: Data? = nil
    ) -> Request {
        Request(
            method: method,
            path: path,
            query: query,
            headers: options.headers,
            body: body,
            timeout: options.timeout
        )
    }

    /// Encodes a body, builds the request, and executes it.
    func execute<T: Decodable, B: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: B?,
        query: [String: String]?,
        options: RequestOptions
    ) async throws -> T {
        let encodedBody: Data?
        do {
            encodedBody = try body.map { try encoder.encode($0) }
        } catch {
            throw LaravelError.encodingError(error)
        }
        return try await executeRequest(
            makeRequest(method, path, query: query, options: options, body: encodedBody)
        )
    }
}
