import SwiftUI

import LaravelMobileKit

/// A paginated Laravel collection, loaded a page at a time.
///
/// The view never builds a `?page=` URL: it asks the kit for the next page,
/// which follows whatever the paginator returned — `next_page_url` for
/// `paginate()` and `simplePaginate()`, a cursor for `cursorPaginate()`.
@MainActor
final class EventsModel: ObservableObject {
    @Published private(set) var events: [Event] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failure: String?
    @Published private(set) var total: Int?

    private var latestPage: Page<Event>?
    private var loadTask: Task<Void, Never>?

    var hasMore: Bool { latestPage?.hasNextPage ?? false }

    func loadFirstPage(using client: LaravelClient) {
        // Starting over cancels whatever is in flight: a cancelled request is
        // cancelled all the way down to the transport.
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load(using: client, reset: true)
        }
    }

    func loadNextPage(using client: LaravelClient) {
        guard !isLoading, hasMore else { return }
        loadTask = Task { [weak self] in
            await self?.load(using: client, reset: false)
        }
    }

    func cancel() {
        loadTask?.cancel()
    }

    private func load(using client: LaravelClient, reset: Bool) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let page: Page<Event>?
            if reset || latestPage == nil {
                page = try await client.page("/api/events", query: ["per_page": "15"])
            } else if let latestPage {
                page = try await client.nextPage(after: latestPage)
            } else {
                page = nil
            }

            guard let page else { return }
            latestPage = page
            total = page.total
            events = reset ? page.items : events + page.items
        } catch let error as LaravelError where error.isCancelled {
            // A cancelled load is not a failure: the user moved on.
        } catch {
            failure = (error as? LaravelError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct EventsListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = EventsModel()

    var body: some View {
        List {
            if let failure = model.failure {
                Section {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(model.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.headline)
                        if let startsAt = event.startsAt {
                            Text(startsAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                if let total = model.total {
                    Text("\(model.events.count) of \(total)")
                }
            }

            if model.hasMore {
                Button(model.isLoading ? "Loading…" : "Load more") {
                    model.loadNextPage(using: environment.client)
                }
                .disabled(model.isLoading)
            }
        }
        .navigationTitle("Events")
        .refreshable { model.loadFirstPage(using: environment.client) }
        .task { model.loadFirstPage(using: environment.client) }
        .onDisappear { model.cancel() }
    }
}
