# Apple Watch 端数据层与双端协作层 v2 架构重塑规范（M1–M5 实施手册）

> **文档性质**：面向 DeepSeek Harness (`dsh`) 分阶段实现与 Codex 独立审查的工程级架构与落地规范。
>
> **适用仓库**：`jifen-ios`（主工程 `jifen`、手表端 `jifenWatch Watch App`、共享本地 Swift Package `Packages/JifenCore`）。
>
> **基准提交 / 分支**：以 `3.4.3` 分支的 `72a0b19e` 为 M1 实施基线。

---

## §1 背景、目标与已锁定决策

### 1.1 背景与一次性窗口
- 产品已确认，本次 Watch 版本及手机↔手表联动协议此前从未面向用户发布。Watch 本地数据和双端联动会话、传输队列、退役场次均按首发格式实现，无需迁移开发版数据或支持旧联动协议。
- iPhone 主端已经发布。兼容原有比赛记录、独立续玩草稿、手机个人记录、业务 `RecordSyncOutbox` 及云端和安卓/鸿蒙跨端记录格式。
- 本次重塑利用 Watch 重新上线前的窗口，一次做透四个模块（**A + B + C + D**），按 **5 个独立可编译、可测试、可提交的里程碑（M1–M5）** 推进。

### 1.2 核心目标
1. **更精简**：消灭伪历史兼容/迁移债、多轨模型翻译税、冗余单主控权移交状态机与双端镜像复制代码（预期协作层与计分板联动胶水代码净减 40%～50%）。
2. **更高效**：重型业务数据全面迁离 `UserDefaults`、引入 `index.json` + 单记录原子文件、引入 `WCSession.transferFile` 与增量动作同步、消除 `receive()` 10+ 次盲解 JSON 与主线程同步编码。
3. **更具扩展性**：开放式能力协商（不再被 `==` 锁死升级）、单一事实来源运动能力注册表、全部 19 项联动运动 100% Reducer 化、Phone 定序 Intent 并发同步 + Watch 乐观重放、代码层存储容器抽象（平滑预留未来 App Group / WidgetKit / HealthKit）。

### 1.3 已拍板锁定的产品与架构决策

| 编号 | 决策项 | 最终拍板口径 |
|---|---|---|
| **D-1** | 双端协作模式 | **纯 `.shared`（双端均可随时计分）**。彻底删除旧单主控权移交协议与 UI（`takeoverByPhone`、`forceTakeover`、`reclaimRequest`/`Accepted`/`Denied`、`watchBackgrounded`、`resumeDiscarded`、`authorityEpoch` 三阶段提交）；**保留双向手动「同步积分」（`resyncRequest`）** 作为弱网/丢包逃生门。Watch 离线可继续计分并提交结束请求，结束后显示「待同步确认」。联动完赛由手机定序确认，两端以同一比赛 ID 幂等落库。手机若已先确认完赛，Watch 对齐该结果并显示未纳入的离线操作笔数。Watch 独立开局可直接保存。 |
| **D-2** | 实施范围 | **A + B + C + D 全做**，其中 **D2 采用彻底版**：为足球（11 人制/5 人制）与投篮训练补齐纯 `ScoreCore` `DomainReducer`，并实现 Phone Host 定序的 Intent/Op 并发同步 + Watch 乐观重放与冲突回滚。 |
| **D-3** | D3 能力预留边界 | **仅做代码层 `WatchStorageContainer` 目录抽象**（默认落地沙盒 `Application Support/jifen-watch-v1/`）。**本次首发严禁新增任何 `.entitlements`、App Group 或 HealthKit 能力**，避免触碰 Watch Provisioning Profile 与提审证书。 |
| **D-4** | 手表本地记录上限 | 维持 **500 条**，改用 `index.json` + 单条原子文件存储，列表只读轻量索引，记录详情与正文按单条读取。 |
| **D-5** | 已发布数据的兼容边界 | 保持 iPhone 的 `ScoreboardRecord`（schema v5）、`RecordCore.DetailedScoreAction`、独立续玩草稿及 `RecordSyncOutbox` / `CloudSync` 的存储和编码兼容。Watch 联动与独立记录摄取到手机后仍适配现有 `ScoreboardRecord`。Watch 旧开发版数据和双端旧联动协议、联动续赛、联动终态队列及退役场次均无需兼容。 |
| **D-6** | 分阶段与门禁 | 拆为 M1→M2→M3→M4→M5 五个里程碑；**每个里程碑结束必须保证 `JifenCore`、手表端、手机端全量构建与单测通过**才进入下一里程碑。 |

---

## §2 全局红线与工程约束（DeepSeek & Codex 审查基准）

任何里程碑在编码和 Review 时都必须逐条满足以下红线：

1. **证书 / Entitlements 零改动红线**
   - 严禁修改 `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Config/JifenAppStore.entitlements` 或 `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Config/JifenDebug.entitlements`。
   - 严禁在 `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifenWatch Watch App/` 下新建 `.entitlements` 文件或向 `project.pbxproj` 的 Watch target 注入 App Groups / HealthKit capability。
2. **手机存量数据与跨端兼容红线**
   - 不得破坏 `jifen/Features/Records/ScoreboardRecord.swift` 的现有 JSON `CodingKeys`、schema v5 读取及 `ScoreboardRecordFileStore` 存储路径。
   - 不得破坏 `RecordCore.DetailedScoreAction` 现有可序列化字段名（安卓/鸿蒙跨端与手机历史档案依赖这些字段）。
   - 手机业务 `RecordSyncOutbox` 与 Watch 联动终态队列用途不同。保留前者的既有存储和读取行为；后者、`PhoneLinkResumeContext` 及联动退役场次从本次格式起算。首发格式仍须保障同版本的持久化、重启恢复、迟到完赛、业务 ACK 和幂等。
3. **WCSession 工程红线**
   - **文件接收同步读取**：`WCSessionDelegate.session(_:didReceive file: WCSessionFile)` 返回后 watchOS/iOS 会立即删除临时文件，必须在回调返回前**同步**将 `file.fileURL` 读入 `Data` 或 `FileManager.default.moveItem` / `copyItem` 到持久化暂存目录后再异步派发。
   - **压缩帧前置探测**：`receive(_ data:)` / `handleIncoming(_ data:)` 路由分发时，必须先检测 `LinkFinishedEncoding` 的 3 字节魔数 `[0x4A, 0x46, 0x01]`（LZFSE 压缩的 `matchFinished` 帧无法被 `LinkEnvelopeHead` 直接 JSON 解码），先走 `LinkFinishedEncoding.decode(data)`，非压缩帧再一次性解码 `LinkEnvelopeHead` 并按 `head.kind` `switch` 路由。
   - **65,536 字节硬防线**：所有走 `sendMessageData`、`sendMessage`、`transferUserInfo`、`updateApplicationContext` 的调用都必须经过字节上限检查（交互/实时消息 ≤ `60_000` 字节；`applicationContext` 常用名分区独立预算 ≤ `24_000` 字节），杜绝 `WCSession` 原生 Objective-C 异常崩溃。
4. **DomainReducer 纯净性红线（M4/M5）**
   - `ScoreCore` 内所有 `DomainReducer.reduce(state:intent:at:)` 必须**纯函数化、确定性**：严禁在 reducer 内部调用 `Date()`、`DispatchTime.now()`、`UUID()`，所有时间/随机值必须由调用方通过 `epochMilliseconds` 或 `Intent` 参数显式传入。
5. **Xcode 工程与构建脚本红线**
   - `jifen`、`jifenWatch Watch App`、`jifenWatch Watch AppTests`、`jifenWatch Watch AppUITests` 均在 `jifen.xcodeproj/project.pbxproj` 中使用 `PBXFileSystemSynchronizedRootGroup`，增删文件自动生效；**`jifenTests` 未使用同步目录组**，在 `jifenTests/` 下新增/删除测试文件时必须同步更新 `jifen.xcodeproj/project.pbxproj`。
   - 构建/测试手表目标时，**严禁同时传递 `-sdk watchsimulator` 和 `-destination`**（会触发本机 Xcode linker filelist 路径错配），必须只传 `-destination`（见 §5）。
   - 遵守 `AGENTS.md`：实底绿色 Save/Confirm 按钮必须显式 `.foregroundStyle(.white)`；若运行产生 `.xcresult` / 截图产物，必须放到 `python3 scripts/test_artifacts.py new-run <label> --active` 托管目录并在完成后 `finish`。

---

## §3 目标分层架构与数据流图

### 3.1 分层总览

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                     Packages/JifenCore (共享单一事实来源)                      │
├──────────────────────────────────────────────────────────────────────────────┤
│ 1. ScoreCore       : GameType / TeamID / ShotTrainingState / Reducers        │
│                      (含新增 FootballMatchReducer & ShotTrainingReducer)     │
│ 2. SessionCore     : ScoreSessionMachine (同步值类型内核)                     │
│                      + ScoreSessionCore (actor 包装，保持手机侧完全兼容)       │
│ 3. RecordCore      : ScoreboardWinnerIdentity / RecordGameKind               │
│                      + CanonicalMatchRecord / DetailedScoreAction            │
│                      + 共享 ScoreActionProjector & MatchRecordProjector       │
│ 4. PersistenceCore : AtomicJSONFileStore                                    │
│                      + 通用索引+单文件 RecordStore / StorageContainer 抽象     │
│ 5. LinkCore        : FileLinkDataStore + 开放式 LinkCapability 协商           │
│                      + WatchSportRegistry                                   │
│                      + LinkEnvelopeHead 单次解码路由 + LinkSessionEngine      │
│                      + WCSession 三通道传输抽象 + Intent/Op 并发协议          │
└──────────────────────────────────┬───────────────────────────┬───────────────┘
                                   │                           │
                ┌──────────────────▼────────────┐  ┌───────────▼───────────────┐
                │        jifen (iPhone App)     │  │   jifenWatch Watch App    │
                │ - PhoneWatchLinkService       │  │ - WatchLinkService        │
                │   (薄 @Observable 外观)        │  │   (薄 @Observable 外观)    │
                │ - PhoneHostSequencer (.shared)│  │ - WatchStorageContainer   │
                │ - Canonical -> ScoreboardRecord│ │ - WatchReducerSessionStore│
                │   v5 薄摄取适配层              │  │ - 8 块极薄计分板 View     │
                └───────────────────────────────┘  └───────────────────────────┘
