import Foundation

struct MobilePerformanceImportPayload: Encodable, Equatable, Sendable {
    let schemaVersion = 1
    let idempotencyKey: String
    let installationId: String
    let source = "ios"
    let appVersion: String?
    let piuVersion: PIUGameVersion
    let generatedAt: String
    let profile: Profile
    let recentPlays: [Play]

    struct Profile: Encodable, Equatable, Sendable {
        let username: String
        let displayName: String
        let titleName: String?
        let gameId: String?
        let pumpTag: String?
        let avatarUrl: String?
        let pumbilityScore: Double?
        let pp: Double?
        let rating: Int?
        let playCount: Int?
        let clearCount: Int?
        let totalCharts: Int?
        let progressPercent: Int?
        let plateCounts: [String: Int]
        let recentArcade: String?
        let lastAccess: String?
    }

    struct Play: Encodable, Equatable, Sendable {
        let songName: String
        let mode: String
        let level: String
        let score: Int?
        let grade: String?
        let plate: String?
        let stageBreak: Bool
        let judgments: JudgmentCounts
        let playedAt: String
    }

    init(snapshot: PIUSnapshot, installationId: String, appVersion: String?) {
        let generatedAt = Self.timestamp(snapshot.fetchedAt)
        self.idempotencyKey = "ios:\(installationId):\(generatedAt)"
        self.installationId = installationId
        self.appVersion = appVersion
        self.piuVersion = snapshot.version
        self.generatedAt = generatedAt
        self.profile = Profile(
            username: snapshot.profile.username,
            displayName: snapshot.profile.displayName,
            titleName: snapshot.profile.titleName,
            gameId: nil,
            pumpTag: snapshot.profile.gameIDTag,
            avatarUrl: snapshot.profile.avatarURL?.absoluteString,
            pumbilityScore: snapshot.profile.pumbilityScore,
            pp: snapshot.profile.pp,
            rating: snapshot.profile.rating,
            playCount: snapshot.profile.playCount,
            clearCount: snapshot.profile.clearCount,
            totalCharts: snapshot.profile.totalCharts,
            progressPercent: snapshot.profile.progressPercent,
            plateCounts: snapshot.profile.plateCounts,
            recentArcade: snapshot.profile.recentArcade,
            lastAccess: snapshot.profile.lastAccess
        )
        self.recentPlays = snapshot.recentPlays.compactMap { play in
            guard let mode = play.mode?.uppercased(),
                  let level = play.level,
                  let playedAt = play.playedAt else { return nil }
            return Play(
                songName: play.songName,
                mode: mode,
                level: level,
                score: play.score,
                grade: play.grade,
                plate: play.plate,
                stageBreak: play.stageBreak,
                judgments: play.judgments,
                playedAt: playedAt
            )
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
