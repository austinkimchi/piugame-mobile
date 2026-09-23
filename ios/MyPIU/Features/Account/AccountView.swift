import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    private let applicationInfo = ApplicationInfo()
    @Binding private var username: String
    @Binding private var password: String
    @Binding private var showingAccountDeletion: Bool

    init(
        username: Binding<String>,
        password: Binding<String>,
        showingAccountDeletion: Binding<Bool>
    ) {
        _username = username
        _password = password
        _showingAccountDeletion = showingAccountDeletion
    }

    var body: some View {
        Form {
            Section("MYPIU") {
                if let account = model.myPIUAccount {
                    LabeledContent("Account", value: account.name)
                    if let player = account.piuProfile {
                        LabeledContent("Linked player", value: player.displayName)
                    }
                    myPIUStatus
                } else if model.isMyPIUConnected {
                    myPIUStatus
                    Button("Retry MyPIU", systemImage: "arrow.clockwise") {
                        Task { await model.retryMyPIU() }
                    }
                    .disabled(model.isMyPIUBusy)
                } else {
                    Button("Continue with Google", systemImage: "person.badge.key") {
                        Task { await model.connectMyPIU(provider: .google) }
                    }
                    .disabled(model.isMyPIUBusy)
                    Button("Continue with Discord", systemImage: "person.badge.key") {
                        Task { await model.connectMyPIU(provider: .discord) }
                    }
                    .disabled(model.isMyPIUBusy)
                    myPIUStatus
                }
            }

            if let profile = model.snapshot?.profile {
                Section("PIUGAME") {
                    LabeledContent("Player", value: profile.displayName)
                    LabeledContent("Email", value: profile.username)
                    LabeledContent("Version", value: model.selectedVersion.displayName)
                }

                Section {
                    Button("Sync now", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    .disabled(model.state == .syncing)

                }
            } else {
                Section("PIUGAME") {
                    TextField("Email", text: $username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Picker("Version", selection: $model.selectedVersion) {
                        ForEach(PIUGameVersion.allCases) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                }

                Section {
                    Button("Connect", systemImage: "link") {
                        Task {
                            if await model.connect(username: username, password: password) {
                                password = ""
                            }
                        }
                    }
                    .disabled(model.state == .syncing || username.isEmpty || password.isEmpty)
                }
            }

            if case .failed(let message) = model.state {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.danger)
                }
            }

            Section("ABOUT & SUPPORT") {
                Link(destination: ApplicationInfo.supportURL) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                Link(destination: ApplicationInfo.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                LabeledContent("Version", value: applicationInfo.displayVersion)
            }

            if model.isConnected || model.isMyPIUConnected {
                Section("CONNECTED ACCOUNTS") {
                    if model.isConnected {
                        Button("Disconnect PIUGAME", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            model.disconnect()
                        }
                    }
                    if model.isMyPIUConnected {
                        Button("Disconnect MyPIU", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await model.disconnectMyPIU() }
                        }
                        .disabled(model.isMyPIUBusy)

                        Button("Delete MyPIU Account", systemImage: "trash", role: .destructive) {
                            showingAccountDeletion = true
                        }
                        .disabled(model.isMyPIUBusy)
                    }
                }
            }
        }
        .navigationTitle("Account")
        .overlay {
            if model.state == .syncing {
                ProgressView("Syncing")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .alert("Delete MyPIU Account?", isPresented: $showingAccountDeletion) {
            Button("Delete Account", role: .destructive) {
                Task { await model.deleteMyPIUAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes your MyPIU profile, synced scores, saved songs, community posts, and linked Discord bot data. Your PIUGAME account and on-device PIUGAME login are not deleted."
            )
        }
    }

    @ViewBuilder
    private var myPIUStatus: some View {
        switch model.myPIUState {
        case .signedOut, .ready:
            EmptyView()
        case .restoring:
            LabeledContent("MyPIU") { ProgressView() }
        case .authenticating:
            LabeledContent("Signing in") { ProgressView() }
        case .uploading:
            LabeledContent("Uploading") { ProgressView() }
        case .deleting:
            LabeledContent("Deleting account") { ProgressView() }
        case .synced(let imported, let duplicates):
            LabeledContent("Last sync", value: imported > 0 ? "\(imported) new" : "\(duplicates) already saved")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(AppTheme.danger)
        }
    }
}
