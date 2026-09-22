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
    var isMyPIUBusy: Bool { myPIUState == .authenticating || myPIUState == .uploading }

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
        await restoreMyPIU()
        do {
            guard let credentials = try credentialStore.load() else {
                state = .signedOut
                return
            }
            self.credentials = credentials
            selectedVersion = credentials.version
            state = .restoring
            _ = await sync(using: credentials, saveAfterSuccess: false)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func connectMyPIU(provider: MyPIUAuthProvider) async -> Bool {
        myPIUState = .authenticating
        do {
            let token = try await oauthCoordinator.authorize(provider: provider)
            try tokenStore.save(token)
            accessToken = token
            myPIUAccount = try await apiClient.account(accessToken: token.value)
            myPIUState = .ready
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

    func disconnectMyPIU() async {
        let token = accessToken?.value
        clearMyPIUSession()
        if let token {
            try? await apiClient.revoke(accessToken: token)
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
            await uploadToMyPIU(snapshot)
            return true
        } catch {
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
            accessToken = token
            myPIUState = .restoring
            myPIUAccount = try await apiClient.account(accessToken: token.value)
            myPIUState = .ready
        } catch {
            if let apiError = error as? MyPIUAPIError, apiError.isUnauthorized {
                clearMyPIUSession()
            } else {
                myPIUState = .failed(error.localizedDescription)
            }
        }
    }

    private func uploadToMyPIU(_ snapshot: PIUSnapshot) async {
        guard let token = accessToken, !token.isExpired else { return }
        myPIUState = .uploading
        do {
            let result = try await apiClient.upload(
                snapshot: snapshot,
                accessToken: token.value,
                installationID: installationID,
                appVersion: appVersion
            )
            myPIUState = .synced(
                imported: result.importedRecentPlays,
                duplicates: result.duplicateRecentPlays
            )
        } catch {
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
