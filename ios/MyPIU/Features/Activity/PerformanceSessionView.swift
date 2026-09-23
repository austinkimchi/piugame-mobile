import SwiftUI

struct PerformanceSessionsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var songCatalog: SongCatalogModel
    @State private var state: LoadState = .idle
    @State private var sessions: [MyPIUPerformanceSession] = []
    @State private var nextOffset: Int?
    @State private var isLoadingMore = false
    @State private var paginationError: String?

    var body: some View {
        Group {
            if appModel.catalogCacheScope?.hasPrefix("account:") != true {
                ContentUnavailableView(
                    "Connect MyPIU",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Session history is available after you connect your MyPIU account.")
                )
            } else {
                loadedContent
            }
        }
        .navigationTitle("Sessions")
        .task(id: appModel.catalogCacheScope) {
            await load()
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch state {
        case .idle where sessions.isEmpty,
             .loading where sessions.isEmpty:
            ProgressView("Loading sessions")
        case .failed(let message) where sessions.isEmpty:
            ContentUnavailableView {
                Label("Sessions unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task { await load() }
                }
            }
        default:
            if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock.arrow.circlepath")
            } else {
                List {
                    ForEach(sessions) { session in
                        SessionRow(
                            session: session,
                            snapshotPlays: appModel.snapshot?.recentPlays ?? [],
                            catalogArtworkURL: songCatalog.artworkURL
                        )
                        .task {
                            await loadMoreIfNeeded(after: session)
                        }
                    }

                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else if paginationError != nil {
                        Button("Retry loading more", systemImage: "arrow.clockwise") {
                            Task { await loadMore() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.pageBackground)
                .refreshable { await load() }
            }
        }
    }

    @MainActor
    private func load() async {
        guard let scope = appModel.catalogCacheScope, scope.hasPrefix("account:") else {
            sessions = []
            nextOffset = nil
            paginationError = nil
            state = .idle
            return
        }

        state = .loading
        do {
            let page = try await appModel.performanceSessions()
            try Task.checkCancellation()
            guard appModel.catalogCacheScope == scope else { return }
            sessions = page.sessions
            nextOffset = page.nextOffset
            paginationError = nil
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard appModel.catalogCacheScope == scope else { return }
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func loadMoreIfNeeded(after session: MyPIUPerformanceSession) async {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }),
              index >= max(0, sessions.count - 4) else { return }
        await loadMore()
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore,
              let offset = nextOffset,
              let scope = appModel.catalogCacheScope,
              scope.hasPrefix("account:") else { return }

        isLoadingMore = true
        paginationError = nil
        defer { isLoadingMore = false }

        do {
            let page = try await appModel.performanceSessions(offset: offset)
            try Task.checkCancellation()
            guard appModel.catalogCacheScope == scope else { return }
            var knownIDs = Set(sessions.map(\.id))
            sessions.append(contentsOf: page.sessions.filter { knownIDs.insert($0.id).inserted })
            nextOffset = page.nextOffset == offset ? nil : page.nextOffset
        } catch is CancellationError {
            return
        } catch {
            guard appModel.catalogCacheScope == scope else { return }
            paginationError = error.localizedDescription
        }
    }
}

struct PerformanceSessionView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var songCatalog: SongCatalogModel
    let session: MyPIUPerformanceSession
    private let initiallyPresentedPlayID: String?
    @State private var presentedPlayID: String?
    @State private var didPresentInitialPlay = false

    init(session: MyPIUPerformanceSession, initiallyPresentedPlayID: String? = nil) {
        self.session = session
        self.initiallyPresentedPlayID = initiallyPresentedPlayID
        _presentedPlayID = State(initialValue: nil)
    }

    var body: some View {
        List {
            if let arcadeName = session.arcadeName, !arcadeName.isEmpty {
                Section {
                    Label(arcadeName, systemImage: "mappin.and.ellipse")
                }
            }

            Section("Summary") {
                clearSummaryRow
                summaryRow("Average score", value: scoreLabel(session.summary.averageScore))
                summaryRow("Best score", value: scoreLabel(session.summary.bestScore))
                summaryRow("Unique charts", value: session.summary.distinctCharts.formatted())
                summaryRow("Duration", value: durationLabel(session.summary.durationMinutes))
            }

            Section("Plays (\(playModeSummary(session.plays)))") {
                ForEach(session.plays) { play in
                    let snapshotPlay = matchingRecentPlay(
                        for: play,
                        in: appModel.snapshot?.recentPlays ?? []
                    )
                    NavigationLink {
                        RecentPlayDetailView(
                            play: RecentPlayPresentation(
                                play: play,
                                snapshotPlay: snapshotPlay,
                                catalogImageURL: songCatalog.artworkURL(for: play.songName)
                            )
                        )
                    } label: {
                        PerformanceRecentPlayRow(play: play, snapshotPlay: snapshotPlay)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(sessionDayLabel(session.summary.endedAt))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didPresentInitialPlay, let initiallyPresentedPlayID else { return }
            didPresentInitialPlay = true
            Task { @MainActor in
                await Task.yield()
                presentedPlayID = initiallyPresentedPlayID
            }
        }
        .navigationDestination(isPresented: playDestinationIsPresented) {
            if let play = presentedPlay {
                RecentPlayDetailView(
                    play: RecentPlayPresentation(
                        play: play,
                        snapshotPlay: matchingRecentPlay(
                            for: play,
                            in: appModel.snapshot?.recentPlays ?? []
                        ),
                        catalogImageURL: songCatalog.artworkURL(for: play.songName)
                    )
                )
            }
        }
    }

    private var presentedPlay: MyPIUPerformanceDashboard.Play? {
        guard let presentedPlayID else { return nil }
        return session.plays.first { $0.id == presentedPlayID }
    }

    private var playDestinationIsPresented: Binding<Bool> {
        Binding(
            get: { presentedPlay != nil },
            set: { isPresented in
                if !isPresented { presentedPlayID = nil }
            }
        )
    }

    private var clearSummaryRow: some View {
        LabeledContent("Clear") {
            HStack(spacing: 0) {
                Text("\(session.summary.clearCount.formatted())/\(session.summary.playCount.formatted()) (")
                Text(percentLabel(session.summary.clearRate))
                    .foregroundStyle(clearRateTint(session.summary.clearRate))
                Text(")")
            }
            .font(.body.weight(.semibold).monospacedDigit())
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
        }
    }
}

private struct SessionRow: View {
    let session: MyPIUPerformanceSession
    let snapshotPlays: [RecentPlay]
    let catalogArtworkURL: (String) -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                PerformanceSessionView(session: session)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(sessionTimestampLabel(session.summary.endedAt))
                        .font(.headline)
                    if let arcadeName = session.arcadeName, !arcadeName.isEmpty {
                        Label(arcadeName, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("Clear \(session.summary.clearCount.formatted())/\(session.summary.playCount.formatted())")
                        Text("(\(percentLabel(session.summary.clearRate)))")
                            .foregroundStyle(clearRateTint(session.summary.clearRate))
                        Text("· \(playModeSummary(session.plays))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the complete session")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(session.plays) { play in
                        let snapshotPlay = matchingRecentPlay(for: play, in: snapshotPlays)
                        NavigationLink {
                            PerformanceSessionView(
                                session: session,
                                initiallyPresentedPlayID: play.id
                            )
                        } label: {
                            SessionPlayArtwork(
                                play: play,
                                snapshotPlay: snapshotPlay,
                                catalogImageURL: catalogArtworkURL(play.songName)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this play inside the session")
                    }
                }
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, 7)
    }
}

private struct SessionPlayArtwork: View {
    let play: MyPIUPerformanceDashboard.Play
    let snapshotPlay: RecentPlay?
    let catalogImageURL: URL?

    var body: some View {
        VStack(spacing: 4) {
            SongArtwork(
                url: play.songImageURL ?? snapshotPlay?.songImageURL ?? catalogImageURL,
                size: 56
            )
            Text(play.displayChartToken)
                .font(.caption2.bold().monospaced())
                .foregroundStyle(AppTheme.mutedInk)
                .lineLimit(1)
        }
        .frame(width: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(play.songName), \(performanceChartTokenAccessibilityLabel(play.displayChartToken))")
    }
}

private enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

private func scoreLabel(_ score: Int?) -> String {
    score?.formatted() ?? "-"
}

private func percentLabel(_ percent: Double?) -> String {
    guard let percent else { return "-" }
    return percent.formatted(.number.precision(.fractionLength(0))) + "%"
}

private func clearRateTint(_ percent: Double?) -> Color {
    guard let percent else { return .secondary }
    return percent >= 80 ? AppTheme.positive : (percent < 50 ? AppTheme.danger : AppTheme.warning)
}

private func durationLabel(_ minutes: Int) -> String {
    let safeMinutes = max(0, minutes)
    let hours = safeMinutes / 60
    let remainingMinutes = safeMinutes % 60
    if hours == 0 { return "\(remainingMinutes) min" }
    if remainingMinutes == 0 { return "\(hours) hr" }
    return "\(hours) hr \(remainingMinutes) min"
}

private func playModeSummary(_ plays: [MyPIUPerformanceDashboard.Play]) -> String {
    var singles = 0
    var doubles = 0
    var coops = 0
    var other = 0

    for play in plays {
        switch play.mode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().first {
        case "s": singles += 1
        case "d": doubles += 1
        case "c": coops += 1
        default: other += 1
        }
    }

    let parts = [
        modeCount(singles, singular: "single", plural: "singles"),
        modeCount(doubles, singular: "double", plural: "doubles"),
        modeCount(coops, singular: "co-op", plural: "co-op"),
        modeCount(other, singular: "other", plural: "other"),
    ].compactMap { $0 }
    return parts.isEmpty ? "0 plays" : parts.joined(separator: ", ")
}

private func modeCount(_ count: Int, singular: String, plural: String) -> String? {
    guard count > 0 else { return nil }
    return "\(count.formatted()) \(count == 1 ? singular : plural)"
}

private func sessionDate(_ value: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private func sessionDayLabel(_ value: String) -> String {
    guard let date = sessionDate(value) else { return "Session" }
    return date.formatted(.dateTime.month(.abbreviated).day().year())
}

private func sessionTimestampLabel(_ value: String) -> String {
    guard let date = sessionDate(value) else { return "Session" }
    return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}
