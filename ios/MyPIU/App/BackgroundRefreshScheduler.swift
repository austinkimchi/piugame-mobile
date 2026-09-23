import BackgroundTasks
import Foundation

enum BackgroundRefreshScheduler {
    static let identifier = "com.austinkimchi.mypiu.refresh"
    static let activationRefreshInterval: TimeInterval = 15 * 60

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    static func shouldRefreshAfterActivation(lastRefreshAt: Date?, now: Date = Date()) -> Bool {
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= activationRefreshInterval
    }
}
