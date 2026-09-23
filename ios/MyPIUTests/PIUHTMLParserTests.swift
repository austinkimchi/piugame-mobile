import XCTest
@testable import MyPIU

final class PIUHTMLParserTests: XCTestCase {
    private let parser = PIUHTMLParser()

    func testProfileParsingMatchesSDKShape() throws {
        let profile = try parser.parseProfile(html: Fixtures.profile, username: "fixture_user", pumbilityScore: 15_770.43)

        XCTAssertEqual(profile.username, "fixture_user")
        XCTAssertEqual(profile.titleName, "CONRAD FOLLOWER")
        XCTAssertEqual(profile.gameIDTag, "PKIMCHI#7501")
        XCTAssertEqual(profile.playCount, 215)
        XCTAssertEqual(profile.rating, 18_318)
        XCTAssertEqual(profile.pp, 1_034)
        XCTAssertEqual(profile.clearCount, 125)
        XCTAssertEqual(profile.totalCharts, 3_646)
        XCTAssertEqual(profile.progressPercent, 3)
        XCTAssertEqual(profile.pumbilityScore, 15_770.43)
        XCTAssertEqual(profile.plateCounts["mg"], 39)
    }

    func testRecentPlayParsingIncludesFailuresAndScores() throws {
        let plays = try parser.parseRecentPlays(html: Fixtures.recent)

        XCTAssertEqual(plays.count, 2)
        XCTAssertEqual(plays[0].songName, "Clematis Rapsodia")
        XCTAssertEqual(plays[0].chartToken, "S15")
        XCTAssertTrue(plays[0].stageBreak)
        XCTAssertNil(plays[0].score)
        XCTAssertEqual(plays[0].judgments.perfect, 555)
        XCTAssertEqual(plays[1].songName, "BATTLE NO.1")
        XCTAssertEqual(plays[1].score, 927_332)
        XCTAssertEqual(plays[1].grade, "aa_p")
        XCTAssertEqual(plays[1].plate, "fg")
    }

    func testRelativeSongArtworkResolvesAgainstPIUGameOrigin() throws {
        let html = Fixtures.recent.replacingOccurrences(
            of: "https://www.piugame.com/data/song_img/a.png",
            with: "/data/song_img/a.png"
        )

        let plays = try parser.parseRecentPlays(
            html: html,
            baseURL: URL(string: "https://www.piugame.com")
        )

        XCTAssertEqual(
            plays.first?.songImageURL?.absoluteString,
            "https://www.piugame.com/data/song_img/a.png"
        )
    }

    func testPumbilityDecimalIsPreserved() throws {
        XCTAssertEqual(try parser.parsePumbilityScore(html: Fixtures.pumbility), 15_770.43)
    }

    func testPumbilityUsesVisibleLabelWhenWebsiteClassesChange() throws {
        let html = """
        <section class="performance-summary-card">
          <p class="metric-label">Pumbility</p>
          <strong class="metric-value">15,770.43</strong>
        </section>
        """

        XCTAssertEqual(try parser.parsePumbilityScore(html: html), 15_770.43)
    }

    func testPumbilityParsesCurrentPIUGamePointClass() throws {
        let html = """
        <div class="pumbility_total_wrap">
          <div class="info-wrap"><div class="score">
            <span class="pumbility-point-sub">15,770.43</span>
          </div></div>
        </div>
        """

        XCTAssertEqual(try parser.parsePumbilityScore(html: html), 15_770.43)
    }

    func testInvalidLevelAssetsAreRejected() throws {
        let plays = try parser.parseRecentPlays(html: Fixtures.invalidLevels)

        XCTAssertEqual(plays.count, 3)
        XCTAssertTrue(plays.allSatisfy { $0.level == nil })
    }
}

