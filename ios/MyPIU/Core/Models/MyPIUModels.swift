import Foundation

enum MyPIUAuthProvider: String, CaseIterable, Identifiable, Sendable {
    case google
    case discord

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: "Google"
        case .discord: "Discord"
        }
    }
}

struct MyPIUAccessToken: Codable, Equatable, Sendable {
    let value: String
    let expiresAt: Date

    var isExpired: Bool { expiresAt <= Date() }
}

struct MyPIUAccount: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let email: String
    let username: String?
    let imageUrl: URL?
    let piuGameVersion: PIUGameVersion
    let piuProfile: LinkedPIUProfile?

    struct LinkedPIUProfile: Codable, Equatable, Sendable {
        let piuUsername: String
        let displayName: String
        let avatarUrl: URL?
    }
}

struct MyPIUSyncResult: Codable, Equatable, Sendable {
    let accepted: Bool
    let importedRecentPlays: Int
    let duplicateRecentPlays: Int
    let syncCursor: String
    let duplicateRequest: Bool
}
