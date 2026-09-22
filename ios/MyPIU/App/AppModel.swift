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

    enum MyPIUState: Equatable {
        case signedOut
        case restoring
        case authenticating
        case ready
        case uploading
        case synced(imported: Int, duplicates: Int)
        case failed(String)
    }

    @Published private(set) var state: SyncState = .restoring
    @Published private(set) var snapshot: PIUSnapshot?
    @Published private(set) var myPIUAccount: MyPIUAccount?
    @Published private(set) var myPIUState: MyPIUState = .restoring
    @Published var selectedVersion: PIUGameVersion = .phoenix2

    private let credentialStore: KeychainCredentialStore
    private let tokenStore: KeychainTokenStore
    private let apiClient: MyPIUAPIClient
    private let installationID: String
    private let appVersion: String?
    private let oauthCoordinator: MyPIUOAuthCoordinator
    private var client: PIUGameClient?
    private var credentials: PIUCredentials?
    private var accessToken: MyPIUAccessToken?
    private var hasRestored = false

    init(
        credentialStore: KeychainCredentialStore = KeychainCredentialStore(),
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        apiClient: MyPIUAPIClient = MyPIUAPIClient(),
        installationID: String = InstallationIdentity.current()
    ) {
        self.credentialStore = credentialStore
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.installationID = installationID
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        self.oauthCoordinator = MyPIUOAuthCoordinator(
            apiClient: apiClient,
            installationID: installationID,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }

    var isConnected: Bool { credentials != nil }
    var isMyPIUConnected: Bool { accessToken != nil }
    var isMyPIUBusy: Bool {
        myPIUState == .restoring || myPIUState == .authenticating || myPIUState == .uploading
    }

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
        Task { await retryPendingMyPIURevocations() }

        let savedCredentials: PIUCredentials?
        do {
            savedCredentials = try credentialStore.load()
        } catch {
            state = .failed(error.localizedDescription)
            await restoreMyPIU()
            return
        }

        guard let savedCredentials else {
            state = .signedOut
            await restoreMyPIU()
            return
        }

        credentials = savedCredentials
        selectedVersion = savedCredentials.version
        state = .restoring

        async let myPIURestore: Void = restoreMyPIU()
        let didSync = await sync(
            using: savedCredentials,
            saveAfterSuccess: false,
            uploadAfterSuccess: false
        )
        await myPIURestore
        if didSync, let snapshot {
            await uploadToMyPIU(snapshot)
        }
    }

    func connectMyPIU(provider: MyPIUAuthProvider) async -> Bool {
        myPIUState = .authenticating
        do {
            let token = try await oauthCoordinator.authorize(provider: provider)
            try tokenStore.save(token)
            accessToken = token
            guard await loadMyPIUAccount(using: token) else { return false }
            if let snapshot {
                await uploadToMyPIU(snapshot)
            }
            return true
        } catch {
            if let apiError = error as? MyPIUAPIError, apiError.isUnauthorized {
                clearMyPIUSession()
            } else {
                myPIUState = .failed(error.localizedDescription)
            }
            return false
        }
    }

    func retryMyPIU() async {
        guard let token = accessToken else {
            myPIUState = .signedOut
            return
        }
        guard await loadMyPIUAccount(using: token) else { return }
        if let snapshot {
            await uploadToMyPIU(snapshot)
        }
    }

    func disconnectMyPIU() async {
        guard let token = accessToken else {
            clearMyPIUSession()
            return
        }
        do {
            try tokenStore.enqueuePendingRevocation(token)
        } catch {
            myPIUState = .failed("MyPIU could not securely queue this sign-out. Try again.")
            return
        }
        clearMyPIUSession()
        await retryPendingMyPIURevocations()
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

    private func sync(
        using credentials: PIUCredentials,
        saveAfterSuccess: Bool,
        uploadAfterSuccess: Bool = true
    ) async -> Bool {
        state = .syncing
        let client = PIUGameClient(version: credentials.version)
        self.client = client
        do {
            let snapshot = try await client.loginAndFetch(username: credentials.username, password: credentials.password)
            guard saveAfterSuccess || self.credentials == credentials else { return false }
            if saveAfterSuccess { try credentialStore.save(credentials) }
            self.credentials = credentials
            self.snapshot = snapshot
            state = .ready
            BackgroundRefreshScheduler.schedule()
            if uploadAfterSuccess {
                await uploadToMyPIU(snapshot)
            }
            return true
        } catch {
            guard saveAfterSuccess || self.credentials == credentials else { return false }
            state = .failed(error.localizedDescription)
            return false
        }
    }

    private func restoreMyPIU() async {
        do {
            guard let token = try tokenStore.load() else {
                myPIUState = .signedOut
                return
            }
            guard !token.isExpired else {
                clearMyPIUSession()
                return
            }
            accessToken = token
            _ = await loadMyPIUAccount(using: token)
        } catch {
            myPIUState = .failed(error.localizedDescription)
        }
    }

    private func loadMyPIUAccount(using token: MyPIUAccessToken) async -> Bool {
        myPIUState = .restoring
        do {
            let account = try await apiClient.account(accessToken: token.value)
            guard accessToken?.value == token.value else { return false }
            myPIUAccount = account
            myPIUState = .ready
            return true
        } catch {
            guard accessToken?.value == token.value else { return false }
            if let apiError = error as? MyPIUAPIError, apiError.isUnauthorized {
                clearMyPIUSession()
            } else {
                myPIUState = .failed(error.localizedDescription)
            }
            return false
        }
    }

    private func retryPendingMyPIURevocations() async {
        guard let tokens = try? tokenStore.pendingRevocations() else { return }
        for token in tokens {
            do {
                try await apiClient.revoke(accessToken: token.value)
                try tokenStore.removePendingRevocation(token)
            } catch let error as MyPIUAPIError where error.isUnauthorized {
                try? tokenStore.removePendingRevocation(token)
            } catch {
                continue
            }
        }
    }

    private func uploadToMyPIU(_ snapshot: PIUSnapshot) async {
        guard let token = accessToken else { return }
        guard !token.isExpired else {
            clearMyPIUSession()
            return
        }
        myPIUState = .uploading
        do {
            let result = try await apiClient.upload(
                snapshot: snapshot,
                accessToken: token.value,
                installationID: installationID,
                appVersion: appVersion
            )
            guard accessToken?.value == token.value else { return }
            myPIUState = .synced(
                imported: result.importedRecentPlays,
                duplicates: result.duplicateRecentPlays
            )
        } catch {
            guard accessToken?.value == token.value else { return }
            if let apiError = error as? MyPIUAPIError, apiError.isUnauthorized {
                clearMyPIUSession()
            } else {
                myPIUState = .failed(error.localizedDescription)
            }
        }
    }

    private func clearMyPIUSession() {
        try? tokenStore.delete()
        accessToken = nil
        myPIUAccount = nil
        myPIUState = .signedOut
    }
}
