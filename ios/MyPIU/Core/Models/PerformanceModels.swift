import Foundation

struct MyPIUPerformanceDashboard: Decodable, Equatable, Sendable {
    let profile: Profile?
    let totals: Totals
    let recentPlays: [Play]
    let topCharts: [Chart]
    let canSync: Bool
    let mongoReady: Bool

    struct Profile: Decodable, Equatable, Sendable {
        let displayName: String
        let pumbilityScore: Double?
        let rating: Double?
        let playCount: Int?
        let clearCount: Int?
        let totalCharts: Int?
        let progressPercent: Double?
        let nextTitle: NextTitle?
        let recentArcade: String?
        let lastSyncedAt: String?
    }

    struct NextTitle: Decodable, Equatable, Sendable {
        let name: String
        let metric: String
        let current: Double
        let previousTarget: Double?
        let target: Double

        var progressFraction: Double {
            let intervalStart = previousTarget ?? 0
            let interval = target - intervalStart
            guard interval > 0 else { return 0 }
            return min(1, max(0, (current - intervalStart) / interval))
        }

        var remaining: Double {
            max(0, target - current)
        }
    }

    struct Totals: Decodable, Equatable, Sendable {
        let trackedPlays: Int
        let trackedCharts: Int
        let trackedPumbilityCharts: Int
        let upscores: Int
        let upscoresThisWeek: Int
        let upscoresThisMonth: Int
        let upscoresToday: Int
        let averageBestScore: Int?
        let pumbilityChange24Hours: Double?
        let averageBestScoreChange24Hours: Double?
        let recentlyPlayed: Int
    }

    struct Play: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let songName: String
        let chartToken: String
        let score: Int?
        let grade: String?
        let plate: String?
        let mode: String?
        let level: String?
        let playedAt: String?
        let stageBreak: Bool
        var arcadeName: String? = nil
        var judgments: JudgmentCounts? = nil
        var songImageUrl: URL? = nil

        var songImageURL: URL? { songImageUrl }

        var displayChartToken: String {
            guard let mode, let level else { return chartToken }
            return "\(mode.uppercased())\(level)"
        }
    }

    struct Chart: Decodable, Equatable, Identifiable, Sendable {
        let songName: String
        let chartToken: String
        let bestScore: Int?
        let previousBestScore: Int?
        let delta: Int?
        let bestGrade: String?
        let bestPlate: String?
        let mode: String?
        let level: String?
        let topPlayRank: Int?
        let topPumbilityScore: Double?

        var id: String { "\(songName):\(chartToken)" }

        var displayChartToken: String {
            guard let mode, let level else { return chartToken }
            return "\(mode.uppercased())\(level)"
        }
    }
}

struct PerformanceProgressSummary: Equatable, Sendable {
    let clearedCharts: Int?
    let totalCharts: Int?
    let playCount: Int?
    let completionPercent: Double?

    var remainingCharts: Int? {
        guard let clearedCharts, let totalCharts else { return nil }
        return max(0, totalCharts - clearedCharts)
    }

    var completionFraction: Double? {
        completionPercent.map { $0 / 100 }
    }

    init(
        clearCount: Int?,
        totalCharts: Int?,
        progressPercent: Double?,
        playCount: Int?
    ) {
        let normalizedClears = clearCount.map { max(0, $0) }
        let normalizedTotal = totalCharts.map { max(0, $0) }
        self.clearedCharts = normalizedClears
        self.totalCharts = normalizedTotal
        self.playCount = playCount.map { max(0, $0) }

        if let progressPercent, progressPercent.isFinite {
            self.completionPercent = min(100, max(0, progressPercent))
        } else if let normalizedClears, let normalizedTotal, normalizedTotal > 0 {
            self.completionPercent = min(100, Double(normalizedClears) / Double(normalizedTotal) * 100)
        } else {
            self.completionPercent = nil
        }
    }

    init(profile: MyPIUPerformanceDashboard.Profile) {
        self.init(
            clearCount: profile.clearCount,
            totalCharts: profile.totalCharts,
            progressPercent: profile.progressPercent,
            playCount: profile.playCount
        )
    }

    init(profile: PIUProfile) {
        self.init(
            clearCount: profile.clearCount,
            totalCharts: profile.totalCharts,
            progressPercent: profile.progressPercent.map(Double.init),
            playCount: profile.playCount
        )
    }
}
