import SwiftUI

struct RecentPlayPresentation: Equatable, Identifiable {
    let id: String
    let songName: String
    let songImageURL: URL?
    let chartToken: String
    let score: Int?
    let grade: String?
    let plate: String?
    let stageBreak: Bool
    let judgments: JudgmentCounts
    let playedAt: String?

    init(play: RecentPlay) {
        id = play.id
        songName = play.songName
        songImageURL = play.songImageURL
        chartToken = play.chartToken
        score = play.score
        grade = play.grade
        plate = play.plate
        stageBreak = play.stageBreak
        judgments = play.judgments
        playedAt = play.playedAt
    }

    init(play: MyPIUPerformanceDashboard.Play, snapshotPlay: RecentPlay? = nil) {
        id = play.id
        songName = play.songName
        songImageURL = snapshotPlay?.songImageURL
        chartToken = play.displayChartToken
        score = play.score
        grade = play.grade
        plate = play.plate ?? snapshotPlay?.plate
        stageBreak = play.stageBreak
        judgments = snapshotPlay?.judgments ?? JudgmentCounts(
            perfect: nil,
            great: nil,
            good: nil,
            bad: nil,
            miss: nil
        )
        playedAt = play.playedAt ?? snapshotPlay?.playedAt
    }

    var isFailed: Bool {
        performancePlayIsFailed(grade: grade, stageBreak: stageBreak)
    }

    var hasJudgments: Bool {
        judgmentValues.isEmpty == false
    }

    var judgmentValues: [PlayJudgmentValue] {
        [
            judgments.perfect.map { PlayJudgmentValue(label: "Perfect", value: $0, tint: AppTheme.accent) },
            judgments.great.map { PlayJudgmentValue(label: "Great", value: $0, tint: AppTheme.info) },
            judgments.good.map { PlayJudgmentValue(label: "Good", value: $0, tint: AppTheme.warning) },
            judgments.bad.map { PlayJudgmentValue(label: "Bad", value: $0, tint: AppTheme.judgmentBad) },
            judgments.miss.map { PlayJudgmentValue(label: "Miss", value: $0, tint: AppTheme.danger) }
        ].compactMap { $0 }
    }
}

struct PlayJudgmentValue: Identifiable, Equatable {
    let label: String
    let value: Int
    let tint: Color

    var id: String { label }
}

func matchingRecentPlay(
    for play: MyPIUPerformanceDashboard.Play,
    in snapshotPlays: [RecentPlay]
) -> RecentPlay? {
    let songName = normalizedPlayValue(play.songName)
    let chartToken = normalizedPlayValue(play.displayChartToken)
    let candidates = snapshotPlays.filter {
        normalizedPlayValue($0.songName) == songName
            && normalizedPlayValue($0.chartToken) == chartToken
    }
    if let exactScore = candidates.first(where: { $0.score == play.score }) {
        return exactScore
    }
    if let exactResult = candidates.first(where: {
        normalizedPlayValue($0.grade ?? "") == normalizedPlayValue(play.grade ?? "")
            && $0.stageBreak == play.stageBreak
    }) {
        return exactResult
    }
    return candidates.first
}

private func normalizedPlayValue(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .filter { $0.isLetter || $0.isNumber }
}

struct RecentPlayDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let play: RecentPlayPresentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                songHeader
                resultCard
                judgmentsCard
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("Play detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var songHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECENT PLAY")
                .font(.caption.bold())
                .tracking(1.6)
                .foregroundStyle(AppTheme.mutedInk)

            HStack(alignment: .top, spacing: 14) {
                SongArtwork(url: play.songImageURL, size: 112)
                VStack(alignment: .leading, spacing: 8) {
                    Text(play.songName)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    ChartTokenBadge(chartToken: play.chartToken)
                    Text(performanceDateLabel(play.playedAt))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .websiteCard()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            WebsiteSectionTitle(title: "RESULT", detail: performanceGradeLabel(play.grade))

            Text(play.isFailed ? "FAILED" : (play.score?.formatted() ?? "Score unavailable"))
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 34 : 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(play.isFailed ? AppTheme.danger : AppTheme.ink)
                .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                if let plate = displayAssetName(play.plate) {
                    resultChip(plate)
                }
            }
        }
        .padding(18)
        .websiteCard()
    }

    @ViewBuilder
    private var judgmentsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WebsiteSectionTitle(title: "JUDGMENTS", detail: judgmentTotalLabel)

            if play.hasJudgments {
                LazyVGrid(columns: judgmentColumns, spacing: 10) {
                    ForEach(play.judgmentValues) { judgment in
                        VStack(alignment: .leading, spacing: 7) {
                            Rectangle()
                                .fill(judgment.tint)
                                .frame(height: 4)
                            Text(judgment.value.formatted())
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                            Text(judgment.label.uppercased())
                                .font(.caption2.bold())
                                .tracking(0.8)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                        .padding(12)
                        .background(AppTheme.pageBackground)
                        .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text("Judgment data is not available for this stored play yet. Refresh from PIUGAME to attach the on-device result details.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(18)
        .websiteCard()
    }

    private var judgmentColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    private var judgmentTotalLabel: String? {
        guard play.hasJudgments else { return nil }
        return play.judgmentValues.reduce(0) { $0 + $1.value }.formatted() + " steps"
    }

    private func resultChip(_ label: String) -> some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.pageBackground)
            .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
            .foregroundStyle(AppTheme.ink)
    }

    private func displayAssetName(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        return value.replacingOccurrences(of: "_", with: " ").uppercased()
    }
}

struct SongArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .background(AppTheme.pageBackground)
        .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.title2.bold())
            .foregroundStyle(AppTheme.mutedInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WebsiteSectionTitle: View {
    let title: String
    let detail: String?

    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.bold())
                .tracking(1.4)
                .foregroundStyle(AppTheme.mutedInk)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
            }
        }
    }
}

extension View {
    func websiteCard() -> some View {
        background(AppTheme.cardBackground)
            .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
    }
}
