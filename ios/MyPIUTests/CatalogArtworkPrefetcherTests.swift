import XCTest
@testable import MyPIU

@MainActor
final class CatalogArtworkPrefetcherTests: XCTestCase {
    func testFastScrollReplacesQueuedWorkWithoutExceedingTwoActiveDownloads() async {
        let loader = PrefetchGate()
        let prefetch = CatalogArtworkPrefetcher(isCached: { _ in false }, load: loader.load)
        let original = urls(20)
        prefetch.update(original)
        await loader.waitForCalls(2)
        XCTAssertEqual(Set(loader.calls), Set(original.prefix(2)))
        let newest = urls(3, prefix: "new")
        prefetch.update(newest)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.calls.count, 2)
        loader.finish(original[0])
        await loader.waitForCalls(3)
        XCTAssertEqual(loader.calls.last, newest[0])
        loader.finish(original[1])
        await loader.waitForCalls(4)
        XCTAssertEqual(loader.calls.last, newest[1])
        XCTAssertEqual(loader.peakActive, 2)
        prefetch.stop()
        loader.finish(newest[0]); loader.finish(newest[1])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.calls.count, 4)
    }

    func testPrefetchSkipsDuplicatesAndCachedImagesAndCapsQueue() async {
        let loader = PrefetchGate()
        let values = urls(25)
        let prefetch = CatalogArtworkPrefetcher(isCached: { $0 == values[0] }, load: loader.load)
        prefetch.update([values[0], values[1], values[1]] + Array(values.dropFirst(2)))
        await loader.waitForCalls(2)
        XCTAssertEqual(Set(loader.calls), Set(values[1...2]))
        for index in 1...12 {
            loader.finish(values[index])
            for _ in 0..<20 { await Task.yield() }
        }
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
    private(set) var peakActive = 0
    func load(_ url: URL) async {
        calls.append(url)
        await withCheckedContinuation {
            pending[url] = $0
            peakActive = max(peakActive, pending.count)
        }
    }
    func finish(_ url: URL) { pending.removeValue(forKey: url)?.resume() }
    func waitForCalls(_ count: Int) async {
        for _ in 0..<1000 {
            if calls.count == count { return }
            await Task.yield()
        }
        XCTFail("Prefetch did not start")
    }
}