private enum Fixtures {
    static let profile = """
    <div class="subProfile_wrap">
      <div class="profile_name"><div class="name_w"><span class="t1">CONRAD FOLLOWER</span><span class="t2">PKIMCHI # 7501</span></div></div>
      <div class="profile_img"><div class="re" style="background-image:url('https://www.piugame.com/data/avatar_img/abc.png')"></div></div>
      <div class="profile_etc"><span class="tt">1,034</span></div>
      <ul class="time_w"><li><span class="tt">last access date : 2026-04-11 12:37:31</span></li><li><span class="tt">recently access games : ROUND1 SLM 2</span></li></ul>
    </div>
    <div class="board_search"><div class="total"><span class="t2">215</span></div></div>
    <div class="play_data_wrap">
      <div class="my_w"><span class="num">18318</span></div>
      <div class="clear_w"><div class="l_con"><span class="t1">125 / 3,646</span></div><div class="graph"><span class="num">3%</span></div></div>
      <div class="plate_w"><ul class="list"><li><a data-type="mg"></a><span class="t_num">39</span></li></ul></div>
    </div>
    """

    static let recent = """
    <ul class="recently_playeList">
      <li>
        <div class="wrap_in"><div class="in" style="background-image:url('https://www.piugame.com/data/song_img/a.png')"></div></div>
        <div class="song_name"><p>Clematis Rapsodia</p></div>
        <div class="stepBall_in"><div class="tw"><img src="https://www.piugame.com/l_img/stepball/full/s_text.png" /></div><div class="numw"><img src="https://www.piugame.com/l_img/stepball/full/s_num_1.png" /><img src="https://www.piugame.com/l_img/stepball/full/s_num_5.png" /></div></div>
        <div class="con2"><ul class="list"><li></li><li><div class="tx">STAGE BREAK</div></li><li></li></ul></div>
        <table class="recently_play"><tr><td data-th="Perfect"><span class="tx">555</span></td><td data-th="Miss"><span class="tx">28</span></td></tr></table>
        <div class="recently_date_tt">2026-04-11 12:45:50 (GMT+9)</div>
      </li>
      <li>
        <div class="song_name"><p>BATTLE NO.1</p></div>
        <div class="stepBall_in"><div class="tw"><img src="https://www.piugame.com/l_img/stepball/full/s_text.png" /></div><div class="numw"><img src="https://www.piugame.com/l_img/stepball/full/s_num_1.png" /><img src="https://www.piugame.com/l_img/stepball/full/s_num_4.png" /></div></div>
        <div class="con2"><ul class="list"><li></li><li><div class="tx">927,332</div><img src="https://www.piugame.com/l_img/grade/aa_p.png" /></li><li><img src="https://www.piugame.com/l_img/plate/fg.png" /></li></ul></div>
        <table class="recently_play"><tr><td data-th="Perfect"><span class="tx">1</span></td></tr></table>
        <div class="recently_date_tt">2026-04-11 12:30:00 (GMT+9)</div>
      </li>
    </ul>
    """

    static let pumbility = """
    <div class="pumbility_total_wrap"><div class="inn"><div class="t1">Pumbility</div><div class="t2">15,770.43</div></div></div>
    """

    static let invalidLevels = """
    <ul class="recently_playeList">
      <li>
        <div class="song_name"><p>PARTIAL LEVEL</p></div>
        <div class="stepBall_in"><div class="tw"><img src="https://www.piugame.com/l_img/stepball/full/s_text.png" /></div><div class="numw"><img src="https://www.piugame.com/l_img/stepball/full/s_num_1.png" /><img src="https://www.piugame.com/l_img/stepball/full/renamed.png" /></div></div>
        <div class="recently_date_tt">2026-04-11 12:30:00 (GMT+9)</div>
      </li>
      <li>
        <div class="song_name"><p>COMBINED LEVEL</p></div>
        <div class="stepBall_in"><div class="tw"><img src="https://www.piugame.com/l_img/stepball/full/s_text.png" /></div><div class="numw"><img src="https://www.piugame.com/l_img/stepball/full/s_num_19.png" /></div></div>
        <div class="recently_date_tt">2026-04-11 12:30:00 (GMT+9)</div>
      </li>
      <li>
        <div class="song_name"><p>PLACEHOLDER LEVEL</p></div>
        <div class="stepBall_in"><div class="tw"><img src="https://www.piugame.com/l_img/stepball/full/s_text.png" /></div><div class="numw"><img src="https://www.piugame.com/l_img/stepball/full/placeholder_9.png" /></div></div>
        <div class="recently_date_tt">2026-04-11 12:30:00 (GMT+9)</div>
      </li>
    </ul>
    """
}
