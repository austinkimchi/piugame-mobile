import SwiftUI

struct PlayerProgressView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let performance = model.performance, let profile = performance.profile {
                performanceContent(performance, profile: profile)
            } else if let snapshot = model.snapshot {
                snapshotContent(snapshot)
            } else if model.isMyPIUConnected || model.isConnected {
                ContentUnavailableView(
                    "Progress unavailable",
                    systemImage: "chart.pie",
                    description: Text("Refresh your performance to load progress.")
                )
            } else {
                ContentUnavailableView(
                    "Connect PIUGAME",
                    systemImage: "link",
                    description: Text("Open Account to start tracking progress.")
                )
            }
        }
        .navigationTitle("Progress")
        .toolbar {
            if model.isConnected || model.isMyPIUConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.state == .syncing || model.performanceState == .loading)
                    .accessibilityLabel("Refresh progress")
                }
            }
        }
    }

    private func performanceContent(
        _ performance: MyPIUPerformanceDashboard,
        profile: MyPIUPerformanceDashboard.Profile
    ) -> some View {
        let summary = PerformanceProgressSummary(profile: profile)
        let pumbilityScore = profile.pumbilityScore ?? model.snapshot?.profile.pumbilityScore
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                completionPanel(summary, displayName: profile.displayName)

                progressSection("Score health") {
                    metricGrid([
                        ProgressMetric(
                            title: "Pumbility",
                            value: format(pumbilityScore),
                            detail: changeLabel(performance.totals.pumbilityChange24Hours),
                            icon: "chart.line.uptrend.xyaxis",
                            tint: AppTheme.positive
                        ),
                        ProgressMetric(
                            title: "Average best",
                            value: format(performance.totals.averageBestScore),
                            detail: changeLabel(performance.totals.averageBestScoreChange24Hours),
                            icon: "chart.bar.xaxis",
                            tint: AppTheme.accent
                        )
                    ])

                    NavigationLink {
                        PumbilityBreakdownView(
                            performance: performance,
                            pumbilityScore: pumbilityScore
                        )
                    } label: {
                        Label("Pumbility breakdown", systemImage: "list.number")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                progressSection("Momentum") {
                    metricGrid([
                        ProgressMetric(title: "Today", value: format(performance.totals.upscoresToday), detail: "Upscored charts", icon: "bolt.fill", tint: AppTheme.warning),
                        ProgressMetric(title: "This week", value: format(performance.totals.upscoresThisWeek), detail: "Upscored charts", icon: "calendar", tint: .blue),
                        ProgressMetric(title: "This month", value: format(performance.totals.upscoresThisMonth), detail: "Upscored charts", icon: "calendar.badge.clock", tint: .indigo),
                        ProgressMetric(title: "All time", value: format(performance.totals.upscores), detail: "Upscored charts", icon: "trophy.fill", tint: AppTheme.positive)
                    ])
                }

                progressSection("Coverage") {
                    metricGrid([
                        ProgressMetric(title: "Tracked charts", value: format(performance.totals.trackedCharts), detail: "Saved chart bests", icon: "square.stack.3d.up", tint: .blue),
                        ProgressMetric(title: "Recent plays", value: format(performance.totals.trackedPlays), detail: "Stored attempts", icon: "clock.arrow.circlepath", tint: AppTheme.accent),
                        ProgressMetric(title: "Play count", value: format(summary.playCount), detail: "PIUGAME total", icon: "figure.run", tint: AppTheme.positive),
                        ProgressMetric(title: "Recent session", value: format(performance.totals.recentlyPlayed), detail: "Plays", icon: "play.circle", tint: AppTheme.warning)
                    ])
                }
            }
            .padding()
        }
        .refreshable { await model.refresh() }
    }

    private func snapshotContent(_ snapshot: PIUSnapshot) -> some View {
        let summary = PerformanceProgressSummary(profile: snapshot.profile)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                completionPanel(summary, displayName: snapshot.profile.displayName)
                progressSection("On-device snapshot") {
                    metricGrid([
                        ProgressMetric(title: "Pumbility", value: format(snapshot.profile.pumbilityScore), detail: nil, icon: "chart.line.uptrend.xyaxis", tint: AppTheme.positive),
                        ProgressMetric(title: "Rating", value: format(snapshot.profile.rating), detail: nil, icon: "gauge.with.dots.needle.50percent", tint: AppTheme.accent),
                        ProgressMetric(title: "Play count", value: format(summary.playCount), detail: nil, icon: "figure.run", tint: .blue),
                        ProgressMetric(title: "Recent plays", value: format(snapshot.recentPlays.count), detail: "On this device", icon: "clock.arrow.circlepath", tint: AppTheme.warning)
                    ])
                }
            }
            .padding()
        }
        .refreshable { await model.refresh() }
    }

    private func completionPanel(_ summary: PerformanceProgressSummary, displayName: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.headline)
                Text("Chart completion")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(percent(summary.completionPercent))
                    .font(.largeTitle.bold().monospacedDigit())
                Spacer()
                if let cleared = summary.clearedCharts, let total = summary.totalCharts {
                    Text("\(cleared.formatted()) / \(total.formatted())")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let fraction = summary.completionFraction {
                SwiftUI.ProgressView(value: fraction)
                    .tint(AppTheme.positive)
                    .accessibilityLabel("Chart completion")
                    .accessibilityValue(percent(summary.completionPercent))
            }

            if let remaining = summary.remainingCharts {
                Label("\(remaining.formatted()) charts remaining", systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func progressSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func metricGrid(_ metrics: [ProgressMetric]) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
            ),
            spacing: 10
        ) {
            ForEach(metrics) { metric in
                ProgressMetricTile(metric: metric)
            }
        }
    }

    private func format(_ value: Int?) -> String {
        value?.formatted() ?? "-"
    }

    private func format(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(0...2))) ?? "-"
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private func changeLabel(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "\(value >= 0 ? "+" : "")\(format(value)) / 24h"
    }
}

