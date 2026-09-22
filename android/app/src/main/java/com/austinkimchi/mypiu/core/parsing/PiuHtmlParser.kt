package com.austinkimchi.mypiu.core.parsing

import com.austinkimchi.mypiu.core.model.JudgmentCounts
import com.austinkimchi.mypiu.core.model.PiuProfile
import com.austinkimchi.mypiu.core.model.RecentPlay
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

class PiuParsingException(message: String) : Exception(message)

class PiuHtmlParser {
    fun parseProfile(html: String, username: String, pumbilityScore: Double? = null): PiuProfile {
        val document = Jsoup.parse(html)
        if (document.select(".subProfile_wrap, .play_data_wrap").isEmpty()) {
            throw PiuParsingException("PIUGAME returned an unrecognized profile page.")
        }

        val gameIdTag = text(document, ".profile_name .name_w .t2")
            ?.replace(Regex("\\s*#\\s*"), "#")
        val clearParts = text(document, ".clear_w .l_con .t1")
            ?.split("/", limit = 2)
            ?.map(String::trim)
            .orEmpty()
        val plateCounts = buildMap {
            document.select(".plate_w .list li").forEach { item ->
                val code = item.selectFirst("[data-type]")?.attr("data-type")?.lowercase().orEmpty()
                val count = integer(item.selectFirst(".t_num")?.text())
                if (code.isNotEmpty() && count != null) put(code, count)
            }
        }

        return PiuProfile(
            username = username,
            titleName = text(document, ".profile_name .name_w .t1"),
            gameIdTag = gameIdTag,
            avatarUrl = backgroundImageUrl(document.selectFirst(".profile_img .re")?.attr("style")),
            pp = decimal(text(document, ".profile_etc .tt")),
            pumbilityScore = pumbilityScore,
            playCount = integer(text(document, ".board_search .total .t2, .board_search .total_wrap .t2")),
            rating = integer(text(document, ".play_data_wrap .my_w .num")),
            clearCount = clearParts.firstOrNull()?.let(::integer),
            totalCharts = clearParts.getOrNull(1)?.let(::integer),
            progressPercent = integer(text(document, ".clear_w .graph .num")),
            recentArcade = valueAfterColon(timeValue(document, "recently access games")),
            lastAccess = valueAfterColon(timeValue(document, "last access date")),
            plateCounts = plateCounts,
        )
    }

    fun parsePumbilityScore(html: String): Double? {
        val document = Jsoup.parse(html)
        return decimal(text(document, ".pumbility_total_wrap .t2, .total_pumbility .t2, .pumbility_total .t2"))
    }

    fun parseRecentPlays(html: String): List<RecentPlay> {
        val document = Jsoup.parse(html)
        if (document.select(".recently_playeList").isEmpty()) {
            throw PiuParsingException("PIUGAME returned an unrecognized recent-play page.")
        }

        return document.select(".recently_playeList > li").mapNotNull { item ->
            val songName = text(item, ".song_name p")?.takeIf(String::isNotEmpty) ?: return@mapNotNull null
            val scoreText = text(item, ".con2 .list > li:nth-child(2) .tx")
            val stageBreak = scoreText?.contains("stage break", ignoreCase = true) == true
            val judgments = item.select("table.recently_play td").associate { cell ->
                cell.attr("data-th").lowercase() to integer(cell.selectFirst(".tx")?.text())
            }

            RecentPlay(
                songName = songName,
                songImageUrl = backgroundImageUrl(item.selectFirst(".wrap_in .in")?.attr("style")),
                mode = chartMode(item),
                level = chartLevel(item),
                score = if (stageBreak) null else integer(scoreText),
                grade = assetCode(item, "/grade/"),
                plate = assetCode(item, "/plate/"),
                stageBreak = stageBreak,
                judgments = JudgmentCounts(
                    perfect = judgments["perfect"],
                    great = judgments["great"],
                    good = judgments["good"],
                    bad = judgments["bad"],
                    miss = judgments["miss"],
                ),
                playedAt = text(item, ".recently_date_tt"),
            )
        }
    }

    private fun chartMode(root: Element): String? {
        val filename = root.selectFirst(".stepBall_in .tw img")
            ?.attr("src")
            ?.substringAfterLast('/')
            ?.substringBeforeLast('.')
            ?.lowercase()
            ?: return null
        return when {
            filename.startsWith("s_") -> "S"
            filename.startsWith("d_") -> "D"
            filename.startsWith("c_") -> "C"
            else -> null
        }
    }

    private fun chartLevel(root: Element): String? {
        val images = root.select(".stepBall_in .numw img")
        if (images.isEmpty()) return null
        val digits = images.map { image ->
            val filename = image.attr("src").substringAfterLast('/').substringBeforeLast('.').lowercase()
            if (!filename.matches(Regex("^[sdc]_num_[0-9]$"))) return null
            filename.last().toString()
        }
        return digits.joinToString(separator = "")
    }

    private fun assetCode(root: Element, path: String): String? = root.select("img")
        .firstNotNullOfOrNull { image ->
            image.attr("src").takeIf { it.contains(path, ignoreCase = true) }
                ?.substringAfterLast('/')
                ?.substringBeforeLast('.')
                ?.lowercase()
        }

    private fun timeValue(root: Element, prefix: String): String? = root.select(".time_w .tt")
        .map(Element::text)
        .firstOrNull { it.startsWith(prefix, ignoreCase = true) }

    private fun text(root: Element, selector: String): String? = root.selectFirst(selector)
        ?.text()
        ?.trim()
        ?.takeIf(String::isNotEmpty)

    private fun valueAfterColon(value: String?): String? = value
        ?.substringAfter(':', value)
        ?.trim()
        ?.takeIf(String::isNotEmpty)

    private fun integer(value: String?): Int? = value
        ?.filter(Char::isDigit)
        ?.takeIf(String::isNotEmpty)
        ?.toIntOrNull()

    private fun decimal(value: String?): Double? = value
        ?.filter { it.isDigit() || it == '.' }
        ?.takeIf(String::isNotEmpty)
        ?.toDoubleOrNull()

    private fun backgroundImageUrl(style: String?): String? = style
        ?.let { Regex("url\\(['\"]?([^'\")]+)").find(it)?.groupValues?.getOrNull(1) }
}
