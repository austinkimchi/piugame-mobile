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

    private func makeCache(_ loader: PendingArtwork) -> RemoteImageCache {
        RemoteImageCache(
            responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0),
            loadData: loader.load
        )
    }

    private func imageResponse() -> (Data, URLResponse) {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
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
        for _ in 0..<1000 {
            if calls == count { return }
            await Task.yield()
        }
        XCTFail("Request did not start")
    }

    func finish(_ result: Result<(Data, URLResponse), Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
