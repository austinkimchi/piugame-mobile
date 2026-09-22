import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
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

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(title: "Pumbility", value: format(snapshot.profile.pumbilityScore), icon: "chart.line.uptrend.xyaxis", tint: AppTheme.positive)
                    MetricTile(title: "Rating", value: format(snapshot.profile.rating), icon: "gauge.with.dots.needle.50percent", tint: AppTheme.accent)
                    MetricTile(title: "Plays", value: format(snapshot.profile.playCount), icon: "figure.run", tint: .blue)
                    MetricTile(title: "Clears", value: format(snapshot.profile.clearCount), icon: "checkmark.circle", tint: AppTheme.warning)
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
}

private struct MetricTile: View {
    let title: String
    let value: String
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
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
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
