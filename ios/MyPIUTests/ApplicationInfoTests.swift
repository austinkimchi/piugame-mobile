import XCTest
@testable import MyPIU

final class ApplicationInfoTests: XCTestCase {
    func testDisplaysVersionAndBuild() {
        let info = ApplicationInfo(
            infoDictionary: [
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "42",
            ]
        )

        XCTAssertEqual(info.displayVersion, "0.1.0 (42)")
    }

    func testFallsBackWhenBundleValuesAreMissingOrBlank() {
        let buildOnly = ApplicationInfo(
            infoDictionary: [
                "CFBundleShortVersionString": "  ",
                "CFBundleVersion": "42",
            ]
        )
        let missing = ApplicationInfo(infoDictionary: nil)

        XCTAssertEqual(buildOnly.displayVersion, "Build 42")
        XCTAssertEqual(missing.displayVersion, "Unavailable")
    }

    func testPublicLinksUseExpectedSecureDestinations() {
        XCTAssertEqual(ApplicationInfo.supportURL.scheme, "https")
        XCTAssertEqual(ApplicationInfo.supportURL.host, "mypiu.austin.kim")
        XCTAssertEqual(ApplicationInfo.privacyPolicyURL.absoluteString, "https://mypiu.austin.kim/privacy")
    }
}
