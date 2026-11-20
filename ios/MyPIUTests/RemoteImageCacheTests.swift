import UIKit
import XCTest
@testable import MyPIU

@MainActor
final class RemoteImageCacheTests: XCTestCase {
    private let url = URL(string: "https://example.test/jacket.png")!

    func testConcurrentSameURLSharesOneRequestAndCachesSuccess() async {
        let loader = PendingArtwork()
        let cache = makeCache(loader)
        let first = Task { await cache.image(for: url) }
        await loader.waitForCalls(1)
        let second = Task { await cache.image(for: url) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.calls, 1)
        loader.finish(.success(imageResponse()))
        let firstImage = await first.value
        let secondImage = await second.value
        XCTAssertNotNil(firstImage)
        XCTAssertTrue(firstImage === secondImage)
        let cached = await cache.image(for: url)
        XCTAssertTrue(cached === firstImage)
        XCTAssertEqual(loader.calls, 1)
    }

    func testFailedSharedRequestIsRemovedAndCanBeRetried() async {
        let loader = PendingArtwork()
        let cache = makeCache(loader)
        let first = Task { await cache.image(for: url) }
        await loader.waitForCalls(1)
        let second = Task { await cache.image(for: url) }
        for _ in 0..<20 { await Task.yield() }
        loader.finish(.failure(URLError(.timedOut)))
        let firstImage = await first.value
        let secondImage = await second.value
        XCTAssertNil(firstImage)
        XCTAssertNil(secondImage)
        XCTAssertNil(cache.cachedImage(for: url))
        let retry = Task { await cache.image(for: url) }
        await loader.waitForCalls(2)
        loader.finish(.success(imageResponse()))
        let recovered = await retry.value
        XCTAssertNotNil(recovered)
        XCTAssertEqual(loader.calls, 2)
    }

    func testCancellingOneViewDoesNotCancelOtherViewSharedArtwork() async {
        let loader = PendingArtwork()
        let cache = makeCache(loader)
        let disappearing = Task { await cache.image(for: url) }
        await loader.waitForCalls(1)
        let visible = Task { await cache.image(for: url) }
        for _ in 0..<20 { await Task.yield() }
        disappearing.cancel()
        loader.finish(.success(imageResponse()))
        _ = await disappearing.value
        let displayed = await visible.value
        XCTAssertNotNil(displayed)
        XCTAssertTrue(cache.cachedImage(for: url) === displayed)
        XCTAssertFalse(loader.wasCancelled)
        XCTAssertEqual(loader.calls, 1)
    }

    func testInvalidResponseDoesNotPoisonCache() async {
        let loader = PendingArtwork()
        let cache = makeCache(loader)
        let failed = Task { await cache.image(for: url) }
        await loader.waitForCalls(1)
        let (data, _) = imageResponse()
        loader.finish(.success((data, HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)))
        let image = await failed.value
        XCTAssertNil(image)
        XCTAssertNil(cache.cachedImage(for: url))
        let retry = Task { await cache.image(for: url) }
        await loader.waitForCalls(2)
        loader.finish(.success(imageResponse()))
        let recovered = await retry.value
        XCTAssertNotNil(recovered)
    }

    func testCancellingLastViewerCancelsDownloadAndAllowsRetry() async {
        let loader = CancellableArtwork()
        defer { loader.finishAll() }
        let cache = RemoteImageCache(responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0), loadData: loader.load)
        let disappearing = Task { await cache.image(for: url, pixelSize: 204) }
        await fulfillment(of: [loader.callsReached(1)], timeout: 10)
        guard loader.calls.count == 1 else { return }
        disappearing.cancel()
        await fulfillment(of: [loader.cancellationsReached(1)], timeout: 10)
        guard loader.cancelled.count == 1 else { return }
        let cancelled = await disappearing.value
        XCTAssertNil(cancelled)
        XCTAssertNil(cache.cachedImage(for: url, pixelSize: 204))
        XCTAssertEqual(loader.pendingCount, 0)

