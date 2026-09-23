import Foundation
import XCTest
@testable import MyPIU

final class PIUGameClientTests: XCTestCase {
    func testRefreshReusesAuthenticatedSessionAndAvoidsDuplicateProfileFetch() async throws {
        let transport = PIUGameTransportStub()
        let client = PIUGameClient(version: .phoenix2, transport: transport)

        let first = try await client.loginAndFetch(username: "fixture", password: "secret")
        let firstRequests = await transport.recordedRequests()
        let second = try await client.loginAndFetch(username: "fixture", password: "secret")
        let requests = await transport.recordedRequests()

        XCTAssertEqual(first.profile.username, "fixture")
        XCTAssertEqual(second.profile.pumbilityScore, 123.45)
        XCTAssertEqual(firstRequests.count, 4)
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(requests.filter { $0.method == "POST" && $0.path == "/bbs/login_check.php" }.count, 1)
        XCTAssertEqual(requests.filter { $0.path == "/my_page/play_data.php" }.count, 2)
        XCTAssertEqual(requests.filter { $0.path == "/my_page/recently_played.php" }.count, 2)
        XCTAssertEqual(requests.filter { $0.path == "/my_page/pumbility.php" }.count, 2)
    }

    func testExpiredSessionRelogsInAndRetriesWithFreshCookies() async throws {
        let transport = PIUGameTransportStub()
        let client = PIUGameClient(version: .phoenix2, transport: transport)

        _ = try await client.loginAndFetch(username: "fixture", password: "secret")
        await transport.expireSession()
        _ = try await client.loginAndFetch(username: "fixture", password: "secret")
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.count, 9)
        XCTAssertEqual(requests.filter { $0.path == "/bbs/login_check.php" }.count, 2)
        XCTAssertEqual(requests.filter { $0.path == "/my_page/play_data.php" }.count, 3)
    }

    func testAuthenticatedSessionIsBoundToTheUsername() async throws {
        let transport = PIUGameTransportStub()
        let client = PIUGameClient(version: .phoenix2, transport: transport)

        _ = try await client.loginAndFetch(username: "first", password: "secret")
        _ = try await client.loginAndFetch(username: "second", password: "secret")
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.count, 8)
        XCTAssertEqual(requests.filter { $0.path == "/bbs/login_check.php" }.count, 2)
        XCTAssertEqual(requests.filter { $0.path == "/my_page/play_data.php" }.count, 2)
    }

    func testLoginPageFromAuthenticatedEndpointInvalidatesSession() async throws {
        let transport = PIUGameTransportStub()
        let client = PIUGameClient(version: .phoenix2, transport: transport)

        _ = try await client.loginAndFetch(username: "fixture", password: "secret")
        await transport.expireDuringNextRecentFetch()
        _ = try await client.loginAndFetch(username: "fixture", password: "secret")
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.count, 11)
        XCTAssertEqual(requests.filter { $0.path == "/bbs/login_check.php" }.count, 2)
    }

    func testAuthenticationStatusFromProfileRelogsWithinTheSameRefresh() async throws {
        let transport = PIUGameTransportStub()
        let client = PIUGameClient(version: .phoenix2, transport: transport)

        _ = try await client.loginAndFetch(username: "fixture", password: "secret")
        await transport.rejectNextProfileRequest(statusCode: 401)
        _ = try await client.loginAndFetch(username: "fixture", password: "secret")
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.count, 9)
        XCTAssertEqual(requests.filter { $0.path == "/bbs/login_check.php" }.count, 2)
        XCTAssertEqual(requests.filter { $0.path == "/my_page/play_data.php" }.count, 3)
    }

    func testLoginRedirectFromAuthenticatedEndpointRelogsBeforeParsing() async throws {
        let transport = PIUGameTransportStub()
        let client = PIUGameClient(version: .phoenix2, transport: transport)

        _ = try await client.loginAndFetch(username: "fixture", password: "secret")
        await transport.redirectNextPumbilityRequestToLogin()
        let snapshot = try await client.loginAndFetch(username: "fixture", password: "secret")
        let requests = await transport.recordedRequests()

        XCTAssertEqual(snapshot.profile.pumbilityScore, 123.45)
        XCTAssertEqual(requests.count, 11)
        XCTAssertEqual(requests.filter { $0.path == "/bbs/login_check.php" }.count, 2)
    }
}

private actor PIUGameTransportStub: PIUGameHTTPTransport {
    struct RecordedRequest: Sendable {
        let method: String
        let path: String
    }

    private var authenticated = false
    private var shouldExpireDuringRecentFetch = false
    private var rejectedProfileStatusCode: Int?
    private var shouldRedirectPumbilityToLogin = false
    private var requests: [RecordedRequest] = []

    func response(for request: URLRequest) async throws -> PIUGameHTTPResponse {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        requests.append(RecordedRequest(method: method, path: path))

        let body: String
        let statusCode: Int
        let responseURL: URL?
        if method == "POST", path == "/bbs/login_check.php" {
            authenticated = true
            body = "OK"
            statusCode = 200
            responseURL = request.url
        } else if path == "/my_page/play_data.php", let rejectedProfileStatusCode {
            self.rejectedProfileStatusCode = nil
            authenticated = false
            body = ""
            statusCode = rejectedProfileStatusCode
            responseURL = request.url
        } else if !authenticated {
            body = Self.loginHTML
            statusCode = 200
            responseURL = request.url
        } else {
            switch path {
            case "/my_page/play_data.php": body = Self.profileHTML
            case "/my_page/recently_played.php" where shouldExpireDuringRecentFetch:
                shouldExpireDuringRecentFetch = false
                authenticated = false
                body = Self.loginHTML
            case "/my_page/recently_played.php": body = Self.recentHTML
            case "/my_page/pumbility.php" where shouldRedirectPumbilityToLogin:
                shouldRedirectPumbilityToLogin = false
                authenticated = false
                body = "<html><body>Sign in</body></html>"
            case "/my_page/pumbility.php": body = Self.pumbilityHTML
            default: body = ""
            }
            statusCode = 200
            responseURL = path == "/my_page/pumbility.php" && !authenticated
                ? URL(string: "https://www.piugame.com/bbs/login.php")
                : request.url
        }

        return PIUGameHTTPResponse(
            data: Data(body.utf8),
            statusCode: statusCode,
            url: responseURL
        )
    }

    func expireSession() {
        authenticated = false
    }

    func expireDuringNextRecentFetch() {
        shouldExpireDuringRecentFetch = true
    }

    func rejectNextProfileRequest(statusCode: Int) {
        rejectedProfileStatusCode = statusCode
    }

    func redirectNextPumbilityRequestToLogin() {
        shouldRedirectPumbilityToLogin = true
    }

    func recordedRequests() -> [RecordedRequest] {
        requests
    }

    private static let loginHTML = #"""
    <form action="/bbs/login_check.php">
      <input name="mb_id" />
      <input name="mb_password" />
    </form>
    """#

    private static let profileHTML = #"""
    <div class="play_data_wrap">
      <div class="profile_name"><div class="name_w"><span class="t2">PLAYER#1234</span></div></div>
    </div>
    """#

    private static let recentHTML = #"<ul class="recently_playeList"></ul>"#

    private static let pumbilityHTML = #"""
    <div class="pumbility_total_wrap"><span class="t2">123.45</span></div>
    """#
}
