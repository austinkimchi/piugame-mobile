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
                "id": "play-1",
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
        XCTAssertEqual(dashboard.recentPlays.first?.id, "play-1")
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

    func testPerformanceRowsUseServerIdentifiers() throws {
        let play = MyPIUPerformanceDashboard.Play(
            id: "play-1",
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
            delta: 8_767,
            bestGrade: "aa",
            bestPlate: "fg",
            mode: "S",
            level: "19",
            topPlayRank: 3,
            topPumbilityScore: 550
        )

        XCTAssertEqual(play.id, "play-1")
        XCTAssertEqual(play.displayChartToken, "S19")
        XCTAssertEqual(chart.id, "Big Daddy:big-daddy:s:19")
        XCTAssertEqual(chart.displayChartToken, "S19")
        let accessibilityValue = performanceChartAccessibilityValue(chart)
        XCTAssertTrue(accessibilityValue.contains("Rank 3"))
        XCTAssertTrue(accessibilityValue.contains("Improved by"))
    }

    func testPerformanceAccessibilityLabelsDescribeChartsAndFailedGrades() {
        XCTAssertEqual(performanceChartTokenAccessibilityLabel("S19"), "Single level 19")
        XCTAssertEqual(performanceChartTokenAccessibilityLabel("d24"), "Double level 24")
        XCTAssertEqual(performanceChartTokenAccessibilityLabel("C2"), "Co-op level 2")
        XCTAssertEqual(performanceChartTokenAccessibilityLabel("S17+"), "Single level 17 plus")
        XCTAssertEqual(
            performanceChartTokenAccessibilityLabel("single-lady:s:19"),
            "single-lady:s:19"
        )
        XCTAssertTrue(performancePlayIsFailed(grade: "x_aa", stageBreak: false))
        XCTAssertTrue(performancePlayIsFailed(grade: "s", stageBreak: true))
        XCTAssertFalse(performancePlayIsFailed(grade: "s", stageBreak: false))
    }

    func testRecentPerformancePlayUsesMatchingSnapshotArtworkAndJudgments() {
        let serverPlay = MyPIUPerformanceDashboard.Play(
            id: "server-play",
            songName: "BATTLE NO.1",
            chartToken: "battle-no-1:s:19",
            score: 954_848,
            grade: "s",
            plate: nil,
            mode: "S",
            level: "19",
            playedAt: "2026-09-22T07:20:00.000Z",
            stageBreak: false
        )
        let snapshotPlay = RecentPlay(
            songName: "Battle No. 1",
            songImageURL: URL(string: "https://www.piugame.com/data/song_img/battle.png"),
            mode: "s",
            level: "19",
            score: 954_848,
            grade: "s",
            plate: "rg",
            stageBreak: false,
            judgments: JudgmentCounts(perfect: 900, great: 20, good: 3, bad: 1, miss: 2),
            playedAt: "2026-09-22 16:20:00 (GMT+9)"
        )

        let match = matchingRecentPlay(for: serverPlay, in: [snapshotPlay])
        let presentation = RecentPlayPresentation(play: serverPlay, snapshotPlay: match)

        XCTAssertEqual(match, snapshotPlay)
        XCTAssertEqual(presentation.songImageURL, snapshotPlay.songImageURL)
        XCTAssertEqual(presentation.plate, "rg")
        XCTAssertEqual(presentation.judgments.perfect, 900)
        XCTAssertEqual(presentation.judgmentValues.reduce(0) { $0 + $1.value }, 926)
    }

    func testStoredPerformancePlayPrefersServerJudgments() {
        let serverJudgments = JudgmentCounts(perfect: 850, great: 30, good: 4, bad: 2, miss: 1)
        let serverPlay = MyPIUPerformanceDashboard.Play(
            id: "stored-play",
            songName: "BATTLE NO.1",
            chartToken: "battle-no-1:s:19",
            score: 940_000,
            grade: "s",
            plate: "fg",
            mode: "S",
            level: "19",
            playedAt: "2026-09-20T07:20:00.000Z",
            stageBreak: false,
            judgments: serverJudgments
        )

        let presentation = RecentPlayPresentation(play: serverPlay)

        XCTAssertEqual(presentation.judgments, serverJudgments)
        XCTAssertEqual(presentation.judgmentValues.reduce(0) { $0 + $1.value }, 887)
    }

    func testDecodesSongChartHistoryNewestFirst() throws {
        let data = Data(
            #"""
            {
              "latestPlay": {
                "id": "latest",
                "score": null,
                "grade": "x_s",
                "plate": null,
                "playedAt": "2026-09-22T08:10:00.000Z",
                "stageBreak": true,
                "judgments": {"perfect": 810, "great": 20, "good": 4, "bad": 2, "miss": 31}
              },
              "history": [
                {
                  "id": "older",
                  "score": 928767,
                  "grade": "aa",
                  "plate": "fg",
                  "playedAt": "2026-09-21T08:10:00.000Z",
                  "stageBreak": false,
                  "judgments": {"perfect": 900, "great": 10, "good": 2, "bad": 0, "miss": 3}
                },
                {
                  "id": "latest",
                  "score": null,
                  "grade": "x_s",
                  "plate": null,
                  "playedAt": "2026-09-22T08:10:00.000Z",
                  "stageBreak": true,
                  "judgments": {"perfect": 810, "great": 20, "good": 4, "bad": 2, "miss": 31}
                }
              ],
              "stats": {
                "bestScore": 928767,
                "previousBestScore": 920000,
                "latestScore": null,
                "latestStageBreak": true,
                "latestPlayedAt": "2026-09-22T08:10:00.000Z",
                "recentPlayCount": 2,
                "stageBreakCount": 1,
                "bestGrade": "aa",
                "bestPlate": "fg",
                "bestBucketPage": 1,
                "bestSyncedAt": "2026-09-21T08:10:00.000Z"
              }
            }
            """#.utf8
        )

        let performance = try JSONDecoder().decode(MyPIUSongChartPerformance.self, from: data)

        XCTAssertEqual(performance.latestPlay?.id, "latest")
        XCTAssertEqual(performance.latestPlay?.judgments.miss, 31)
        XCTAssertEqual(performance.stats?.bestScore, 928_767)
        XCTAssertEqual(performance.stats?.recentPlayCount, 2)
        XCTAssertEqual(performance.attemptsNewestFirst.map(\.id), ["latest", "older"])
    }

    func testDecodesCompletePerformanceSession() throws {
        let data = Data(
            #"""
            {
              "id": "session-1",
              "arcadeName": "Round1 Eastridge",
              "summary": {
                "playCount": 3,
                "clearCount": 2,
                "failedCount": 1,
                "stageBreakCount": 1,
                "averageScore": 925000,
                "bestScore": 950000,
                "distinctCharts": 2,
                "startedAt": "2026-09-22T07:00:00.000Z",
                "endedAt": "2026-09-22T08:00:00.000Z",
                "durationMinutes": 60
              },
              "plays": [
                {
                  "id": "play-2",
                  "songName": "Big Daddy",
                  "chartToken": "big-daddy:s:19",
                  "score": null,
                  "grade": "x_s",
                  "plate": null,
                  "mode": "S",
                  "level": "19",
                  "playedAt": "2026-09-22T08:00:00.000Z",
                  "stageBreak": true
                },
                {
                  "id": "play-3",
                  "songName": "Big Daddy",
                  "chartToken": "big-daddy:s:19",
                  "score": null,
                  "grade": "x_s",
                  "plate": null,
                  "mode": "S",
                  "level": "19",
                  "playedAt": "2026-09-22T08:00:00.000Z",
                  "stageBreak": true
                }
              ]
            }
            """#.utf8
        )

        let session = try JSONDecoder().decode(MyPIUPerformanceSession.self, from: data)

        XCTAssertEqual(session.summary.playCount, 3)
        XCTAssertEqual(session.id, "session-1")
        XCTAssertEqual(session.arcadeName, "Round1 Eastridge")
        XCTAssertEqual(session.summary.failedCount, 1)
        XCTAssertEqual(try XCTUnwrap(session.summary.clearRate), 200.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(session.summary.durationMinutes, 60)
        XCTAssertEqual(session.plays.first?.displayChartToken, "S19")
        XCTAssertEqual(session.plays.first?.stageBreak, true)
        XCTAssertEqual(session.plays.map(\.id), ["play-2", "play-3"])
    }

    func testSessionClearRateRequiresPlaysAndClampsBadCounts() {
        let empty = MyPIUPerformanceSession.Summary(
            playCount: 0,
            clearCount: 0,
            failedCount: 0,
            stageBreakCount: 0,
            averageScore: nil,
            bestScore: nil,
            distinctCharts: 0,
            startedAt: "2026-09-22T07:00:00.000Z",
            endedAt: "2026-09-22T07:00:00.000Z",
            durationMinutes: 0
        )
        let corrupt = MyPIUPerformanceSession.Summary(
            playCount: 1,
            clearCount: 2,
            failedCount: 0,
            stageBreakCount: 0,
            averageScore: nil,
            bestScore: nil,
            distinctCharts: 1,
            startedAt: "2026-09-22T07:00:00.000Z",
            endedAt: "2026-09-22T07:00:00.000Z",
            durationMinutes: 0
        )

        XCTAssertNil(empty.clearRate)
        XCTAssertEqual(corrupt.clearRate, 100)
    }
}
