import Foundation

struct MyPIUSongChartPerformance: Decodable, Equatable, Sendable {
    let latestPlay: Attempt?
    let history: [Attempt]
    let stats: Stats?

    var attemptsNewestFirst: [Attempt] {
        Array(history.reversed())
    }

    struct Attempt: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        let score: Int?
        let grade: String?
        let plate: String?
        let playedAt: String?
        let stageBreak: Bool
        let judgments: JudgmentCounts
    }

    struct Stats: Decodable, Equatable, Sendable {
        let bestScore: Int?
        let previousBestScore: Int?
        let latestScore: Int?
        let latestStageBreak: Bool
        let latestPlayedAt: String?
        let recentPlayCount: Int
        let stageBreakCount: Int
        let bestGrade: String?
        let bestPlate: String?
        let bestBucketPage: Int?
        let bestSyncedAt: String?
    }
}
