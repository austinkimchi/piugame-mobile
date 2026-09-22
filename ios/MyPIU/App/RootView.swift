import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { SongsView() }
                .tabItem { Label("Songs", systemImage: "music.note.list") }

            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }

            NavigationStack { AccountView() }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .tint(AppTheme.accent)
    }
}
