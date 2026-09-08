import Foundation
import Testing

import LaravelMobileKitCore
import LaravelMobileKitLaravel

/// The three paginators, in both envelopes Laravel produces.
enum PaginationFixtures {
    /// `paginate()` returned straight from a controller.
    static let lengthAware = """
    {
      "current_page": 2,
      "data": [{"id": 3, "title": "Third"}],
      "first_page_url": "https://api.example.com/api/events?page=1",
      "from": 3,
      "last_page": 3,
      "last_page_url": "https://api.example.com/api/events?page=3",
      "links": [
        {"url": "https://api.example.com/api/events?page=1", "label": "1", "active": false},
        {"url": null, "label": "Next", "active": false}
      ],
      "next_page_url": "https://api.example.com/api/events?page=3",
      "path": "https://api.example.com/api/events",
      "per_page": 1,
      "prev_page_url": "https://api.example.com/api/events?page=1",
      "to": 3,
      "total": 3
    }
    """

    /// `paginate()` wrapped by an API resource collection.
    static let resourceWrapped = """
    {
      "data": [{"id": 1, "title": "First"}],
      "links": {
        "first": "https://api.example.com/api/events?page=1",
        "last": "https://api.example.com/api/events?page=3",
        "prev": null,
        "next": "https://api.example.com/api/events?page=2"
      },
      "meta": {
        "current_page": 1,
        "from": 1,
        "last_page": 3,
        "path": "https://api.example.com/api/events",
        "per_page": 1,
        "to": 1,
        "total": 3
      }
    }
    """

    /// `simplePaginate()` — no total, no last page.
    static let simple = """
    {
      "current_page": 1,
      "data": [{"id": 1, "title": "First"}],
      "first_page_url": "https://api.example.com/api/events?page=1",
      "from": 1,
      "next_page_url": "https://api.example.com/api/events?page=2",
      "path": "https://api.example.com/api/events",
      "per_page": 1,
      "prev_page_url": null,
      "to": 1
    }
    """

    /// `cursorPaginate()`.
    static let cursor = """
    {
      "data": [{"id": 1, "title": "First"}],
      "path": "https://api.example.com/api/events",
      "per_page": 1,
      "next_cursor": "eyJpZCI6MX0",
      "next_page_url": "https://api.example.com/api/events?cursor=eyJpZCI6MX0",
      "prev_cursor": null,
      "prev_page_url": null
    }
    """

    /// `cursorPaginate()` through a resource collection, which drops the URLs.
    static let cursorInMeta = """
    {
      "data": [{"id": 1, "title": "First"}],
      "meta": {
        "path": "https://api.example.com/api/events",
        "per_page": 1,
        "next_cursor": "eyJpZCI6MX0",
        "prev_cursor": null
      }
    }
    """

    /// The last page of a length-aware paginator.
    static let lastPage = """
    {
      "current_page": 3,
      "data": [],
      "last_page": 3,
      "next_page_url": null,
      "path": "https://api.example.com/api/events",
      "per_page": 1,
      "prev_page_url": "https://api.example.com/api/events?page=2",
      "to": null,
      "total": 3
    }
    """
}

@Suite("Pagination formats")
struct PaginationFormatTests {
    private func decode(_ json: String) throws -> Page<Event> {
        try LaravelJSONDecoder.makeDefault().decode(Page<Event>.self, from: Data(json.utf8))
    }

    @Test("A length-aware paginator exposes counts and neighbours")
    func lengthAwarePaginator() throws {
        let page = try decode(PaginationFixtures.lengthAware)

        #expect(page.items == [Event(id: 3, title: "Third")])
        #expect(page.kind == .length)
        #expect(page.currentPage == 2)
        #expect(page.lastPage == 3)
        #expect(page.total == 3)
        #expect(page.perPage == 1)
        #expect(page.from == 3)
        #expect(page.hasNextPage)
        #expect(page.hasPreviousPage)
        #expect(page.nextPageURL == "https://api.example.com/api/events?page=3")
    }

    @Test("A resource collection puts the same values under meta and links")
    func resourceWrappedPaginator() throws {
        let page = try decode(PaginationFixtures.resourceWrapped)

        #expect(page.items == [Event(id: 1, title: "First")])
        #expect(page.kind == .length)
        #expect(page.currentPage == 1)
        #expect(page.lastPage == 3)
        #expect(page.total == 3)
        #expect(page.nextPageURL == "https://api.example.com/api/events?page=2")
        #expect(page.previousPageURL == nil)
        #expect(page.hasNextPage)
        #expect(!page.hasPreviousPage)
    }

    @Test("simplePaginate reports no total")
    func simplePaginator() throws {
        let page = try decode(PaginationFixtures.simple)

        #expect(page.kind == .simple)
        #expect(page.total == nil)
        #expect(page.lastPage == nil)
        #expect(page.hasNextPage)
        #expect(!page.hasPreviousPage)
    }

    @Test("Cursor pagination is recognised by its cursors")
    func cursorPaginator() throws {
        let page = try decode(PaginationFixtures.cursor)

        #expect(page.kind == .cursor)
        #expect(page.nextCursor == "eyJpZCI6MX0")
        #expect(page.previousCursor == nil)
        #expect(page.hasNextPage)
        #expect(!page.hasPreviousPage)
    }

