import SwiftUI

struct CatalogSongDetailView: View {
    let song: CatalogSong

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metadata
                charts
                tags

                if let websiteURL = song.websiteURL {
                    Link(destination: websiteURL) {
                        Label("Open on MyPIU", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ink)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            CatalogArtwork(url: song.imageURL, size: 220)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(song.title)
                    .font(.title.bold())
                if song.isPremium {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(AppTheme.warning)
                        .accessibilityLabel("Premium")
                }
            }
            Text(song.artist)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        VStack(spacing: 0) {
            if let bpm = song.bpm {
                metadataRow("BPM", value: bpm, systemImage: "metronome")
            }
            if let folder = song.folder {
                Divider()
                metadataRow("Folder", value: folder, systemImage: "folder")
            }
            if let series = song.series {
                Divider()
                metadataRow("Series", value: series, systemImage: "square.stack")
            }
        }
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Charts")
                .font(.headline)

            ForEach(CatalogChartMode.allCases) { mode in
                let chartTokens = song.charts(for: mode)
                if !chartTokens.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 82))], spacing: 8) {
                            ForEach(chartTokens, id: \.self) { token in
                                Text(token)
                                    .font(.subheadline.bold().monospaced())
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(chartColor(token), in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.white)
                                    .accessibilityLabel(chartAccessibilityLabel(token))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tags: some View {
        if !song.tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.headline)
                Text(song.tags.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metadataRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .padding(.vertical, 11)
    }

    private func chartColor(_ token: String) -> Color {
        switch token.first?.uppercased() {
        case "S": AppTheme.accent
        case "D": .blue
        default: AppTheme.positive
        }
    }

    private func chartAccessibilityLabel(_ token: String) -> String {
        guard let mode = CatalogChartMode.allCases.first(where: { $0.contains(token) }) else { return token }
        return "\(mode.title) level \(token.dropFirst())"
    }
}