```

### 3.2 WCSession 三通道分层（替代“64KB 硬塞 + 砍动作”）

| 通道 | WCSession API | 承载内容 | 字节预算 | 离线/大包策略 |
|---|---|---|---|---|
| **① 实时交互通道** | `sendMessageData` | 握手（`setupRequest`/`Accepted`/`Rejected`）、`intentSubmit`（M5 <300B）、`intentCommit`（M5 <500B）、增量 `stateSnapshot`（M1/M3）、`resyncRequest`、`connectivityProbe`、`sessionLeft` | ≤ 60,000 B（正常 < 4KB） | 仅前台可达使用；仅带**未 ACK 增量动作** |
| **② 最新状态兜底** | `updateApplicationContext` | `latestLinkSnapshot`（剥离动作历史，仅轻状态/checkpoint）+ `commonNames` 轻量快照 | 总字典 < 60KB（其中常用名预算 ≤ 24KB） | 各自写入前强制预算校验，防止互相挤爆 |
| **③ 离线可靠大包** | `transferUserInfo` + **`transferFile`** | 联动完赛 `matchFinished`、手表独立完赛记录 `CanonicalWatchRecordTransfer`、常用名变更批次 `CommonNameMutationBatch` | `≤ 32KB` 走 `transferUserInfo`；`> 32KB`（或 LZFSE 压缩后仍超 60KB）走 `transferFile` | 应用队列保留完整记录，按接收端落库回执出队 |

### 3.3 M5（D2-彻底）Phone 定序与 Watch 乐观重放时序

```text
[Watch UI] ──(同步 dispatch)──▶ [WatchReducerSessionStore]
   │                              │ 1. 追加 pendingLocalOps (持久化)
   │                              │ 2. 本地乐观重放 UI 零延迟刷新
   │                              ▼
   │                        [LinkOperation(opId, clientSeq, baseRev, intent)]
   │                              │ sendMessageData (.intentSubmit)
   │                              ▼
[Phone UI] ──(同步本地提交)──▶ [PhoneHostSequencer (@MainActor)]
                                  │ 3. opId 幂等判重
                                  │ 4. 校验 baseRev / 足球时间戳单调钳制
                                  │ 5. Reducer 执行并分配 committedRevision += 1
                                  │ 6. 每 10 次或 rejected/undo/nextMatch 附带 snapshot checkpoint
                                  │
                                  ├──▶ [Phone UI] 即时推进 confirmedState + 重放(若有)
                                  └──▶ sendMessageData (.intentCommit) ──▶ [Watch]
                                                                             │ 7. 推进 confirmedState
                                                                             │ 8. 弹出已确认 opId
                                                                             │ 9. 重放剩余 pendingLocalOps
                                                                             │ 10. 校验 stateHash，漂移/跳号则发 .resyncRequest
