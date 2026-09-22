import Foundation

enum InstallationIdentity {
    private static let key = "com.austinkimchi.mypiu.installation-id"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let identifier = UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: key)
        return identifier
    }
}
