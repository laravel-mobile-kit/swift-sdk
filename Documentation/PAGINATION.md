# Pagination

Laravel returns pagination in two envelopes — the paginator's own JSON and the
`{"data": …, "meta": …, "links": …}` shape an API Resource collection produces —
across three paginators. `Page` reads all of them, so an app does not have to
know which one an endpoint uses.

## One page

```swift
let page: Page<Event> = try await client.page("/api/events", query: ["per_page": "20"])

page.items          // [Event]
page.currentPage    // 1
page.lastPage       // 5
page.perPage        // 20
page.total          // 93
page.from, page.to  // 1, 20
page.hasNextPage
page.isEmpty
```

Fields a given format does not carry stay `nil`: `simplePaginate()` reports no
`total`, and cursor pagination reports no page numbers.

```swift
switch page.kind {
case .length: …   // paginate()
case .simple: …   // simplePaginate()
case .cursor: …   // cursorPaginate()
}
```

## Moving between pages

```swift
if let next = try await client.nextPage(after: page) { … }
if let previous = try await client.previousPage(before: page) { … }
```

Both follow what the paginator returned: `next_page_url` when there is one, and
the path plus the next cursor for cursor pagination. Your code never builds a
`?page=` URL, and never has to know which paginator is on the other end.

> **Server note:** Laravel drops the query string from paginator links unless you
> ask it to keep it. An endpoint that accepts `per_page` should call
> `->withQueryString()`, or page two silently reverts to the default page size.

## Walking a collection

```swift
for try await page in client.pages(of: Event.self, at: "/api/events") {
    render(page.items)
}
```

Pages are fetched lazily, so `break` stops the requests. This is the shape that
fits an infinite-scrolling list:

```swift
@MainActor
final class EventsModel: ObservableObject {
    @Published private(set) var events: [Event] = []
    private var latest: Page<Event>?

    func loadMore(using client: LaravelClient) async throws {
        let page: Page<Event>? = if let latest {
            try await client.nextPage(after: latest)
        } else {
            try await client.page("/api/events", query: ["per_page": "20"])
        }

        guard let page else { return }
        latest = page
        events += page.items
    }
}
```

## Resource collections

An API Resource collection nests its records under `data` and its counts under
`meta`. Nothing changes at the call site:

```swift
let page: Page<Event> = try await client.page("/api/events")   // works for both shapes
```

## Endpoints that wrap a page in something else

When a payload is more than a paginator — a collection plus a summary, say —
decode it as your own type and let `Page` decode the part that is a page:

```swift
struct EventFeed: Decodable, Sendable {
    let unreadCount: Int
    let events: Page<Event>
}

let feed: EventFeed = try await client.get("/api/feed")
```
