package com.austinkimchi.mypiu.core.parsing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PiuHtmlParserTest {
    private val parser = PiuHtmlParser()

    @Test
    fun profileParsingMatchesReferenceShape() {
        val profile = parser.parseProfile(PROFILE, "fixture_user", 15_770.43)

        assertEquals("CONRAD FOLLOWER", profile.titleName)
        assertEquals("PKIMCHI#7501", profile.gameIdTag)
        assertEquals(215, profile.playCount)
        assertEquals(18_318, profile.rating)
        assertEquals(1_034.0, profile.pp)
        assertEquals(125, profile.clearCount)
        assertEquals(3_646, profile.totalCharts)
        assertEquals(3, profile.progressPercent)
        assertEquals(39, profile.plateCounts["mg"])
    }

    @Test
    fun recentPlayParsingIncludesFailuresAndScores() {
        val plays = parser.parseRecentPlays(RECENT)

        assertEquals(2, plays.size)
        assertEquals("S15", plays[0].chartToken)
        assertTrue(plays[0].stageBreak)
        assertNull(plays[0].score)
        assertEquals(555, plays[0].judgments.perfect)
        assertEquals(927_332, plays[1].score)
        assertEquals("aa_p", plays[1].grade)
        assertEquals("fg", plays[1].plate)
    }

    @Test
    fun pumbilityDecimalIsPreserved() {
        assertEquals(
            15_770.43,
            requireNotNull(
                parser.parsePumbilityScore("<div class='pumbility_total_wrap'><span class='t2'>15,770.43</span></div>"),
            ),
            0.001,
        )
    }

    @Test
    fun invalidLevelAssetsAreRejected() {
        val plays = parser.parseRecentPlays(INVALID_LEVELS)
        assertEquals(3, plays.size)
        assertTrue(plays.all { it.level == null })
    }

    private companion object {
        val PROFILE = """
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
        """.trimIndent()

        val RECENT = """
            <ul class="recently_playeList">
              <li>
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
        """.trimIndent()

        val INVALID_LEVELS = """
            <ul class="recently_playeList">
              <li><div class="song_name"><p>PARTIAL</p></div><div class="stepBall_in"><div class="tw"><img src="/s_text.png" /></div><div class="numw"><img src="/s_num_1.png" /><img src="/renamed.png" /></div></div></li>
              <li><div class="song_name"><p>COMBINED</p></div><div class="stepBall_in"><div class="tw"><img src="/s_text.png" /></div><div class="numw"><img src="/s_num_19.png" /></div></div></li>
              <li><div class="song_name"><p>PLACEHOLDER</p></div><div class="stepBall_in"><div class="tw"><img src="/s_text.png" /></div><div class="numw"><img src="/placeholder_9.png" /></div></div></li>
            </ul>
        """.trimIndent()
    }
}
