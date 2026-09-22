import Foundation

enum PIUGameClientError: LocalizedError {
    case invalidResponse
    case authenticationFailed
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "PIUGAME returned an invalid response."
        case .authenticationFailed: "PIUGAME could not verify those credentials."
        case .unexpectedStatus(let status): "PIUGAME returned HTTP \(status)."
        }
    }
}

actor PIUGameClient {
    private let version: PIUGameVersion
    private let session: URLSession
    private let parser: PIUHTMLParser

    init(version: PIUGameVersion, parser: PIUHTMLParser = PIUHTMLParser()) {
        self.version = version
        self.parser = parser

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": "MyPIU-iOS/0.1"
        ]
        self.session = URLSession(configuration: configuration)
    }

    func loginAndFetch(username: String, password: String) async throws -> PIUSnapshot {
        try await login(username: username, password: password)
        return try await fetchSnapshot(username: username)
    }

    func login(username: String, password: String) async throws {
        var request = URLRequest(url: url(path: "/bbs/login_check.php"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(version.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(version.baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "url", value: "/"),
            URLQueryItem(name: "mb_id", value: username),
            URLQueryItem(name: "mb_password", value: password)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        _ = try await send(request)
        let probe = try await fetchHTML(path: "/my_page/play_data.php")
        guard probe.range(of: "subProfile_wrap|play_data_wrap|profile_name", options: .regularExpression) != nil else {
            throw PIUGameClientError.authenticationFailed
        }
    }

    func fetchSnapshot(username: String) async throws -> PIUSnapshot {
        async let profileHTML = fetchHTML(path: "/my_page/play_data.php")
        async let recentHTML = fetchHTML(path: "/my_page/recently_played.php")
        async let pumbilityHTML = fetchHTML(path: "/my_page/pumbility.php")

        let (profilePage, recentPage, pumbilityPage) = try await (profileHTML, recentHTML, pumbilityHTML)
        let pumbility = try parser.parsePumbilityScore(html: pumbilityPage)
        return try PIUSnapshot(
            version: version,
            profile: parser.parseProfile(html: profilePage, username: username, pumbilityScore: pumbility),
            recentPlays: parser.parseRecentPlays(html: recentPage),
            fetchedAt: Date()
        )
    }

    private func fetchHTML(path: String) async throws -> String {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw PIUGameClientError.invalidResponse
        }
        return html
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PIUGameClientError.invalidResponse
        }
        guard (200..<400).contains(response.statusCode) else {
            throw PIUGameClientError.unexpectedStatus(response.statusCode)
        }
        return data
    }

    private func url(path: String) -> URL {
        URL(string: path, relativeTo: version.baseURL)!.absoluteURL
    }
}
