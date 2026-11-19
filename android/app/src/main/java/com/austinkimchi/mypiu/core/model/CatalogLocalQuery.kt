package com.austinkimchi.mypiu.core.model

import java.util.Locale

/** Public query parity with the web catalog; ranked personal feeds stay on the server. */
object CatalogLocalQuery {
    data class Filters(
        val folders: List<String> = emptyList(), val series: List<String> = emptyList(),
        val levels: List<String> = emptyList(), val charts: List<String> = emptyList(),
        val levelMode: String = "and", val sortBy: CatalogSortOption = CatalogSortOption.SERIES,
        val sortDirection: CatalogSortDirection = CatalogSortDirection.DESCENDING,
    )
    data class Result(val page: CatalogSearchPage, val filterOptions: PublicCatalogFilterOptions)
    private val seriesOrder = listOf("1st", "nx", "fiesta", "prime", "prime2", "xx", "phoenix", "phoenix2")
    private val chartOrder = listOf("singles", "doubles", "co-op")
    private val prefixes = mapOf("singles" to "S", "doubles" to "D", "co-op" to "C")
    fun isOrdinary(query: String) = clean(query).lowercase(Locale.ROOT) !in listOf("favorites", "recommendation", "recent")
    fun modeKey(charts: List<String>) = unique(charts).mapNotNull(prefixes::get).joinToString("").ifEmpty { "all" }

    fun query(snapshot: PublicCatalogSnapshot, overlay: MobileCatalogOverlay?, query: String, filters: Filters = Filters()): Result {
        require(overlay == null || overlay.schemaVersion == 1 && overlay.version == snapshot.selectedVersion) { "Invalid account catalog response." }
        val text = clean(query).takeIf { it.isNotEmpty() }?.let { regex(Regex.escape(it)) }
        val compact = clean(query).replace(" ", "")
        val tokenQuery = if (regex("^C(?:X)?[2-5]$").containsMatchIn(compact)) regex("^C(?:X)?${compact.last()}$") else text
        val folders = unique(filters.folders)
        val series = unique(filters.series)
        val levels = unique(filters.levels)
        val charts = unique(filters.charts)
        val groups = if (levels.isEmpty()) charts.mapNotNull { prefixes[it]?.let { prefix -> listOf(regex("^$prefix")) } }
            else levels.flatMap { level -> if (charts.isEmpty()) listOf(levelPatterns(level, null)) else charts.map { levelPatterns(level, it) } }
        val selected = snapshot.songs.filter { song ->
            val alias = text != null && "because of you".contains(clean(query).lowercase(Locale.ROOT)) &&
                regex("^\\s*Becouse\\s+of\\s+You\\s*$").containsMatchIn(song.title) &&
                regex("^\\s*Srav3R\\s+&\\s+USAO\\s*$").containsMatchIn(song.artist)
            val textMatch = text == null || alias || (listOf(song.title, song.songKey, song.artist, song.folder.orEmpty(), song.series.orEmpty()) + song.tags).any(text::containsMatchIn) || song.chartSummary.any(tokenQuery!!::containsMatchIn)
            val levelMatch: (List<Regex>) -> Boolean = { patterns -> song.chartSummary.any { token -> patterns.any { it.containsMatchIn(token) } } }
            textMatch && (folders.isEmpty() || song.folder in folders) &&
                (series.isEmpty() || series.any { seriesMatches(it, song.series) }) &&
                (groups.isEmpty() || if (filters.levelMode == "and") groups.all(levelMatch) else groups.any(levelMatch))
        }
        val favorites = overlay?.favoriteSlugs.orEmpty().toSet()
        val mode = modeKey(charts)
        val songs = selected.map { it.catalogSong().copy(isFavorite = it.slug in favorites, recommendedChartToken = overlay?.recommendations?.get(it.slug)?.get(mode)) }
            .sortedWith(comparator(filters.sortBy, filters.sortDirection))
        return Result(CatalogSearchPage(songs, total = songs.size), filterOptions(selected, charts))
    }

    fun comparator(sort: CatalogSortOption, direction: CatalogSortDirection): Comparator<CatalogSong> = Comparator { a, b ->
        val sign = if (direction == CatalogSortDirection.ASCENDING) 1 else -1
        fun rank(value: String?) = seriesOrder.indexOf(value.orEmpty().lowercase(Locale.ROOT).replace(" ", "")).let { if (it < 0 && sign == 1) Int.MAX_VALUE else it }
        val series = listOf(rank(a.series).compareTo(rank(b.series)), binary(a.series, b.series))
        val comparisons = when (sort) {
            CatalogSortOption.TITLE -> listOf(binary(a.title, b.title), binary(a.artist, b.artist)) + series + compareValues(a.folderPosition, b.folderPosition)
            CatalogSortOption.ARTIST -> listOf(binary(a.artist, b.artist), binary(a.title, b.title)) + series + compareValues(a.folderPosition, b.folderPosition)
            CatalogSortOption.FOLDER -> listOf(compareValues(a.folderPosition, b.folderPosition), binary(a.folder, b.folder)) + series + listOf(binary(a.title, b.title), binary(a.artist, b.artist))
            CatalogSortOption.SERIES -> series + listOf(compareValues(a.folderPosition, b.folderPosition), binary(a.title, b.title), binary(a.artist, b.artist))
        }
        comparisons.firstOrNull { it != 0 }?.let { it * sign } ?: binary(a.slug, b.slug)
    }

