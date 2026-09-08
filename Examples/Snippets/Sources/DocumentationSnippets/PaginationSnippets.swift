import Foundation

import LaravelMobileKit

/// A payload that carries a page alongside other fields.
struct EventFeed: Decodable, Sendable {
    let unreadCount: Int
    let events: Page<Event>
}

/// Examples from `Documentation/PAGINATION.md`.
enum PaginationSnippets {
    static func onePage(client: LaravelClient) async throws {
        let page: Page<Event> = try await client.page("/api/events", query: ["per_page": "20"])

        _ = page.items
        _ = page.currentPage
        _ = page.lastPage
        _ = page.perPage
        _ = page.total
        _ = (page.from, page.to)
        _ = page.hasNextPage
        _ = page.isEmpty

        switch page.kind {
        case .length: break
        case .simple: break
        case .cursor: break
        }
    }

    static func moving(client: LaravelClient, page: Page<Event>) async throws {
        if let next = try await client.nextPage(after: page) { _ = next }
        if let previous = try await client.previousPage(before: page) { _ = previous }
    }

    static func walking(client: LaravelClient) async throws {
        for try await page in client.pages(of: Event.self, at: "/api/events") {
            _ = page.items
        }
    }

    static func wrappedPage(client: LaravelClient) async throws {
        let feed: EventFeed = try await client.get("/api/feed")
        _ = (feed.unreadCount, feed.events.items)
    }
}

/// The infinite-scrolling model from the guide.
@MainActor
final class EventsModel: ObservableObject {
    @Published private(set) var events: [Event] = []
    private var latest: Page<Event>?

    func loadMore(using client: LaravelClient) async throws {
        let page: Page<Event>? =
            if let latest {
                try await client.nextPage(after: latest)
            } else {
                try await client.page("/api/events", query: ["per_page": "20"])
            }

        guard let page else { return }
        latest = page
        events += page.items
    }
}
