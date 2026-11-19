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
    @State private var filters = CatalogFilters.empty
    @State private var showingFilters = false
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
            case .idle where catalog.listing.songs.isEmpty, .loading where catalog.listing.songs.isEmpty:
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
                        Text(catalog.refreshError ?? "No matching songs are available in the saved catalog.")
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
                version: catalogVersion,
                canUpdateFavorite: canUpdateFavorites,
                isUpdatingFavorite: isUpdatingFavorite(song.slug)
            ) {
                updateFavorite(for: song)
            }
        }
        .modifier(CatalogSearchModifier(query: $query, enabled: feed == .catalog))
        .toolbar {
            if feed == .catalog {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if filters.selectionCount > 0 {
                                Text(filters.selectionCount.formatted())
                                    .font(.caption2.bold().monospacedDigit())
                            }
                        }
                    }
                    .accessibilityLabel(
                        filters.selectionCount == 0
                            ? "Sort and filter songs"
                            : "Sort and filter songs, \(filters.selectionCount) filters selected"
                    )
                }
            }
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
        .sheet(isPresented: $showingFilters) {
            SongFilterSheet(
                filters: filters,
                options: catalog.listing.filterOptions,
                onApply: { filters = $0 }
            )
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
            filters: filters,
            cacheScope: appModel.catalogCacheScope
        )) {
            await catalog.loadIfNeeded(
                query: query,
                version: catalogVersion,
                filters: filters,
                cacheScope: appModel.catalogCacheScope,
                debounce: feed == .catalog && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                using: { query, cursor, version in
                    try await appModel.searchCatalog(
                        query: query,
                        cursor: cursor,
                        version: version
                    )
                },
                usingFiltered: { query, cursor, version, filters in
                    try await appModel.searchCatalog(
                        query: query,
                        cursor: cursor,
                        version: version,
                        filters: filters
                    )
                },
                usingOverlay: { [scope = appModel.catalogCacheScope] version in
                    guard appModel.catalogCacheScope == scope else { throw CancellationError() }
                    return try await appModel.catalogOverlay(version: version)
                }
            )
        }
        .onChange(of: appModel.catalogRefreshGeneration) { _, _ in
            Task { await catalog.retry() }
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
                    NavigationLink(value: song) {
                        CatalogSongRow(song: song)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if canUpdateFavorites {
                            Button {
                                updateFavorite(for: song)
                            } label: {
                                Label(
                                    song.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: song.isFavorite ? "star.slash.fill" : "star.fill"
                                )
                            }
                            .tint(song.isFavorite ? .gray : AppTheme.warning)
                            .disabled(isUpdatingFavorite(song.slug))
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
                        Label("Saved", systemImage: "arrow.down.circle")
                    }
                }
            }

            if let refreshError = catalog.refreshError {
                Section {
                    Text(refreshError).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry refresh", systemImage: "arrow.clockwise") {
                        Task { await catalog.retry() }
                    }
                }
            }
            if catalog.state == .loading || catalog.isLoadingMore {
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
                filters: filters,
                cacheScope: appModel.catalogCacheScope,
                debounce: false,
                using: { query, cursor, version in
                    try await appModel.searchCatalog(
                        query: query,
                        cursor: cursor,
                        version: version
                    )
                },
                usingFiltered: { query, cursor, version, filters in
                    try await appModel.searchCatalog(
                        query: query,
                        cursor: cursor,
                        version: version,
                        filters: filters
                    )
                }
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
    let filters: CatalogFilters
    let cacheScope: String?
}

