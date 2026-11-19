import Combine
import Foundation

/// Speculates only a small nearby window. Visible rows load independently; scrolling
/// replaces queued work without starting more workers or canceling shared downloads.
@MainActor
final class CatalogArtworkPrefetcher: ObservableObject {
    typealias Load = @MainActor (URL) async -> Void
    private let load: Load
    private let isCached: @MainActor (URL) -> Bool
    private let concurrency: Int
    private var queued: [URL] = []
    private var active = Set<URL>()

    init(concurrency: Int = 2, isCached: @escaping @MainActor (URL) -> Bool,
         load: @escaping Load) {
        self.concurrency = max(1, min(concurrency, 2))
        self.isCached = isCached
        self.load = load
    }

    func update(_ urls: [URL]) {
        guard !Task.isCancelled else { return }
        var seen = Set<URL>()
        queued = urls.filter { seen.insert($0).inserted && !active.contains($0) && !isCached($0) }.prefix(12).map { $0 }
        startWorkers()
    }

    func stop() {
        // Active requests remain bounded and may now be shared with a visible row.
        queued.removeAll()
    }

    static func nearbyURLs(songs: [CatalogSong], anchor: String) -> [URL] {
        guard let index = songs.firstIndex(where: { $0.slug == anchor }) else { return [] }
        let forward = songs.dropFirst(index + 1).prefix(8)
        let backward = songs.prefix(index).suffix(4).reversed()
        return (Array(forward) + Array(backward)).compactMap(\.imageURL)
    }

    private func startWorkers() {
        while active.count < concurrency, !queued.isEmpty {
            let url = queued.removeFirst()
            guard !isCached(url), active.insert(url).inserted else { continue }
            Task(priority: .utility) {
                await load(url)
                active.remove(url)
                startWorkers()
            }
        }
    }
}