        let retry = Task { await cache.image(for: url, pixelSize: 204) }
        await fulfillment(of: [loader.callsReached(2)], timeout: 10)
        guard loader.calls.count == 2 else { return }
        loader.finish(1, with: .success(imageResponse()))
        let image = await retry.value
        XCTAssertNotNil(image)
        XCTAssertEqual(loader.calls.count, 2)
        XCTAssertEqual(loader.cancelled, [0])
    }

    func testDifferentSizeViewerKeepsSharedDownloadAfterOtherViewerCancels() async {
        let loader = CancellableArtwork()
        defer { loader.finishAll() }
        let cache = RemoteImageCache(responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0), loadData: loader.load)
        let smaller = Task { await cache.image(for: url, pixelSize: 140) }
        await fulfillment(of: [loader.callsReached(1)], timeout: 10)
        guard loader.calls.count == 1 else { return }
        let larger = Task { await cache.image(for: url, pixelSize: 280) }
        for _ in 0..<20 { await Task.yield() }
        smaller.cancel()
        loader.finish(0, with: .success(imageResponse(size: CGSize(width: 700, height: 393))))
        let smallImage = await smaller.value
        let largeImage = await larger.value
        XCTAssertNil(smallImage)
        XCTAssertEqual(largeImage?.cgImage?.height, 280)
        XCTAssertEqual(loader.calls.count, 1)
        XCTAssertTrue(loader.cancelled.isEmpty)
    }

    func testLateCancelledFlightCannotRemoveRapidReplacement() async {
        let loader = CancellableArtwork(finishesOnCancellation: false)
        defer { loader.finishAll() }
        let cache = RemoteImageCache(responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0), loadData: loader.load)
        let old = Task { await cache.image(for: url, pixelSize: 204) }
        await fulfillment(of: [loader.callsReached(1)], timeout: 10)
        guard loader.calls.count == 1 else { return }
        old.cancel()
        await fulfillment(of: [loader.cancellationsReached(1)], timeout: 10)
        guard loader.cancelled.count == 1 else { return }

        let replacement = Task { await cache.image(for: url, pixelSize: 204) }
        await fulfillment(of: [loader.callsReached(2)], timeout: 10)
        guard loader.calls.count == 2 else { return }
        // An uncooperative old transport finishes only after a new request owns this URL.
        loader.finish(0, with: .success(imageResponse()))
        let oldImage = await old.value
        XCTAssertNil(oldImage)
        XCTAssertNil(cache.cachedImage(for: url, pixelSize: 204))

        let joining = Task { await cache.image(for: url, pixelSize: 204) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.calls.count, 2, "Old cleanup must not remove a replacement's shared task")
        guard loader.calls.count == 2 else { return }
        loader.finish(1, with: .success(imageResponse()))
        let replacementImage = await replacement.value
        let joinedImage = await joining.value
        XCTAssertNotNil(replacementImage)
        XCTAssertTrue(replacementImage === joinedImage)
        XCTAssertEqual(loader.calls.count, 2)
    }

    func testFastScrollCancelsEveryUnobservedDistinctDownload() async {
        let loader = CancellableArtwork()
        defer { loader.finishAll() }
        let cache = RemoteImageCache(responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0), loadData: loader.load)
        let rows = (0..<12).map { index in
            Task { await cache.image(for: URL(string: "https://example.test/row-\(index).png")!, pixelSize: 204) }
        }
        await fulfillment(of: [loader.callsReached(12)], timeout: 10)
        guard loader.calls.count == 12 else { return }
        rows.forEach { $0.cancel() }
        await fulfillment(of: [loader.cancellationsReached(12)], timeout: 10)
        guard loader.cancelled.count == 12 else { return }
        for row in rows {
            let image = await row.value
            XCTAssertNil(image)
        }
        XCTAssertEqual(loader.pendingCount, 0)
        XCTAssertEqual(loader.cancelled.count, 12)

        let visible = Task { await cache.image(for: url, pixelSize: 204) }
        await fulfillment(of: [loader.callsReached(13)], timeout: 10)
        guard loader.calls.count == 13 else { return }
        loader.finish(12, with: .success(imageResponse()))
        let image = await visible.value
        XCTAssertNotNil(image)
    }

    func testDifferentSizesShareRawRequestButKeepSeparatePreparedImages() async {
        let loader = PendingArtwork()
        let cache = makeCache(loader)
        let small = Task { await cache.image(for: url, pixelSize: 140) }
        await loader.waitForCalls(1)
        let large = Task { await cache.image(for: url, pixelSize: 280) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.calls, 1)
        loader.finish(.success(imageResponse(size: CGSize(width: 700, height: 393))))
        let smallImage = await small.value
        let largeImage = await large.value
        XCTAssertEqual(smallImage?.cgImage?.height, 140)
        XCTAssertEqual(largeImage?.cgImage?.height, 280)
        XCTAssertNotEqual(smallImage?.cgImage?.width, largeImage?.cgImage?.width)
        XCTAssertTrue(cache.cachedImage(for: url, pixelSize: 140) === smallImage)
        XCTAssertTrue(cache.cachedImage(for: url, pixelSize: 280) === largeImage)
        XCTAssertNil(cache.cachedImage(for: url))
        XCTAssertEqual(loader.calls, 1)
    }

    func testNewSizeReusesRawResponseCacheWithoutNetwork() async {
        let loader = PendingArtwork()
        let raw = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 0)
        let cache = RemoteImageCache(responseCache: raw, loadData: loader.load)
        let first = Task { await cache.image(for: url, pixelSize: 140) }
        await loader.waitForCalls(1)
        loader.finish(.success(imageResponse(size: CGSize(width: 700, height: 393))))
        _ = await first.value
        let second = await cache.image(for: url, pixelSize: 280)
        XCTAssertEqual(second?.cgImage?.height, 280)
        XCTAssertEqual(loader.calls, 1)
        XCTAssertNotNil(raw.cachedResponse(for: URLRequest(url: url)))
    }

    func testPreparedImagesDecodeOffMainAndUseDecodedMemoryCost() async {
        let response = imageResponse(size: CGSize(width: 700, height: 393))
        let cache = RemoteImageCache(
            responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0),
            loadData: { _ in response },
            decode: { data, size in
                XCTAssertFalse(Thread.isMainThread, "Image preparation must not block UI work")
                return ArtworkImageDecoder.decode(data, pixelSize: size)
            }
        )
        let image = await cache.image(for: url, pixelSize: 204)
        guard let decoded = image?.cgImage else { return XCTFail("Expected prepared thumbnail") }
        XCTAssertEqual(decoded.width, 364)
        XCTAssertEqual(decoded.height, 204)
        XCTAssertEqual(ArtworkImageDecoder.decodedCost(decoded), decoded.bytesPerRow * 204)
        XCTAssertGreaterThan(ArtworkImageDecoder.decodedCost(decoded), response.0.count)
        XCTAssertLessThan(ArtworkImageDecoder.decodedCost(decoded), 700 * 393 * 4)
        XCTAssertNotNil(cache.cachedImage(for: url, pixelSize: 203.5), "Equivalent physical pixel requests share a key")
    }

    func testExistingRawCacheAlsoPreparesOffMainAndRetainsFullSizeCompatibility() async {
        let response = imageResponse(size: CGSize(width: 700, height: 393))
        let raw = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 0)
        raw.storeCachedResponse(CachedURLResponse(response: response.1, data: response.0), for: URLRequest(url: url))
        let cache = RemoteImageCache(responseCache: raw, loadData: { _ in
            XCTFail("Cached artwork must not need a network request")
            throw URLError(.notConnectedToInternet)
        }, decode: { data, size in
            XCTAssertFalse(Thread.isMainThread)
            return ArtworkImageDecoder.decode(data, pixelSize: size)
        })
        let image = await cache.image(for: url)
        XCTAssertEqual(image?.cgImage?.width, 700)
        XCTAssertEqual(image?.cgImage?.height, 393)
    }

    func testAlreadyCancelledWaiterStartsNoDownload() async {
        let loader = PendingArtwork()
        let cache = makeCache(loader)
        let task = Task { await cache.image(for: url, pixelSize: 204) }
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(loader.calls, 0)
    }

    func testInvalidRawCacheEntryCanBeReplacedByValidNetworkImage() async {
        let loader = PendingArtwork()
        let raw = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 0)
        raw.storeCachedResponse(CachedURLResponse(response: imageResponse().1, data: Data("not an image".utf8)), for: URLRequest(url: url))
        let cache = RemoteImageCache(responseCache: raw, loadData: loader.load)
        let task = Task { await cache.image(for: url) }
        await loader.waitForCalls(1)
        loader.finish(.success(imageResponse()))
        let image = await task.value
        XCTAssertNotNil(image)
        XCTAssertEqual(loader.calls, 1)
    }

    func testFailedPreparationDoesNotPoisonRawCacheAndLaterRequestCanRetry() async {
        let loader = PendingArtwork()
        let raw = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 0)
        let failing = RemoteImageCache(responseCache: raw, loadData: loader.load, decode: { _, _ in nil })
        let first = Task { await failing.image(for: url, pixelSize: 204) }
        await loader.waitForCalls(1)
        loader.finish(.success(imageResponse()))
        let failed = await first.value
        XCTAssertNil(failed)
        XCTAssertNil(raw.cachedResponse(for: URLRequest(url: url)))
        let recoveredCache = RemoteImageCache(responseCache: raw, loadData: loader.load)
        let retry = Task { await recoveredCache.image(for: url, pixelSize: 204) }
        await loader.waitForCalls(2)
        loader.finish(.success(imageResponse()))
        let recovered = await retry.value
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.cgImage?.width, 2, "Never enlarge a source smaller than its display target")
        XCTAssertEqual(loader.calls, 2)
    }

    private func makeCache(_ loader: PendingArtwork) -> RemoteImageCache {
        RemoteImageCache(
            responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0),
            loadData: loader.load
        )
    }

    private func imageResponse(size: CGSize = CGSize(width: 2, height: 2)) -> (Data, URLResponse) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return (image.pngData()!, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
private final class PendingArtwork {
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private(set) var calls = 0
    private(set) var wasCancelled = false

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        let response = try await withCheckedThrowingContinuation { continuation = $0 }
        wasCancelled = Task.isCancelled
        return response
    }

    func waitForCalls(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if calls == count { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Request did not start")
    }

    func finish(_ result: Result<(Data, URLResponse), Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
private final class CancellableArtwork {
    private let finishesOnCancellation: Bool
    private var isClosed = false
    private var pending: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    private var callWaiters: [(Int, XCTestExpectation)] = []
    private var cancellationWaiters: [(Int, XCTestExpectation)] = []
    private(set) var calls: [URLRequest] = []
    private(set) var cancelled = Set<Int>()
    var pendingCount: Int { pending.count }

    init(finishesOnCancellation: Bool = true) {
        self.finishesOnCancellation = finishesOnCancellation
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard !isClosed else { throw CancellationError() }
        let index = calls.count
        calls.append(request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                pending[index] = $0
                fulfill(&callWaiters, count: calls.count)
            }
        } onCancel: {
            Task { @MainActor in
                guard self.cancelled.insert(index).inserted else { return }
                self.fulfill(&self.cancellationWaiters, count: self.cancelled.count)
                if self.finishesOnCancellation { self.finish(index, with: .failure(CancellationError())) }
            }
        }
    }

    func callsReached(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Artwork started \(count) requests")
        callWaiters.append((count, expectation))
        fulfill(&callWaiters, count: calls.count)
        return expectation
    }

    func cancellationsReached(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Artwork cancelled \(count) requests")
        cancellationWaiters.append((count, expectation))
        fulfill(&cancellationWaiters, count: cancelled.count)
        return expectation
    }

    func finish(_ index: Int, with result: Result<(Data, URLResponse), Error>) {
        pending.removeValue(forKey: index)?.resume(with: result)
    }

    func finishAll() {
        isClosed = true
        let continuations = Array(pending.values)
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: CancellationError()) }
    }

    private func fulfill(_ waiters: inout [(Int, XCTestExpectation)], count: Int) {
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.fulfill() }
    }
}
