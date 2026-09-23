import SwiftUI

struct PerformanceSessionsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var state: LoadState = .idle
    @State private var sessions: [MyPIUPerformanceSession] = []

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
                List(sessions) { session in
                    NavigationLink {
                        PerformanceSessionView(session: session)
                    } label: {
                        SessionRow(session: session)
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
            state = .idle
            return
        }

        state = .loading
        do {
            let sessions = try await appModel.performanceSessions()
            try Task.checkCancellation()
            guard appModel.catalogCacheScope == scope else { return }
            self.sessions = sessions
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard appModel.catalogCacheScope == scope else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

struct PerformanceSessionView: View {
    @EnvironmentObject private var appModel: AppModel
    let session: MyPIUPerformanceSession

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
                            play: RecentPlayPresentation(play: play, snapshotPlay: snapshotPlay)
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

    var body: some View {
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
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
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
