import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var songCatalog = SongCatalogModel()
    @State private var selectedDestination: Destination = .home
    @State private var visitedDestinations: Set<Destination> = [.home]
    @State private var homePath = NavigationPath()
    @State private var songsPath = NavigationPath()
    @State private var progressPath = NavigationPath()
    @State private var activityPath = NavigationPath()
    @State private var accountPath = NavigationPath()
    @State private var songQuery = ""
    @State private var activitySection: ActivityView.Section = .recent
    @State private var accountUsername = ""
    @State private var accountPassword = ""
    @State private var showingAccountDeletion = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .onChange(of: selectedDestination) { _, destination in
            visitedDestinations.insert(destination)
            resignFocus()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            resignFocus()
        }
        .onChange(of: appModel.catalogCacheScope) { oldScope, newScope in
            guard oldScope != newScope else { return }
            homePath = NavigationPath()
            songsPath = NavigationPath()
            progressPath = NavigationPath()
        }
        .onReceive(appModel.favoriteChanges) { change in
            guard change.accountID == appModel.myPIUAccount?.id else { return }
            Task {
                await songCatalog.applyConfirmedFavorite(
                    change.isFavorite,
                    slug: change.songSlug,
                    version: change.version,
                    cacheScope: "account:\(change.accountID)"
                )
            }
        }
    }

    private var compactLayout: some View {
        TabView(selection: $selectedDestination) {
            ForEach(Destination.allCases) { destination in
                navigationStack(for: destination)
                .tabItem {
                    Label(destination.title, systemImage: destination.compactSystemImage)
                }
                .tag(destination)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: sidebarSelection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("MyPIU")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            ZStack {
                ForEach(Destination.allCases.filter(visitedDestinations.contains)) { destination in
                    navigationStack(for: destination)
                        .opacity(selectedDestination == destination ? 1 : 0)
                        .allowsHitTesting(selectedDestination == destination)
                        .accessibilityHidden(selectedDestination != destination)
                        .zIndex(selectedDestination == destination ? 1 : 0)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarSelection: Binding<Destination?> {
        Binding(
            get: { selectedDestination },
            set: { destination in
                if let destination {
                    selectedDestination = destination
                }
            }
        )
    }

    private func navigationStack(for destination: Destination) -> some View {
        NavigationStack(path: navigationPath(for: destination)) {
            destinationView(destination)
        }
        .id(destination)
    }

    private func navigationPath(for destination: Destination) -> Binding<NavigationPath> {
        switch destination {
        case .home: $homePath
        case .songs: $songsPath
        case .progress: $progressPath
        case .activity: $activityPath
        case .account: $accountPath
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .home:
            DashboardView()
        case .songs:
            SongsView(catalog: songCatalog, query: $songQuery)
        case .progress:
            PlayerProgressView()
        case .activity:
            ActivityView(section: $activitySection)
        case .account:
            AccountView(
                username: $accountUsername,
                password: $accountPassword,
                showingAccountDeletion: $showingAccountDeletion
            )
        }
    }

    @MainActor
    private func resignFocus() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private enum Destination: String, CaseIterable, Identifiable {
    case home
    case songs
    case progress
    case activity
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .songs: "Songs"
        case .progress: "Progress"
        case .activity: "Activity"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .songs: "music.note.list"
        case .progress: "chart.pie"
        case .activity: "clock.arrow.circlepath"
        case .account: "person.crop.circle"
        }
    }

    var compactSystemImage: String {
        self == .home ? "house.fill" : systemImage
    }
}
