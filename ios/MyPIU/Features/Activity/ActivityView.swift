import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let plays = model.snapshot?.recentPlays, !plays.isEmpty {
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
    }
}
