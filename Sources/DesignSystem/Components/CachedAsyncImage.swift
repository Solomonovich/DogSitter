import SwiftUI
import UIKit
import ImageIO

/// Process-wide in-memory image cache, keyed by URL + target size.
enum AppImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()
}

@MainActor
final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var task: Task<Void, Never>?
    private var loadedKey: String?

    func load(_ urlString: String?, maxPixel: CGFloat) {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            image = nil
            return
        }
        let key = "\(urlString)@\(Int(maxPixel))"
        if key == loadedKey, image != nil { return }
        loadedKey = key

        if let cached = AppImageCache.shared.object(forKey: key as NSString) {
            image = cached
            return
        }

        task?.cancel()
        task = Task { [weak self] in
            guard let img = await Self.fetch(url: url, maxPixel: maxPixel) else { return }
            AppImageCache.shared.setObject(img, forKey: key as NSString)
            if Task.isCancelled { return }
            self?.image = img
        }
    }

    func cancel() {
        task?.cancel()
    }

    nonisolated static func fetch(url: URL, maxPixel: CGFloat) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return downsample(data: data, maxPixel: maxPixel) ?? UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// Downsamples image data to a thumbnail no larger than `maxPixel` points (× screen scale).
    nonisolated static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let scale = UIScreen.main.scale
        let maxDimensionInPixels = max(maxPixel, 1) * scale
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Drop-in async image that downsamples + caches and always shows a themed placeholder.
/// Always give it a `.frame(...)`; pass `targetSize` as the largest dimension you display.
struct CachedAsyncImage<Placeholder: View>: View {
    let urlString: String?
    var contentMode: ContentMode = .fill
    var targetSize: CGFloat = 300
    @ViewBuilder var placeholder: () -> Placeholder

    @StateObject private var loader = CachedImageLoader()

    init(_ urlString: String?,
         contentMode: ContentMode = .fill,
         targetSize: CGFloat = 300,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.urlString = urlString
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .onAppear { loader.load(urlString, maxPixel: targetSize) }
        .onDisappear { loader.cancel() }
        .onChange(of: urlString) { _, newValue in
            loader.load(newValue, maxPixel: targetSize)
        }
    }
}