```

---

## §4 五阶段实施手册（M1 ～ M5）

> **执行规则**：每个里程碑必须严格按顺序完成，跑通本阶段适用的验收命令并独立提交后，再开始下一阶段。M3 与 M4 的纯 `.shared` 联动用于开发验收，公开启用须等 M5 验证并发计分与完赛一致性。

---

### Milestone 1 (M1)：首发存储底座、协议前向兼容与 WCSession 三通道重构
- **对应原方案**：模块 A + 模块 D3（纯代码存储容器抽象）
- **阶段目标**：消除协议未来升级锁死隐患、将 Watch 重型状态全部迁离 `UserDefaults`、引入 `WCSession.transferFile` 与增量动作传输、清零所有伪历史迁移债。

#### 1. 精确 Swift 契约与类型设计

1. **`Packages/JifenCore/Sources/LinkCore/LinkCore.swift`**
   - 将 `LinkCapability` 从封闭 `enum` 改为开放式 `RawRepresentable` struct（未知字符串值解码不失败）：
     ```swift
     public struct LinkCapability: RawRepresentable, Codable, Hashable, Sendable {
         public let rawValue: String
         public init(rawValue: String) { self.rawValue = rawValue }

         public static let independentMatches = Self(rawValue: "independentMatches")
         public static let authorityEpoch = Self(rawValue: "authorityEpoch") // M1 仍保留主控协议，M3 删除
         public static let correlatedRequests = Self(rawValue: "correlatedRequests")
         public static let durableTerminalQueue = Self(rawValue: "durableTerminalQueue")
         public static let latestSnapshotContext = Self(rawValue: "latestSnapshotContext")
         // 新增能力（M1/M5 使用）
         public static let compressedFinish = Self(rawValue: "compressedFinish")
         public static let deltaActions = Self(rawValue: "deltaActions")
         public static let fileTransfer = Self(rawValue: "fileTransfer")
         public static let sharedIntentSync = Self(rawValue: "sharedIntentSync")
     }
     ```
   - 协议版本与能力集合改为子集协商：
     ```swift
     public enum LinkProtocol {
         public static let currentVersion = 1
         public static let minimumSupportedVersion = 1
         public static let requiredCapabilities: Set<LinkCapability> = [
             .independentMatches,
             .authorityEpoch, // M1 仍运行现有主控协议
             .correlatedRequests,
             .durableTerminalQueue
         ]
         public static let capabilities: Set<LinkCapability> = [
             .independentMatches,
             .authorityEpoch,
             .correlatedRequests,
             .durableTerminalQueue,
             .latestSnapshotContext,
             .compressedFinish,
             .deltaActions,
             .fileTransfer
         ]
     }
     ```
   - 能力以 JSON 字符串表示。握手校验已支持的协议版本范围，核对信封与 setup 声明，保存双方已知能力的交集。只有双方协商通过后才启用对应的新能力。此机制用于本次首发及后续扩展，开发版协议与队列无需双读、回退或互通。
   - 拒绝原因枚举与 payload：
     ```swift
     public enum LinkSetupRejectionReason: String, Codable, Equatable, Sendable {
         case userDeclined = "user_declined"
         case unsupportedSport = "unsupported_sport"
         case incompatibleProtocol = "incompatible_protocol"
         case malformedSetup = "malformed_setup"
     }

     public struct LinkSetupRejectedPayload: Codable, Equatable, Sendable {
         public let reason: LinkSetupRejectionReason
         public let detail: String?
         public init(reason: LinkSetupRejectionReason = .userDeclined, detail: String? = nil) {
             self.reason = reason
             self.detail = detail
         }
     }
     ```
     `PhoneWatchLinkMessageHandling.handleSetupResponse` 使用 `LinkEnvelope<LinkSetupRejectedPayload>` 处理拒绝响应，双端夹具使用本次协议格式。
   - 新增增量动作差集标记：`LinkedScoreboardSetup` 增加可选字段 `public var isDeltaActions: Bool?`（`nil` 用于不声明动作差集的快照，`true` 用于追加型动作增量。撤销、重置用 `false` 和明确的 `removedActionIDs` 表示动作删除，并重置增量确认状态。接收端按 ID 保留未被撤销的并发动作，已删除 ID 在场次内持久化以过滤旧帧）。
   - `WatchLinkTransport` & `WatchConnectivityTransport` 扩展文件传输与常量：
     ```swift
     public enum WatchTransferFileKind: String, Codable, Sendable {
         case watchRecord = "watch_record"
         case matchFinished = "match_finished"
     }
     ```
     在 `WatchLinkTransport` 增加：
     - `var onReceivedFile: (@Sendable (Data, [String: Any]) -> Void)? { get set }`
     - `func transferFileData(_ data: Data, metadata: [String: Any]) throws`
     在 `WatchConnectivityTransport` 实现：
     - `transferFileData(_ data: Data, metadata: [String: Any]) throws`：将 `data` 写入 `FileManager.default.temporaryDirectory` 下唯一临时文件（后缀 `.jifenlink`），调用 `session.transferFile(fileURL, metadata: metadata)`；并在 `session(_:didFinish fileTransfer:error:)` 中清理临时发送文件。传输完成回调只用于管理暂存文件，应用内完整载荷保留到收到接收端的落库 ACK。
     - `session(_ session: WCSession, didReceive file: WCSessionFile)`：**同步**读取 `let data = try? Data(contentsOf: file.fileURL)`（或同步移动/拷贝）后立刻传给 `onReceivedFile?(data, file.metadata ?? [:])`。
     - 按最终合并后的字典校验 `updateApplicationContext` 字节预算，并给保留的常用名传输与回执补齐预算校验（抛出 `WatchConnectivityTransportError.payloadTooLarge`）。

2. **`Packages/JifenCore/Sources/LinkCore/WatchSideChannelSync.swift`**
   - 下沉双端统一预制名称库 `PresetCommonNames`（合并 `WatchCommonNamesStore.presetNameKeys` 与 `CommonNamesManager.presetNameKeys`，含简繁体及英文预设词）。
   - 为 `CommonNamesSyncSnapshot` 增加 `budgetConstrainedData(maxBytes: Int = 24_000) -> CommonNamesSyncSnapshot`：在超出 `applicationContext` 常用名分区 24KB 预算时按队名/人名尾部裁剪并保留最新条目，防止挤爆 `WCSession.applicationContext` 的 65KB 总限额。
   - **删除** `CommonNameUsagePayload`（以及 `WatchLinkTransport.transferCommonNameUsage`、`onCommonNameUsageData`、`commonNameUsageUserInfoKey`、`pendingCommonNameUsageKey`）——统一走 `CommonNameMutation`（`.add`）单通道，彻底消灭双通道重复发送。

3. **文件存储实现与容器抽象**
   - 在 `LinkCore` 中与 `LinkDataStore` 放在同一个目标里，新增线程安全文件实现 `FileLinkDataStore: @unchecked Sendable, LinkDataStore`：
     ```swift
     public final class FileLinkDataStore: @unchecked Sendable, LinkDataStore {
         private let directoryURL: URL
         private let lock = NSLock()
         public init(directoryURL: URL) { ... }
         public func data(forKey key: String) -> Data?
         public func set(_ data: Data, forKey key: String)
         public func removeObject(forKey key: String)
     }
     ```
     内部将 `key` 做安全文件名映射（如字母数字下划线连字符保留，或 SHA256/Base64URL），使用 `Data.write(to: url, options: .atomic)` 落盘，替代双端联动服务默认的 `UserDefaultsLinkDataStore.standard`。完赛队列和清理等需要验证落盘的路径使用可返回错误的写入和删除接口。
   - `PersistenceCore` 内的存储根目录抽象协议 `AppStorageContainer: Sendable`：
     ```swift
     public protocol AppStorageContainer: Sendable {
         var rootURL: URL { get }
         func subdirectory(_ name: String) -> URL
     }
     ```

4. **`jifenWatch Watch App` 侧本地存储重构**
   - **[新增] `jifenWatch Watch App/Managers/WatchStorageContainer.swift`**：
     - 默认实现指向 `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("jifen-watch-v1", isDirectory: true)`。
     - 显式注释：未来切换 App Group 只需将 `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ...)` 注入此唯一入口，上层零改动。
     - 统一划分子目录：`records/`、`resume/`、`link/`、`common-names/`、`outbox/`。
   - **`jifenWatch Watch App/Managers/WatchRecordManager.swift`**：
     - 改造成与手机端 `ScoreboardRecordFileStore` 同构的 **索引 + 单记录原子文件** 存储：
       - `records/index.json` 存储 `[WatchScoreboardRecordIndexEntry]`（含 `WatchScoreboardRecordSummary` 的列表展示字段 + `syncState: WatchRecordSyncState?`，无需单独维护 `UserDefaults` 中的 `watch_record_sync_states` 字典）。
       - `records/<safe-id>.record.json` 存放完整记录（含 `actions`）。
       - 上限保持 `500` 条，淘汰超出条数时同步清理对应单记录文件。
       - 索引丢失或损坏时扫描单记录文件重建，依据持久化的同步信息恢复待发送和已同步状态。索引保存单记录文件标识。正常打开列表只读取索引和文件元数据；索引更新中断后只重读发生变更的记录正文，删除或淘汰的记录不会复现。
     - 彻底移除 `legacyRecordsKey`（`"watch_scoreboard_records"`）迁移代码与 `UserDefaults` 同步状态读写。
   - **`jifenWatch Watch App/Models/WatchScoreboardRecord.swift`**：
     - 修复 `WatchScoreboardRecordSummary.init(from:)` 每次实例化 `DateFormatter()` 的问题：改为静态缓存 formatter（注意线程安全：Swift 仅在固定 locale 下或主线程使用/加锁 `NSLock`，或使用 `Date.FormatStyle` 值类型）。
   - **`jifenWatch Watch App/Models/WatchResumeSession.swift`**：
     - 从 `UserDefaults` 迁到 `WatchStorageContainer` 下的 `resume/current.json` 与 `resume/pending-finished.json`（使用 `AtomicJSONFileStore` 或串行队列原子文件）。
     - **防抖优化**：`scheduleWrite` 改为防抖整个 `JSONEncoder().encode(session)` + 后台写盘任务，主线程只保存轻量的内存 `WatchResumeSession` 引用，彻底消除每次得分在主线程同步编码全量 `undoFrames` + `actionLog`。清理与写盘使用同一串行边界，取消或隔离已排队的旧写入，避免清空后恢复已删草稿。
     - **清零伪迁移债**：删除 `legacyCleanupMarkerKey`、删除 `watch_resume_session_v1` / `jifen-v2` / `jifen/resume` 清理分支、删除 `schemaVersion == 2` 射箭 `normalizedFromLegacyPhysicalSideSwap` 迁移逻辑（当前直接起算干净的 `schemaVersion = 1` 或保留当前干净版本）。
   - **`jifenWatch Watch App/Managers/WatchCommonNamesStore.swift`**：
     - 从 `UserDefaults` 的 7 个零散 key 迁到 `WatchStorageContainer` 下的 `common-names/store.json` 单一原子文件；改用 `LinkCore.PresetCommonNames` 判断预制词。
   - **双端 `LinkService` 文件存储 & 去嵌套**：
     - `WatchLinkService` 默认 `contextStore` / `outboxStore` 改为 `WatchStorageContainer.shared.linkDataStore`；`pendingWatchRecords` 迁入 `outbox/` 文件存储。
     - `PhoneWatchLinkService` 默认 `contextStore` / `outboxStore` 使用手机端 `Application Support/<bundleId>/WatchLink/` 目录的 `FileLinkDataStore`。联动续赛、待发送完赛和退役场次直接按新格式写入与恢复，无需读取开发版旧键。同步更新 `LocalDataResetComposition.swift`，保持只清手机侧的现有语义。
     - 消除 `WatchLinkResumeContext` / `PhoneLinkResumeContext` 的双份 `detailedActions` 与 `setup.detailedActions` 冗余：在 `persistContext()` 与 `WatchResumeSession.link` 构造时，`setup.detailedActions` 置空数组 `[]`，仅由外层 `detailedActions` 持有唯一权威动作列表。
     - 移除 Watch 和双端联动的开发版旧键、旧路径和版本迁移分支。删除 `WatchGameType.basketball` / `.threeBasketball` 及 `WatchSetupModels` 中未发版过的旧档位兼容回退。

5. **WCSession 通道重构（增量动作 + 离线大包 `transferFile`）**
   - **增量动作跟踪**：在 `WatchLinkService` 与 `PhoneWatchLinkService` 中维护 `lastAcknowledgedActionIDs: Set<UUID>` 与 `inFlightMessageActions: [UUID: [UUID]]`（记录某条 `messageId` 发出的动作 id）。发送实时 `stateSnapshot` 时：
     - 过滤 `mergedDetailedActions` 中不在 `lastAcknowledgedActionIDs` 的增量动作（按时间保序）；设置 `setup.isDeltaActions = true`。
     - 每条实时帧最多 60 KB，以最终编码中实际包含的动作登记待确认 ID。`applicationContext` 检查点剥离动作并分配独立的消息 ID。
     - 收到与当前待发帧的比赛、权限和版本匹配的回执后，仅确认该帧实际承载的新增或删除 ID。还有待发历史变更时，在相同比分版本下立即发送下一批；断连时保留待发帧，恢复可达后自动重试。
     - 已确认的动作 ID 在该场生命周期内保留。手动 `resyncRequest` 和换场时重置台账。
   - **压缩与文件传输降级**：
     - `publishMatchFinished` / `notifyMatchFinished` 先生成并保存完整完赛载荷。路由判断使用未裁剪的 JSON 或双方支持的无损压缩结果。现有 `LinkFinishedEncoding.encode` 可能在返回前已裁剪动作，选择通道前不得调用该回退路径。实时预算 ≤60 KB，后台字典预算 ≤32 KB。超出当前可用通道预算时，使用已协商的 `transferFile`；对端暂不支持时保留完整待发送载荷。文件通道解码使用独立且有界的预算。
     - 独立记录回传 `WatchLinkSideChannels.transferFinishedRecord` 改为：保存后立刻按大小选择传输——编码后 `<= 32_000` 字节直接调用 `transport.transferWatchRecord(data)`（系统 `transferUserInfo` 后台排队），`> 32_000` 字节调用 `transport.transferFileData(data, metadata: ["kind": "watch_record"])`；若当前 `isReachable == true` 同时通过 `sendPendingWatchRecords` 快路径加速首屏到达（仍以 `clearPendingWatchRecords` ACK 为出队依据，保证幂等）。
   - **收包路由升级**：`WatchLinkMessageHandling.receive(_:)` 和 `PhoneWatchLinkMessageHandling.handleIncoming(_:)` 改为：
     1. 先探测 `LinkFinishedEncoding` 压缩魔数 `[0x4A, 0x46, 0x01]` → 直接进入完赛处理；
     2. 否则解码一次 `LinkEnvelopeHead` → `switch head.kind` 精确派发到对应 handler；
     3. 解码失败且 `head.kind == .setupRequest` 时回发 `LinkSetupRejectedPayload(reason: .malformedSetup)`；
     4. `handleSetupRequest` 仅为支持范围内的协议版本建立会话。已知基础能力采用子集校验，扩展能力取交集并在握手响应中确认。
   - **常用名管理**：`CommonNamesManager.swift` 改用 `PresetCommonNames.isPreset(...)`，并在 `pushCommonNamesToWatch()` 使用 `.budgetConstrainedData()`。

#### 2. 涉及文件清单
- **修改（JifenCore）**：`LinkCore.swift`、`WatchSideChannelSync.swift`、`PersistenceCore.swift`、`LinkFinishedEncoding.swift`（暴露魔数检测辅助 `isCompressedFrame(_ data: Data) -> Bool`）
- **新增（Watch）**：`jifenWatch Watch App/Managers/WatchStorageContainer.swift`
- **修改（Watch）**：`WatchRecordManager.swift`、`WatchScoreboardRecord.swift`、`WatchResumeSession.swift`、`WatchCommonNamesStore.swift`、`WatchPreferences.swift`、`WatchGameType.swift`、`WatchSetupModels.swift`、`WatchLinkService.swift`、`WatchLinkSession.swift`、`WatchLinkMessageHandling.swift`、`WatchLinkReliability.swift`、`WatchLinkSideChannels.swift`、`WatchRootView.swift`、`WatchRecordListView.swift`、`WatchRecordDetailView.swift`、`WatchSportsSetupView.swift`
- **修改（Phone）**：`PhoneWatchLinkService.swift`、`PhoneWatchLinkSession.swift`、`PhoneWatchLinkMessageHandling.swift`、`PhoneWatchLinkReliability.swift`、`PhoneWatchLinkSideChannels.swift`、`CommonNamesManager.swift`、`LocalDataResetComposition.swift`
- **修改（Tests）**：`WatchLinkServiceTests.swift`、`WatchRecordCacheTests.swift`、`WatchStartupOptimizationTests.swift`、`WatchCommonNamesStoreTests.swift`、`WatchSportsSetupTests.swift`、`PhoneWatchLinkServiceTests.swift`、`LocalDataResetCoordinatorTests.swift`、`ScoreboardDisplayTests.swift`、`LinkPayloadSafetyTests.swift`（以及 `JifenCoreTests` 新增 `FileLinkDataStore` / `LinkCapability` 协商测试）

#### 3. 避坑要点
- `LinkEnvelopeHead` 解码时注意：`protocolVersion` 可能高于当前 `currentVersion`（未来版本发来的请求），只要 `LinkEnvelopeHead` 字段齐全即可解析出 `kind` / `messageId` / `sessionId`；若协议版本不在支持范围内，或 `capabilities` 缺少 `requiredCapabilities`，应显式回复 `.setupRejected(reason: .incompatibleProtocol)`。
- 测试替身 `WatchLinkTestTransport`（`WatchLinkServiceTests.swift`）与 `FakeWatchLinkTransport`（`PhoneWatchLinkServiceTests.swift`）和 `ScoreboardDisplayTests` 若引用同一协议，需同步实现新增的 `transferFileData` 与 `onReceivedFile` 并移除已删除的 `transferCommonNameUsage` / `onCommonNameUsageData`。
- `WatchRecordManager` 可从内存索引读取 `syncState(for:)`。单记录正文、索引和同步状态之间的部分写入或删除须可恢复。持久化失败应反馈给调用方，业务 ACK 以成功落盘为准。

#### 4. M1 验收清单与标准
- **新增/更新测试**：
  - `JifenCoreTests`：开放式 `LinkCapability` 未知值编解码兼容、子集协商放行新增未知能力、缺少必需能力拒绝；`FileLinkDataStore` 并发原子读写删除；`CommonNamesSyncSnapshot.budgetConstrainedData` ≤ 24KB 约束；`LinkFinishedEncoding.isCompressedFrame`。
  - `WatchLinkServiceTests` & `WatchRecordCacheTests`：增量动作差集发送与 ACK 后不再重复携带；完赛超 60KB 自动降级 `transferFileData` 且不丢任何动作；独立记录 ≤32KB 走 `transferUserInfo`、>32KB 走 `transferFileData`；`WatchRecordManager` 索引重建（删掉 `index.json` 后可从单文件目录全量恢复）；`WatchStartupOptimizationTests` 验证清理掉旧清理逻辑后的干净初始化。
  - 双端联动与存储额外验收：超出支持范围的协议版本被拒绝；未知能力可解码但不会被启用；完整动作包经收包路由往返，写入失败时发送端保留载荷；同协议内上一场完赛在换场、重启、跨通道重复投递后仍只落一条并可回执；清理与待写任务竞态后已清理的数据不会复现。
  - `PhoneWatchLinkServiceTests`：`didReceiveFile` 注入后手机持久化大记录并发送 `clearPendingWatchRecords`。M1 使用模拟器与测试替身验证代码路径，并记录真机验证状态。发布候选按 §5.5 用配对真机验证后台传输、重连、落库和 ACK。
- **验收标准**：按 §5 跑共享包、Watch 与 iPhone 编译和完整单测，M1 涉及的测试须全部通过；`UserDefaults.standard` 不再存任何记录/续玩/Outbox/常用名大 blob。
- **Commit 建议**：`refactor(watch-data): M1 storage container, open capabilities, delta sync & file transfer`

---

### Milestone 2 (M2)：共享数据模型、统一投影器与运动能力注册表
- **对应原方案**：模块 B
- **阶段目标**：彻底消灭 `WatchScoreAction`、`WatchScoreActionProjector`、3 套投篮训练模型、4 份重复记录投影以及 10+ 处分散的运动支持白名单；手表记录采用类型安全的 `ScoreboardWinnerIdentity` 与 `DetailedScoreAction`。

#### 1. 精确 Swift 契约与类型设计

1. **`Packages/JifenCore/Sources/RecordCore/`**
   - **上移 `ScoreboardWinnerIdentity`**（从 `jifen/Features/Records/ScoreboardRecord.swift:28-113` 原样迁至 `RecordCore/RecordCore.swift` 为 `public enum ScoreboardWinnerIdentity: Codable, Equatable, Sendable`，`jifen` 端直接复用不再重复定义，JSON 编码格式 100% 不变）。
   - **清理死模型**：删除 `SharedTwoSideMatchRecord.swift` 及 `RecordCore.ScoreRecordV2`（先确认并清理 `JifenCoreTests` 中仅针对 `ScoreRecordV2` 与 `toSharedRecord()` 的过期断言）。
   - **定义统一游戏标识与规范记录 `[新增] Packages/JifenCore/Sources/RecordCore/CanonicalMatchRecord.swift`**：
     ```swift
     public enum RecordGameKind: Codable, Equatable, Hashable, Sendable {
         case sport(ScoreCore.GameType)
         case counter
     }

     public struct RecordParticipantScore: Codable, Equatable, Sendable {
         public let name: String
         public let score: Int
         public init(name: String, score: Int) { ... }
     }

     public struct CanonicalMatchRecord: Codable, Equatable, Identifiable, Sendable {
         public static let currentSchemaVersion = 1
         public let schemaVersion: Int
         public let id: String
         public let kind: RecordGameKind
         public let source: RecordSource
         public let startEpochMilliseconds: Int64
         public let endEpochMilliseconds: Int64
         public let durationSeconds: Double
         public let team1Name: String
         public let team2Name: String
         public let team1FinalScore: Int
         public let team2FinalScore: Int
         public let team1SetScore: Int?
         public let team2SetScore: Int?
         public let winnerIdentity: ScoreboardWinnerIdentity?
         public let detailedActions: [DetailedScoreAction]
         public let totalScoreChanges: Int
         public let participants: [RecordParticipantScore]?
         public let projectConfiguration: [String: String]
         public let basketballTraining: ShotTrainingState?
     }
     ```
   - **共享投影器 `[新增] Packages/JifenCore/Sources/RecordCore/MatchRecordProjector.swift` & `ScoreActionProjector.swift`**：
     - 将 `WatchScoreActionProjector`（Rally / Tennis / Archery / EightBall / NineBall / Snooker + M4 后扩到 Football / ShotTraining）重命名并下沉为 `RecordCore.ScoreActionProjector`，直接产出 `[DetailedScoreAction]`。
     - 在 `RecordCore` 提供 `MatchRecordProjector.project(from: SnapshotInput, ...)`（`SnapshotInput` 在 M2 可先用协议或枚举桥接 `LinkCore.LinkedScoreboardSnapshot` 与本地快照，建议由 `LinkCore` 提供 `LinkedScoreboardSnapshot.toCanonicalRecord(...)` 调用 `RecordCore` 原子构建器，避免循环依赖：`LinkCore` 已依赖 `ScoreCore`、`SessionCore`、`RecordCore`）。

2. **统一投篮训练与射箭状态（`Packages/JifenCore/Sources/ScoreCore/`）**
   - 将 `LinkedShotTrainingState.swift` 中的核心模型 `ShotTrainingMode`、`ShotTrainingShot`、`ShotTrainingCounts`、`ShotTrainingState`（保留 `packedShots` 2,048 压缩与 `earlierCounts`）**下沉到 `ScoreCore`**（`LinkCore` 中 `typealias LinkedShotTrainingState = ShotTrainingState` 等保持平滑过渡）。
   - 手表删除 `WatchBasketballTrainingMode`、`WatchBasketballTrainingShot`、`WatchBasketballTrainingDetails`；手机端 `ShotTrainingScoreboardView.swift` / `ShotTrainingSetupDialogView.swift` 改用 `ScoreCore` 类型（注意手机已有本地磁盘存量 `ShotTrainingResumeState` 的 JSON 键名兼容！保留旧键名解码或用 `CodingKeys` 对齐）。
   - **消除 `LinkedArcheryState` 字段漂移**：优先让 `LinkedScoreboardSnapshot.archery(ArcheryMatchState)` 直接使用 `ScoreCore.ArcheryMatchState`。若为缩减首发联动载荷而保留独立表示，补齐字段映射和同协议往返测试。开发版联动草稿与完赛包无需兼容。

3. **单一事实来源注册表 `[新增] Packages/JifenCore/Sources/LinkCore/WatchSportRegistry.swift`**
   - 收口当前分散在 10+ 处的所有运动配置：
     ```swift
     public enum WatchSetupFamily: String, Codable, Sendable {
         case rally, tennis, archery, eightBall, nineBall, snooker, football, basketballTraining
     }

     public struct WatchSportDescriptor: Equatable, Sendable {
         public let gameType: ScoreCore.GameType
         public let baseKind: RecordGameKind
         public let setupFamily: WatchSetupFamily
         public let supportsWatchLocalSetup: Bool
         public let supportsPhoneWatchLink: Bool
         public let isDoubles: Bool
         public let defaultMaxSets: Int?
         public let defaultFootballHalfLengthSeconds: Int?
     }

     public enum WatchSportRegistry {
         public static let allLinkedGameTypes: Set<ScoreCore.GameType> = ... // 全部 19 项
         public static func descriptor(for gameType: ScoreCore.GameType) -> WatchSportDescriptor?
         public static func supportsPhoneWatchLink(_ gameType: ScoreCore.GameType, playerCount: Int?, competitionFormat: CompetitionFormat?) -> Bool
         public static func isValidLinkedSetup(_ setup: LinkedScoreboardSetup) -> Bool
     }
     ```
   - 手机端 `AppFeatureFlags.isWatchLinkSupportedProject`、`PhoneWatchLinkService.phoneInteractiveStartSupported`、手表端 `WatchLinkSession.isValidLinkedSetup`、`WatchScoreboardRoute(linkedSetup:)` 全部委派给 `WatchSportRegistry`。

4. **彻底删除 `WatchScoreAction` & 简化 Watch 本地记录层**
   - 删除 `WatchScoreAction`、`WatchScoreActionType`；`WatchScoreActionLog` 直接存储 `[DetailedScoreAction]`，并**修复** `merge(detailedActions:)` 为真正按 `action.id` 去重求并集 + 排序（不再全量覆写！）。
   - `WatchScoreboardRecord` 改为 `typealias WatchScoreboardRecord = CanonicalMatchRecord`（或极薄包装带 UI 计算属性 extension）；`WatchRecordTransferPayload` 直接携带 `CanonicalMatchRecord`（消除了 20 个手动拷贝字段）。
   - 手表 9 个计分板/工具页（含 `WatchCounterView`）全部调用共享投影器构建 `CanonicalMatchRecord` 传给 `WatchResumeSessionStore.saveFinishedRecord(...)`；`WatchRecordDetailView` 直接使用 `record.winnerIdentity`（彻底修掉同名队高亮 bug）与 `record.detailedActions` 渲染。
   - 手机端 `WatchStandaloneRecordIngestor` 与 `LinkedMatchRecordIngestor` 合并为一个统一的 `WatchCanonicalRecordAdapter.toScoreboardRecord(_ record: CanonicalMatchRecord, linkedSessionId: UUID?) -> ScoreboardRecord`（输出与现有 schema v5 `ScoreboardRecord` 完全一致）。

#### 2. 涉及文件清单
- **新增**：`Packages/JifenCore/Sources/RecordCore/CanonicalMatchRecord.swift`、`Packages/JifenCore/Sources/RecordCore/MatchRecordProjector.swift`、`Packages/JifenCore/Sources/RecordCore/ScoreActionProjector.swift`、`Packages/JifenCore/Sources/ScoreCore/s2/ShotTraining.swift`、`Packages/JifenCore/Sources/LinkCore/WatchSportRegistry.swift`
- **删除**：`Packages/JifenCore/Sources/RecordCore/SharedTwoSideMatchRecord.swift`、`Packages/JifenCore/Sources/LinkCore/LinkedShotTrainingState.swift`（或改为兼容 re-export）
- **修改**：`RecordCore.swift`、`LinkCore.swift`、`WatchSideChannelSync.swift`、`ScoreboardRecord.swift`、`AppFeatureFlags.swift`、`PhoneWatchLinkSession.swift`、`WatchLinkMenuSupport.swift`、`ShotTrainingScoreboardView.swift`、`ShotTrainingSetupDialogView.swift`、`WatchGameType.swift`、`WatchScoreboardRecord.swift`、`WatchScoreAction.swift`、`WatchScoreboardRoute.swift`、`WatchSetupModels.swift`、`WatchRecordManager.swift`、`WatchLinkService.swift`、`WatchLinkSession.swift`、`WatchRecordListView.swift`、`WatchRecordDetailView.swift`、`WatchRootView.swift` 及 8 块手表计分板 + `WatchCounterView.swift`
- **更新测试**：`RecordCoreV4Tests.swift`、`WatchSportsSetupTests.swift`、`WatchRecordCacheTests.swift`、`WatchLinkServiceTests.swift`、`PhoneWatchLinkServiceTests.swift`（更新原 `toSharedRecord` / `WatchScoreboardRecord` / 白名单对齐断言）

#### 3. 避坑要点
- **手机端存量兼容检查**：`ShotTrainingResumeState` 在手机磁盘可能存有老用户草稿；将底层类型收口到 `ScoreCore.ShotTrainingMode` 时务必确认 `rawValue` 字符串（`"fixed_1"`, `"fixed_2"`, `"fixed_3"`, `"free"`）或提供兼容解码器，绝不让手机存量草稿解码失败！
- **`WatchScoreActionLog.scoreChangeCount` 口径**：原口径精准排除了 `basketball_` 前缀犯规与 0 分调整（见 `WatchScoreAction.swift:269-289`），下沉到 `RecordCore` 时必须完整保留该统计口径并通过单测验证。
- **`WatchScoreboardRecordSummary` 展示分值规则**：网球 `tiebreak_only`、双打 4 人拼名、九球多玩家 `·` 分隔展示必须在新扩展中保持 100% UI 一致，不破坏 UI Tests。

#### 4. M2 验收清单与标准
- **新增/更新测试**：
  - `JifenCoreTests`：`WatchSportRegistry` 19 项全覆盖校验 & `setup` 合法性矩阵测试；`ScoreActionProjector` & `MatchRecordProjector` 全运动投影单测；`ShotTrainingState` `packedShots` > 2048 溢出聚合测试；`ScoreboardWinnerIdentity` 编解码与兼容 token 测试。
  - `WatchSportsSetupTests` / `WatchRecordCacheTests`：同名队伍记录详情胜者高亮测试（验证 `winnerIdentity` 修复）；`WatchScoreActionLog.merge` 并集合并保留本地离线动作测试。
  - `PhoneWatchLinkServiceTests`：`WatchCanonicalRecordAdapter` 映射到 `ScoreboardRecord` v5 字段完整性验证（含足球无局分、`setResults`、九球 `players`、投篮 `extraData`）。
- **验收标准**：`swift test` + Watch target 编译与单测 + `PhoneWatchLinkServiceTests` + `WatchDialogConsistencyUITests` 全绿。
- **Commit 建议**：`refactor(models): M2 canonical match record, shared projectors & WatchSportRegistry`

---

### Milestone 3 (M3)：纯 `.shared` 协作瘦身与共享 `LinkSessionEngine` 下沉
- **对应原方案**：模块 C（已拍板：双端均可计分，移除单主控移交）
- **阶段目标**：彻底删除 1,000+ 行单主控权移交代码（`takeover` / `forceTakeover` / `reclaim` / `watchBackgrounded` / `authorityEpoch` 三阶段提交），并将双端镜像重复的 `LinkSession` / `Reliability` 引擎下沉到 `LinkCore`。

#### 1. 精确 Swift 契约与类型设计

1. **协议与状态机瘦身（`Packages/JifenCore/Sources/LinkCore/LinkCore.swift`）**
   - 精简 `LinkControlRole` 为 `.shared`，同时切换到本阶段的联动持久化格式。
   - 精简 `LinkMessageKind`：删除 `.takeoverByPhone`、`.reclaimRequest`、`.reclaimAccepted`、`.reclaimDenied`、`.watchBackgrounded`、`.resumeDiscarded`。保留：
     - `.setupRequest`、`.setupAccepted`、`.setupRejected`
     - `.stateSnapshot`、`.acknowledgement`、`.recordAcknowledgement`
     - `.statusQuery`、`.statusResponse`、`.resyncRequest`
     - `.matchFinished`、`.scoreboardExitedToHome`、`.sessionLeft`
     - `.commonNamesSyncRequest`、`.connectivityProbe`、`.connectivityProbeResponse`
     *(同时移除已废弃的 `LinkAuthorityTransferPayload`、`LinkResumeDiscardReason`、`LinkResumeDiscardPayload`、`LinkManualResyncPolicy` 的单向限制)*。
   - **双向 `resyncRequest` 策略**：任何一端处于活跃 `.shared` 会话中均可发起 `.resyncRequest`，对端收到后立即回发自身当前最新的 `.stateSnapshot`（携带完整 `mergedDetailedActions` 或自对端已确认游标后的全量动作，供修复漏帧）。
   - 精简 `LinkSessionStateMachine`：
     - 删除 `PendingAuthorityTransfer`、`beginAuthorityTransfer`、`prepareAuthorityTransfer`、`commitAuthorityTransfer`、`rejectAuthorityTransfer`、`adoptAuthority`、`transferAuthority`、`forceAuthority`、`authorityEpoch`（或将 `authorityEpoch` 从状态机移除）。
     - 保留 `handle: LinkedMatchHandle`、`revision: UInt64`（沿用奇偶轮次定序 `LinkSharedRevision` 直到 M5 切换为 Host 定序）、`completedMatchIds`、`lifecycle`、`pendingAcknowledgementIds`。
     - **删除冗余 `LinkRevisionGate`**：所有消息排序、重复判定和 `matchGeneration` 推进统一由 `LinkSessionStateMachine.accept(handle:revision:)` 单一真相源完成。

2. **合并双端上下文与下沉共享引擎 `[新增] Packages/JifenCore/Sources/LinkCore/LinkSessionEngine.swift`**
   - 合并 `PhoneLinkResumeContext` 与 `WatchLinkResumeContext` 为统一的 `LinkSessionContext`（在 M1 已去除重复 `detailedActions` 嵌套的基础上）。
   - 抽出共享结构体 `LinkedSnapshotUpdate: Equatable, Sendable`（移入 `LinkCore`，两端共用，不再双边各写一份）。
   - 抽出共享动作合并器 `DetailedActionMerger`（按 `id` 并集合并 + 时间排序）。
   - 抽出核心协议与参数化引擎 `LinkSessionEngine`:
     - 参数化 `localPeer: LinkPeer`（`.phone` vs `.watch`）、`contextKey`、`outboxKey`、`pendingEndsKey`、`localRecordIDPrefix`（`"w_"` / `""`）。
     - 统一封装：`sessionMachine` 持有、`pendingAck` 重试队列、`terminalOutbox` 持久化及防重、`pendingSessionEnds` 管理、统一 `nextRetryDelayNanoseconds()` / `performRetryWork()`、`mergeDetailedActions`、增量 `acknowledgedActionIDs` 跟踪、`handleIncoming(_:)` 路由分派、`sendEnvelope(_:)` / `sendAck(...)`。
     - 两端的 `PhoneWatchLinkService` 与 `WatchLinkService` 从各 2,500+ 行退化为**极薄的 `@MainActor @Observable` SwiftUI 状态绑定层 + 端特有辅助**（Phone 端特有：发起 `setupRequest`、本地清理 hook；Watch 端特有：待确认浮层 `pendingConfirmRequest`、侧通道记录队列）。

3. **双端 UI 与菜单同步瘦身**
   - `jifen/Core/Link/WatchLinkMenuSupport.swift`：
     - 删除 `takeover`、`forceTakeover`、`watchBackgroundedHint` 菜单项及参数 `isFollower` / `watchBackgrounded`。
     - 只要 `entryEnabled && sessionId != nil`，即展示：**「同步积分」(`resync`)** + **「结束联动」(`endLink`)**。
   - 清理手机端 8 个计分板 View（`RallyScoreboardView`、`TennisScoreboardView`、`ArcheryScoreboardView`、`FootballScoreboardView`、`EightBallScoreboardView`、`NineBallChaseScoreboardView`、`SnookerScoreboardView`、`ShotTrainingScoreboardView`）及 `jifenApp.swift`、`UnfinishedGameBarView.swift` 中所有的 `isFollower`、`takeover`、`forceTakeover`、`reclaimAlert`、`pendingTakeoverApplication`、`watchBackgrounded`、`forceTakeoverConfirmationSessionId` 死分支。
   - 清理手表端 8 个计分板 View + `WatchScoreboardMenuOverlay` + `WatchRestOverlay` + `WatchRootView` 中的 `scoringLocked`、`isFollower`、`onReclaim`、`pendingReclaimAcceptance`、`isReadOnly`（连带顺手关闭此前审查记录中的 P2-3「只读休息遮罩无退出按钮」与 `WatchBasketballTrainingView` 相关残留）。

#### 2. 涉及文件清单
- **新增**：`Packages/JifenCore/Sources/LinkCore/LinkSessionEngine.swift`
- **修改（LinkCore）**：`LinkCore.swift`
- **修改（Phone）**：`PhoneWatchLinkService.swift`、`PhoneWatchLinkSession.swift`、`PhoneWatchLinkMessageHandling.swift`、`PhoneWatchLinkReliability.swift`、`PhoneWatchLinkSideChannels.swift`、`WatchLinkMenuSupport.swift`、`jifenApp.swift`、`UnfinishedGameBarView.swift`、以及手机端 8 个计分板 View
- **修改（Watch）**：`WatchLinkService.swift`、`WatchLinkSession.swift`、`WatchLinkMessageHandling.swift`、`WatchLinkReliability.swift`、`WatchRootView.swift`、`WatchScoreboardComponents.swift`、以及手表端 8 个计分板 View
- **更新/重写测试**：`WatchLinkServiceTests.swift`、`PhoneWatchLinkServiceTests.swift`、`LinkPendingAckQueueTests.swift`、`ScoreboardDisplayTests.swift`（删除针对 `takeover`/`forceTakeover`/`reclaim`/`follower` 的失效用例，补齐纯 `.shared` 下双端并发编辑、双向 `resyncRequest`、断连恢复、再来一场与双端同时完赛幂等用例）

#### 3. 避坑要点
- **切勿在删除 `isFollower` 时误删 `peerFinishedSharedMatch` 护栏**：在 `.shared` 模式下，如果手机或手表其中一端已经先点了「结束比赛」，`peerFinishedSharedMatch` 仍负责防止另一端在收完赛弹层期间再次调用 `publishMatchFinished` / `notifyMatchFinished` 产生第二条记录！
- **Watch 端 `WatchScoreboardComponents` 休息层**：移除了 `isReadOnly` 分支后，休息遮罩在双端 `.shared` 下本地始终允许点「继续/撤销」（因为双端都可操作）。
- **`UnfinishedGameBarView.swift`**：删除 `watchBackgrounded` 与 `phoneFollower` 文案分支后，续赛栏文案统一展示「双端联动 · 已连接/已断开」。

#### 4. M3 验收清单与标准
- **静态检查**：全局检索 `takeoverByPhone`、`forceTakeover`、`reclaimRequest`、`watchBackgrounded`、`resumeDiscarded`、`phoneTookOver`、`isFollower`、`scoringLocked` 全部 **0 命中**。
- **新增/更新测试**：
  - `LinkCoreTests`：`LinkSessionEngine` 状态流转（setup → shared scoring → bidirectional resync → nextMatch → matchFinished → sessionLeft）、并发 revision 奇偶冲突通知触发、已完赛 session 对同协议内迟到的上一场完赛包幂等应答。
  - `WatchLinkServiceTests` & `PhoneWatchLinkServiceTests`：全部保留/重写用例全绿。
- **验收标准**：`swift test` + Watch & iPhone 构建 + `jifenWatch Watch AppTests` + `PhoneWatchLinkServiceTests` + `WatchDialogConsistencyUITests` 全绿。
- **Commit 建议**：`refactor(link): M3 pure shared collaboration & unified LinkSessionEngine`

---

### Milestone 4 (M4)：补齐足球/投篮 Reducer 与通用 `WatchReducerSessionStore`
- **对应原方案**：模块 D1 + D2 前置基础
- **阶段目标**：让手表支持的全部 19 项联动运动在 `ScoreCore` 中 100% 拥有纯确定性 `DomainReducer`；抽出同步值类型 `ScoreSessionMachine`，并在手表端用单一通用 `WatchReducerSessionStore` 替代 3 种风格并存的状态管理（顺手彻底根治 `WatchBasketballTrainingView` 完赛失败锁死 P2 问题）。

#### 1. 精确 Swift 契约与类型设计

1. **新增纯确定性足球 Reducer `[新增] Packages/JifenCore/Sources/ScoreCore/s1/FootballMatch.swift`**
   - 直接复用现有 `ScoreCore.FootballTimerStateV2`（见 `OfflineScoreboardTypes.swift:302`），补全纯值类型状态、意图与事件：
     ```swift
     public struct FootballMatchState: Codable, Equatable, Sendable {
         public var leftName: String
         public var rightName: String
         public var leftScore: Int
         public var rightScore: Int
         public var timer: FootballTimerStateV2
         public var stoppageHistory: [Int]
         public var isFiveAside: Bool
         public var kickedOff: Bool
         public var sidesSwapped: Bool
         public var finished: Bool
         // 构造器与校验
     }

     public enum FootballMatchIntent: Codable, Equatable, Sendable {
         case goal(side: MatchSide)
         case subtractGoal(side: MatchSide)
         case kickOff
         case toggleClock
         case startClock
         case pauseClock
         case addStoppage(seconds: Int)
         case undoLastStoppage
         case advanceStage
         case setNames(left: String, right: String)
         case exchangeSides
         case finish
         case reset(halfLengthSeconds: Int? = nil)
     }

     public enum FootballMatchEvent: Codable, Equatable, Sendable {
         case goalScored(side: MatchSide, leftScore: Int, rightScore: Int, period: Int, elapsedSeconds: Int)
         case goalSubtracted(side: MatchSide, leftScore: Int, rightScore: Int, period: Int, elapsedSeconds: Int)
         case kickedOff
         case clockToggled(isRunning: Bool, period: Int)
         case stoppageAdded(seconds: Int, period: Int)
         case stoppageUndone(seconds: Int, period: Int)
         case stageAdvanced(newStage: Int)
         case namesChanged
         case sidesExchanged
         case matchFinished(winner: MatchSide?)
         case matchReset
     }

     public struct FootballMatchReducer: DomainReducer { ... }
     ```
   - **纯函数时钟结算规则（核心难点与红线）**：
     - 严禁在 `reduce` 内部调用 `Date()`！必须使用传入的 `at epochMilliseconds: Int64` 与 `state.timer.savedWallClockMilliseconds` 计算流逝秒数：`let deltaSec = state.timer.isRunning && state.timer.savedWallClockMilliseconds > 0 ? max(0, Int((epochMilliseconds - state.timer.savedWallClockMilliseconds) / 1_000)) : 0`，并钳制在当前半场 `targetSeconds` 上限内，同时更新 `savedWallClockMilliseconds = epochMilliseconds`（若流逝超过 `targetSeconds`，自动 `isRunning = false`）。
     - **重要细节**：为了保证未操作时 UI 每秒跳表不污染 undo 栈、也不产生网络流量，View 层仍用 1 秒本地只读定时器 + `FootballMatchReducer.displayElapsedSeconds(state:at:)`（纯静态计算方法，不改状态、不入 undo 栈）渲染实时秒数；只有发生真实动作（进球、启停表、加补时、切半场、完赛）时才触发 `Intent` 并精确结算锚点！

2. **新增纯确定性投篮训练 Reducer `[新增] Packages/JifenCore/Sources/ScoreCore/s2/ShotTrainingReducer.swift`**
   - 与 M2 下沉到 `ScoreCore` 的 `ShotTrainingState` 配合：
     ```swift
     public enum ShotTrainingIntent: Codable, Equatable, Sendable {
         case recordShot(points: Int, made: Bool)
         case undoLastShot
         case finish
         case reset
     }

     public enum ShotTrainingEvent: Codable, Equatable, Sendable {
         case shotRecorded(points: Int, made: Bool, counts: ShotTrainingCounts)
         case shotUndone(counts: ShotTrainingCounts)
         case finished(counts: ShotTrainingCounts)
         case reset
     }

     public struct ShotTrainingReducer: DomainReducer { ... }
     ```
   - 保持 `ShotTrainingState.maxDetailedShots = 2_048` 上限与 `earlierCounts` 溢出折叠逻辑；`recordShot` 使用传入的 `at epochMilliseconds: Int64` 构造时间戳，不在 reducer 内调 `Date()`。

3. **更新注册表与工厂（`ScoreboardKernelRegistry.swift` & `ScoreboardSessionFactory.swift`）**
   - `ScoreboardKernelRegistry.descriptor(for: .football/.football5v5)` 可升级为专用 `.football` kind（或保持 `ScoreboardKernelKind` 兼容 `LineScoreReducer` 给 `.billiards`/`.simpleScore`，新增 `case football` 给 `.football`/`.football5v5`）。注意同步检查 `ScoreboardSessionFactoryCoverageTests.swift`！
   - `ScoreboardSessionFactory` 新增 `football(...)` 与 `shotTraining(...)` 工厂方法，让 `ScoreboardSessionFactoryCoverageTests` 中 `GameType.allCases` 实现 **100% 全部由 Reducer 驱动（无需再排除 `.basketballTraining`）**。
   - **LinkCore 统一快照模型**：让 `LinkedScoreboardSnapshot.football(FootballMatchState)`、`.basketballTraining(ShotTrainingState)`、`.archery(ArcheryMatchState)` 直接携带 `ScoreCore` Reducer State。手机独立草稿继续保留历史格式读取。

4. **抽出同步值类型 `ScoreSessionMachine` (`Packages/JifenCore/Sources/SessionCore/SessionCore.swift`)**
   - 手机端继续使用 `public actor ScoreSessionCore<Reducer: DomainReducer>` 零破坏。
   - 将 `ScoreSessionCore` 内部全部核心逻辑（`replaySeed`、`currentSession`、`undoStack`、`timeline`、`dispatch`、`dispatchNonUndoable`、`undo`、`rebase`、`resumeBundle`）下沉到值类型 `public struct ScoreSessionMachine<Reducer: DomainReducer>: Sendable`，`ScoreSessionCore` actor 直接持有并转发给该 `var machine`。
   - 好处：手表端直接在 `@MainActor` 上同步操作 `ScoreSessionMachine`，**彻底消除目前 `WatchRallySessionStore` / `WatchTennisSessionStore` 每次点击开一个 `Task {}` 异步调度带来的延迟与连点状态竞态**！

5. **手表通用状态宿主 `[新增] jifenWatch Watch App/Scoreboard/WatchReducerSessionStore.swift`**
   - 统一封装全部 8 块手表计分板：
     ```swift
     @MainActor
     @Observable
     final class WatchReducerSessionStore<R: DomainReducer> {
         private var machine: ScoreSessionMachine<R>
         var state: R.State { machine.currentSession.state }
         private(set) var actionLog: WatchScoreActionLog
         // 统一提供：
         // - dispatch(_ intent: R.Intent, at nowMs: Int64 = ...)
         // - dispatchNonUndoable(...)
         // - undo() -> Bool
         // - rebase(to state: R.State, status: SessionStatus, detailedActions: [DetailedScoreAction], ...)
         // - resumeBundle() -> ScoreSessionResumeBundle<R.State, R.Event, R.Intent>
         // - persistResumeSession(...) / finish(...)
     }
     ```
   - 将 `WatchResumePayload` 统一为各运动直接持久化标准 `ScoreSessionResumeBundle<State, Event, Intent>`（统一 1 种模式），不再各存各的散装 `undoStates` 数组。
   - 改造全部 8 块手表计分板接入 `WatchReducerSessionStore`（删除 `WatchArcherySessionStore.swift`、`WatchFootballState.swift`、以及 `WatchRallyScoreView` / `WatchTennisScoreView` 中的私有 Store）；改造 `WatchBasketballTrainingView` 用 `savedRecordID == nil` 唯一门闩，彻底消除取消保存失败 alert 后棋盘锁死的 P2 Bug。

#### 2. 涉及文件清单
- **新增（JifenCore）**：`Packages/JifenCore/Sources/ScoreCore/s1/FootballMatch.swift`、`Packages/JifenCore/Sources/ScoreCore/s2/ShotTrainingReducer.swift`
- **修改（JifenCore）**：`ScoreboardKernelRegistry.swift`、`ScoreboardSessionFactory.swift`、`SessionCore.swift`、`LinkCore.swift`、`ScoreActionProjector.swift`、`MatchRecordProjector.swift`
- **新增（Watch）**：`jifenWatch Watch App/Scoreboard/WatchReducerSessionStore.swift`
- **删除（Watch）**：`jifenWatch Watch App/Scoreboard/WatchArcherySessionStore.swift`、`jifenWatch Watch App/Models/WatchFootballState.swift`
- **修改（Watch）**：`WatchResumeSession.swift`、`WatchRootView.swift`、`WatchScoreboardRoute.swift`、`WatchRallyScoreView.swift`、`WatchTennisScoreView.swift`、`WatchArcheryScoreView.swift`、`WatchEightBallScoreView.swift`、`WatchNineBallScoreView.swift`、`WatchSnookerScoreView.swift`、`WatchFootballScoreView.swift`、`WatchBasketballTrainingView.swift`
- **修改（Phone）**：`FootballViewModel.swift` / `FootballScoreboardView.swift` / `ShotTrainingScoreboardView.swift` / `SportsSetupWatchSessionLauncher.swift` / `UnfinishedGameBarView.swift`（适配 `LinkedScoreboardSnapshot` 原生使用 `FootballMatchState` / `ShotTrainingState` / `ArcheryMatchState`）
- **更新/新增测试**：`ScoreboardSessionFactoryCoverageTests.swift`、`CrossPlatformParityTests.swift`、`JifenCoreTests` 新增 `FootballMatchReducerTests.swift` & `ShotTrainingReducerTests.swift`；更新手表和手机 Link/Flow 单测。

#### 3. 避坑要点
- **足球/投篮手机端本地历史档案兼容**：手机本地旧存档的 `FootballResumeStateV2`（内嵌 `LineScoreResumeState` + `FootballTimerStateV2`）与 `ShotTrainingResumeState` 必须仍能被手机本地恢复逻辑读取；**仅联动快照与 Watch 端切到 `FootballMatchState` / `ShotTrainingState`**，切勿破坏手机老草稿恢复！
- **Watch 足球双击减分定时器**：`WatchFootballScoreView` 的 260ms 单/双击消抖仍在 UI 层完成，判定完成后再向 `WatchReducerSessionStore` 发送 `.goal(side)` 或 `.subtractGoal(side)`。
- **Watch 完赛 `undoFinish` 边界**：在完赛后 5 秒撤销窗内点击撤销，通过 `WatchReducerSessionStore` 恢复状态，且若已经写了本地记录要同步回滚或把写库延后到倒计时结束/退出（建议统一遵循当前“倒计时结束或点退出才最终落库”，避免写后删的竞态）。

#### 4. M4 验收清单与标准
- **新增/更新测试**：
  - `FootballMatchReducerTests`：11v11 与 5v5 开球、启停表、时钟注入结算、补时加减与撤回、半场/加时推进、完赛冻结时钟、重置、换边；与旧 `FootballMatchClockSession` 行为等价性验证。
  - `ShotTrainingReducerTests`：1/2/3 分与自由模式、命中/未中计数、撤销、>2048 溢出 `earlierCounts` 折叠与撤销边界、完赛、重置。
  - `ScoreboardSessionFactoryCoverageTests`：`GameType.allCases` 100% 全部走工厂创建，无需豁免 `.basketballTraining`。
  - `WatchBasketballTrainingUITests` / `WatchScoreboardFlowTests`：验证保存失败点击取消后棋盘不锁死、可继续记分或重试。
- **验收标准**：`swift test` + Watch & iPhone 构建 + `jifenWatch Watch AppTests` + `jifenTests` 相关用例全绿。
- **Commit 建议**：`feat(scorecore,watch): M4 Football/ShotTraining reducers & unified WatchReducerSessionStore`

---

### Milestone 5 (M5)：D2-彻底 — Phone 定序 Intent/Op 并发同步与乐观重放
- **对应原方案**：模块 D2（彻底版）
- **阶段目标**：将 `.shared` 双端协作从“奇偶版号整包快照覆盖（LWW 会吞掉并发加分）”升级为 **Phone Host 定序的 Intent/Op 增量同步 + Watch 本地零延迟乐观重放 + StateHash 校验与冲突自动回滚**。

#### 1. 精确 Swift 契约与类型设计

1. **统一联动 Intent 与 Op 协议（`[新增] Packages/JifenCore/Sources/LinkCore/LinkedIntentSync.swift`）**
   - 覆盖全部 8 类 Reducer 的可序列化 Intent 外加会话控制动作：
     ```swift
     public enum LinkedScoreboardIntent: Codable, Equatable, Sendable {
         case rally(RallyMatchIntent)
         case tennis(TennisMatchIntent)
         case archery(ArcheryMatchIntent)
         case eightBall(EightBallIntent)
         case nineBall(NineBallChaseIntent)
         case snooker(SnookerIntent)
         case football(FootballMatchIntent)
         case shotTraining(ShotTrainingIntent)
         case undo(targetOpId: UUID?) // 指定撤销某次操作或最近一次有效操作
         case finish // 联动会话中的手动结束请求，由手机定序确认
         case nextMatch(matchId: UUID, matchGeneration: UInt64)
     }

     public struct LinkOperation: Codable, Equatable, Identifiable, Sendable {
         public let opId: UUID
         public let origin: LinkPeer
         public let clientSeq: UInt64
         public let baseRevision: UInt64
         public let createdAtEpochMilliseconds: Int64
         public let intent: LinkedScoreboardIntent
         public var id: UUID { opId }
     }

     public enum LinkOperationOutcome: String, Codable, Equatable, Sendable {
         case accepted
         case rejected
         case duplicateIgnored = "duplicate_ignored"
     }

     public struct LinkOperationCommitPayload: Codable, Equatable, Sendable {
         public let committedRevision: UInt64
         public let op: LinkOperation
         public let outcome: LinkOperationOutcome
         public let rejectionReason: String?
         public let stateHash: UInt64
         /// 每 N=10 个 commit、或 undo/rejected/nextMatch 时携带，平时为 nil 保持帧 < 500B
         public let authoritativeSnapshot: LinkedScoreboardSnapshot?
         public let deltaActions: [DetailedScoreAction]
     }
     ```
   - `LinkMessageKind` 新增 `.intentSubmit`（Watch → Phone 携带 `LinkOperation`）与 `.intentCommit`（Phone → Watch 携带 `LinkOperationCommitPayload`）。
   - 在 `LinkProtocol.capabilities` 中正式加入 `.sharedIntentSync`。
   - **确定性 `StateHash`**：在 `LinkedScoreboardSnapshot` 上实现跨进程稳定的 FNV-1a 64-bit 哈希（**严禁使用 `Swift.Hasher`**，因为 Swift `Hasher` 每次进程重启随机化种子！必须基于 `JSONEncoder` 配合 `[.sortedKeys]` 对 Snapshot 规范编码后计算 FNV-1a 64 位整数），用于两端比对是否完全一致。

2. **Phone Host Sequencer (`LinkCore/PhoneHostSequencer.swift` + `PhoneWatchLinkSession.swift`)**
   - **唯一真相源定序**：无论是 Phone 本地点击还是收到 Watch 发来的 `.intentSubmit`，Phone 端全部通过同一入口 `submitOperation(_ op: LinkOperation)` 处理：
     1. 检查 `opId` 是否已在已处理滑窗集合 `processedOpIds`（保留最近 1,000 条）中——若已存在，直接返回幂等结果（`duplicateIgnored`），或补发上次对应 `commit`，绝不重复计分；
     2. 对于 **足球时钟时间戳定序规则**：若 Watch 离线时按了进球但手机钟已推进到更晚锚点，Phone 执行前以 `max(op.createdAtEpochMilliseconds, lastCommittedEpochMs)` 作为确定性 `reduce(..., at:)` 时间参数，**并把定序后实际采用的 `effectiveEpochMilliseconds` 写入 `commit.op` 回传**，确保 Watch 重放时与 Phone 计算出的 `timer.savedWallClockMilliseconds` 与 `stateHash` 比特级一致！
     3. 用对应运动 `DomainReducer` 执行，推进 `committedRevision += 1`、投影追加 `DetailedScoreAction`、更新 `confirmedSnapshot` 与 `stateHash`；
     4. 将 `commit` 通过 `sendRealtime` 发给 Watch（并持久化在待重发队列，直到 Watch ACK 或推进确认游标），同时更新 `applicationContext` 中的轻量化最新 snapshot；
     5. 若 `committedRevision % 10 == 0` 或 `outcome == .rejected` 或 `.undo` / `.nextMatch`，附带 `authoritativeSnapshot` checkpoint。
   - 收到 Watch 批量离线恢复积压的多个 `pendingLocalOps` 时，支持按 `clientSeq` 顺序批量定序；若 Watch 重连时发现跳号（`commit.committedRevision > confirmedRevision + 1`）或 `stateHash != localConfirmedHash`，自动发 `.resyncRequest`，Phone 立即回发当前最新 `confirmedSnapshot` + `committedRevision` + 未确认增量动作。
   - 双端的联动结束请求均进入同一手机定序入口。Watch 补发时，同场离线操作按 `clientSeq` 先于随后发起的结束请求处理。每场只确认一次完赛，以 `LinkedMatchHandle.matchId` 作为双端记录的共同幂等键。手机先确认完赛时，后到操作获取已确认的完赛结果和各自的处理结果，既有记录的比分和动作保持稳定。

3. **Watch Optimistic Replay Engine (`WatchLinkService` & `WatchReducerSessionStore`)**
   - **状态模型**：Watch 端持有双态：
     - `confirmedState` / `confirmedRevision` / `confirmedHash`（经 Phone `intentCommit` 确认的最新状态）
     - `pendingLocalOps: [LinkOperation]`（本地已触发但尚未收到 Phone `.intentCommit` 的操作，持久化到 `WatchStorageContainer` 的 `link/pending-ops.json`）
     - `displayedState` = `replay(confirmedState, over: pendingLocalOps)`（同步计算，UI 零等待）
   - **提交路径**：用户在手表点加分 → 同步生成 `LinkOperation(origin: .watch, clientSeq += 1, baseRevision: confirmedRevision, createdAtEpochMilliseconds: nowMs, intent: ...)` → 立即追加 `pendingLocalOps`、同步重放刷新表盘与 `actionLog`、同时经 `sendMessageData(.intentSubmit)` 发送（若断连则保留在 `pendingLocalOps`，重连恢复可达时按 `clientSeq` 顺序补发）。
   - **离线结束**：将结束请求排在同场已记录的计分操作之后，一起持久化。手表当场显示「待同步确认」，重启后恢复该状态。收到手机确认的完赛结果后，再以同一比赛 ID 保存联动记录。手表独立开局仍走本地直接保存流程。
   - **收到 `.intentCommit` 处理**：
     1. 校验 `committedRevision == confirmedRevision + 1`（若跳号 → 触发 `.resyncRequest` 并暂缓本地重放覆盖）；
     2. 若 `commit.op.origin == .watch`，从 `pendingLocalOps` 弹出 `commit.op.opId`；
     3. 在 `confirmedState` 上用 `commit.op.createdAtEpochMilliseconds` 重放 `commit.op.intent`（若为 `.accepted`）或直接使用 `commit.authoritativeSnapshot`（特别是 `.rejected` / `.undo` / checkpoint 时）；
     4. 若无 `authoritativeSnapshot`，比对重放后的 FNV-1a `stateHash` 与 `commit.stateHash`——若一致则无感推进；若意外不一致则自动发 `.resyncRequest` 用 Phone 权威快照自我修复；
     5. 若 `commit.outcome == .rejected`，则剔除被拒操作并重放其余仍合法的操作。若手机已先确认完赛，Watch 对齐手机的完赛结果，按唯一操作 ID 统计因该场已结束而未纳入的离线操作，并显示实际笔数，例如「有 2 笔离线操作未纳入本场成绩」。重复回执和重复结束请求不增加计数。

4. **双端计分板接入**
   - 手表端：只需在 `WatchReducerSessionStore` 内部统一对接 `WatchLinkService.submitLinkedIntent(...)` —— 8 块手表计分板 UI 代码几乎零额外改动！
   - 手机端：8 块计分板（`RallySessionStore`、`TennisSessionStore`、`ArcherySessionStore`、`BilliardsSessionStore`、`FootballViewModel`、`ShotTrainingScoreboardView`）在处于联动会话时，将本地用户操作通过 `PhoneWatchLinkService.submitLocalIntent(...)` 走 Phone Host Sequencer 统一定序，并在收到 Watch op 导致的 state 更新时平滑刷新自身 UI。

#### 2. 涉及文件清单
- **新增（LinkCore）**：`Packages/JifenCore/Sources/LinkCore/LinkedIntentSync.swift`、`Packages/JifenCore/Sources/LinkCore/PhoneHostSequencer.swift`、`Packages/JifenCore/Sources/LinkCore/WatchOptimisticReplayEngine.swift`
- **修改（LinkCore）**：`LinkCore.swift`、`LinkSessionEngine.swift`
- **修改（Watch）**：`WatchReducerSessionStore.swift`、`WatchLinkService.swift`、`WatchLinkSession.swift`、`WatchLinkMessageHandling.swift`、`WatchLinkReliability.swift`（计分板显示「待同步确认」及未纳入的离线操作笔数）
- **修改（Phone）**：`PhoneWatchLinkService.swift`、`PhoneWatchLinkSession.swift`、`PhoneWatchLinkMessageHandling.swift`、手机端 6 个 Store / ViewModel（`RallySessionStore`、`TennisSessionStore`、`ArcherySessionStore`、`BilliardsSessionStore`、`FootballViewModel`、`ShotTrainingScoreboardView`）及对应 ScoreboardView 接入 `submitLocalIntent`
- **新增/更新测试**：`Packages/JifenCore/Tests/JifenCoreTests/SharedIntentSyncTests.swift`（[新增]）、`WatchLinkServiceTests.swift`、`PhoneWatchLinkServiceTests.swift`（记得把 `jifenTests/` 新测试文件加入 `project.pbxproj`）

#### 3. 避坑要点
- **绝对不要用 `Swift.Hasher` 计算跨端 `stateHash`**：跨进程种子不同必假报警！必须用自定义确定的 FNV-1a 64-bit 算在 `.sortedKeys` JSON `Data` 上。
- **双端本地撤销 `.undo` 在并发下的语义**：Phone Sequencer 收到 Watch 发来的 `.undo(targetOpId)` 时，应基于 Phone 自己的 `ScoreSessionMachine` 回退；对于“手表的离线本地误触撤销” vs “只撤销自己的最后一分”，M5 约定：若 `targetOpId` 仍在 Watch 尚未发出的本地 `pendingLocalOps` 队列里，Watch 直接在本地队列弹出即可，无需发给 Phone；若 `targetOpId` 已发出或无指定，则作为 `.undo` op 送 Phone 定序回退，且 `commit` 强制携带 `authoritativeSnapshot` 让 Watch 直接对齐，避免双端撤销栈步调不一致。
- **Phone 端 `FootballViewModel` / `RallySessionStore` 等原有持久化与 CloudSync**：Phone Host Sequencer 产出的最新状态仍要同步写入手机的 `ScoreSessionCore` / `ResumeSessionRepository`，确保手机端退出重进与投屏（`LocalScoreboardSyncCoordinator` / `RemoteSyncController`）不受影响。

#### 4. M5 验收清单与标准
- **必须覆盖的 7 类并发边界单测（在 `SharedIntentSyncTests` 与双端 LinkTests 中强制断言）**：
  1. **并发各加一分合并**：Phone 与 Watch 在同一 `baseRevision = 0` 下各自加 1 分（左+1、右+1），定序后最终比分 **必须为 `1:1`**（彻底解决原 LWW 覆盖丢分问题），且双端 `stateHash` 一致。
  2. **重复 `opId` 幂等**：同一 `.intentSubmit` 重发 3 次，Phone 只推进 1 次 revision，比分只加 1 分。
  3. **乱序 / 跳号自愈**：模拟丢掉 `committedRevision = 2` 直接收到 `3`，Watch 拒绝推进并自动发出 `.resyncRequest`，随后收到权威快照对齐。
  4. **完赛与离线恢复**
     - Watch 断连后连续计分并点结束。重启后仍显示「待同步确认」。手机尚未完赛时，重连后先处理计分，再确认结束。两端各保存一条比赛 ID 相同、比分一致的记录。
     - Phone 已先确认完赛。Watch 重连补发两笔离线计分和结束请求后，对齐 Phone 的完赛结果，显示「有 2 笔离线操作未纳入本场成绩」。重复投递后仍为 2 笔，两端各保留一条该场记录。
     - 两端同时发起结束请求，最终共享一个完赛结果和比赛 ID。另验证 Watch 独立开局在断连时可直接保存。
  5. **撤销竞态**：Watch 本地快速连打 2 分后立刻本地撤销第 2 分（若尚未送出直接本地消除；若已送出由 Phone 返回 `.undo` + 权威快照），最终双端一致。
  6. **Watch 离线连打 10 分后重连**：Watch 在 `isReachable == false` 时连续得分 10 次并保存 `pendingLocalOps`（甚至模拟 Watch 进程重启恢复），重连后按 `clientSeq` 顺序补发，与期间 Phone 得分无损合并。
  7. **足球时钟单调定序**：Phone 时钟在前，Watch 携带稍早时钟时间戳送 `.goal`，Phone 按单调时钟定序后回传确定时间戳，双端时钟锚点与进球分钟标注完全一致且 `stateHash` 匹配。
- **验收标准**：`swift test` + Watch & iPhone 构建 + `jifenWatch Watch AppTests` + `jifenTests` + `WatchDialogConsistencyUITests` + 多人计分发布门禁全部通过。
- **Commit 建议**：`feat(link): M5 phone-sequenced intent sync & watch optimistic replay`

---

## §5 统一验收命令与测试门禁

> **重要提醒**：
> 1. 根据仓库约定，运行测试生成的 `.xcresult` 与临时截图不得留在源码目录，需通过 `python3 scripts/test_artifacts.py new-run <label> --active` 创建受管目录，测试完运行 `python3 scripts/test_artifacts.py finish <batch-path>`（失败加 `--failed`）。
> 2. **Watch 目标严禁将 `-sdk watchsimulator` 与 `-destination` 同传**，请严格使用下方命令模板（DerivedData 固定复用，避免每次全量重编）。

### 5.1 核心包测试（所有阶段必跑）
```bash
swift test --package-path Packages/JifenCore
```

### 5.2 Apple Watch 编译与单元测试（所有阶段必跑）
查询本机可用 Watch 模拟器（当前已确认存在 `Apple Watch Ultra 4 (49mm)` / `Apple Watch SE 3 (44mm)`）：
```bash
xcrun simctl list devices available | grep "Apple Watch"
```
构建与运行全部手表单元测试（替换 `<WATCH_UDID>`）：
```bash
BATCH=$(python3 scripts/test_artifacts.py new-run watch-v2-verify --active | tail -n 1)

