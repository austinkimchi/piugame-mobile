import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Form {
            if let profile = model.snapshot?.profile {
                Section("PIUGAME") {
                    LabeledContent("Player", value: profile.displayName)
                    LabeledContent("Username", value: profile.username)
                    LabeledContent("Version", value: model.selectedVersion.displayName)
                }

                Section {
                    Button("Sync now", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    .disabled(model.state == .syncing)

                    Button("Disconnect PIUGAME", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        model.disconnect()
                    }
                }
            } else {
                Section("PIUGAME") {
                    TextField("Username", text: $username)
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
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .navigationTitle("Account")
        .overlay {
            if model.state == .syncing {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
