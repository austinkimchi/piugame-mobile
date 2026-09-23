import Foundation
import XCTest
@testable import MyPIU

final class MobileSyncTests: XCTestCase {
    func testActivationRefreshPolicyRunsInitiallyAndAtTheStaleThreshold() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        XCTAssertTrue(
            BackgroundRefreshScheduler.shouldRefreshAfterActivation(
                lastRefreshAt: nil,
                now: now
            )
        )
        XCTAssertTrue(
            BackgroundRefreshScheduler.shouldRefreshAfterActivation(
                lastRefreshAt: now.addingTimeInterval(-BackgroundRefreshScheduler.activationRefreshInterval),
                now: now
            )
        )
    }

    func testActivationRefreshPolicyThrottlesRecentAndFutureAttempts() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        XCTAssertFalse(
            BackgroundRefreshScheduler.shouldRefreshAfterActivation(
                lastRefreshAt: now.addingTimeInterval(-BackgroundRefreshScheduler.activationRefreshInterval + 1),
                now: now
            )
        )
        XCTAssertFalse(
            BackgroundRefreshScheduler.shouldRefreshAfterActivation(
                lastRefreshAt: now.addingTimeInterval(60),
                now: now
            )
        )
    }

    func testExpiredAccessTokenRequiresReauthentication() {
        let token = MyPIUAccessToken(
            value: "expired-token",
            expiresAt: Date(timeIntervalSinceNow: -1),
            installationID: "fixture-installation"
        )

        XCTAssertTrue(token.isExpired)
    }

    func testAccessTokenPersistsItsInstallationIdentity() throws {
        let token = MyPIUAccessToken(
            value: "mypiu_fixture",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            installationID: "fixture-installation"
        )

        let restored = try JSONDecoder().decode(MyPIUAccessToken.self, from: JSONEncoder().encode(token))

        XCTAssertEqual(restored.installationID, "fixture-installation")
    }

    func testPKCEChallengeMatchesRFC7636() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(mobilePkceChallenge(verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testAppleNonceUsesLowercaseSHA256Hex() {
        XCTAssertEqual(
            appleNonceHash("apple-nonce"),
            "18720d3fd6296cd04d1ee76981969261a6ca5f34af0ca82a912cd0b38d5d2e8a"
        )
    }

    func testImportPayloadContainsNormalizedDataOnly() throws {
        let snapshot = PIUSnapshot(
            version: .phoenix2,
            profile: PIUProfile(
                username: "fixture_user",
                titleName: "CONRAD FOLLOWER",
                gameIDTag: "PLAYER#1234",
                avatarURL: URL(string: "https://www.piugame.com/avatar.png"),
                pp: 1_034,
                pumbilityScore: 15_770.43,
                playCount: 1_200,
                rating: 18_318,
                clearCount: 640,
                totalCharts: 3_900,
                progressPercent: 16,
                recentArcade: "ROUND1",
                lastAccess: "2026-09-22 10:55:00",
                plateCounts: ["rg": 12]
            ),
            recentPlays: [
                RecentPlay(
                    songName: "BATTLE NO.1",
                    songImageURL: nil,
                    mode: "S",
                    level: "19",
                    score: 954_848,
                    grade: "s",
                    plate: "rg",
                    stageBreak: false,
                    judgments: JudgmentCounts(perfect: 1_234, great: 20, good: 4, bad: 0, miss: 1),
                    playedAt: "2026-09-22 10:55:00 (GMT+9)"
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_790_035_200)
        )

        let payload = MobilePerformanceImportPayload(
            snapshot: snapshot,
            installationId: "fixture-install",
            appVersion: "0.1.0"
        )
        let data = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let profile = try XCTUnwrap(object["profile"] as? [String: Any])
        let recentPlays = try XCTUnwrap(object["recentPlays"] as? [[String: Any]])

        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["source"] as? String, "ios")
        XCTAssertEqual(profile["username"] as? String, "fixture_user")
        XCTAssertEqual(profile["pp"] as? Double, 1_034)
        XCTAssertEqual(recentPlays.first?["level"] as? String, "19")
        XCTAssertNil(object["password"])
        XCTAssertFalse(String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains("rawHtml") == true)
    }
}
