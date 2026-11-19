import SwiftUI

struct DashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var songCatalog: SongCatalogModel

    var body: some View {
        Group {
            if let performance = model.performance, performance.profile != nil {
                dashboard(performance)
            } else if let snapshot = model.snapshot {
                dashboard(snapshot)
            } else if model.state == .signedOut {
                ContentUnavailableView(
                    "Connect PIUGAME",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Open Account to connect and load your performance.")
                )
            } else if case .failed(let message) = model.state {
                ContentUnavailableView(
                    "Sync failed",
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                    description: Text(message)
                )
            } else {
                ProgressView("Loading performance")
            }
        }
        .navigationTitle("MyPIU")
    }

    private func dashboard(_ performance: MyPIUPerformanceDashboard) -> some View {
        let snapshotPlays = model.snapshot?.recentPlays ?? []
        let pumbilityScore = performance.profile?.pumbilityScore ?? model.snapshot?.profile.pumbilityScore

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                dashboardHeader(
                    displayName: performance.profile?.displayName ?? model.myPIUAccount?.displayUsername ?? "MyPIU",
                    version: model.myPIUAccount?.piuGameVersion.displayName ?? model.selectedVersion.displayName
                )

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    NavigationLink {
                        PumbilityBreakdownView(
                            performance: performance,
                            pumbilityScore: pumbilityScore
                        )
                    } label: {
                        MetricTile(
                            title: "Pumbility",
                            value: format(pumbilityScore),
                            detail: changeLabel(performance.totals.pumbilityChange24Hours),
                            icon: "chart.line.uptrend.xyaxis",
                            tint: AppTheme.positive
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the Pumbility chart breakdown")

                    NavigationLink {
                        RecommendationSongsView()
                    } label: {
                        MetricTile(
                            title: "Average best",
                            value: format(performance.totals.averageBestScore),
                            detail: changeLabel(performance.totals.averageBestScoreChange24Hours),
                            icon: "chart.bar.xaxis",
                            tint: AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows recommended charts")

                    MetricTile(
                        title: "Upscores",
                        value: format(performance.totals.upscoresThisWeek),
                        detail: "This week",
                        icon: "bolt.fill",
                        tint: AppTheme.warning
                    )

                    NavigationLink {
                        PerformanceSessionsView()
                    } label: {
                        MetricTile(
                            title: "Recent session",
                            value: format(performance.totals.recentlyPlayed),
                            detail: "Plays",
                            icon: "clock.arrow.circlepath",
                            tint: AppTheme.ink
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows play session history")
                }

                dashboardSection(title: "RECENT PLAYS", detail: "View all in Sessions") {
                    let recentPlays = Array(performance.recentPlays.prefix(5))
                    if recentPlays.isEmpty {
                        Text("No recent plays yet.")
                            .foregroundStyle(AppTheme.mutedInk)
                    } else {
                        ForEach(recentPlays) { play in
                            let snapshotPlay = matchingRecentPlay(for: play, in: snapshotPlays)
                            let presentation = RecentPlayPresentation(
                                play: play,
                                snapshotPlay: snapshotPlay,
                                catalogImageURL: songCatalog.artworkURL(for: play.songName)
                            )
                            NavigationLink {
                                RecentPlayDetailView(play: presentation)
                            } label: {
                                RecentPlayRowContent(play: presentation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows score and judgment details")
                            if play.id != recentPlays.last?.id { Divider() }
                        }
                    }
                }

                dashboardSection(title: "TOP TRACKED CHARTS") {
                    let charts = Array(performance.topCharts.prefix(5))
                    if charts.isEmpty {
                        Text("No tracked chart bests yet.")
                            .foregroundStyle(AppTheme.mutedInk)
                    } else {
                        ForEach(charts) { chart in
                            PerformanceChartRow(chart: chart)
                            if chart.id != charts.last?.id { Divider() }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .refreshable { await model.refresh() }
    }

    private func dashboard(_ snapshot: PIUSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                dashboardHeader(
                    displayName: snapshot.profile.displayName,
                    version: snapshot.version.displayName
                )

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    MetricTile(
                        title: "Pumbility",
                        value: format(snapshot.profile.pumbilityScore),
                        detail: nil,
                        icon: "chart.line.uptrend.xyaxis",
                        tint: AppTheme.positive
                    )
                    MetricTile(
                        title: "Rating",
                        value: format(snapshot.profile.rating),
                        detail: nil,
                        icon: "gauge.with.dots.needle.50percent",
                        tint: AppTheme.info
                    )
                    MetricTile(
                        title: "Plays",
                        value: format(snapshot.profile.playCount),
                        detail: nil,
                        icon: "figure.run",
                        tint: AppTheme.ink
                    )
                    MetricTile(
                        title: "Clears",
                        value: format(snapshot.profile.clearCount),
                        detail: nil,
                        icon: "checkmark.circle",
                        tint: AppTheme.warning
                    )
                }

                dashboardSection(title: "RECENT PLAYS", detail: "Tap a play for judgments") {
                    let recentPlays = Array(snapshot.recentPlays.prefix(5))
                    if recentPlays.isEmpty {
                        Text("No recent plays yet.")
                            .foregroundStyle(AppTheme.mutedInk)
                    } else {
                        ForEach(recentPlays) { play in
                            NavigationLink {
                                RecentPlayDetailView(play: RecentPlayPresentation(play: play))
                            } label: {
                                RecentPlayRow(play: play)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows score and judgment details")
                            if play.id != recentPlays.last?.id { Divider() }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .refreshable { await model.refresh() }
    }

    private func dashboardHeader(displayName: String, version: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PERFORMANCE")
                    .font(.caption.bold())
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.mutedInk)
                Spacer()
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
            }
            Text(displayName)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(AppTheme.ink)
            Text("Your \(version) play data, progress, and latest results.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .websiteCard()
        .accessibilityElement(children: .combine)
    }

    private func dashboardSection<Content: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WebsiteSectionTitle(title: title, detail: detail)
            content()
        }
        .padding(16)
        .websiteCard()
    }

    private func format(_ value: Int?) -> String {
        value.map { $0.formatted() } ?? "-"
    }

    private func format(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "-"
    }

    private func changeLabel(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "\(value >= 0 ? "+" : "")\(format(value)) / 24h"
    }

    private var metricColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String?
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline.bold())
                    .foregroundStyle(tint)
                Text(value)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title.uppercased())
                    .font(.caption.bold())
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .websiteCard()
        .accessibilityElement(children: .combine)
    }
}

struct PerformanceRecentPlayRow: View {
    let play: MyPIUPerformanceDashboard.Play
    var snapshotPlay: RecentPlay?

    init(play: MyPIUPerformanceDashboard.Play, snapshotPlay: RecentPlay? = nil) {
        self.play = play
        self.snapshotPlay = snapshotPlay
    }

    var body: some View {
        RecentPlayRowContent(play: RecentPlayPresentation(play: play, snapshotPlay: snapshotPlay))
    }
}

struct RecentPlayRow: View {
    let play: RecentPlay

    var body: some View {
        RecentPlayRowContent(play: RecentPlayPresentation(play: play))
    }
}

private struct RecentPlayRowContent: View {
    let play: RecentPlayPresentation

    var body: some View {
        HStack(spacing: 12) {
            SongArtwork(url: play.songImageURL, size: 62)
            VStack(alignment: .leading, spacing: 5) {
                Text(play.songName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    ChartTokenBadge(chartToken: play.chartToken)
                    Text(performanceDateLabel(play.playedAt))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(play.isFailed ? "FAILED" : (play.score?.formatted() ?? "-"))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(play.isFailed ? AppTheme.danger : AppTheme.ink)
                Text(performanceGradeLabel(play.grade))
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.mutedInk)
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(play.songName)
        .accessibilityValue(
            [
                performanceChartTokenAccessibilityLabel(play.chartToken),
                performanceGradeLabel(play.grade),
                play.isFailed ? "Failed" : (play.score?.formatted() ?? "Score unavailable"),
                performanceDateLabel(play.playedAt)
            ].joined(separator: ", ")
        )
    }
}

struct PerformanceChartRow: View {
    let chart: MyPIUPerformanceDashboard.Chart

    var body: some View {
        HStack(spacing: 12) {
            if let rank = chart.topPlayRank {
                Text("#\(rank)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(minWidth: 30, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(chart.songName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(performanceGradeLabel(chart.bestGrade))
                    if let delta = chart.delta, delta > 0 {
                        Text("+\(delta.formatted())")
                            .foregroundStyle(AppTheme.positive)
                    }
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.mutedInk)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                ChartTokenBadge(chartToken: chart.displayChartToken)
                Text(chart.bestScore?.formatted() ?? "-")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chart.songName)
        .accessibilityValue(performanceChartAccessibilityValue(chart))
    }
}

struct ChartTokenBadge: View {
    let chartToken: String

    var body: some View {
        Text(chartToken)
            .font(.caption.bold().monospaced())
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppTheme.levelBadgeBackground)
            .foregroundStyle(.white)
            .accessibilityLabel(performanceChartTokenAccessibilityLabel(chartToken))
    }
}

func performanceGradeLabel(_ value: String?) -> String {
    var grade = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if grade.hasPrefix("x_") { grade.removeFirst(2) }
    guard !grade.isEmpty else { return "Played" }
    let isPlus = grade.hasSuffix("_p")
    if isPlus { grade.removeLast(2) }
    return grade.replacingOccurrences(of: "_", with: " ").uppercased() + (isPlus ? "+" : "")
}

func performancePlayIsFailed(grade: String?, stageBreak: Bool) -> Bool {
    stageBreak || grade?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("x_") == true
}

func performanceChartTokenAccessibilityLabel(_ token: String) -> String {
    let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let prefix = normalized.first, normalized.count > 1 else { return token }
    var level = String(normalized.dropFirst())
    let isPlus = level.hasSuffix("+")
    if isPlus {
        level.removeLast()
    }
    guard !level.isEmpty, level.allSatisfy({ $0.isNumber }) else { return token }
    let spokenLevel = level + (isPlus ? " plus" : "")
    switch prefix {
    case "S": return "Single level \(spokenLevel)"
    case "D": return "Double level \(spokenLevel)"
    case "C": return "Co-op level \(spokenLevel)"
    default: return token
    }
}

func performanceChartAccessibilityValue(_ chart: MyPIUPerformanceDashboard.Chart) -> String {
    var parts: [String] = []
    if let rank = chart.topPlayRank {
        parts.append("Rank \(rank)")
    }
    parts.append(performanceChartTokenAccessibilityLabel(chart.displayChartToken))
    parts.append(performanceGradeLabel(chart.bestGrade))
    parts.append(chart.bestScore?.formatted() ?? "Score unavailable")
    if let delta = chart.delta, delta > 0 {
        parts.append("Improved by \(delta.formatted())")
    }
    return parts.joined(separator: ", ")
}

func performanceDateLabel(_ value: String?) -> String {
    guard let value else { return "Time unavailable" }
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    let standard = Date.ISO8601FormatStyle()
    guard let date = (try? fractional.parse(value)) ?? (try? standard.parse(value)) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
}
