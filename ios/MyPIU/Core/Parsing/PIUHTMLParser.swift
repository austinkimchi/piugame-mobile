import Foundation
import SwiftSoup

enum PIUParsingError: LocalizedError {
    case missingProfile
    case missingRecentPlayList

    var errorDescription: String? {
        switch self {
        case .missingProfile: "PIUGAME returned an unrecognized profile page."
        case .missingRecentPlayList: "PIUGAME returned an unrecognized recent-play page."
        }
    }
}

struct PIUHTMLParser: Sendable {
    func parseProfile(
        html: String,
        username: String,
        pumbilityScore: Double? = nil,
        baseURL: URL? = nil
    ) throws -> PIUProfile {
        let document = try SwiftSoup.parse(html)
        guard !(try document.select(".subProfile_wrap, .play_data_wrap")).isEmpty() else {
            throw PIUParsingError.missingProfile
        }

        let gameIDTag = try text(document, ".profile_name .name_w .t2")
            .map { $0.replacingOccurrences(of: #"\s*#\s*"#, with: "#", options: .regularExpression) }
        let clearText = try text(document, ".clear_w .l_con .t1")
        let clearParts = clearText?.split(separator: "/", maxSplits: 1).map(String.init) ?? []

        var plateCounts: [String: Int] = [:]
        for item in try document.select(".plate_w .list li").array() {
            guard let code = try item.select("[data-type]").first()?.attr("data-type").lowercased(),
                  !code.isEmpty,
                  let count = integer(try item.select(".t_num").first()?.text()) else { continue }
            plateCounts[code] = count
        }

        return PIUProfile(
            username: username,
            titleName: try text(document, ".profile_name .name_w .t1"),
            gameIDTag: gameIDTag,
            avatarURL: try backgroundImageURL(
                document.select(".profile_img .re").first()?.attr("style"),
                baseURL: baseURL
            ),
            pp: decimal(try text(document, ".profile_etc .tt")),
            pumbilityScore: pumbilityScore,
            playCount: integer(try text(document, ".board_search .total .t2, .board_search .total_wrap .t2")),
            rating: integer(try text(document, ".play_data_wrap .my_w .num")),
            clearCount: clearParts.first.flatMap(integer),
            totalCharts: clearParts.dropFirst().first.flatMap(integer),
            progressPercent: integer(try text(document, ".clear_w .graph .num")),
            recentArcade: valueAfterColon(try timeValue(document, prefix: "recently access games")),
            lastAccess: valueAfterColon(try timeValue(document, prefix: "last access date")),
            plateCounts: plateCounts
        )
    }

    func parsePumbilityScore(html: String) throws -> Double? {
        let document = try SwiftSoup.parse(html)
        let selectors = [
            ".pumbility_total_wrap .pumbility-point-sub",
            ".pumbility_total_wrap .t2",
            ".total_pumbility .t2",
            ".pumbility_total .t2",
            "[class*=pumbility] [class*=total] .num",
            "[class*=pumbility] [class*=score]"
        ]
        for selector in selectors {
            if let value = decimal(try text(document, selector)) {
                return value
            }
        }

        // PIUGAME has changed this summary's class names between releases. Keep
        // the visible label as the stable anchor and inspect its nearest card.
        for element in try document.getAllElements().array() {
            let label = element.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.caseInsensitiveCompare("Pumbility") == .orderedSame else { continue }

            var ancestor = element.parent()
            for _ in 0..<3 {
                guard let context = ancestor else { break }
                for candidate in try context.select(".t2, .num, [class*=score], strong, b, dd, span").array() {
                    guard candidate !== element,
                          let value = decimal(candidate.ownText()) else { continue }
                    return value
                }
                ancestor = context.parent()
            }
        }
        return nil
    }

    func parseRecentPlays(html: String, baseURL: URL? = nil) throws -> [RecentPlay] {
        let document = try SwiftSoup.parse(html)
        let containers = try document.select(".recently_playeList")
        guard !containers.isEmpty() else {
            throw PIUParsingError.missingRecentPlayList
        }

        return try document.select(".recently_playeList > li").array().compactMap { item in
            guard let songName = try text(item, ".song_name p"), !songName.isEmpty else { return nil }
            let scoreText = try text(item, ".con2 .list > li:nth-child(2) .tx")
            let stageBreak = scoreText?.localizedCaseInsensitiveContains("stage break") == true
            var judgments: [String: Int] = [:]
            for cell in try item.select("table.recently_play td").array() {
                let key = try cell.attr("data-th").lowercased()
                judgments[key] = integer(try cell.select(".tx").first()?.text())
            }

            return RecentPlay(
                songName: songName,
                songImageURL: try backgroundImageURL(
                    item.select(".wrap_in .in").first()?.attr("style"),
                    baseURL: baseURL
                ),
                mode: try chartMode(item),
                level: try chartLevel(item),
                score: stageBreak ? nil : integer(scoreText),
                grade: try assetCode(item, containing: "/grade/"),
                plate: try assetCode(item, containing: "/plate/"),
                stageBreak: stageBreak,
                judgments: JudgmentCounts(
                    perfect: judgments["perfect"],
                    great: judgments["great"],
                    good: judgments["good"],
                    bad: judgments["bad"],
                    miss: judgments["miss"]
                ),
                playedAt: try text(item, ".recently_date_tt")
            )
        }
    }

    private func chartMode(_ root: Element) throws -> String? {
        guard let source = try root.select(".stepBall_in .tw img").first()?.attr("src").lowercased() else { return nil }
        let filename = URL(string: source)?.deletingPathExtension().lastPathComponent ?? source
        if filename.hasPrefix("s_") { return "S" }
        if filename.hasPrefix("d_") { return "D" }
        if filename.hasPrefix("c_") { return "C" }
        return nil
    }

    private func chartLevel(_ root: Element) throws -> String? {
        let images = try root.select(".stepBall_in .numw img").array()
        guard !images.isEmpty else { return nil }

        var digits: [String] = []
        for image in images {
            let source = try image.attr("src")
            let filename = (URL(string: source)?.deletingPathExtension().lastPathComponent ?? source).lowercased()
            guard filename.range(of: #"^[sdc]_num_[0-9]$"#, options: .regularExpression) != nil else { return nil }
            guard let digit = filename.last, digit.isNumber else { return nil }
            digits.append(String(digit))
        }
        return digits.joined()
    }

    private func assetCode(_ root: Element, containing path: String) throws -> String? {
        for image in try root.select("img").array() {
            let source = try image.attr("src")
            guard source.localizedCaseInsensitiveContains(path) else { continue }
            return URL(string: source)?.deletingPathExtension().lastPathComponent.lowercased()
        }
        return nil
    }

    private func timeValue(_ document: Document, prefix: String) throws -> String? {
        for value in try document.select(".time_w .tt").array() {
            let candidate = try value.text()
            if candidate.lowercased().hasPrefix(prefix) { return candidate }
        }
        return nil
    }

    private func text(_ root: Element, _ selector: String) throws -> String? {
        let value = try root.select(selector).first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func valueAfterColon(_ value: String?) -> String? {
        guard let value, let colon = value.firstIndex(of: ":") else { return value }
        let result = value[value.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func integer(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private func decimal(_ value: String?) -> Double? {
        guard let value else { return nil }
        let normalized = value.filter { $0.isNumber || $0 == "." }
        return normalized.isEmpty ? nil : Double(normalized)
    }

    private func backgroundImageURL(_ style: String?, baseURL: URL?) -> URL? {
        guard let style,
              let range = style.range(of: #"url\(['\"]?([^'\")]+)"#, options: .regularExpression) else { return nil }
        let match = String(style[range])
            .replacingOccurrences(of: #"^url\(['\"]?"#, with: "", options: .regularExpression)
        return URL(string: match, relativeTo: baseURL)?.absoluteURL
    }

}
