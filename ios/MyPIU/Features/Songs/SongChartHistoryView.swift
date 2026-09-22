import SwiftUI

struct SongChartHistoryView: View {
    @EnvironmentObject private var appModel: AppModel
    let song: CatalogSong
    let chartToken: String
    let version: PIUGameVersion

    @State private var state: LoadState = .idle
    @State private var performance: MyPIUSongChartPerformance?
    @State private var loadedRequest: Request?
    @State private var refreshID = UUID()

    var body: some View {
        Group {
            if request.accountScope?.hasPrefix("account:") != true {
                ContentUnavailableView(
                    "Connect MyPIU",
                    systemImage: "person.crop.circle.badge.plus"
                )
            } else if loadedRequest != request {
                ProgressView("Loading chart history")
            } else {
                loadedContent
            }
        }
        .navigationTitle(chartToken)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appModel.isMyPIUConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshID = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(state == .loading)
                    .accessibilityLabel("Refresh chart history")
                }
            }
        }
        .task(id: request) {
            await load(request)
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading chart history")
        case .failed(let message):
            ContentUnavailableView {
                Label("History unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    refreshID = UUID()
                }
            }
        case .loaded:
            if let performance {
                historyList(performance)
            } else {
                ContentUnavailableView(
                    "No tracked plays",
                    systemImage: "chart.bar.doc.horizontal"
                )
            }
        }
    }

    private func historyList(_ performance: MyPIUSongChartPerformance) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ChartTokenBadge(chartToken: chartToken)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(version.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            if let stats = performance.stats {
                let latestFailed = performance.latestPlay.map {
                    performancePlayIsFailed(grade: $0.grade, stageBreak: $0.stageBreak)
                } ?? stats.latestStageBreak
                Section("Summary") {
                    summaryRow("Best score", value: scoreLabel(stats.bestScore))
                    summaryRow(
                        "Latest score",
                        value: latestFailed ? "FAILED" : scoreLabel(stats.latestScore),
                        tint: latestFailed ? AppTheme.accent : nil
                    )
                    summaryRow("Tracked attempts", value: stats.recentPlayCount.formatted())
                    summaryRow("Stage breaks", value: stats.stageBreakCount.formatted())
                }
            }

            Section("Attempts") {
                if performance.history.isEmpty {
                    ContentUnavailableView(
                        "No recent attempts",
                        systemImage: "clock"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(performance.attemptsNewestFirst) { attempt in
                        ChartAttemptRow(attempt: attempt)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            refreshID = UUID()
        }
    }

    @ViewBuilder
    private func summaryRow(_ title: String, value: String, tint: Color? = nil) -> some View {
        LabeledContent(title) {
            if let tint {
                Text(value)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            } else {
                Text(value)
                    .font(.body.weight(.semibold).monospacedDigit())
            }
        }
    }

    private func scoreLabel(_ score: Int?) -> String {
        score?.formatted() ?? "-"
    }

    @MainActor
    private func load(_ request: Request) async {
        guard request.accountScope?.hasPrefix("account:") == true else {
            performance = nil
            state = .idle
            loadedRequest = request
            return
        }

        performance = nil
        state = .loading
        do {
            let performance = try await appModel.chartPerformance(
                songSlug: request.songSlug,
                chartToken: request.chartToken,
                version: request.version
            )
            try Task.checkCancellation()
            guard self.request == request else { return }
            self.performance = performance
            state = .loaded
            loadedRequest = request
        } catch is CancellationError {
            return
        } catch {
            guard self.request == request else { return }
            performance = nil
            state = .failed(error.localizedDescription)
            loadedRequest = request
        }
    }

    private var request: Request {
        Request(
            songSlug: song.slug,
            chartToken: chartToken,
            version: version,
            accountScope: appModel.catalogCacheScope,
            refreshID: refreshID
        )
    }
}

private extension SongChartHistoryView {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct Request: Hashable {
        let songSlug: String
        let chartToken: String
        let version: PIUGameVersion
        let accountScope: String?
        let refreshID: UUID
    }
}

private struct ChartAttemptRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let attempt: MyPIUSongChartPerformance.Attempt

    var body: some View {
        let failed = performancePlayIsFailed(grade: attempt.grade, stageBreak: attempt.stageBreak)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(performanceGradeLabel(attempt.grade))
                        .font(.body.weight(.semibold))
                    Text(performanceDateLabel(attempt.playedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(failed ? "FAILED" : attempt.score?.formatted() ?? "-")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(failed ? AppTheme.accent : .primary)
            }

            let judgments = judgmentValues
            if !judgments.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 88 : 48),
                            spacing: 8
                        )
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(judgments) { judgment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(judgment.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(judgment.value.formatted())
                                .font(.caption.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var judgmentValues: [JudgmentValue] {
        [
            attempt.judgments.perfect.map { JudgmentValue(label: "Perfect", value: $0) },
            attempt.judgments.great.map { JudgmentValue(label: "Great", value: $0) },
            attempt.judgments.good.map { JudgmentValue(label: "Good", value: $0) },
            attempt.judgments.bad.map { JudgmentValue(label: "Bad", value: $0) },
            attempt.judgments.miss.map { JudgmentValue(label: "Miss", value: $0) }
        ].compactMap { $0 }
    }
}

private struct JudgmentValue: Identifiable {
    let label: String
    let value: Int

    var id: String { label }
}
