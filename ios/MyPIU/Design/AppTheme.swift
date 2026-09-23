import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 0.16, green: 0.79, blue: 0.31)
    static let positive = accent
    static let warning = Color(red: 0.93, green: 0.58, blue: 0.10)
    static let judgmentBad = Color(red: 0.55, green: 0.28, blue: 0.76)
    static let danger = Color(red: 0.83, green: 0.19, blue: 0.20)
    static let info = Color(red: 0.08, green: 0.48, blue: 0.85)
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

@MainActor
private final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private let responseCache: URLCache
    private let session: URLSession

    private init() {
        images.countLimit = 400
        images.totalCostLimit = 96 * 1_024 * 1_024

        let configuration = URLSessionConfiguration.default
        responseCache = URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            diskPath: "mypiu-artwork"
        )
        configuration.urlCache = responseCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func cachedImage(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        let request = URLRequest(url: url)
        if let cachedResponse = responseCache.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            images.setObject(image, forKey: url as NSURL, cost: cachedResponse.data.count)
            return image
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard
                ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                let image = UIImage(data: data)
            else {
                return nil
            }
            responseCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data),
                for: request
            )
            images.setObject(image, forKey: url as NSURL, cost: data.count)
            return image
        } catch {
            return nil
        }
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedURL: URL?
    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let url, let image = displayedImage(for: url) {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            loadedURL = nil
            loadedImage = nil
            guard let url else { return }
            let image = await RemoteImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            loadedURL = url
            loadedImage = image
        }
    }

    private func displayedImage(for url: URL) -> UIImage? {
        if loadedURL == url, let loadedImage {
            return loadedImage
        }
        return RemoteImageCache.shared.cachedImage(for: url)
    }
}
