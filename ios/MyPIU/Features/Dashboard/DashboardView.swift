import SwiftUI

struct DashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: AppModel

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
                ContentUnavailableView("Sync failed", systemImage: "exclamationmark.arrow.triangle.2.circlepath", description: Text(message))
            } else {
                ProgressView("Loading performance")
            }
        }
        .navigationTitle("MyPIU")
        .toolbar {
            if model.isConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.state == .syncing)
                    .accessibilityLabel("Refresh performance")
                }
            }
        }
    }

    private func dashboard(_ performance: MyPIUPerformanceDashboard) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(performance.profile?.displayName ?? model.myPIUAccount?.name ?? "MyPIU")
                        .font(.title2.bold())
                    Text(model.myPIUAccount?.piuGameVersion.displayName ?? model.selectedVersion.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    NavigationLink {
                        PumbilityBreakdownView(performance: performance)
                    } label: {
                        MetricTile(
                            title: "Pumbility",
                            value: format(performance.profile?.pumbilityScore),
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
                            tint: AppTheme.accent
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
                        PerformanceSessionView()
                    } label: {
                        MetricTile(
                            title: "Recent session",
                            value: format(performance.totals.recentlyPlayed),
                            detail: "Plays",
                            icon: "clock.arrow.circlepath",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the latest play session summary")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recently played")
                        .font(.headline)
                    ForEach(Array(performance.recentPlays.prefix(5))) { play in
                        PerformanceRecentPlayRow(play: play)
                        if play.id != performance.recentPlays.prefix(5).last?.id { Divider() }
                    }
                }
            }
            .padding()
        }
        .refreshable { await model.refresh() }
    }

    private func dashboard(_ snapshot: PIUSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.profile.displayName)
                        .font(.title2.bold())
                    Text(snapshot.version.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    MetricTile(title: "Pumbility", value: format(snapshot.profile.pumbilityScore), detail: nil, icon: "chart.line.uptrend.xyaxis", tint: AppTheme.positive)
                    MetricTile(title: "Rating", value: format(snapshot.profile.rating), detail: nil, icon: "gauge.with.dots.needle.50percent", tint: AppTheme.accent)
                    MetricTile(title: "Plays", value: format(snapshot.profile.playCount), detail: nil, icon: "figure.run", tint: .blue)
                    MetricTile(title: "Clears", value: format(snapshot.profile.clearCount), detail: nil, icon: "checkmark.circle", tint: AppTheme.warning)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recently played")
                        .font(.headline)
                    ForEach(snapshot.recentPlays.prefix(5)) { play in
                        RecentPlayRow(play: play)
                        if play.id != snapshot.recentPlays.prefix(5).last?.id { Divider() }
                    }
                }
            }
            .padding()
        }
        .refreshable { await model.refresh() }
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
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct PerformanceRecentPlayRow: View {
    let play: MyPIUPerformanceDashboard.Play

    var body: some View {
        let failed = performancePlayIsFailed(grade: play.grade, stageBreak: play.stageBreak)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(play.songName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("\(performanceGradeLabel(play.grade)) / \(performanceDateLabel(play.playedAt))")
                    .font(.caption)
                    .foregroundStyle(failed ? AppTheme.accent : .secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                ChartTokenBadge(chartToken: play.displayChartToken)
                Text(failed ? "FAILED" : play.score?.formatted() ?? "-")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(failed ? AppTheme.accent : .primary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(play.songName)
        .accessibilityValue(
            [
                performanceChartTokenAccessibilityLabel(play.displayChartToken),
                performanceGradeLabel(play.grade),
                failed ? "Failed" : (play.score?.formatted() ?? "Score unavailable"),
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
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(chart.songName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(performanceGradeLabel(chart.bestGrade))
                    if let delta = chart.delta, delta > 0 {
                        Text("+\(delta.formatted())")
                            .foregroundStyle(AppTheme.positive)
                    }
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                ChartTokenBadge(chartToken: chart.displayChartToken)
                Text(chart.bestScore?.formatted() ?? "-")
                    .font(.caption.weight(.semibold).monospacedDigit())
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
            .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 4))
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
    let level = normalized.dropFirst()
    switch prefix {
    case "S": return "Single level \(level)"
    case "D": return "Double level \(level)"
    case "C": return "Co-op level \(level)"
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

struct RecentPlayRow: View {
    let play: RecentPlay

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(play.songName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(play.playedAt ?? "Time unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(play.chartToken)
                    .font(.caption.bold().monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                Text(play.stageBreak ? "FAILED" : play.score?.formatted() ?? "-")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(play.stageBreak ? AppTheme.accent : .primary)
            }
        }
        .padding(.vertical, 4)
    }
}
