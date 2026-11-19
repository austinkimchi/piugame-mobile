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
