import SwiftUI
import UIKit
import ImageIO

enum AppTheme {
    static let accent = Color(red: 0.16, green: 0.79, blue: 0.31)
    static let positive = accent
    static let warning = Color(red: 0.93, green: 0.58, blue: 0.10)
    static let judgmentBad = Color(red: 0.55, green: 0.28, blue: 0.76)
    static let danger = Color(red: 0.83, green: 0.19, blue: 0.20)
    static let info = Color(red: 0.08, green: 0.48, blue: 0.85)
    static let judgmentPerfect = info
    static let judgmentGreat = accent
    static let levelBadgeBackground = Color(red: 0.09, green: 0.10, blue: 0.09)
    static let ink = adaptive(
        light: UIColor(red: 0.09, green: 0.10, blue: 0.09, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1)
    )
    static let mutedInk = adaptive(
        light: UIColor(red: 0.40, green: 0.44, blue: 0.37, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.69, blue: 0.63, alpha: 1)
    )
    static let border = adaptive(
        light: UIColor(red: 0.85, green: 0.87, blue: 0.82, alpha: 1),
        dark: UIColor(red: 0.23, green: 0.25, blue: 0.22, alpha: 1)
    )
    static let pageBackground = adaptive(
        light: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.08, blue: 0.07, alpha: 1)
    )
    static let cardBackground = adaptive(
        light: .white,
        dark: UIColor(red: 0.11, green: 0.13, blue: 0.10, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// Decode on the worker actor before publishing an image to SwiftUI. The side is
/// the required square crop in physical pixels, not the source's longest edge.
enum ArtworkImageDecoder {
    static func decode(_ data: Data, pixelSize: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { return nil }
        let longest = max(width.doubleValue, height.doubleValue)
        let shortest = min(width.doubleValue, height.doubleValue)
        let maximum = pixelSize.map { min(longest, ceil(Double($0) * longest / shortest)) } ?? longest
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
        ] as CFDictionary)
    }

    static func decodedCost(_ image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}

private actor ArtworkImageWorker {
    let responseCache: URLCache
    let decode: RemoteImageCache.ImageDecoder

    init(responseCache: URLCache, decode: @escaping RemoteImageCache.ImageDecoder) {
        self.responseCache = responseCache
        self.decode = decode
    }

    func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        guard let response = responseCache.cachedResponse(for: request) else { return nil }
        guard validImageData(response.data),
              ((response.response as? HTTPURLResponse)?.statusCode ?? 200) < 400 else {
            responseCache.removeCachedResponse(for: request)
            return nil
        }
        return response
    }

    func store(_ data: Data, response: URLResponse, for request: URLRequest) -> Bool {
        guard validImageData(data) else { return false }
        responseCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        return true
    }

    func prepare(_ data: Data, pixelSize: Int?, for request: URLRequest) -> CGImage? {
        let image = decode(data, pixelSize)
        if image == nil { responseCache.removeCachedResponse(for: request) }
        return image
    }

    private func validImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetStatus(source) == .statusComplete
    }
}

@MainActor
final class RemoteImageCache {
    typealias DataLoader = @MainActor @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias ImageDecoder = @Sendable (Data, Int?) -> CGImage?
    static let shared = RemoteImageCache()

    private struct Key: Hashable {
        let url: URL
        let pixelSize: Int?
        var cacheKey: NSString { "\(pixelSize ?? 0):\(url.absoluteString)" as NSString }

        init(url: URL, pixelSize: CGFloat?) {
            self.url = url
            self.pixelSize = pixelSize.flatMap { $0.isFinite && $0 > 0 ? Int(min(4096, ceil($0))) : nil }
        }
    }

    private let images = NSCache<NSString, UIImage>()
    private let worker: ArtworkImageWorker
    private let loadData: DataLoader
    private var inFlightImages: [Key: Task<UIImage?, Never>] = [:]
    private var inFlightData: [URL: Task<Data?, Never>] = [:]

    init(responseCache: URLCache? = nil, loadData: DataLoader? = nil,
         decode: @escaping ImageDecoder = ArtworkImageDecoder.decode) {
        images.countLimit = 400
        images.totalCostLimit = 96 * 1_024 * 1_024
        let cache = responseCache ?? URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            diskPath: "mypiu-artwork"
        )
        worker = ArtworkImageWorker(responseCache: cache, decode: decode)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration)
        self.loadData = loadData ?? { request in try await session.data(for: request) }
    }

    func cachedImage(for url: URL, pixelSize: CGFloat? = nil) -> UIImage? {
        images.object(forKey: Key(url: url, pixelSize: pixelSize).cacheKey)
    }

    func image(for url: URL, pixelSize: CGFloat? = nil) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let key = Key(url: url, pixelSize: pixelSize)
        if let cached = images.object(forKey: key.cacheKey) { return cached }
        if let existing = inFlightImages[key] { return await existing.value }

        // Same-size viewers share preparation; different sizes share the raw request.
        // A canceled viewer cannot cancel artwork still needed by another visible row.
        let task = Task<UIImage?, Never> { @MainActor in
            guard let data = await data(for: url),
                  let decoded = await worker.prepare(data, pixelSize: key.pixelSize, for: URLRequest(url: url)) else { return nil as UIImage? }
            let image = UIImage(cgImage: decoded)
            images.setObject(image, forKey: key.cacheKey, cost: ArtworkImageDecoder.decodedCost(decoded))
            return image
        }
        inFlightImages[key] = task
        let result = await task.value
        inFlightImages[key] = nil
        return result
    }

    private func data(for url: URL) async -> Data? {
        if let existing = inFlightData[url] { return await existing.value }
        let task = Task<Data?, Never> { @MainActor in
            let request = URLRequest(url: url)
            if let cached = await worker.cachedResponse(for: request) { return cached.data }
            do {
                let (data, response) = try await loadData(request)
                guard ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                      await worker.store(data, response: response, for: request) else { return nil as Data? }
                return data
            } catch { return nil }
        }
        inFlightData[url] = task
        let result = await task.value
        inFlightData[url] = nil
        return result
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var pixelSize: CGFloat? = nil
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    private struct RequestID: Equatable { let url: URL?; let pixelSize: CGFloat? }
    private var requestID: RequestID { RequestID(url: url, pixelSize: pixelSize) }

    @State private var loadedID: RequestID?
    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let url, let image = displayedImage(for: url) {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: requestID) {
            loadedID = nil
            loadedImage = nil
            guard let url else { return }
            let image = await RemoteImageCache.shared.image(for: url, pixelSize: pixelSize)
            guard !Task.isCancelled else { return }
            loadedID = requestID
            loadedImage = image
        }
    }

    private func displayedImage(for url: URL) -> UIImage? {
        if loadedID == requestID, let loadedImage {
            return loadedImage
        }
        return RemoteImageCache.shared.cachedImage(for: url, pixelSize: pixelSize)
    }
}
