/// Stand-in for responses without a body, such as `204 No Content`.
///
/// ```swift
/// let _: EmptyResponse = try await client.delete("/api/events/1")
/// ```
public struct EmptyResponse: Decodable, Sendable, Hashable {
    public init() {}

    public init(from decoder: any Decoder) throws {
        self.init()
    }
}
