import SwiftUI

struct SongsView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var catalog: SongCatalogModel
    @Binding private var query: String
    private let versionOverride: PIUGameVersion?

    init(
        catalog: SongCatalogModel,
        query: Binding<String>,
        versionOverride: PIUGameVersion? = nil
    ) {
        self.catalog = catalog
        _query = query
        self.versionOverride = versionOverride
    }

    var body: some View {
        Group {
            switch catalog.state {
            case .idle, .loading where catalog.listing.songs.isEmpty:
                ProgressView("Loading songs")
            case .failed(let message) where catalog.listing.songs.isEmpty:
                ContentUnavailableView {
                    Label("Catalog unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task { await catalog.retry() }
                    }
                }
            case .loaded where catalog.listing.songs.isEmpty:
                if catalog.isShowingCachedData {
                    ContentUnavailableView {
                        Label("No cached results", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Catalog is offline.")
                    } actions: {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            Task { await catalog.retry() }
                        }
                    }
                } else {
                    ContentUnavailableView.search(text: query)
                }
            default:
                songList
            }
        }
        .navigationTitle(isRecommendationFeed ? "Recommendations" : "Songs")
        .navigationDestination(for: CatalogSong.self) { song in
            CatalogSongDetailView(song: song)
        }
        .searchable(text: $query, prompt: "Search the catalog")
        .task(id: CatalogRequest(
            query: query,
            version: catalogVersion,
            cacheScope: appModel.catalogCacheScope
        )) {
            await catalog.loadIfNeeded(
                query: query,
                version: catalogVersion,
                cacheScope: appModel.catalogCacheScope,
                debounce: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                using: appModel.searchCatalog
            )
        }
    }

    private var songList: some View {
        List {
            Section {
                ForEach(catalog.listing.songs) { song in
                    NavigationLink(value: song) {
                        CatalogSongRow(song: song)
                    }
                    .task(id: catalog.paginationGeneration) {
                        await catalog.loadMoreIfNeeded(after: song)
                    }
                }
            } header: {
                HStack {
                    Text("\(catalog.listing.total.formatted()) \(isRecommendationFeed ? "recommendations" : "songs")")
                    if catalog.isShowingCachedData {
                        Spacer()
                        Label("Offline", systemImage: "arrow.down.circle")
                    }
                }
            }

            if catalog.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if catalog.paginationError != nil {
                Button("Retry loading more", systemImage: "arrow.clockwise") {
                    Task { await catalog.retryPagination() }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await catalog.reload(
                query: query,
                version: catalogVersion,
                cacheScope: appModel.catalogCacheScope,
                debounce: false,
                using: appModel.searchCatalog
            )
        }
    }

    private var isRecommendationFeed: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "recommendation"
    }

    private var catalogVersion: PIUGameVersion {
        versionOverride ?? appModel.selectedVersion
    }
}

struct RecommendationSongsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var catalog = SongCatalogModel()
    @State private var query = "recommendation"

    var body: some View {
        SongsView(
            catalog: catalog,
            query: $query,
            versionOverride: appModel.myPIUAccount?.piuGameVersion ?? appModel.selectedVersion
        )
    }
}

private struct CatalogRequest: Hashable {
    let query: String
    let version: PIUGameVersion
    let cacheScope: String?
}

private struct CatalogSongRow: View {
    let song: CatalogSong

    var body: some View {
        HStack(spacing: 12) {
            CatalogArtwork(url: song.imageURL, size: 68)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(song.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if song.isPremium {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(AppTheme.warning)
                            .accessibilityLabel("Premium")
                    }
                    if song.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(AppTheme.warning)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let recommendedChartToken = song.recommendedChartToken {
                    Label(recommendedChartToken, systemImage: "sparkles")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("Recommended chart \(recommendedChartToken)")
                }
                Text(song.chartSummary.prefix(6).joined(separator: "  "))
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let folder = song.folder ?? song.series {
                    Text(folder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CatalogArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                artworkPlaceholder(systemImage: "music.note")
            case .empty:
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    ProgressView()
                }
            @unknown default:
                artworkPlaceholder(systemImage: "music.note")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func artworkPlaceholder(systemImage: String) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}
