import Foundation

// MARK: - 后端 scoreboard client-config（对齐安卓 ScoreboardClientConfigStore / 鸿蒙 ScoreboardClientConfigStore）
//
// GET /api/client-config/scoreboard 是同步项目的唯一仲裁口径。三端统一到
// SCOREBOARD_CATALOG_REVISION = 12：服务端 revision 变化时整体覆盖缓存，
// 请求失败或目录尚无该项目能力行时回退本地白名单，不影响既有同步链路。
// APIClient.applyDefaultHeaders 已统一带上 X-Client-Platform / X-App-Version-Code。

nonisolated struct ScoreboardSyncCapability: Decodable, Sendable {
    var controller: Bool = false
    var display: Bool = false
    var minVersionCode: Int? = nil
    var reason: String? = nil
}

nonisolated struct ScoreboardClientConfigEntry: Decodable, Sendable {
    var id: String
    var sync: ScoreboardSyncCapability?
}

nonisolated struct ScoreboardClientConfig: Decodable, Sendable {
    var revision: Int = 0
    var serverTime: Int64? = nil
    var platform: String? = nil
    var versionCode: Int? = nil
    var gameTypes: [ScoreboardClientConfigEntry] = []
}

final class ScoreboardClientConfigStore: @unchecked Sendable {
    static let shared = ScoreboardClientConfigStore()

    private let lock = NSLock()
    private var capabilities: [String: Bool] = [:]
    private var revision: Int? = nil
    private var refreshing = false
    private var lastAttempt: Date? = nil

    private init() {}

    /// nil 表示服务端目录尚未加载，或该项目没有能力行；调用方应回退本地白名单。
    func canControl(_ gameType: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return capabilities[gameType]
    }

    var cachedRevision: Int? {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    /// 5 分钟内不重复拉取；失败时沿用旧缓存，无缓存则继续用本地白名单。
    func refresh() async {
        lock.lock()
        let recent = lastAttempt.map { Date().timeIntervalSince($0) < 300 } ?? false
        if refreshing || recent {
            lock.unlock()
            return
        }
        lastAttempt = Date()
        refreshing = true
        lock.unlock()
        defer {
            lock.lock()
            refreshing = false
            lock.unlock()
        }
        do {
            let config: ScoreboardClientConfig = try await APIClient.shared.request(
                "/api/client-config/scoreboard",
                requiresAuth: false,
                timeout: 8
            )
            var next: [String: Bool] = [:]
            for entry in config.gameTypes {
                guard let sync = entry.sync else { continue }
                next[entry.id] = sync.controller
            }
            lock.lock()
            if revision != config.revision {
                revision = config.revision
                capabilities = next
            }
            lock.unlock()
        } catch {
            // 离线 / 目录接口异常时保持现状：旧缓存或本地白名单继续生效。
        }
    }
}
