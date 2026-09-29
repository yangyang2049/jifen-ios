import SwiftUI
import UIKit

/// 远端图片两级缓存（项目内版 SDWebImage/Glide，不引第三方依赖）。
/// 内存层 NSCache 在视图构建时同步命中：重进页面直接出图，不再出现
/// 「先占位后跳图」的闪烁；磁盘层复用 URLSession.shared 的 URLCache
///（服务端对已过审图片下发 immutable Cache-Control，天然免重拉）。
/// 同一 URL 的并发请求合并为单个任务。
nonisolated final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private let lock = NSLock()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {}

    /// 同步查内存层（可在 body 里安全调用）。
    func image(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func insert(_ image: UIImage, for url: URL) {
        memory.setObject(
            image,
            forKey: url.absoluteString as NSString,
            cost: max(1, Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        )
    }

    /// 内存 → 合并中的任务 → 网络（URLSession 自带磁盘缓存）。
    func fetch(_ url: URL) async -> UIImage? {
        if let hit = image(for: url) { return hit }
        lock.lock()
        if let task = inFlight[url] {
            lock.unlock()
            return await task.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else {
                return nil
            }
            self?.insert(image, for: url)
            return image
        }
        inFlight[url] = task
        lock.unlock()
        let result = await task.value
        lock.lock()
        inFlight[url] = nil
        lock.unlock()
        return result
    }
}

/// AsyncImage 的替代品：API 对齐 `AsyncImage(url:content:placeholder:)`，
/// 差别仅在内存层同步命中——首帧就能出图。
struct RemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loadedImage ?? url.flatMap(RemoteImageCache.shared.image(for:)) {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                loadedImage = nil
                return
            }
            let image = await RemoteImageCache.shared.fetch(url)
            guard !Task.isCancelled, let image else { return }
            loadedImage = image
        }
    }
}
