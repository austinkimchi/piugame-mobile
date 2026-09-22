import SwiftUI

@main
struct MyPIUApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    BackgroundRefreshScheduler.schedule()
                    await model.restore()
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefreshScheduler.identifier)) {
            await model.refresh()
            BackgroundRefreshScheduler.schedule()
        }
    }
}
