import Foundation
import LinkCore

/// D3 存储根目录注入点（Watch 侧唯一入口）。
///
/// 默认落在应用沙盒 `Application Support/jifen-watch-v1/`。**未来切换 App Group
/// 时只需把 `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ...)`
/// 注入这一个构造器参数**，所有子目录与上层存储零改动；M1 刻意不新增任何
/// `.entitlements` / App Group 能力（见规范 §2 红线 1）。
/// `nonisolated`：默认参数（如 `WatchLinkService.init`）与非主线程路径都要能
/// 直接取用 `shared` / `linkDataStore`；线程安全由内部 NSLock 保证。
nonisolated final class WatchStorageContainer: @unchecked Sendable {
    static let shared = WatchStorageContainer()

    /// 默认根目录：Application Support/jifen-watch-v1/。
    /// 唯一 App Group 切换点：向 `init(rootURL:)` 注入 group containerURL 即可。
    private static func defaultRootURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport.appendingPathComponent("jifen-watch-v1", isDirectory: true)
    }

    let rootURL: URL
    private let appStorage: AppStorageContainer
    private let lock = NSLock()
    private var cachedSubdirectories: [String: URL] = [:]

    /// - Parameter rootURL: 存储根目录；nil 使用默认沙盒根目录（测试传临时目录）。
    init(rootURL: URL? = nil) {
        let resolved = rootURL ?? Self.defaultRootURL()
        self.rootURL = resolved
        self.appStorage = DefaultAppStorageContainer(rootURL: resolved)
    }

    /// 惰性创建并缓存子目录（records/ resume/ link/ common-names/ outbox/）。
    func directory(_ name: String) -> URL {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedSubdirectories[name] { return cached }
        let url = appStorage.subdirectory(name)
        cachedSubdirectories[name] = url
        return url
    }

    var recordsDirectory: URL { directory("records") }
    var resumeDirectory: URL { directory("resume") }
    var linkDirectory: URL { directory("link") }
    var commonNamesDirectory: URL { directory("common-names") }
    var outboxDirectory: URL { directory("outbox") }

    /// 双端联动 key→file 存储，固定指向 link/ 子目录。
    /// 先解析目录再进临界区：directory() 自带同一把 NSLock（不可重入），
    /// 持锁调用会造成死锁。
    var linkDataStore: FileLinkDataStore {
        let linkDirectory = directory("link")
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedLinkDataStore { return cached }
        let store = FileLinkDataStore(directoryURL: linkDirectory)
        cachedLinkDataStore = store
        return store
    }
    private var cachedLinkDataStore: FileLinkDataStore?
}