xcodebuild test \
  -project jifen.xcodeproj \
  -scheme "jifenWatch Watch App" \
  -destination "platform=watchOS Simulator,id=<WATCH_UDID>" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/jifen-watch-v2" \
  -resultBundlePath "$BATCH/WatchAppTests.xcresult" \
  -only-testing:'jifenWatch Watch AppTests'
```

### 5.3 Apple Watch UI 冒烟测试（M2/M3/M4/M5 必跑）
> **注意**：只指定具体的 UI 测试套件（勿直接全量跑 `jifenWatch Watch AppUITests`，其中含营销捕获套件）。遇到无配对手机的独立模拟器弹系统 `WCSession` 错窗时留意区分测试环境与产品缺陷。
```bash
xcodebuild test \
  -project jifen.xcodeproj \
  -scheme "jifenWatchUITests" \
  -destination "platform=watchOS Simulator,id=<WATCH_UDID>" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/jifen-watch-v2" \
  -resultBundlePath "$BATCH/WatchDialogConsistency.xcresult" \
  -only-testing:'jifenWatch Watch AppUITests/WatchDialogConsistencyUITests' \
  -only-testing:'jifenWatch Watch AppUITests/WatchBasketballTrainingUITests'
```

### 5.4 iPhone 编译与单元测试（所有阶段必跑）
调试时可选跑相关套件，阶段验收使用整个 `jifenTests` target，并记录已有的按需探针跳过项。
```bash
xcodebuild test \
  -project jifen.xcodeproj \
  -scheme "jifen" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/jifen-phone-check" \
  -resultBundlePath "$BATCH/PhoneWatchTests.xcresult" \
  -only-testing:'jifenTests'
