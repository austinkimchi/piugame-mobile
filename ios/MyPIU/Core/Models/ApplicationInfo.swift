import Foundation

struct ApplicationInfo: Equatable {
    static let supportURL = URL(string: "https://mypiu.austin.kim")!
    static let privacyPolicyURL = URL(string: "https://mypiu.austin.kim/privacy")!

    let version: String?
    let build: String?

    init(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) {
        version = Self.nonEmptyString(infoDictionary?["CFBundleShortVersionString"])
        build = Self.nonEmptyString(infoDictionary?["CFBundleVersion"])
    }

    var displayVersion: String {
        switch (version, build) {
        case let (.some(version), .some(build)):
            "\(version) (\(build))"
        case let (.some(version), .none):
            version
        case let (.none, .some(build)):
            "Build \(build)"
        case (.none, .none):
            "Unavailable"
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
