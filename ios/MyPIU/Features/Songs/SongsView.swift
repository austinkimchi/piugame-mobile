import SwiftUI

struct SongsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var songs: [RecentPlay] {
        let unique = Dictionary(grouping: model.snapshot?.recentPlays ?? [], by: \.songName)
            .compactMap { $0.value.first }
            .sorted { $0.songName.localizedCaseInsensitiveCompare($1.songName) == .orderedAscending }
        guard !query.isEmpty else { return unique }
        return unique.filter { $0.songName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if songs.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(songs) { play in
                    HStack {
                        Text(play.songName)
                        Spacer()
                        Text(play.chartToken)
                            .font(.caption.bold().monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Songs")
        .searchable(text: $query, prompt: "Search recent songs")
    }
}
