import Foundation

enum MyPIUAPIError: LocalizedError, Equatable {
    case invalidResponse
    case server(status: Int, code: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "MyPIU returned an invalid response."
        case .server(_, let code):
            switch code {
            case "invalid_token": "Your MyPIU session expired. Sign in again."
            case "piu_account_not_linked": "Link this PIUGAME account on MyPIU before uploading."
            case "piu_username_mismatch": "The PIUGAME username does not match the account linked to MyPIU."
            case "rate_limited": "MyPIU is receiving syncs too quickly. Try again shortly."
            case "account_busy": "MyPIU is finishing another account update. Try again shortly."
            case "account_not_found": "This MyPIU account no longer exists."
            case "deletion_failed": "MyPIU could not delete the account. Try again."
            case "song_not_found": "This song is not available in the selected PIU version."
            case "chart_not_found": "This chart is not available in the selected PIU version."
            case "invalid_chart", "invalid_version": "MyPIU could not identify that chart."
            case "favorite_update_failed": "MyPIU could not update this favorite. Try again."
            default: "MyPIU could not complete the request."
            }
        }
    }

    var isUnauthorized: Bool {
        if case .server(let status, _) = self { return status == 401 }
        return false
    }

    var isAccountNotFound: Bool {
        if case .server(_, let code) = self { return code == "account_not_found" }
        return false
    }
}