    private fun levelPatterns(level: String, chart: String?): List<Regex> {
        if (chart == "co-op") return if (Regex("^[2-5]$").matches(level)) listOf(regex("^C(?:X)?$level$")) else emptyList()
        val prefix = prefixes[chart]?.takeIf { chart != "co-op" }
        if (prefix != null) return listOf(regex(if (level == "+") "^$prefix(?!(?:[1-9]|1[0-9]|2[0-7])$).+$" else "^$prefix${Regex.escape(level)}$"))
        return (if (Regex("^[2-5]$").matches(level)) listOf(regex("^C$level$")) else emptyList()) +
            regex(if (level == "+") "^(?!C(?:O-?OP|[2-5])?$)[^0-9]+(?!(?:[1-9]|1[0-9]|2[0-7])$).+$" else "[^0-9]${Regex.escape(level)}$")
    }
    private fun filterOptions(songs: List<PublicCatalogSong>, charts: List<String>): PublicCatalogFilterOptions {
        val tokens = unique(songs.flatMap { it.chartSummary })
        val levels = tokens.mapNotNull { token ->
            if (charts == listOf("co-op")) regex("^C([2-5])$").find(token)?.groupValues?.get(1)
            else if (regex("^C(?:O-?OP|[2-5])?$").containsMatchIn(token)) null
            else Regex("([0-9]{1,2})$").find(token)?.groupValues?.get(1)?.toIntOrNull().let { if (it != null && it in 1..27) it.toString() else "+" }
        }.distinct().sortedBy { it.toIntOrNull() ?: Int.MAX_VALUE }
        fun rank(value: String) = seriesOrder.indexOf(value.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9]"), "")).let { if (it < 0) Int.MAX_VALUE else it }
        val series = unique(songs.mapNotNull { it.series }.map(::normalizeSeries)).sortedWith(compareBy<String> { rank(it) }.thenBy { it.lowercase(Locale.ROOT) })
        return PublicCatalogFilterOptions(unique(songs.mapNotNull { it.folder }).sorted(), series, levels,
            chartOrder.filter { chart -> tokens.any { regex("^${prefixes[chart]}").containsMatchIn(it) } })
    }
    private fun normalizeSeries(value: String): String = clean(value).let {
        if (regex("^phoenix\\s*2$").matches(it)) "PHOENIX 2" else if (regex("^phoenix$").matches(it)) "PHOENIX" else it
    }
    private fun seriesMatches(filter: String, value: String?): Boolean {
        if (value == null) return false
        return when (val label = normalizeSeries(filter)) {
            "PHOENIX 2" -> regex("^\\s*phoenix\\s*2\\s*$").containsMatchIn(value)
            "PHOENIX" -> regex("^\\s*phoenix\\s*$").containsMatchIn(value)
            else -> regex("^${Regex.escape(label)}$").containsMatchIn(value)
        }
    }
    // ECMAScript whitespace, explicitly enumerated: no JVM-only inline regex flags.
    // ICU's Unicode whitespace also includes NEL, while JavaScript excludes it and includes BOM.
    private fun clean(value: String) = buildString {
        var pendingSpace = false
        for (character in value) {
            val code = character.code
            val whitespace = code in 0x09..0x0D || code == 0x20 || code == 0xA0 || code == 0x1680 ||
                code in 0x2000..0x200A || code in listOf(0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF)
            if (whitespace) pendingSpace = isNotEmpty()
            else {
                if (pendingSpace) append(' ')
                append(character)
                pendingSpace = false
            }
        }
    }
    private fun unique(values: List<String>) = values.map(::clean).filter { it.isNotEmpty() }.distinct()
    private fun regex(pattern: String) = Regex(pattern, RegexOption.IGNORE_CASE)
    private fun binary(left: String?, right: String?): Int {
        if (left == null) return if (right == null) 0 else -1
        if (right == null) return 1
        var a = 0; var b = 0
        while (a < left.length && b < right.length) {
            val x = Character.codePointAt(left, a); val y = Character.codePointAt(right, b)
            if (x != y) return x.compareTo(y)
            a += Character.charCount(x); b += Character.charCount(y)
        }
        return (left.length - a).compareTo(right.length - b)
    }
}
