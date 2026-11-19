import CryptoKit
import Foundation

struct PerformanceSessionsCacheContext: Codable, Equatable, Sendable {
    let origin: String
    let accountID: String
    let version: PIUGameVersion
    let tokenFingerprint: String

    init(origin: String, accountID: String, version: PIUGameVersion, token: String) {
        self.origin = origin
        self.accountID = accountID
        self.version = version
        tokenFingerprint = Self.digest(Data(token.utf8))
    }

    fileprivate static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Invalidated synchronously on the main actor, including while cache IO is in progress.
final class PerformanceSessionsCacheLease: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var isValid: Bool { lock.withLock { valid } }
    func invalidate() { lock.withLock { valid = false } }
}

actor PerformanceSessionsCache {
    struct CachedPage: Sendable {
        let page: MyPIUPerformanceSessionsPage
        let savedAt: Date
    }
    private struct Entry: Codable {
        let schemaVersion: Int
        let context: PerformanceSessionsCacheContext
        let savedAt: Date
        let page: MyPIUPerformanceSessionsPage
    }

    static let maximumPageBytes = 2 * 1024 * 1024
    static let maximumTotalBytes = 4 * 1024 * 1024
    static let maximumAge: TimeInterval = 24 * 60 * 60
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyPIU/PrivateSessions", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
    }

    func load(context: PerformanceSessionsCacheContext, lease: PerformanceSessionsCacheLease,
              now: Date = Date()) -> CachedPage? {
        guard lease.isValid, let url = fileURL(context), let entry = read(url, now: now),
              entry.context == context, lease.isValid else { return nil }
        return CachedPage(page: entry.page, savedAt: entry.savedAt)
    }

    func save(_ page: MyPIUPerformanceSessionsPage, context: PerformanceSessionsCacheContext,
              lease: PerformanceSessionsCacheLease, now: Date = Date()) {
        guard lease.isValid, let url = fileURL(context) else { return }
        guard page.selectedVersion == context.version.rawValue, page.sessions.count <= 20,
              !context.accountID.isEmpty, !context.origin.isEmpty else {
            try? fileManager.removeItem(at: url)
            return
        }
        let entry = Entry(schemaVersion: 1, context: context, savedAt: now, page: page)
        guard let data = try? encoder.encode(entry), data.count <= Self.maximumPageBytes else {
            try? fileManager.removeItem(at: url)
            return
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            var resource = URLResourceValues()
            resource.isExcludedFromBackup = true
            var directoryURL = directory
            try directoryURL.setResourceValues(resource)
            // Remove the replaced slot before atomic staging, keeping even temporary bytes bounded.
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            var retained: [(URL, Entry, Int)] = []
            for file in files {
                if let old = read(file, now: now), old.context.origin == context.origin,
                   old.context.accountID == context.accountID,
                   old.context.tokenFingerprint == context.tokenFingerprint,
                   old.context.version != context.version,
                   let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    retained.append((file, old, bytes))
                } else { try fileManager.removeItem(at: file) }
            }
            retained.sort { $0.1.savedAt > $1.1.savedAt }
            var retainedBytes = data.count
            for (index, item) in retained.enumerated() {
                if index > 0 || retainedBytes + item.2 > Self.maximumTotalBytes {
                    try fileManager.removeItem(at: item.0)
                } else { retainedBytes += item.2 }
            }
            guard lease.isValid else { return }
            var options: Data.WritingOptions = .atomic
            #if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try data.write(to: url, options: options)
            if !lease.isValid { try? fileManager.removeItem(at: url) }
        } catch {
            // Cache availability never changes a successful network result.
        }
    }

    func clear() { try? fileManager.removeItem(at: directory) }

    private func fileURL(_ context: PerformanceSessionsCacheContext) -> URL? {
        guard let data = try? encoder.encode(context) else { return nil }
        return directory.appendingPathComponent("sessions-\(PerformanceSessionsCacheContext.digest(data)).json")
    }

    private func read(_ url: URL, now: Date) -> Entry? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumPageBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maximumPageBytes,
              let entry = try? decoder.decode(Entry.self, from: data), entry.schemaVersion == 1,
              entry.page.sessions.count <= 20,
              entry.page.selectedVersion == entry.context.version.rawValue,
              (0...Self.maximumAge).contains(now.timeIntervalSince(entry.savedAt)) else { return nil }
        return entry
    }
}