struct PumbilityBreakdownView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let performance: MyPIUPerformanceDashboard
    let pumbilityScore: Double?

    init(performance: MyPIUPerformanceDashboard, pumbilityScore: Double? = nil) {
        self.performance = performance
        self.pumbilityScore = pumbilityScore
    }

    private var charts: [MyPIUPerformanceDashboard.Chart] {
        performance.topCharts
            .filter { $0.topPumbilityScore != nil }
            .sorted { ($0.topPlayRank ?? .max) < ($1.topPlayRank ?? .max) }
    }

    private var chartContribution: Double {
        charts.compactMap(\.topPumbilityScore).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                metricLayout {
                    pumbilityMetric(
                        "Pumbility",
                        value: format(pumbilityScore ?? performance.profile?.pumbilityScore)
                    )
                    pumbilityMetric("Chart total", value: format(chartContribution))
                }

                if charts.isEmpty {
                    ContentUnavailableView("No Pumbility charts", systemImage: "chart.line.uptrend.xyaxis")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Contributing charts")
                            .font(.headline)
                        ForEach(charts) { chart in
                            PumbilityChartRow(chart: chart)
                            if chart.id != charts.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Pumbility")
    }

    private func metricLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout { content() }
    }

    private func pumbilityMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func format(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(0...2))) ?? "-"
    }
}

private struct PumbilityChartRow: View {
    let chart: MyPIUPerformanceDashboard.Chart

    var body: some View {
        HStack(spacing: 12) {
            Text(chart.topPlayRank.map { "#\($0)" } ?? "-")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(chart.songName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(chart.displayChartToken)
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(chart.topPumbilityScore?.formatted(.number.precision(.fractionLength(0...2))) ?? "-")
                    .font(.body.bold().monospacedDigit())
                Text(chart.bestScore?.formatted() ?? "-")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressMetric: Identifiable {
    let title: String
    let value: String
    let detail: String?
    let icon: String
    let tint: Color

    var id: String { title }
}

private struct ProgressMetricTile: View {
    let metric: ProgressMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: metric.icon)
                .foregroundStyle(metric.tint)
            Text(metric.value)
                .font(.title3.bold().monospacedDigit())
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let detail = metric.detail {
                Text(detail)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
