import Foundation

struct MyPIUPerformanceSession: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let arcadeName: String?
    let summary: Summary
    let plays: [MyPIUPerformanceDashboard.Play]

    struct Summary: Decodable, Equatable, Sendable {
        let playCount: Int
        let clearCount: Int
        let failedCount: Int
        let stageBreakCount: Int
        let averageScore: Int?
        let bestScore: Int?
        let distinctCharts: Int
        let startedAt: String
        let endedAt: String
        let durationMinutes: Int

        var clearRate: Double? {
            guard playCount > 0 else { return nil }
            return min(100, max(0, Double(clearCount) / Double(playCount) * 100))
        }
    }
}
