import BackgroundTasks
import Foundation

enum BackgroundRefreshScheduler {
    static let identifier = "com.austinkimchi.mypiu.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
