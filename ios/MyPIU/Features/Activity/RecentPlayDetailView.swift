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

    init(
        play: MyPIUPerformanceDashboard.Play,
        snapshotPlay: RecentPlay? = nil,
        catalogImageURL: URL? = nil
    ) {
        id = play.id
        songName = play.songName
        songImageURL = play.songImageURL ?? snapshotPlay?.songImageURL ?? catalogImageURL
        chartToken = play.displayChartToken
        score = play.score
        grade = play.grade
        plate = play.plate ?? snapshotPlay?.plate
        stageBreak = play.stageBreak
        judgments = play.judgments ?? snapshotPlay?.judgments ?? JudgmentCounts(
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
            judgments.perfect.map { PlayJudgmentValue(label: "Perfect", value: $0, tint: AppTheme.judgmentPerfect) },
            judgments.great.map { PlayJudgmentValue(label: "Great", value: $0, tint: AppTheme.judgmentGreat) },
            judgments.good.map { PlayJudgmentValue(label: "Good", value: $0, tint: AppTheme.warning) },
            judgments.bad.map { PlayJudgmentValue(label: "Bad", value: $0, tint: AppTheme.judgmentBad) },
            judgments.miss.map { PlayJudgmentValue(label: "Miss", value: $0, tint: AppTheme.danger) }
        ].compactMap { $0 }
    }

    var judgmentTotal: Int {
        judgmentValues.reduce(0) { $0 + max(0, $1.value) }
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
                JudgmentDistributionBar(judgments: play.judgmentValues)

                LazyVGrid(columns: judgmentColumns, spacing: 8) {
                    ForEach(play.judgmentValues) { judgment in
                        VStack(spacing: 4) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(judgment.tint)
                                    .frame(width: 7, height: 7)
                                Text(judgment.label.uppercased())
                                    .font(.caption2.bold())
                                    .tracking(0.5)
                                    .foregroundStyle(AppTheme.mutedInk)
                                    .lineLimit(1)
                            }
                            Text(judgment.value.formatted())
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 7)
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
            repeating: GridItem(.flexible(), spacing: 8),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
        )
    }

    private var judgmentTotalLabel: String? {
        guard play.hasJudgments else { return nil }
        return play.judgmentTotal.formatted() + " steps"
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

private struct JudgmentDistributionBar: View {
    let judgments: [PlayJudgmentValue]

    private var total: Int {
        judgments.reduce(0) { $0 + max(0, $1.value) }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if total > 0 {
                    ForEach(judgments.filter { $0.value > 0 }) { judgment in
                        Rectangle()
                            .fill(judgment.tint)
                            .frame(
                                width: proxy.size.width * CGFloat(judgment.value) / CGFloat(total)
                            )
                    }
                } else {
                    Rectangle().fill(AppTheme.pageBackground)
                }
            }
        }
        .frame(height: 14)
        .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            judgments
                .map { "\($0.label) \($0.value.formatted())" }
                .joined(separator: ", ")
        )
    }
}

struct SongArtwork: View {
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if url != nil {
                CachedRemoteImage(url: url, pixelSize: size * displayScale) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
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
