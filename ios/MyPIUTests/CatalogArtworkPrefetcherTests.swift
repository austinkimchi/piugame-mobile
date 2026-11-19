import XCTest
@testable import MyPIU

@MainActor
final class CatalogArtworkPrefetcherTests: XCTestCase {
    func testFastScrollReplacesQueuedWorkWithoutExceedingTwoActiveDownloads() async {
        let loader = PrefetchGate()
        let prefetch = CatalogArtworkPrefetcher(isCached: { _ in false }, load: loader.load)
        defer { prefetch.stop(); loader.finishAll() }
        let original = urls(20)
        prefetch.update(original)
        await fulfillment(of: [loader.callsReached(2)], timeout: 10)
        guard loader.calls.count == 2 else { return }
        XCTAssertEqual(Set(loader.calls), Set(original.prefix(2)))
        let newest = urls(3, prefix: "new")
        prefetch.update(newest)
        XCTAssertEqual(loader.calls.count, 2)
        loader.finish(original[0])
        await fulfillment(of: [loader.callsReached(3)], timeout: 10)
        guard loader.calls.count == 3 else { return }
        XCTAssertEqual(loader.calls.last, newest[0])
        loader.finish(original[1])
        await fulfillment(of: [loader.callsReached(4)], timeout: 10)
        guard loader.calls.count == 4 else { return }
        XCTAssertEqual(loader.calls.last, newest[1])
        XCTAssertEqual(loader.peakActive, 2)
        prefetch.stop()
        loader.finish(newest[0]); loader.finish(newest[1])
        await fulfillment(of: [loader.completionsReached(4)], timeout: 10)
        XCTAssertEqual(loader.calls.count, 4)
    }

    func testPrefetchSkipsDuplicatesAndCachedImagesAndCapsQueue() async {
        let loader = PrefetchGate()
        let values = urls(25)
        let prefetch = CatalogArtworkPrefetcher(isCached: { $0 == values[0] }, load: loader.load)
        defer { prefetch.stop(); loader.finishAll() }
        prefetch.update([values[0], values[1], values[1]] + Array(values.dropFirst(2)))
        await fulfillment(of: [loader.callsReached(2)], timeout: 10)
        guard loader.calls.count == 2 else { return }
        XCTAssertEqual(Set(loader.calls), Set(values[1...2]))
        for index in 1...12 {
            loader.finish(values[index])
            let expectedCalls = min(index + 2, 12)
            await fulfillment(of: [loader.callsReached(expectedCalls)], timeout: 10)
            guard loader.calls.count == expectedCalls else { return }
        }
        await fulfillment(of: [loader.completionsReached(12)], timeout: 10)
        XCTAssertEqual(loader.calls.count, 12)
        XCTAssertEqual(Set(loader.calls).count, 12)
        XCTAssertEqual(loader.peakActive, 2)
    }

    private func urls(_ count: Int, prefix: String = "song") -> [URL] {
        (0..<count).map { URL(string: "https://example.test/\(prefix)-\($0).png")! }
    }
}

@MainActor
private final class PrefetchGate {
    private(set) var calls: [URL] = []
    private var pending: [URL: CheckedContinuation<Void, Never>] = [:]
    private var callWaiters: [(count: Int, expectation: XCTestExpectation)] = []
    private var completionWaiters: [(count: Int, expectation: XCTestExpectation)] = []
    private var completed = 0
    private var isClosed = false
    private(set) var peakActive = 0
    func load(_ url: URL) async {
        guard !isClosed else { return }
        calls.append(url)
        fulfillReady(&callWaiters, count: calls.count)
        await withCheckedContinuation {
            pending[url] = $0
            peakActive = max(peakActive, pending.count)
        }
        completed += 1
        fulfillReady(&completionWaiters, count: completed)
    }
    func finish(_ url: URL) { pending.removeValue(forKey: url)?.resume() }
    func finishAll() {
        isClosed = true
        let continuations = Array(pending.values)
        pending.removeAll()
        continuations.forEach { $0.resume() }
    }
    func callsReached(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Prefetch started \(count) downloads")
        callWaiters.append((count, expectation))
        fulfillReady(&callWaiters, count: calls.count)
        return expectation
    }
    func completionsReached(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Prefetch completed \(count) downloads")
        completionWaiters.append((count, expectation))
        fulfillReady(&completionWaiters, count: completed)
        return expectation
    }
    private func fulfillReady(_ waiters: inout [(count: Int, expectation: XCTestExpectation)], count: Int) {
        let ready = waiters.filter { $0.count <= count }
        waiters.removeAll { $0.count <= count }
        ready.forEach { $0.expectation.fulfill() }
    }
}
