import Foundation

import LaravelMobileKitCore

extension LaravelClient {
    /// Fetches one page of a paginated endpoint.
    ///
    /// ```swift
    /// let page: Page<Event> = try await client.page("/api/events", query: ["per_page": "50"])
    /// ```
    public func page<Item: Decodable & Sendable>(
        _ path: String,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) async throws -> Page<Item> {
        try await get(path, query: query, options: options)
    }

    /// Fetches the page after `page`, or `nil` when it is the last one.
    ///
    /// The paginator's own `next_page_url` is followed when the response
    /// carries one; cursor pagination falls back to the paginator's path plus
    /// the next cursor.
    public func nextPage<Item: Decodable & Sendable>(
        after page: Page<Item>,
        options: RequestOptions = .none
    ) async throws -> Page<Item>? {
        guard let step = page.nextStep else { return nil }
        return try await self.page(step.path, query: step.query, options: options)
    }

    /// Fetches the page before `page`, or `nil` when it is the first one.
    public func previousPage<Item: Decodable & Sendable>(
        before page: Page<Item>,
        options: RequestOptions = .none
    ) async throws -> Page<Item>? {
        guard let step = page.previousStep else { return nil }
        return try await self.page(step.path, query: step.query, options: options)
    }

    /// Walks a paginated endpoint page by page.
    ///
    /// ```swift
    /// for try await page in client.pages(of: Event.self, at: "/api/events") {
    ///     render(page.items)
    /// }
    /// ```
    ///
    /// Pages are fetched lazily, so stopping early stops the requests.
    public nonisolated func pages<Item: Decodable & Sendable>(
        of type: Item.Type,
        at path: String,
        query: [String: String]? = nil,
        options: RequestOptions = .none
    ) -> PageSequence<Item> {
        PageSequence(client: self, path: path, query: query, options: options)
    }
}

extension Page {
    /// Where to ask for the next page.
    var nextStep: PageStep? {
        if let nextPageURL { return PageStep(path: nextPageURL, query: nil) }
        guard let nextCursor, let path else { return nil }
        return PageStep(path: path, query: ["cursor": nextCursor])
    }

    /// Where to ask for the previous page.
    var previousStep: PageStep? {
        if let previousPageURL { return PageStep(path: previousPageURL, query: nil) }
        guard let previousCursor, let path else { return nil }
        return PageStep(path: path, query: ["cursor": previousCursor])
    }
}

/// A request that fetches one adjacent page.
struct PageStep: Sendable, Hashable {
    let path: String
    let query: [String: String]?
}

/// An asynchronous sequence over the pages of one endpoint.
public struct PageSequence<Item: Decodable & Sendable>: AsyncSequence, Sendable {
    public typealias Element = Page<Item>

    let client: LaravelClient
    let path: String
    let query: [String: String]?
    let options: RequestOptions

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(client: client, step: PageStep(path: path, query: query), options: options)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let client: LaravelClient
        private var step: PageStep?
        private let options: RequestOptions

        init(client: LaravelClient, step: PageStep?, options: RequestOptions) {
            self.client = client
            self.step = step
            self.options = options
        }

        public mutating func next() async throws -> Page<Item>? {
            guard let step else { return nil }

            let page: Page<Item> = try await client.page(
                step.path,
                query: step.query,
                options: options
            )
            // The paginator's own links carry the query from here on.
            self.step = page.nextStep
            return page
        }
    }
}
