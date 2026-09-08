import Foundation
import Testing

import LaravelMobileKit

extension LaravelIntegration {
    @Suite("Pagination formats")
    struct PaginationIntegrationTests {
        @Test("A length-aware paginator reports its position and totals")
        func lengthAwarePagination() async throws {
            let client = await IntegrationHarness.makeClient()

            let page: Page<APIEvent> = try await client.page(
                "/api/events", query: ["per_page": "10"])

            #expect(page.kind == .length)
            #expect(page.items.count == 10)
            #expect(page.currentPage == 1)
            #expect(page.perPage == 10)
            #expect(page.total == IntegrationEnvironment.seededEventCount)
            #expect(page.lastPage == 5)
            #expect(page.hasNextPage)
            #expect(!page.hasPreviousPage)
            #expect(page.items.first?.title == "Event 01")
        }

        @Test("Following the paginator's own links walks the collection")
        func followingNextAndPreviousLinks() async throws {
            let client = await IntegrationHarness.makeClient()
            let first: Page<APIEvent> = try await client.page(
                "/api/events", query: ["per_page": "10"])

            let second = try #require(try await client.nextPage(after: first) as Page<APIEvent>?)
            #expect(second.currentPage == 2)
            #expect(second.items.first?.title == "Event 11")

            let backAgain = try #require(
                try await client.previousPage(before: second) as Page<APIEvent>?)
            #expect(backAgain.currentPage == 1)
            #expect(backAgain.items == first.items)
        }

        @Test("The last page has no next page")
        func lastPageEndsTheWalk() async throws {
            let client = await IntegrationHarness.makeClient()

            let last: Page<APIEvent> = try await client.page(
                "/api/events",
                query: ["per_page": "10", "page": "5"]
            )

            #expect(last.currentPage == 5)
            #expect(last.items.count == 5)
            #expect(!last.hasNextPage)
            #expect(try await client.nextPage(after: last) as Page<APIEvent>? == nil)
        }

        @Test("A resource collection's data, links, and meta are understood")
        func apiResourcePagination() async throws {
            let client = await IntegrationHarness.makeClient()

            let page: Page<APIEvent> = try await client.page(
                "/api/events/resource",
                query: ["per_page": "15"]
            )

            #expect(page.kind == .length)
            #expect(page.items.count == 15)
            #expect(page.total == IntegrationEnvironment.seededEventCount)
            #expect(page.items.first?.startsAt != nil)
        }

        @Test("simplePaginate has no total but still moves forward")
        func simplePagination() async throws {
            let client = await IntegrationHarness.makeClient()

            let page: Page<APIEvent> = try await client.page(
                "/api/events/simple",
                query: ["per_page": "10"]
            )

            #expect(page.items.count == 10)
            #expect(page.total == nil)
            #expect(page.hasNextPage)

            let second = try #require(try await client.nextPage(after: page) as Page<APIEvent>?)
            #expect(second.items.first?.title == "Event 11")
        }

        @Test("Cursor pagination follows its cursors")
        func cursorPagination() async throws {
            let client = await IntegrationHarness.makeClient()

            let first: Page<APIEvent> = try await client.page(
                "/api/events/cursor",
                query: ["per_page": "10"]
            )

            #expect(first.kind == .cursor)
            #expect(first.nextCursor != nil)
            #expect(first.items.count == 10)

            let second = try #require(try await client.nextPage(after: first) as Page<APIEvent>?)
            #expect(second.items.first?.title == "Event 11")
            #expect(second.previousCursor != nil)
        }

        @Test("The page sequence walks every seeded record exactly once")
        func pageSequenceWalksEverything() async throws {
            let client = await IntegrationHarness.makeClient()

            var titles: [String] = []
            for try await page in client.pages(
                of: APIEvent.self,
                at: "/api/events",
                query: ["per_page": "20"]
            ) {
                titles.append(contentsOf: page.items.map(\.title))
            }

            #expect(titles.count == IntegrationEnvironment.seededEventCount)
            #expect(Set(titles).count == titles.count)
            #expect(titles.first == "Event 01")
        }

        @Test("Stopping early stops requesting pages")
        func stoppingEarlyStopsFetching() async throws {
            let client = await IntegrationHarness.makeClient()

            var pagesSeen = 0
            for try await _ in client.pages(
                of: APIEvent.self, at: "/api/events", query: ["per_page": "10"])
            {
                pagesSeen += 1
                if pagesSeen == 2 { break }
            }

            #expect(pagesSeen == 2)
        }
    }
}
