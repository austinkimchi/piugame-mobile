import Foundation

/// Mirrors the web catalog's literal search, chart intersections and binary sort order.
/// Ranked private feeds remain server-owned.
enum CatalogLocalQuery {
    private static let seriesOrder = ["1st", "nx", "fiesta", "prime", "prime2", "xx", "phoenix", "phoenix2"]
    private static let chartOrder = ["singles", "doubles", "co-op"]

    static func isOrdinary(_ query: String) -> Bool {
        !["favorites", "recommendation", "recent"].contains(clean(query).lowercased())
    }

    static func modeKey(_ charts: [String]) -> String {
        let modes = unique(charts).compactMap { ["singles": "S", "doubles": "D", "co-op": "C"][$0] }
        return modes.isEmpty ? "all" : modes.joined()
    }

    static func page(snapshot: PublicCatalogSnapshot, overlay: MobileCatalogOverlay?,
                     query: String, filters: CatalogFilters) throws -> CatalogSearchPage {
        if let overlay {
            guard overlay.schemaVersion == 1, overlay.version == snapshot.selectedVersion else {
                throw PublicCatalogError.invalidSnapshot
            }
        }
        let query = clean(query)
        let text = query.isEmpty ? nil : regex(NSRegularExpression.escapedPattern(for: query))
        let compactQuery = query.replacingOccurrences(of: " ", with: "")
        let tokenQuery = matches(#"^C(?:X)?[2-5]$"#, compactQuery)
            ? regex("^C(?:X)?\(compactQuery.last!)$") : text
        let folders = unique(filters.folders), series = unique(filters.series)
        let levels = unique(filters.levels), charts = unique(filters.charts)
        let predicates: [[NSRegularExpression]] = levels.isEmpty
            ? charts.compactMap { chartPattern($0).map { [regex($0)] } }
            : levels.flatMap { level in
                charts.isEmpty ? [levelPatterns(level, chart: nil)] : charts.map { levelPatterns(level, chart: $0) }
            }
        let selected = snapshot.songs.filter { song in
            if let text {
                let values = [song.title, song.songKey, song.artist, song.folder ?? "", song.series ?? ""] + song.tags
                let titleAlias = "because of you".contains(query.lowercased())
                    && matches(#"^\s*Becouse\s+of\s+You\s*$"#, song.title)
                    && matches(#"^\s*Srav3R\s+&\s+USAO\s*$"#, song.artist)
                guard titleAlias || values.contains(where: { matches(text, $0) })
                    || song.chartSummary.contains(where: { matches(tokenQuery!, $0) }) else { return false }
            }
            if !folders.isEmpty, !folders.contains(song.folder ?? "") { return false }
            if !series.isEmpty, !series.contains(where: { seriesMatches($0, song.series) }) { return false }
            let passes = { (patterns: [NSRegularExpression]) in
                song.chartSummary.contains { token in patterns.contains { matches($0, token) } }
            }
            if !predicates.isEmpty {
                if filters.levelMode == .and, !predicates.allSatisfy(passes) { return false }
                if filters.levelMode == .or, !predicates.contains(where: passes) { return false }
            }
            return true
        }
        let favorites = Set(overlay?.favoriteSlugs ?? [])
        let mode = modeKey(charts)
        let songs = selected.map { source in
            source.catalogSong.withAccountFields(
                favorite: favorites.contains(source.slug),
                recommendation: overlay?.recommendations[source.slug]?[mode] ?? nil
            )
        }.sorted { compare($0, $1, sort: filters.sortBy, direction: filters.sortDirection) }
        return CatalogSearchPage(songs: songs, nextCursor: nil, total: songs.count,
                                 filterOptions: filterOptions(selected, charts: charts))
    }

    static func compare(_ a: CatalogSong, _ b: CatalogSong, sort: CatalogSortOption,
                        direction: CatalogSortDirection) -> Bool {
        let ascending = direction == .ascending
        func rank(_ value: String?) -> Int {
            seriesOrder.firstIndex(of: (value ?? "").lowercased().replacingOccurrences(of: " ", with: ""))
                ?? (ascending ? Int.max : -1)
        }
        let series = [number(rank(a.series), rank(b.series)), binary(a.series, b.series)]
        let comparisons: [Int]
        switch sort {
        case .title: comparisons = [binary(a.title, b.title), binary(a.artist, b.artist)] + series + [number(a.folderPosition, b.folderPosition)]
        case .artist: comparisons = [binary(a.artist, b.artist), binary(a.title, b.title)] + series + [number(a.folderPosition, b.folderPosition)]
        case .folder: comparisons = [number(a.folderPosition, b.folderPosition), binary(a.folder, b.folder)] + series + [binary(a.title, b.title), binary(a.artist, b.artist)]
        case .series: comparisons = series + [number(a.folderPosition, b.folderPosition), binary(a.title, b.title), binary(a.artist, b.artist)]
        }
        if let order = comparisons.first(where: { $0 != 0 }) { return ascending ? order < 0 : order > 0 }
        return binary(a.slug, b.slug) < 0
    }

    private static func levelPatterns(_ level: String, chart: String?) -> [NSRegularExpression] {
        if chart == "co-op" { return matches(#"^[2-5]$"#, level) ? [regex("^C(?:X)?\(level)$")] : [] }
        if let prefix = ["singles": "S", "doubles": "D"][chart ?? ""] {
            return [regex(level == "+" ? "^\(prefix)(?!(?:[1-9]|1[0-9]|2[0-7])$).+$" : "^\(prefix)\(NSRegularExpression.escapedPattern(for: level))$")]
        }
        var patterns = matches(#"^[2-5]$"#, level) ? [regex("^C\(level)$")] : []
        patterns.append(regex(level == "+" ? #"^(?!C(?:O-?OP|[2-5])?$)[^0-9]+(?!(?:[1-9]|1[0-9]|2[0-7])$).+$"# : "[^0-9]\(NSRegularExpression.escapedPattern(for: level))$"))
        return patterns
    }

    private static func filterOptions(_ songs: [PublicCatalogSong], charts: [String]) -> CatalogFilterOptions {
        let tokens = unique(songs.flatMap(\.chartSummary))
        let levels = unique(tokens.compactMap { token -> String? in
            if charts == ["co-op"] {
                return matches(#"^C[2-5]$"#, token) ? String(token.last!) : nil
            }
            if matches(#"^C(?:O-?OP|[2-5])?$"#, token) { return nil }
            let range = regex(#"([0-9]{1,2})$"#).firstMatch(in: token, range: NSRange(token.startIndex..., in: token))?.range(at: 1)
            let value = range.flatMap { Range($0, in: token) }.flatMap { Int(token[$0]) }
            return value.map { (1...27).contains($0) ? String($0) : "+" } ?? "+"
        }).sorted { ($0 == "+" ? Int.max : Int($0) ?? 0) < ($1 == "+" ? Int.max : Int($1) ?? 0) }
        let series = unique(songs.compactMap(\.series).map(normalizeSeries)).sorted {
            func rank(_ value: String) -> Int {
                seriesOrder.firstIndex(of: value.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }) ?? Int.max
            }
            return rank($0) == rank($1)
                ? $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: Locale(identifier: "en_US_POSIX")) == .orderedAscending
                : rank($0) < rank($1)
        }
        return CatalogFilterOptions(
            folders: unique(songs.compactMap(\.folder)).sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) },
            series: series, levels: levels,
            charts: chartOrder.filter { chart in tokens.contains { matches(chartPattern(chart)!, $0) } }
        )
    }

    private static func normalizeSeries(_ value: String) -> String {
        let value = clean(value)
        if matches(#"^phoenix\s*2$"#, value) { return "PHOENIX 2" }
        return matches(#"^phoenix$"#, value) ? "PHOENIX" : value
    }
    private static func seriesMatches(_ filter: String, _ series: String?) -> Bool {
        guard let series else { return false }
        let label = normalizeSeries(filter)
        if label == "PHOENIX 2" { return matches(#"^\s*phoenix\s*2\s*$"#, series) }
        if label == "PHOENIX" { return matches(#"^\s*phoenix\s*$"#, series) }
        return matches("^\(NSRegularExpression.escapedPattern(for: label))$", series)
    }
    private static func chartPattern(_ value: String) -> String? { ["singles": "^S", "doubles": "^D", "co-op": "^C"][value] }
    private static func clean(_ value: String) -> String {
        value.unicodeScalars.split { scalar in
            let code = scalar.value
            return (0x09...0x0D).contains(code) || code == 0x20 || code == 0xA0 || code == 0x1680
                || (0x2000...0x200A).contains(code) || [0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains(code)
        }.map(String.init).joined(separator: " ")
    }
    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map(clean).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern, options: .caseInsensitive) }
    private static func matches(_ pattern: String, _ value: String) -> Bool { matches(regex(pattern), value) }
    private static func matches(_ pattern: NSRegularExpression, _ value: String) -> Bool {
        pattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
    private static func binary(_ a: String?, _ b: String?) -> Int {
        guard let a else { return b == nil ? 0 : -1 }
        guard let b else { return 1 }
        let left = Array(a.unicodeScalars.map(\.value)), right = Array(b.unicodeScalars.map(\.value))
        return left == right ? 0 : (left.lexicographicallyPrecedes(right) ? -1 : 1)
    }
    private static func number(_ a: Int?, _ b: Int?) -> Int {
        guard let a else { return b == nil ? 0 : -1 }
        guard let b else { return 1 }
        return a == b ? 0 : (a < b ? -1 : 1)
    }
}

extension CatalogSong {
    func withAccountFields(favorite: Bool, recommendation: String?) -> CatalogSong {
        CatalogSong(slug: slug, title: title, artist: artist, supportedVersions: supportedVersions,
                    imagePath: imagePath, bpm: bpm, chartSummary: chartSummary, folder: folder,
                    folderPosition: folderPosition, series: series, tags: tags, isPremium: isPremium,
                    isFavorite: favorite, recommendedChartToken: recommendation)
    }
}