private struct SongFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filters: CatalogFilters
    let options: CatalogFilterOptions
    let onApply: (CatalogFilters) -> Void

    private let levelColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(
        filters: CatalogFilters,
        options: CatalogFilterOptions,
        onApply: @escaping (CatalogFilters) -> Void
    ) {
        _filters = State(initialValue: filters)
        self.options = options
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("SORT BY") {
                    Picker("Sort by", selection: $filters.sortBy) {
                        ForEach(CatalogSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("Direction", selection: $filters.sortDirection) {
                        ForEach(CatalogSortDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                }

                Section("LEVEL MATCHING") {
                    Picker("Match selected levels", selection: $filters.levelMode) {
                        Text("All").tag(CatalogLevelMode.and)
                        Text("Any").tag(CatalogLevelMode.or)
                    }
                    .pickerStyle(.segmented)
                }

                if !options.charts.isEmpty {
                    Section("CHART TYPE") {
                        ForEach(options.charts, id: \.self) { value in
                            filterRow(
                                label: chartLabel(value),
                                selected: filters.charts.contains(value)
                            ) {
                                toggle(value, at: \.charts)
                            }
                        }
                    }
                }

                if !options.levels.isEmpty {
                    Section("LEVEL") {
                        LazyVGrid(columns: levelColumns, spacing: 8) {
                            ForEach(options.levels, id: \.self) { value in
                                FilterChip(
                                    label: value.uppercased(),
                                    selected: filters.levels.contains(value)
                                ) {
                                    toggle(value, at: \.levels)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !options.folders.isEmpty {
                    Section {
                        NavigationLink {
                            MultiSelectFilterView(
                                title: "Folders",
                                options: options.folders,
                                selection: $filters.folders
                            )
                        } label: {
                            filterNavigationLabel("Folder", count: filters.folders.count)
                        }
                    }
                }

                if !options.series.isEmpty {
                    Section {
                        NavigationLink {
                            MultiSelectFilterView(
                                title: "Series",
                                options: options.series,
                                selection: $filters.series
                            )
                        } label: {
                            filterNavigationLabel("Series", count: filters.series.count)
                        }
                    }
                }
            }
            .navigationTitle("Sort and filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filters.clearSelections()
                    }
                    .disabled(filters.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(filters)
                        dismiss()
                    }
                }
            }
        }
    }

    private func filterRow(
        label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    private func filterNavigationLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            if count > 0 {
                Text(count.formatted())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chartLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "singles": "Singles"
        case "doubles": "Doubles"
        case "co-op": "Co-op"
        default: value.uppercased()
        }
    }

    private func toggle(
        _ value: String,
        at keyPath: WritableKeyPath<CatalogFilters, [String]>
    ) {
        var values = filters[keyPath: keyPath]
        if let index = values.firstIndex(of: value) {
            values.remove(at: index)
        } else {
            values.append(value)
        }
        filters[keyPath: keyPath] = values
    }
}

private struct MultiSelectFilterView: View {
    let title: String
    let options: [String]
    @Binding var selection: [String]

    var body: some View {
        List(options, id: \.self) { value in
            Button {
                if let index = selection.firstIndex(of: value) {
                    selection.remove(at: index)
                } else {
                    selection.append(value)
                }
            } label: {
                HStack {
                    Text(value)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if selection.contains(value) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold().monospaced())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : AppTheme.ink)
                .background(selected ? AppTheme.levelBadgeBackground : AppTheme.pageBackground)
                .overlay(Rectangle().stroke(selected ? AppTheme.levelBadgeBackground : AppTheme.border))
        }
        .buttonStyle(.plain)
    }
}

private struct CatalogSongRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let song: CatalogSong

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            CatalogArtwork(url: song.imageURL, size: 68)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(song.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    if song.isPremium {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(AppTheme.warning)
                            .accessibilityLabel("Premium")
                    }
                }
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                HStack(spacing: 5) {
                    ForEach(Array(song.chartSummary.prefix(6)), id: \.self) { token in
                        let recommended = song.recommendedChartToken?.caseInsensitiveCompare(token) == .orderedSame
                        Text(token)
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(recommended ? AppTheme.positive : .secondary)
                            .padding(.horizontal, recommended ? 5 : 0)
                            .padding(.vertical, recommended ? 2 : 0)
                            .background(
                                recommended ? AppTheme.positive.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                            .accessibilityLabel(recommended ? "\(token), recommended" : token)
                    }
                }
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                if let folderLabel = song.folderLabel {
                    Text(folderLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
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
        CachedRemoteImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            artworkPlaceholder(systemImage: "music.note")
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
