import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDestination: Destination = .home
    @State private var homePath = NavigationPath()
    @State private var songsPath = NavigationPath()
    @State private var activityPath = NavigationPath()
    @State private var accountPath = NavigationPath()

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
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
            navigationStack(for: selectedDestination)
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
            SongsView()
        case .activity:
            ActivityView()
        case .account:
            AccountView()
        }
    }
}

private enum Destination: String, CaseIterable, Identifiable {
    case home
    case songs
    case activity
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .songs: "Songs"
        case .activity: "Activity"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .songs: "music.note.list"
        case .activity: "clock.arrow.circlepath"
        case .account: "person.crop.circle"
        }
    }

    var compactSystemImage: String {
        self == .home ? "house.fill" : systemImage
    }
}