    @Test("Cursors are found inside meta as well")
    func cursorInMeta() throws {
        let page = try decode(PaginationFixtures.cursorInMeta)

        #expect(page.kind == .cursor)
        #expect(page.nextCursor == "eyJpZCI6MX0")
        #expect(page.hasNextPage)
    }

    @Test("The last page reports no next page")
    func lastPage() throws {
        let page = try decode(PaginationFixtures.lastPage)

        #expect(page.isEmpty)
        #expect(!page.hasNextPage)
        #expect(page.hasPreviousPage)
    }

    @Test("A plain decoder reads the same payloads")
    func plainDecoderWorksToo() throws {
        let page = try JSONDecoder().decode(
            Page<Event>.self,
            from: Data(PaginationFixtures.lengthAware.utf8)
        )

        #expect(page.currentPage == 2)
        #expect(page.nextPageURL == "https://api.example.com/api/events?page=3")
        #expect(page.hasNextPage)
    }

    @Test("An unpaginated list of records is not a page")
    func plainListIsNotAPage() {
        #expect(throws: (any Error).self) {
            try LaravelJSONDecoder.makeDefault().decode(
                Page<Event>.self,
                from: Data(#"[{"id":1,"title":"First"}]"#.utf8)
            )
        }
    }
}

@Suite("Fetching pages")
struct PaginationFetchingTests {
    let baseURL = URL(string: "https://api.example.com")!

    private func makeClient(_ transport: any HTTPTransport) -> LaravelClient {
        LaravelClient(configuration: .withoutRetries(baseURL), transport: transport)
    }

    @Test("A page is fetched from the given path")
    func fetchFirstPage() async throws {
        let transport = MockTransport(json: PaginationFixtures.resourceWrapped)
        let client = makeClient(transport)

        let page: Page<Event> = try await client.page("/api/events", query: ["per_page": "1"])

        #expect(page.items.count == 1)
        #expect(
            await transport.lastRequest?.url?.absoluteString
                == "https://api.example.com/api/events?per_page=1"
        )
    }

    @Test("The next page is fetched from the paginator's own URL")
    func fetchNextPage() async throws {
        let transport = MockTransport(bodies: [
            PaginationFixtures.resourceWrapped,
            PaginationFixtures.lastPage,
        ])
        let client = makeClient(transport)
        let first: Page<Event> = try await client.page("/api/events")

        let second = try await client.nextPage(after: first)

        #expect(second?.currentPage == 3)
        let paths = await transport.executedRequests.map(\.url?.absoluteString)
        #expect(paths == [
            "https://api.example.com/api/events",
            "https://api.example.com/api/events?page=2",
        ])
    }

    @Test("The last page has no next page to fetch")
    func nextPageOnLastPage() async throws {
        let transport = MockTransport(json: PaginationFixtures.lastPage)
        let client = makeClient(transport)
        let page: Page<Event> = try await client.page("/api/events")

        let next = try await client.nextPage(after: page)

        #expect(next == nil)
        #expect(await transport.attemptCount == 1)
    }

    @Test("The previous page is fetched when there is one")
    func fetchPreviousPage() async throws {
        let transport = MockTransport(bodies: [
            PaginationFixtures.lengthAware,
            PaginationFixtures.resourceWrapped,
        ])
        let client = makeClient(transport)
        let page: Page<Event> = try await client.page("/api/events", query: ["page": "2"])

        let previous = try await client.previousPage(before: page)

        #expect(previous?.currentPage == 1)
        #expect(
            await transport.lastRequest?.url?.absoluteString
                == "https://api.example.com/api/events?page=1"
        )
    }

    @Test("Cursor pagination without URLs falls back to the cursor query")
    func cursorFallback() async throws {
        let transport = MockTransport(bodies: [
            PaginationFixtures.cursorInMeta,
            PaginationFixtures.lastPage,
        ])
        let client = makeClient(transport)
        let page: Page<Event> = try await client.page("/api/events")

        _ = try await client.nextPage(after: page)

        #expect(
            await transport.lastRequest?.url?.absoluteString
                == "https://api.example.com/api/events?cursor=eyJpZCI6MX0"
        )
    }

    @Test("Walking the pages visits each one in order and stops at the end")
    func pageSequence() async throws {
        let transport = MockTransport(bodies: [
            PaginationFixtures.resourceWrapped,
            PaginationFixtures.lengthAware,
            PaginationFixtures.lastPage,
        ])
        let client = makeClient(transport)

        var collected: [Event] = []
        for try await page in client.pages(of: Event.self, at: "/api/events") {
            collected.append(contentsOf: page.items)
        }

        #expect(collected == [Event(id: 1, title: "First"), Event(id: 3, title: "Third")])
        #expect(await transport.attemptCount == 3)
    }

    @Test("Stopping early stops the requests")
    func pageSequenceStopsEarly() async throws {
        let transport = MockTransport(bodies: [
            PaginationFixtures.resourceWrapped,
            PaginationFixtures.lengthAware,
            PaginationFixtures.lastPage,
        ])
        let client = makeClient(transport)

        for try await page in client.pages(of: Event.self, at: "/api/events") {
            if page.currentPage == 1 { break }
        }

        #expect(await transport.attemptCount == 1)
    }
}
