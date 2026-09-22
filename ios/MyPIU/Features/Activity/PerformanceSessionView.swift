import SwiftUI

struct PerformanceSessionView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var state: LoadState = .idle
    @State private var session: MyPIUPerformanceSession?
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
                ProgressView("Loading session")
            } else {
                loadedContent
            }
        }
        .navigationTitle("Recent Session")
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
                    .accessibilityLabel("Refresh recent session")
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
            ProgressView("Loading session")
        case .failed(let message):
            ContentUnavailableView {
                Label("Session unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    refreshID = UUID()
                }
            }
        case .loaded:
            if let session {
                sessionList(session)
            } else {
                ContentUnavailableView(
                    "No recent session",
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
    }

    private func sessionList(_ session: MyPIUPerformanceSession) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.myPIUAccount?.name ?? "MyPIU")
                        .font(.headline)
                    Text(sessionRange(session.summary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section("Summary") {
                summaryRow("Plays", value: session.summary.playCount.formatted())
                summaryRow("Clears", value: session.summary.clearCount.formatted())
                summaryRow(
                    "Clear rate",
                    value: percentLabel(session.summary.clearRate),
                    tint: clearRateTint(session.summary.clearRate)
                )
                summaryRow("Failures", value: session.summary.failedCount.formatted())
                summaryRow("Average clear", value: scoreLabel(session.summary.averageScore))
                summaryRow("Best score", value: scoreLabel(session.summary.bestScore))
                summaryRow("Unique charts", value: session.summary.distinctCharts.formatted())
                summaryRow("Duration", value: durationLabel(session.summary.durationMinutes))
            }

            Section("Plays") {
                ForEach(session.plays) { play in
                    PerformanceRecentPlayRow(play: play)
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

    private func percentLabel(_ percent: Double?) -> String {
        guard let percent else { return "-" }
        return percent.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func clearRateTint(_ percent: Double?) -> Color? {
        guard let percent else { return nil }
        return percent >= 80 ? AppTheme.positive : (percent < 50 ? AppTheme.accent : nil)
    }

    private func durationLabel(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60
        if hours == 0 {
            return "\(remainingMinutes) min"
        }
        if remainingMinutes == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainingMinutes) min"
    }

    private func sessionRange(_ summary: MyPIUPerformanceSession.Summary) -> String {
        "\(performanceDateLabel(summary.startedAt)) - \(performanceDateLabel(summary.endedAt))"
    }

    @MainActor
    private func load(_ request: Request) async {
        guard request.accountScope?.hasPrefix("account:") == true else {
            session = nil
            state = .idle
            loadedRequest = request
            return
        }

        session = nil
        state = .loading
        do {
            let session = try await appModel.performanceSession()
            try Task.checkCancellation()
            guard self.request == request else { return }
            self.session = session
            state = .loaded
            loadedRequest = request
        } catch is CancellationError {
            return
        } catch {
            guard self.request == request else { return }
            session = nil
            state = .failed(error.localizedDescription)
            loadedRequest = request
        }
    }

    private var request: Request {
        Request(accountScope: appModel.catalogCacheScope, refreshID: refreshID)
    }
}

private extension PerformanceSessionView {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct Request: Hashable {
        let accountScope: String?
        let refreshID: UUID
    }
}
