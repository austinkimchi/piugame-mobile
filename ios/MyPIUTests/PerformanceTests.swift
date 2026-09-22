import Foundation
import XCTest
@testable import MyPIU

final class PerformanceTests: XCTestCase {
    func testDecodesPersistedPerformanceDashboard() throws {
        let data = Data(
            #"""
            {
              "profile": {
                "displayName": "PLAYER#1234",
                "pumbilityScore": 15770.43,
                "rating": 18318,
                "playCount": 1200,
                "clearCount": 640,
                "totalCharts": 3900,
                "progressPercent": 16,
                "recentArcade": "ROUND1",
                "lastSyncedAt": "2026-09-22T07:30:00.000Z"
              },
              "totals": {
                "trackedPlays": 42,
                "trackedCharts": 120,
                "trackedPumbilityCharts": 20,
                "upscores": 30,
                "upscoresThisWeek": 7,
                "upscoresThisMonth": 18,
                "upscoresToday": 2,
                "averageBestScore": 954848,
                "pumbilityChange24Hours": 14.5,
                "averageBestScoreChange24Hours": 320,
                "recentlyPlayed": 9
              },
              "recentPlays": [{
                "songName": "BATTLE NO.1",
                "chartToken": "battle-no-1:s:19",
                "score": 954848,
                "grade": "s",
                "plate": "rg",
                "mode": "S",
                "level": "19",
                "playedAt": "2026-09-22T07:20:00.000Z",
                "stageBreak": false
              }],
              "topCharts": [{
                "songName": "Big Daddy",
                "chartToken": "big-daddy:s:19",
                "bestScore": 928767,
                "previousBestScore": 920000,
                "delta": 8767,
                "bestGrade": "aa",
                "bestPlate": "fg",
                "mode": "S",
                "level": "19",
                "topPlayRank": 3,
                "topPumbilityScore": 550
              }],
              "canSync": true,
              "mongoReady": true
            }
            """#.utf8
        )

        let dashboard = try JSONDecoder().decode(MyPIUPerformanceDashboard.self, from: data)

        XCTAssertEqual(dashboard.profile?.displayName, "PLAYER#1234")
        XCTAssertEqual(dashboard.profile?.clearCount, 640)
        XCTAssertEqual(dashboard.profile?.totalCharts, 3_900)
        XCTAssertEqual(dashboard.profile?.progressPercent, 16)
        XCTAssertEqual(dashboard.totals.averageBestScore, 954_848)
        XCTAssertEqual(dashboard.recentPlays.first?.score, 954_848)
        XCTAssertEqual(dashboard.topCharts.first?.topPlayRank, 3)
    }

    func testProgressSummaryUsesReportedPercentageAndSafeCounts() {
        let summary = PerformanceProgressSummary(
            clearCount: 640,
            totalCharts: 3_900,
            progressPercent: 16,
            playCount: 1_200
        )

        XCTAssertEqual(summary.clearedCharts, 640)
        XCTAssertEqual(summary.remainingCharts, 3_260)
        XCTAssertEqual(summary.playCount, 1_200)
        XCTAssertEqual(summary.completionPercent, 16)
        XCTAssertEqual(summary.completionFraction, 0.16)
    }

    func testProgressSummaryDerivesAndClampsCompletion() {
        let derived = PerformanceProgressSummary(
            clearCount: 1,
            totalCharts: 4,
            progressPercent: nil,
            playCount: nil
        )
        let clamped = PerformanceProgressSummary(
            clearCount: 12,
            totalCharts: 10,
            progressPercent: 125,
            playCount: -4
        )

        XCTAssertEqual(derived.completionPercent, 25)
        XCTAssertEqual(clamped.completionPercent, 100)
        XCTAssertEqual(clamped.remainingCharts, 0)
        XCTAssertEqual(clamped.playCount, 0)
    }

    func testPerformanceRowsHaveStableCompositeIdentifiers() throws {
        let play = MyPIUPerformanceDashboard.Play(
            songName: "BATTLE NO.1",
            chartToken: "battle-no-1:s:19",
            score: 954_848,
            grade: "s",
            plate: "rg",
            mode: "S",
            level: "19",
            playedAt: "2026-09-22T07:20:00.000Z",
            stageBreak: false
        )
        let chart = MyPIUPerformanceDashboard.Chart(
            songName: "Big Daddy",
            chartToken: "big-daddy:s:19",
            bestScore: 928_767,
            previousBestScore: nil,
            delta: nil,
            bestGrade: "aa",
            bestPlate: "fg",
            mode: "S",
            level: "19",
            topPlayRank: 3,
            topPumbilityScore: 550
        )

        XCTAssertEqual(play.id, "BATTLE NO.1:battle-no-1:s:19:2026-09-22T07:20:00.000Z:954848")
        XCTAssertEqual(play.displayChartToken, "S19")
        XCTAssertEqual(chart.id, "Big Daddy:big-daddy:s:19")
        XCTAssertEqual(chart.displayChartToken, "S19")
    }
}