```

### 5.5 发布门禁与产物收尾
每个送审或发布候选均须从候选 checkout 运行多人计分发布门禁，在发布清单记录版本、源码修订和通过结果。失败、跳过或缺少结果均阻止送审与发布。后台联动传输在候选上须有配对真机证据。
```bash
python3 scripts/verify_multi_score_release.py --simulator <IPHONE_UDID>
```

每阶段完成测试后关闭自己的产物批次。有待解决的测试失败时加 `--failed`。

```bash
python3 scripts/test_artifacts.py finish "$BATCH"
```

---

## §6 DeepSeek Harness (`dsh`) 执行 Prompt 模板 & Codex 审查清单

### 6.1 喂给 DeepSeek Harness (`dsh`) 的分阶段 Prompt 模板

每次只执行 **1 个里程碑**。在独立 worktree 从已提交的基线开展，带入本规范，保留原工作区的 Watch 设置和数字键盘改动。首次交接把下方 `Milestone X (MX)` 替换为 `Milestone 1 (M1)`。执行者交付 diff、测试结果和未验证事项，Codex 核验后再进入下一阶段。

```text
请先完整阅读仓库中的 `AGENTS.md` 和 `docs/watch-architecture-v2-spec.md` 的 §1、§2、§3 以及 §4 中的【Milestone X (MX)】章节（不要提前实现后续 Milestone 的内容）。

