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
            default: "MyPIU could not complete the request."
            }
        }
    }

    var isUnauthorized: Bool {
        if case .server(let status, _) = self { return status == 401 }
        return false
    }
}

actor MyPIUAPIClient {
    static let productionBaseURL = URL(string: "https://mypiu.austin.kim")!
    static let clientID = "mypiu-ios"
    static let redirectURI = "mypiu://oauth/callback"

    nonisolated private let baseURL: URL
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
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(response.expiresIn))
        )
    }

    func account(accessToken: String) async throws -> MyPIUAccount {
        var request = authenticatedRequest(path: "/api/mobile/v1/me", accessToken: accessToken)
        request.httpMethod = "GET"
        let response: AccountResponse = try await send(request)
        return response.account
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

private struct ErrorResponse: Decodable {
    let error: String
}
