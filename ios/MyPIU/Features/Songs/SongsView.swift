import SwiftUI

struct SongsView: View {
    enum Feed: Equatable {
        case catalog
        case recommendations
        case favorites

        var title: String {
            switch self {
            case .catalog: "Songs"
            case .recommendations: "Recommendations"
            case .favorites: "Favorites"
            }
        }

        var resultLabel: String {
            switch self {
            case .catalog: "songs"
            case .recommendations: "recommendations"
            case .favorites: "favorites"
            }
        }
    }

    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var catalog: SongCatalogModel
    @Binding private var query: String
    private let versionOverride: PIUGameVersion?
    private let feed: Feed

    init(
        catalog: SongCatalogModel,
        query: Binding<String>,
        versionOverride: PIUGameVersion? = nil,
        feed: Feed = .catalog
    ) {
        self.catalog = catalog
        _query = query
        self.versionOverride = versionOverride
        self.feed = feed
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
                    emptyFeedView
                }
            default:
                songList
            }
        }
        .navigationTitle(feed.title)
        .navigationDestination(for: CatalogSong.self) { routedSong in
            let song = catalog.song(slug: routedSong.slug) ?? routedSong
            CatalogSongDetailView(
                song: song,
                canUpdateFavorite: canUpdateFavorites,
                isUpdatingFavorite: isUpdatingFavorite(song.slug)
            ) {
                updateFavorite(for: song)
            }
        }
        .modifier(CatalogSearchModifier(query: $query, enabled: feed == .catalog))
        .toolbar {
            if feed == .catalog, appModel.isMyPIUConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FavoriteSongsView()
                    } label: {
                        Image(systemName: "star.fill")
                    }
                    .accessibilityLabel("Favorite songs")
                }
            }
        }
        .alert(
            "Couldn't Update Favorite",
            isPresented: Binding(
                get: { catalog.favoriteError != nil },
                set: { isPresented in
                    if !isPresented { catalog.clearFavoriteError() }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                catalog.clearFavoriteError()
            }
        } message: {
            Text(catalog.favoriteError ?? "Try again.")
        }
        .task(id: CatalogRequest(
            query: query,
            version: catalogVersion,
            cacheScope: appModel.catalogCacheScope
        )) {
            await catalog.loadIfNeeded(
                query: query,
                version: catalogVersion,
                cacheScope: appModel.catalogCacheScope,
                debounce: feed == .catalog && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                using: appModel.searchCatalog
            )
        }
        .onReceive(appModel.favoriteChanges) { change in
            guard change.accountID == appModel.myPIUAccount?.id,
                  change.version == catalogVersion else { return }
            Task {
                await catalog.applyConfirmedFavorite(
                    change.isFavorite,
                    slug: change.songSlug,
                    version: change.version,
                    cacheScope: "account:\(change.accountID)"
                )
            }
        }
    }

    private var songList: some View {
        List {
            Section {
                ForEach(catalog.listing.songs) { song in
                    HStack(spacing: 8) {
                        NavigationLink(value: song) {
                            CatalogSongRow(song: song)
                        }
                        .buttonStyle(.plain)

                        if canUpdateFavorites {
                            FavoriteButton(
                                isFavorite: song.isFavorite,
                                isUpdating: isUpdatingFavorite(song.slug)
                            ) {
                                updateFavorite(for: song)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .task(id: catalog.paginationGeneration) {
                        await catalog.loadMoreIfNeeded(after: song)
                    }
                }
            } header: {
                HStack {
                    Text("\(catalog.listing.total.formatted()) \(feed.resultLabel)")
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

    @ViewBuilder
    private var emptyFeedView: some View {
        switch feed {
        case .catalog:
            ContentUnavailableView.search(text: query)
        case .recommendations:
            ContentUnavailableView(
                "No Recommendations",
                systemImage: "sparkles",
                description: Text("Sync more plays to build your recommendations.")
            )
        case .favorites:
            ContentUnavailableView(
                "No Favorite Songs",
                systemImage: "star",
                description: Text("Songs you favorite will appear here.")
            )
        }
    }

    private var catalogVersion: PIUGameVersion {
        versionOverride ?? appModel.selectedVersion
    }

    private var canUpdateFavorites: Bool {
        appModel.isMyPIUConnected
            && appModel.catalogCacheScope?.hasPrefix("account:") == true
    }

    private func updateFavorite(for song: CatalogSong) {
        Task {
            await catalog.setFavorite(
                !song.isFavorite,
                for: song,
                using: appModel.setFavorite
            )
        }
    }

    private func isUpdatingFavorite(_ slug: String) -> Bool {
        catalog.isUpdatingFavorite(slug: slug)
            || appModel.isUpdatingFavorite(songSlug: slug)
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
            versionOverride: appModel.myPIUAccount?.piuGameVersion ?? appModel.selectedVersion,
            feed: .recommendations
        )
    }
}

struct FavoriteSongsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var catalog = SongCatalogModel()
    @State private var query = "favorites"

    var body: some View {
        SongsView(
            catalog: catalog,
            query: $query,
            versionOverride: appModel.myPIUAccount?.piuGameVersion ?? appModel.selectedVersion,
            feed: .favorites
        )
    }
}

private struct CatalogSearchModifier: ViewModifier {
    @Binding var query: String
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, prompt: "Search the catalog")
        } else {
            content
        }
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

struct FavoriteButton: View {
    let isFavorite: Bool
    let isUpdating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isUpdating {
                    ProgressView()
                } else {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? AppTheme.warning : .secondary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(isUpdating)
        .accessibilityLabel(
            isUpdating ? "Updating favorite" : (isFavorite ? "Remove from favorites" : "Add to favorites")
        )
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
