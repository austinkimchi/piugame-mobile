import Foundation

enum PIUGameVersion: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case phoenix
    case phoenix2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phoenix: "PHOENIX"
        case .phoenix2: "PHOENIX 2"
        }
    }

    var baseURL: URL {
        switch self {
        case .phoenix: URL(string: "https://phoenix.piugame.com")!
        case .phoenix2: URL(string: "https://www.piugame.com")!
        }
    }
}

struct PIUProfile: Codable, Equatable, Sendable {
    let username: String
    let titleName: String?
    let gameIDTag: String?
    let avatarURL: URL?
    let pp: Double?
    let pumbilityScore: Double?
    let playCount: Int?
    let rating: Int?
    let clearCount: Int?
    let totalCharts: Int?
    let progressPercent: Int?
    let recentArcade: String?
    let lastAccess: String?
    let plateCounts: [String: Int]

    var displayName: String {
        gameIDTag ?? username
    }
}

struct JudgmentCounts: Codable, Equatable, Sendable {
    let perfect: Int?
    let great: Int?
    let good: Int?
    let bad: Int?
    let miss: Int?
}

struct RecentPlay: Codable, Equatable, Identifiable, Sendable {
    let songName: String
    let songImageURL: URL?
    let mode: String?
    let level: String?
    let score: Int?
    let grade: String?
    let plate: String?
    let stageBreak: Bool
    let judgments: JudgmentCounts
    let playedAt: String?

    var id: String {
        [songName, mode ?? "", level ?? "", playedAt ?? "", String(score ?? -1)].joined(separator: ":")
    }

    var chartToken: String {
        guard let mode, let level else { return "-" }
        return "\(mode.uppercased())\(level)"
    }
}

struct PIUSnapshot: Codable, Equatable, Sendable {
    let version: PIUGameVersion
    let profile: PIUProfile
    let recentPlays: [RecentPlay]
    let fetchedAt: Date
}

struct PIUCredentials: Equatable, Sendable {
    let username: String
    let password: String
    let version: PIUGameVersion
}
