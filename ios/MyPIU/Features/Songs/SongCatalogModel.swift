import Combine
import Foundation

@MainActor
final class SongCatalogModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var listing = CatalogListing()
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var paginationError: String?

    private let apiClient: MyPIUAPIClient
    private var requestID = UUID()
    private var listingRequestID: UUID?
    private var currentQuery = ""
    private var currentVersion: PIUGameVersion = .phoenix2

    init(apiClient: MyPIUAPIClient = MyPIUAPIClient()) {
        self.apiClient = apiClient
    }

    func reload(query: String, version: PIUGameVersion, debounce: Bool = true) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        self.requestID = requestID
        listingRequestID = nil
        currentQuery = normalizedQuery
        currentVersion = version
        isLoadingMore = false
        paginationError = nil

        if debounce, !normalizedQuery.isEmpty {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
        }
        guard !Task.isCancelled, self.requestID == requestID else { return }

        listing = CatalogListing()
        state = .loading
        do {
            let page = try await apiClient.searchCatalog(query: normalizedQuery, version: version)
            guard !Task.isCancelled, self.requestID == requestID else { return }
            listing.replace(with: page)
            listingRequestID = requestID
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard self.requestID == requestID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        await reload(query: currentQuery, version: currentVersion, debounce: false)
    }

    func loadMoreIfNeeded(after song: CatalogSong) async {
        guard let index = listing.songs.firstIndex(where: { $0.id == song.id }) else { return }
        guard index >= max(0, listing.songs.count - 5) else { return }
        await loadMore()
    }

    func retryPagination() async {
        await loadMore()
    }

    private func loadMore() async {
        guard listingRequestID == requestID, !isLoadingMore, let cursor = listing.nextCursor else { return }
        let requestID = self.requestID
        isLoadingMore = true
        paginationError = nil
        defer {
            if self.requestID == requestID {
                isLoadingMore = false
            }
        }

        do {
            let page = try await apiClient.searchCatalog(
                query: currentQuery,
                cursor: cursor,
                version: currentVersion
            )
            guard !Task.isCancelled, self.requestID == requestID else { return }
            listing.append(page, requestedCursor: cursor)
        } catch is CancellationError {
            return
        } catch {
            guard self.requestID == requestID else { return }
            paginationError = error.localizedDescription
        }
    }
}