执行要求：
1. 严格遵守 §2 的全部红线。保留已发布的手机本地和云同步数据兼容。Watch 与双端联动按首发格式起算，无需开发版迁移、旧联动协议解码或双端版本混用支持。禁止修改 entitlements、增加 App Group/HealthKit，或在 DomainReducer 内调用 Date()/UUID()。
2. 仅完成【Milestone X】列的契约、文件改动与测试更新；若发现现有文件中涉及 `jifenTests` 新增 Swift 文件，记得同步登记到 `jifen.xcodeproj/project.pbxproj`。
3. 完成后严格按 §5 运行 `swift test --package-path Packages/JifenCore`、Watch 端测试和 iPhone 相关测试（Watch 构建勿传 `-sdk watchsimulator`，只传 `-destination`；使用 `scripts/test_artifacts.py` 管理 xcresult）。
4. 在最终回复中写明基线提交、变更文件、各命令的实测通过/失败/跳过数和规范偏差。配对真机测试尚无证据时明确标注。完成当前阶段后交给 Codex 独立复核。
```

### 6.2 给 Codex 的 Spec 复核 / 代码 Review 检查清单

- **Spec 复核重点（动手前）**：
  1. 核对 M1 的 Watch 目录划分和清理行为，以及已发布手机数据的兼容边界。检查双端联动是否只处理首发格式，并保留同协议下重启、补发、去重和迟到完赛。
  2. 核对 M2 中 `ShotTrainingMode` 与 `ScoreboardRecord` v5 的向后兼容（手机本地存量草稿/记录解码零回归）。
  3. 核对 M3 移除所有单主控移交（`takeover`/`reclaim`/`isFollower`）后，`peerFinishedSharedMatch` 防重复完赛保护及 `WatchScoreboardComponents` 休息遮罩退出路径是否完备。
  4. 核对 M4 `FootballMatchReducer` 的时钟锚点结算是否 100% 纯函数、且 1 秒 UI 刷新不触发不必要持久化/网络帧。
  5. 核对 M5 `stateHash` 算法确定性（`.sortedKeys` JSON + FNV-1a，禁止 `Swift.Hasher`）与足球单调时钟定序、`.undo` 对齐与 7 个并发边界用例设计是否有漏洞。
- **代码 Review 重点（每阶段执行后）**：
  1. `git diff` 核查 `.entitlements` 和 Watch `Info.plist` 无未授权能力新增。
  2. 核查 `WCSessionDelegate.session(_:didReceive file:)` 是否在回调返回前同步读取/拷贝了文件。
  3. 核查 `receive(_ data:)` 是否先检查 `[0x4A, 0x46, 0x01]` 压缩帧再解 `LinkEnvelopeHead`。
  4. 核查所有实底绿色 Save/Confirm 按钮仍显式设置 `.foregroundStyle(.white)`。
  5. 核查所有 §5 测试命令实际执行并 0 failures。
