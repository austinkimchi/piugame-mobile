import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    enum SyncState: Equatable {
        case signedOut
        case restoring
        case syncing
        case ready
        case failed(String)
    }

    @Published private(set) var state: SyncState = .restoring
    @Published private(set) var snapshot: PIUSnapshot?
    @Published var selectedVersion: PIUGameVersion = .phoenix2

    private let credentialStore: KeychainCredentialStore
    private var client: PIUGameClient?
    private var credentials: PIUCredentials?
    private var hasRestored = false

    init(credentialStore: KeychainCredentialStore = KeychainCredentialStore()) {
        self.credentialStore = credentialStore
    }

    var isConnected: Bool { credentials != nil }

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
        do {
            guard let credentials = try credentialStore.load() else {
                state = .signedOut
                return
            }
            self.credentials = credentials
            selectedVersion = credentials.version
            state = .restoring
            await sync(using: credentials, saveAfterSuccess: false)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func connect(username: String, password: String) async -> Bool {
        let credentials = PIUCredentials(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            version: selectedVersion
        )
        guard !credentials.username.isEmpty, !password.isEmpty else {
            state = .failed("Enter your PIUGAME username and password.")
            return false
        }
        return await sync(using: credentials, saveAfterSuccess: true)
    }

    func refresh() async {
        guard let credentials else {
            state = .signedOut
            return
        }
        _ = await sync(using: credentials, saveAfterSuccess: false)
    }

    func disconnect() {
        do {
            try credentialStore.delete()
            credentials = nil
            client = nil
            snapshot = nil
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func sync(using credentials: PIUCredentials, saveAfterSuccess: Bool) async -> Bool {
        state = .syncing
        let client = PIUGameClient(version: credentials.version)
        self.client = client
        do {
            let snapshot = try await client.loginAndFetch(username: credentials.username, password: credentials.password)
            if saveAfterSuccess { try credentialStore.save(credentials) }
            self.credentials = credentials
            self.snapshot = snapshot
            state = .ready
            BackgroundRefreshScheduler.schedule()
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }
}
