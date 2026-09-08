import Foundation

/// Which Laravel paginator produced a page.
public enum PaginationKind: Sendable, Hashable {
    /// `paginate()` — knows the total number of records and the last page.
    case length
    /// `simplePaginate()` — knows only whether another page follows.
    case simple
    /// `cursorPaginate()` — walks the result set by cursor.
    case cursor
}

/// One page of a Laravel paginated response.
///
/// Laravel returns pagination in two envelopes — the paginator's own JSON, and
/// the `{"data": …, "meta": …, "links": …}` shape an API Resource collection
/// produces — across three paginators. `Page` reads all of them, so an app does
/// not have to know which one a given endpoint uses:
///
/// ```swift
/// let page: Page<Event> = try await client.page("/api/events")
/// let next = try await client.nextPage(after: page)
/// ```
///
/// Fields absent from a given format stay `nil`: `simplePaginate` reports no
/// `total`, and cursor pagination reports no page numbers.
public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    /// The records on this page.
    public let items: [Item]
    /// 1-based index of this page, when the paginator counts pages.
    public let currentPage: Int?
    /// Index of the final page, when the paginator knows it.
    public let lastPage: Int?
    /// How many records a full page holds.
    public let perPage: Int?
    /// Total number of records, when the paginator counted them.
    public let total: Int?
    /// Index of the first record on this page, within the whole result set.
    public let from: Int?
    /// Index of the last record on this page.
    public let to: Int?
    /// Base path the paginator built its URLs from.
    public let path: String?
    /// URL of the next page, when there is one.
    public let nextPageURL: String?
    /// URL of the previous page, when there is one.
    public let previousPageURL: String?
    /// URL of the first page, when the response advertises it.
    public let firstPageURL: String?
    /// URL of the last page, when the response advertises it.
    public let lastPageURL: String?
    /// Cursor pointing at the next page, for cursor pagination.
    public let nextCursor: String?
    /// Cursor pointing at the previous page, for cursor pagination.
    public let previousCursor: String?

    public init(
        items: [Item],
        currentPage: Int? = nil,
        lastPage: Int? = nil,
        perPage: Int? = nil,
        total: Int? = nil,
        from: Int? = nil,
        to: Int? = nil,
        path: String? = nil,
        nextPageURL: String? = nil,
        previousPageURL: String? = nil,
        firstPageURL: String? = nil,
        lastPageURL: String? = nil,
        nextCursor: String? = nil,
        previousCursor: String? = nil
    ) {
        self.items = items
        self.currentPage = currentPage
        self.lastPage = lastPage
        self.perPage = perPage
        self.total = total
        self.from = from
        self.to = to
        self.path = path
        self.nextPageURL = nextPageURL
        self.previousPageURL = previousPageURL
        self.firstPageURL = firstPageURL
        self.lastPageURL = lastPageURL
        self.nextCursor = nextCursor
        self.previousCursor = previousCursor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        items = try container.decode([Item].self, forKey: AnyCodingKey("data"))

        // A resource collection nests the numbers under `meta` and the URLs
        // under `links`; the bare paginator puts everything at the top level.
        // `links` is an object there only for resource collections — the bare
        // paginator uses an array of page links, which simply does not match.
        var lookup = PageLookup(container: container)
        lookup.addNested(AnyCodingKey("meta"), in: container)
        lookup.addNested(AnyCodingKey("links"), in: container)

        currentPage = lookup.int("current_page", "currentPage")
        lastPage = lookup.int("last_page", "lastPage")
        perPage = lookup.int("per_page", "perPage")
        total = lookup.int("total")
        from = lookup.int("from")
        to = lookup.int("to")
        path = lookup.string("path")
        nextPageURL = lookup.string("next_page_url", "nextPageUrl", "next")
        previousPageURL = lookup.string("prev_page_url", "prevPageUrl", "prev")
        firstPageURL = lookup.string("first_page_url", "firstPageUrl", "first")
        lastPageURL = lookup.string("last_page_url", "lastPageUrl", "last")
        nextCursor = lookup.string("next_cursor", "nextCursor")
        previousCursor = lookup.string("prev_cursor", "prevCursor")
    }

    // MARK: - Navigation

    /// Which paginator produced this page.
    public var kind: PaginationKind {
        if nextCursor != nil || previousCursor != nil { return .cursor }
        return total != nil || lastPage != nil ? .length : .simple
    }

    /// Whether another page follows.
    public var hasNextPage: Bool {
        if nextPageURL != nil || nextCursor != nil { return true }
        guard let currentPage, let lastPage else { return false }
        return currentPage < lastPage
    }

    /// Whether a page precedes this one.
    public var hasPreviousPage: Bool {
        if previousPageURL != nil || previousCursor != nil { return true }
        guard let currentPage else { return false }
        return currentPage > 1
    }

    /// Whether this page carries no records.
    public var isEmpty: Bool { items.isEmpty }
}

/// Reads values that may live at the top level or inside `meta`/`links`, under
/// either the snake_case or camelCase spelling.
///
/// The spellings both have to be tried because the decoder's key strategy is
/// the app's choice, and a paginated payload has to decode either way.
private struct PageLookup {
    private var containers: [KeyedDecodingContainer<AnyCodingKey>] = []

    init(container: KeyedDecodingContainer<AnyCodingKey>) {
        containers = [container]
    }

    mutating func addNested(_ key: AnyCodingKey, in container: KeyedDecodingContainer<AnyCodingKey>) {
        guard let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else {
            return
        }
        // Nested values take precedence: `meta.current_page` is the real one.
        containers.insert(nested, at: 0)
    }

    func int(_ keys: String...) -> Int? {
        value(keys) { container, key in try container.decodeIfPresent(Int.self, forKey: key) }
    }

    func string(_ keys: String...) -> String? {
        value(keys) { container, key in try container.decodeIfPresent(String.self, forKey: key) }
    }

    private func value<T>(
        _ keys: [String],
        decode: (KeyedDecodingContainer<AnyCodingKey>, AnyCodingKey) throws -> T?
    ) -> T? {
        // `try?` flattens the optional, so a missing, null, or mistyped value
        // simply moves on to the next spelling.
        for container in containers {
            for key in keys {
                if let value = try? decode(container, AnyCodingKey(key)) {
                    return value
                }
            }
        }
        return nil
    }
}

/// A coding key for payloads whose keys are only known at runtime.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }

    init(stringValue: String) {
        self.init(stringValue)
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