actor MyPIUAPIClient {
    static let productionBaseURL = URL(string: "https://mypiu.austin.kim")!
    static let clientID = "mypiu-ios"
    static let redirectURI = "mypiu://oauth/callback"

    nonisolated private let baseURL: URL
    nonisolated var cacheOrigin: String { baseURL.absoluteString }
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL = productionBaseURL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "MyPIU-iOS/0.1"]
        self.session = URLSession(configuration: configuration)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func exchangeAuthorizationCode(
        code: String,
        verifier: String,
        installationID: String,
        appVersion: String?
    ) async throws -> MyPIUAccessToken {
        var request = URLRequest(url: url(path: "/api/mobile/v1/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "installation_id", value: installationID),
            URLQueryItem(name: "app_version", value: appVersion)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let response: TokenResponse = try await send(request)
        guard response.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame else {
            throw MyPIUAPIError.invalidResponse
        }
        return MyPIUAccessToken(
            value: response.accessToken,
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(response.expiresIn)),
            installationID: installationID
        )
    }

    func exchangeAppleIdentityToken(
        identityToken: String,
        nonce: String,
        firstName: String?,
        lastName: String?,
        installationID: String,
        appVersion: String?
    ) async throws -> MyPIUAccessToken {
        var request = URLRequest(url: url(path: "/api/mobile/v1/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:token-exchange"),
            URLQueryItem(name: "subject_token_type", value: "urn:ietf:params:oauth:token-type:id_token"),
            URLQueryItem(name: "subject_token", value: identityToken),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "first_name", value: firstName),
            URLQueryItem(name: "last_name", value: lastName),
            URLQueryItem(name: "installation_id", value: installationID),
            URLQueryItem(name: "app_version", value: appVersion)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let response: TokenResponse = try await send(request)
        guard response.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame else {
            throw MyPIUAPIError.invalidResponse
        }
        return MyPIUAccessToken(
            value: response.accessToken,
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(response.expiresIn)),
            installationID: installationID
        )
    }

    func account(accessToken: String) async throws -> MyPIUAccount {
        var request = authenticatedRequest(path: "/api/mobile/v1/me", accessToken: accessToken)
        request.httpMethod = "GET"
        let response: AccountResponse = try await send(request)
        return response.account
    }

    func performance(accessToken: String) async throws -> MyPIUPerformanceDashboard {
        var request = authenticatedRequest(path: "/api/mobile/v1/performance", accessToken: accessToken)
        request.httpMethod = "GET"
        let response: PerformanceResponse = try await send(request)
        return response.performance
    }

    func performanceSession(accessToken: String) async throws -> MyPIUPerformanceSession? {
        var request = authenticatedRequest(
            path: "/api/mobile/v1/performance/session",
            accessToken: accessToken
        )
        request.httpMethod = "GET"
        let response: PerformanceSessionResponse = try await send(request)
        return response.session
    }

    func performanceSessions(
        offset: Int = 0,
        limit: Int = 20,
        accessToken: String
    ) async throws -> MyPIUPerformanceSessionsPage {
        var components = URLComponents(
            url: url(path: "/api/mobile/v1/performance/sessions"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(max(0, offset))),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]
        guard let requestURL = components.url else {
            throw MyPIUAPIError.invalidResponse
        }
        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        let response: PerformanceSessionsResponse = try await send(request)
        return MyPIUPerformanceSessionsPage(
            sessions: response.sessions,
            nextOffset: response.nextOffset,
            selectedVersion: response.selectedVersion
        )
    }

    func catalogOverlay(version: PIUGameVersion, accessToken: String) async throws -> MobileCatalogOverlay {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/mobile/v1/catalog/overlay"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "version", value: version.rawValue)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func searchCatalog(
        query: String,
        cursor: String? = nil,
        version: PIUGameVersion,
        filters: CatalogFilters = .empty,
        limit: Int = 30,
        accessToken: String? = nil
    ) async throws -> CatalogSearchPage {
        var components = URLComponents(
            url: url(path: "/api/songs/search"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 35))),
            URLQueryItem(name: "sortBy", value: filters.sortBy.rawValue),
            URLQueryItem(name: "sortDirection", value: filters.sortDirection.rawValue),
            URLQueryItem(name: "supportedVersion", value: version.rawValue)
        ]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        queryItems.append(contentsOf: filters.folders.map { URLQueryItem(name: "folder", value: $0) })
        queryItems.append(contentsOf: filters.series.map { URLQueryItem(name: "series", value: $0) })
        queryItems.append(contentsOf: filters.levels.map { URLQueryItem(name: "level", value: $0) })
        queryItems.append(contentsOf: filters.charts.map { URLQueryItem(name: "chart", value: $0) })
        queryItems.append(URLQueryItem(name: "levelMode", value: filters.levelMode.rawValue))
        components.queryItems = queryItems
        guard let requestURL = components.url else {
            throw MyPIUAPIError.invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request)
    }

    func setFavorite(
        songSlug: String,
        saved: Bool,
        version: PIUGameVersion,
        accessToken: String
    ) async throws -> Bool {
        guard let encodedSlug = encodedPathSegment(songSlug) else {
            throw MyPIUAPIError.invalidResponse
        }
        var request = authenticatedRequest(
            path: "/api/mobile/v1/songs/\(encodedSlug)/favorite",
            accessToken: accessToken
        )
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            FavoriteUpdatePayload(saved: saved, version: version)
        )
        let response: FavoriteUpdateResponse = try await send(request)
        guard response.slug == songSlug else {
            throw MyPIUAPIError.invalidResponse
        }
        return response.isFavorite
    }

    func chartPerformance(
        songSlug: String,
        chartToken: String,
        version: PIUGameVersion,
        accessToken: String
    ) async throws -> MyPIUSongChartPerformance? {
        guard let encodedSlug = encodedPathSegment(songSlug) else {
            throw MyPIUAPIError.invalidResponse
        }
        var components = URLComponents(
            url: url(path: "/api/mobile/v1/songs/\(encodedSlug)/performance"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "chart", value: chartToken),
            URLQueryItem(name: "version", value: version.rawValue)
        ]
        guard let requestURL = components.url else {
            throw MyPIUAPIError.invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: ChartPerformanceResponse = try await send(request)
        return response.performance
    }

    func upload(
        snapshot: PIUSnapshot,
        accessToken: String,
        installationID: String,
        appVersion: String?
    ) async throws -> MyPIUSyncResult {
        var request = authenticatedRequest(path: "/api/mobile/v1/performance/import", accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            MobilePerformanceImportPayload(
                snapshot: snapshot,
                installationId: installationID,
                appVersion: appVersion
            )
        )
        return try await send(request)
    }

    func revoke(accessToken: String) async throws {
        var request = authenticatedRequest(path: "/api/mobile/v1/token", accessToken: accessToken)
        request.httpMethod = "DELETE"
        _ = try await sendData(request)
    }

    func deleteAccount(accessToken: String) async throws {
        var request = authenticatedRequest(path: "/api/mobile/v1/account", accessToken: accessToken)
        request.httpMethod = "DELETE"
        _ = try await sendData(request)
    }

    nonisolated func authorizationURL(
        provider: MyPIUAuthProvider,
        challenge: String,
        state: String
    ) -> URL {
        var components = URLComponents(
            url: URL(string: "/api/mobile/v1/authorize", relativeTo: baseURL)!.absoluteURL,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "provider", value: provider.rawValue)
        ]
        return components.url!
    }

    private func authenticatedRequest(path: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url(path: path))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await sendData(request)
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw MyPIUAPIError.invalidResponse
        }
        return decoded
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MyPIUAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? decoder.decode(ErrorResponse.self, from: data))?.error ?? "request_failed"
            throw MyPIUAPIError.server(status: response.statusCode, code: code)
        }
        return data
    }

    private func url(path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private func encodedPathSegment(_ value: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.formUnion(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private struct AccountResponse: Decodable {
    let account: MyPIUAccount
}

private struct PerformanceResponse: Decodable {
    let performance: MyPIUPerformanceDashboard
}

private struct PerformanceSessionResponse: Decodable {
    let session: MyPIUPerformanceSession?
}

private struct PerformanceSessionsResponse: Decodable {
    let sessions: [MyPIUPerformanceSession]
    let nextOffset: Int?
    let selectedVersion: String?
}

private struct FavoriteUpdatePayload: Encodable {
    let saved: Bool
    let version: PIUGameVersion
}

private struct FavoriteUpdateResponse: Decodable {
    let slug: String
    let isFavorite: Bool
}

private struct ChartPerformanceResponse: Decodable {
    let performance: MyPIUSongChartPerformance?
}

private struct ErrorResponse: Decodable {
    let error: String
}
