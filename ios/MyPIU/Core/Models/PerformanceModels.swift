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
        let recentArcade: String?
        let lastSyncedAt: String?
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

    struct Play: Decodable, Equatable, Identifiable, Sendable {
        let songName: String
        let chartToken: String
        let score: Int?
        let grade: String?
        let plate: String?
        let mode: String?
        let level: String?
        let playedAt: String?
        let stageBreak: Bool

        var id: String {
            [songName, chartToken, playedAt ?? "", String(score ?? -1)].joined(separator: ":")
        }

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
