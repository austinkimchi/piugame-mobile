import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @Binding private var section: Section

    enum Section: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case best = "Best"

        var id: String { rawValue }
    }

    init(section: Binding<Section>) {
        _section = section
    }

    var body: some View {
        Group {
            if let performance = model.performance {
                VStack(spacing: 0) {
                    Picker("Activity", selection: $section) {
                        ForEach(Section.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    switch section {
                    case .recent:
                        performanceList(performance.recentPlays)
                    case .best:
                        bestList(performance.topCharts)
                    }
                }
            } else if let plays = model.snapshot?.recentPlays, !plays.isEmpty {
                List(plays) { play in
                    RecentPlayRow(play: play)
                }
                .listStyle(.plain)
                .refreshable { await model.refresh() }
            } else {
                ContentUnavailableView("No recent plays", systemImage: "clock")
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            if model.isConnected || model.isMyPIUConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.state == .syncing || model.performanceState == .loading)
                    .accessibilityLabel("Refresh activity")
                }
            }
        }
    }

    @ViewBuilder
    private func performanceList(_ plays: [MyPIUPerformanceDashboard.Play]) -> some View {
        if plays.isEmpty {
            ContentUnavailableView("No recent plays", systemImage: "clock")
        } else {
            List(plays) { play in
                PerformanceRecentPlayRow(play: play)
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder
    private func bestList(_ charts: [MyPIUPerformanceDashboard.Chart]) -> some View {
        if charts.isEmpty {
            ContentUnavailableView("No chart bests", systemImage: "chart.bar")
        } else {
            List(charts) { chart in
                PerformanceChartRow(chart: chart)
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
        }
    }
}
