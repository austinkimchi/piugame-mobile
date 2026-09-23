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

struct PIUGameHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let url: URL?
}

protocol PIUGameHTTPTransport: Sendable {
    func response(for request: URLRequest) async throws -> PIUGameHTTPResponse
}

private struct URLSessionPIUGameHTTPTransport: PIUGameHTTPTransport {
    let session: URLSession

    func response(for request: URLRequest) async throws -> PIUGameHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PIUGameClientError.invalidResponse
        }
        return PIUGameHTTPResponse(
            data: data,
            statusCode: response.statusCode,
            url: response.url
        )
    }
}

actor PIUGameClient {
    private let version: PIUGameVersion
    private let parser: PIUHTMLParser
    private let transport: any PIUGameHTTPTransport
    private var authenticatedUsername: String?

    init(
        version: PIUGameVersion,
        parser: PIUHTMLParser = PIUHTMLParser(),
        transport: (any PIUGameHTTPTransport)? = nil
    ) {
        self.version = version
        self.parser = parser

        if let transport {
            self.transport = transport
        } else {
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
            self.transport = URLSessionPIUGameHTTPTransport(
                session: URLSession(configuration: configuration)
            )
        }
    }

    func loginAndFetch(username: String, password: String) async throws -> PIUSnapshot {
        let profileHTML = try await authenticatedProfile(username: username, password: password)
        do {
            return try await fetchSnapshot(username: username, profileHTML: profileHTML)
        } catch {
            guard isAuthenticationFailure(error) else { throw error }
            let refreshedProfileHTML = try await authenticate(username: username, password: password)
            return try await fetchSnapshot(username: username, profileHTML: refreshedProfileHTML)
        }
    }

    func login(username: String, password: String) async throws {
        _ = try await authenticate(username: username, password: password)
    }

    private func authenticate(username: String, password: String) async throws -> String {
        authenticatedUsername = nil
        try await prepareLoginSession()

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
        guard hasAuthenticatedProfile(probe) else {
            throw PIUGameClientError.authenticationFailed
        }
        authenticatedUsername = username
        return probe
    }

    private func prepareLoginSession() async throws {
        var request = URLRequest(url: url(path: "/bbs/login.php"))
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        // PIUGAME initializes its PHP session through the AM.PASS SSO redirect
        // chain before it will evaluate a credential POST. The final response is
        // intentionally the login page, so this request cannot use send(_:),
        // which treats that URL as an expired authenticated session.
        let response = try await transport.response(for: request)
        guard (200..<400).contains(response.statusCode) else {
            throw PIUGameClientError.unexpectedStatus(response.statusCode)
        }
    }

    func fetchSnapshot(username: String) async throws -> PIUSnapshot {
        let profileHTML = try await fetchHTML(path: "/my_page/play_data.php")
        guard hasAuthenticatedProfile(profileHTML) else {
            authenticatedUsername = nil
            throw PIUGameClientError.authenticationFailed
        }
        authenticatedUsername = username
        return try await fetchSnapshot(username: username, profileHTML: profileHTML)
    }

    private func authenticatedProfile(username: String, password: String) async throws -> String {
        if authenticatedUsername == username {
            do {
                let profileHTML = try await fetchHTML(path: "/my_page/play_data.php")
                if hasAuthenticatedProfile(profileHTML) {
                    return profileHTML
                }
            } catch {
                guard isAuthenticationFailure(error) else { throw error }
            }
            authenticatedUsername = nil
        }
        return try await authenticate(username: username, password: password)
    }

    private func fetchSnapshot(username: String, profileHTML: String) async throws -> PIUSnapshot {
        async let recentHTML = fetchHTML(path: "/my_page/recently_played.php")
        async let pumbilityHTML = fetchHTML(path: "/my_page/pumbility.php")

        let (recentPage, pumbilityPage) = try await (recentHTML, pumbilityHTML)
        guard !isLoginPage(recentPage), !isLoginPage(pumbilityPage) else {
            authenticatedUsername = nil
            throw PIUGameClientError.authenticationFailed
        }
        let pumbility = try parser.parsePumbilityScore(html: pumbilityPage)
        return try PIUSnapshot(
            version: version,
            profile: parser.parseProfile(html: profileHTML, username: username, pumbilityScore: pumbility),
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
        let response = try await transport.response(for: request)
        if isLoginURL(response.url) {
            authenticatedUsername = nil
            throw PIUGameClientError.authenticationFailed
        }
        guard (200..<400).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                authenticatedUsername = nil
            }
            throw PIUGameClientError.unexpectedStatus(response.statusCode)
        }
        return response.data
    }

    private func hasAuthenticatedProfile(_ html: String) -> Bool {
        !isLoginPage(html) && html.range(
            of: "subProfile_wrap|play_data_wrap|profile_name",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func isLoginPage(_ html: String) -> Bool {
        let hasLoginForm = html.range(
            of: #"form[^>]+action\s*=\s*['"][^'"]*login_check\.php"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let hasUsername = html.range(
            of: #"name\s*=\s*['"]?mb_id['"]?"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let hasPassword = html.range(
            of: #"name\s*=\s*['"]?mb_password['"]?"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return hasLoginForm
            || (hasUsername && hasPassword)
            || html.localizedCaseInsensitiveContains(
                "you must be logged in to use many of pump it up online services"
            )
    }

    private func isLoginURL(_ url: URL?) -> Bool {
        guard let path = url?.path.lowercased() else { return false }
        return path == "/login.php" || path == "/bbs/login.php"
    }

    private func isAuthenticationFailure(_ error: Error) -> Bool {
        if case PIUGameClientError.authenticationFailed = error {
            return true
        }
        if case PIUGameClientError.unexpectedStatus(let status) = error {
            return status == 401 || status == 403
        }
        return false
    }

    private func url(path: String) -> URL {
        URL(string: path, relativeTo: version.baseURL)!.absoluteURL
    }
}
