# iOS 项目全量自检报告（对照鸿蒙端）

日期：2026-07-27（2026-07-28 完成修复状态复核）
范围：iPhone 主应用、iPad 平板布局、Apple Watch 应用、手机手表联动
对照基线：当前工作区 `jifen-ios` 实际代码 vs 鸿蒙 `jifen-hos` 2.7 分支实际代码（部分项参考 2.9）
已知前提：iOS 端有意避开账号、后台（同步计分等）等服务端能力

> 本文主体保留 2026-07-27 首次盘点时的“发现现场”，用于说明问题来源。除各节中的原始发现外，当前工作区状态以紧接下来的修复复核表为准。

## -1. 2026-07-28 修复复核

| 原始发现 | 当前工作区状态 |
| --- | --- |
| 计时项目为 9 项 | 产品决策已删除独立篮球 24 秒/12 秒工具，当前为 7 项；篮球计分板内置进攻计时不受影响。 |
| iPad `HomeTab.loadConfig` 固定传非大屏 | 已改为 `Theme.usesPadLayout`，并补齐 Phone/Tablet/2-in-1 默认配置。 |
| 5 处使用 `UIScreen.main.bounds` | 已改为容器 `Geometry`/`onGeometryChange`，分屏和 Stage Manager 使用实际窗口尺寸。 |
| Watch 篮球无记录类型映射 | 已补 `WatchGameType.basketball/threeBasketball`，仍明确只允许手机联动进入。 |
| Watch 篮球结束可能丢本地记录 | 已增加 Watch 本地兜底记录；联动完赛不走独立自动回传，避免手机重复落库。 |
| Watch 台球/射箭未统一归档 | 已接入 `SessionArchiveRepository`；轻量页面仍可保留本地 undo 栈。 |
| 手机 follower 无手动同步入口 | 已增加“同步积分”，仅允许 Phone follower 向 Watch controller 请求权威全量快照。 |
| Watch 被系统切后台没有通知 | 已增加 `watchBackgrounded` 通知和手机端接管提示；未增加常驻心跳，继续依赖 WatchConnectivity 可达状态。 |
| 足球/拳击/通用台球/简单计分/多人计分专项测试薄 | 已补边界测试，并修复足球/简单计分、拳击完整状态撤销问题。 |

本轮仍有意不处理：协议版本升级、常驻心跳、`PHONE_CONTROLLER_EXITED_TO_HOME` 控制权交回、Watch 通用 `TimerCore` 页面。这些都需要独立产品/协议设计，不能作为低风险补丁直接加入。

---

## 0. 执行摘要

| 维度 | 核对结论 | 关键发现 |
| --- | --- | --- |
| 主应用功能完整性 | ✅ 对齐 | 23 计分 + 7 计时 + 10 工具全部齐备，无占位页 |
| Tab 结构 | ✅ 确认正确 | 五个 Tab：首页 → 记录 → 计分 → 计时 → 我（设置）；工具从首页 push 进入 |
| iPad 平板布局 | ⚠️ 基础到位但有缺口 | 首页两栏对齐鸿蒙；3 处潜在 Bug（UIScreen.main.bounds 分屏问题、详情页无 maxWidth） |
| Apple Watch 应用 | ✅ 对齐 | 12 计分模式 + 投篮训练齐全；篮球代码残留但无入口；4 个本地化问题 |
| 手机手表联动 | ⚠️ 闭环已通但语义弱于鸿蒙 | 双向闭环 + 唯一落库已实现；缺心跳/断连检测/CONTROL_INTERRUPTED，协议版本 v1 vs 鸿蒙 v3 |
| 有意暂缓项 | ✅ 范围明确 | 账号/VIP/云同步/反馈/展示端大屏均未实现，与决策一致 |

**整体判定**：iOS 本地功能与鸿蒙端在「项目覆盖」层面完全对齐（23+9+10），手机手表联动双向闭环可用。主要风险集中在**联动协议语义比鸿蒙弱**（缺心跳、缺中断通知、协议版本落后）和**iPad 分屏适配的几处 UIScreen.main.bounds Bug**。账号/云同步等暂缓项范围明确，无越界实现。

---

## 1. 主应用功能核对

### 1.1 计分项目：23/23 全部对齐

证据：`jifen/Features/Scoreboard/Shared/ScoreboardLaunchView.swift` 第 14-64 行 switch 全覆盖；`jifen/Features/Shared/GameCatalog.swift` 第 100-127 行 `scoreboardItems` 数组共 23 项。

| 分区 | 项目数 | 实现方式 |
| --- | --- | --- |
| 运动（含单双打） | 12 | 乒/羽/网/匹单双打共享视图（`isSingles` 区分）；篮球 5v5 与 3x3 共享 `BasketballScoreboardView`；排球/沙排/气排共享 `VolleyballScoreboardView` |
| 台球 | 4 | 普通台球、黑八、九球、斯诺克均在 `Sports/Billiards` 下使用独立页面文件 |
| 棋牌 | 4 | 斗地主、掼蛋、升级均使用独立页面文件；UNO 复用 `MultiScoreboardView` |
| 其他 | 3 | 桌上足球（单双打共享）、简单计分、多人计分 |

**与鸿蒙 2.7 对比**：鸿蒙 2.7 实际只有 **22 个**对齐项目（缺 `foosball`，2.9 分支才加入 `FoosballScorePage.ets`）。iOS 在此项上反而比鸿蒙 2.7 多 1 个。鸿蒙多出 `BASKETBALL_TRAINING`（篮球训练，无独立视图）。

### 1.2 计时项目：当前 7 项

证据：`jifen/Features/Timer/TimerTab.swift` 的 destination switch 全覆盖；`GameCatalog.swift` 当前 `TimerDestination` 共 7 个 case。

围棋/象棋/国际象棋/国际跳棋共享 `DualPlayerTimerView`；另有魔方、秒表、倒计时。独立篮球 24 秒/12 秒工具已按产品决策删除。

**注意**：`StopwatchView.swift` 物理位于 `Features/Tools/` 目录，但被 `TimerTab` 调用，且未在 `ToolDefinitions.allTools` 中注册。组织上略不一致，功能正常。

### 1.3 工具：10/10 全部对齐

证据：`jifen/Features/Tools/ToolDefinitions.swift` 第 21-35 行 `competitionTools`（5）+ `otherTools`（5）= `allTools`（10）。

抛硬币、骰子、哨子、随机分组、红黄牌、积分表、全屏弹幕、翻页时钟、AA 计算器、十秒挑战。

### 1.4 Tab 结构

五个 Tab：首页 → 记录 → 计分 → 计时 → 我（设置）（`MainTabView.swift` 第 36-69 行），手机与 iPad 一致。

- `ToolsTab` 外壳主要供独立导航和 Preview 使用；同文件的 `ToolsListPageView` 正被首页实际调用，不能把整个文件视为死代码。
- 工具入口实际路径：首页 `ProToolsSectionView` → push `ToolsListPageView`，非顶层 Tab。
- 第 5 个 Tab 是「我」（设置页），与鸿蒙保持底部 Tab 设计一致。

### 1.5 本地数据闭环（完整）

| Manager | 存储 | 上限 |
| --- | --- | --- |
| `ScoreboardRecordManager` | 原子 JSON 文件（Schema-v4） | 1000 条 |
| `TimerRecordManager` | UserDefaults | 500 条 |
| `LocalBookingManager` | UserDefaults（key=`local_bookings_v1`） | - |
| `CommonNamesManager` | UserDefaults | 50 条 |
| `CommonPlacesManager` | UserDefaults | - |
| `QuickStartConfigManager` | UserDefaults | - |

**与鸿蒙对齐情况**：常用名称、常用地点、本地预约球局、快速开始配置、记录列表/详情/分享、主题/字体/振动、清理数据 —— 全部对齐。

**iOS 多出的本地开关**：声音 Toggle、双击减分 Toggle、StoreKit 评分、系统级 ShareLink 分享。鸿蒙端「双击减分」在模板内部实现但设置页未暴露独立开关。

### 1.6 无占位页/TODO（正面发现）

- grep `ComingSoon|占位|敬请期待|开发中` 在 Swift 功能代码中**无任何命中**。
- `feature_coming_soon` 本地化字符串是死字符串（代码无引用）。
- `ScoreboardLaunchView.swift` 第 62 行 `default:` 分支显示 `"(待实现)"`，但所有 23 个 gameType 都有显式 case，正常流程不触发。

---

## 2. iPad 平板布局自检

### 2.1 已对齐鸿蒙的部分

| 能力 | iOS 实现 | 鸿蒙对照 |
| --- | --- | --- |
| 首页两栏布局 | `HomeTab.swift` 第 56-57 行，阈值 768pt，左 2/3 + 右 1/3 | `HomeTab.ets` 一致（注释明确对齐） |
| 计分板响应式字号 | `ScoreboardLayoutMetrics.swift` base 144 → max 480 | `baseMainScoreFontSize.ts` 一致 |
| 队名字号 | Pad 36 / Phone 28 | 对齐 |
| 大分数 1.5× 缩放 | `ScoreboardTemplate.swift` 第 840 行 | 对齐 |
| lockOrientation | iPad 默认不锁（除非 `forceIPadLandscape`） | 鸿蒙不强制旋转一致 |
| 默认队名 | 红方/蓝方、主队/客队 | 注释「与鸿蒙一致」 |

### 2.2 设计选择（非 Bug）

- **未使用 NavigationSplitView**：iPad 与 iPhone 共用底部 TabView，`configureTabBarPresentation` 显式强制 `.tabBar` 模式避开 sidebar。与鸿蒙保持底部 Tab 设计一致。
- **纯 SwiftUI**：未使用 `UICollectionViewCompositionalLayout` / `UISplitViewController`，网格用 `LazyVGrid`，导航用 `NavigationStack`。

### 2.3 发现的潜在 Bug（3 处）

#### Bug 1（中）：UIScreen.main.bounds 在分屏/Stage Manager 下不可靠

5 处计分板用 `UIScreen.main.bounds` 而非 `GeometryReader` 计算，iPad 分屏时取到全屏尺寸而非当前窗口，会导致字号/布局偏大：

| 文件 | 行号 | 代码 |
| --- | --- | --- |
| `BoxingScoreboardView.swift` | 177 | `let w = UIScreen.main.bounds.width` → 字号公式 |
| `ArcheryScoreboardView.swift` | 495 | 同上 |
| `SimpleScoreboardView.swift` | 179 | `let halfH = min(UIScreen.main.bounds.width, ...)` |
| `DoudizhuScoreboardView.swift` | 500 | `.frame(width: UIScreen.main.bounds.width * 0.45, ...)` |
| `MenuDialog.swift` | 232-233 | dialogWidth/syncCardHeight |

**对比**：`BasketballScoreboardView`、`RallyScoreboardView`、`TeamSection` 都正确用了 `GeometryReader`/`proxy.size`，可作正面教材。

#### Bug 2（低）：HomeTab loadConfig 硬编码非大屏

`HomeTab.swift` 第 213 行：`quickStartManager.loadConfig(isLargeScreen: false, is2in1: false)` —— iPad 上也传 `false`。当前 `loadConfigInternal` 未实际使用这两个参数（始终 fallback `defaultPhoneConfig`），但这是**未完成的适配入口**，一旦鸿蒙端用 `isLargeScreen` 区分配置，iPad 端会漏掉。鸿蒙端有 PHONE/TABLET/2IN1 三套快速开始配置。

#### Bug 3（低）：比赛详情页无 maxWidth 限制

`ScoreboardRecordDetailPage.swift` body 中未发现任何 `maxWidth` 限制或 `usesPadLayout` 判断。对比：记录列表（920）、设置页（760）、我的球局（600）都有限制。详情页在 iPad 上内容会撑满整宽，阅读体验差。

### 2.4 一致性问题

iPad idiom 判定方式不统一：
- `ToolsTab`/`TimerTab`：`.pad && width >= 760`（双条件，兼容分屏 compact）
- `RecordsTab`/`SettingsView`：`.pad && horizontalSizeClass == .regular`（双条件）
- 多数计分板：仅 `.pad`（单条件，iPad 分屏 compact 时仍按 Pad 处理，可能布局拥挤）

**建议**：统一为 `userInterfaceIdiom == .pad && horizontalSizeClass == .regular` 或基于 GeometryReader 宽度阈值。

---

## 3. Apple Watch 应用自检

### 3.1 独立功能（12 计分模式 + 投篮训练，全部齐备）

证据：`jifenWatch Watch App/Views/WatchHomeTabView.swift` 第 4-19 行 `WatchHomeItem` 枚举共 13 项。

| 类别 | 项目 | 实现方式 |
| --- | --- | --- |
| Rally 共享视图 | 羽/乒/匹单双打（6 项） | 薄包装 → 复用 `WatchRallyScoreView`，通过 `GameType` + `RallyRuleSet` 区分 |
| 独立实现 | 网球单双打（2 项） | `WatchTennisScoreView`（含抢七/局间休息/换边/双打发球轮转） |
| 独立实现 | 射箭 | `WatchArcheryScoreView` + `WatchArcherySessionStore` |
| 台球聚合 | 黑八/九球/斯诺克（3 项） | `WatchBilliardsScoreViews.swift`（同文件 3 个视图） |
| 训练 | 投篮训练 | `WatchBasketballTrainingView`（1/2/3 分/自由模式，Watch-only 不同步手机） |
| 工具 | 翻硬币/随机数/10秒/计数器（4 项） | 各自独立文件 |

**与鸿蒙 Watch 对比**：完全一致（12 计分模式 + 投篮训练 + 4 工具）。

### 3.2 共享代码（良好）

Watch 复用共享包 `Packages/JifenCore`，import `ScoreCore / SessionCore / RecordCore / PersistenceCore / LinkCore`，**未私造规则引擎**。

**两种会话管理架构并存**：
- **ScoreSessionCore 驱动**（完整共享引擎 + 归档）：Rally（乒/羽/匹）、Tennis、Basketball
- **本地 undoStack 驱动**（复用 ScoreCore 类型但自管撤销）：EightBall、NineBall、Snooker、Archery —— 这些**不经过 ScoreSessionCore，也不写入 SessionArchiveRepository**，断点续赛通过 `WatchResumeSession` 手动传递

### 3.3 设置与小屏适配（齐备）

- 设置项：常用名称、手机联动、振动、声音、常亮、局间休息、布局横竖屏、使用说明
- 窄屏阈值：**实际是 ≤190pt**（`WatchTheme.swift` 第 7 行），非文档所述 180pt；射箭加分面板另有 ≤176pt 特殊档
- 涵盖 40/41/42/44mm（窄屏）与 45/46/49mm（宽屏）

### 3.4 发现的问题（4 个）

#### 问题 1（中）：篮球(3x3/5v5)代码残留但本地菜单无入口

- 存在完整实现：`WatchBasketballScoreView.swift` + `WatchBasketballSessionStore`（使用 `BasketballMatchReducer`，支持 3x3/5v5、计时、罚球）
- 路由存在：`WatchScoreboardRoute.basketball(threeXThree:)`
- **但 `WatchHomeItem`（13 项）和 `WatchSetupSport`（12 项）均不含篮球**
- `WatchGameType` 枚举**无 basketball case**，篮球记录在 Watch 端归类会缺失映射
- 篮球计分仅能通过手机联动进入

**评价**：与鸿蒙基线一致（鸿蒙 Watch 也无篮球正式入口），但代码残留需明确标注为「保留实现，不暴露入口」。

#### 问题 2（中）：篮球本地结束不保存 WatchRecord（数据丢失风险）

`WatchBasketballScoreView.finalizeBasketball()`（第 506-524 行）只在 `linkedSessionId != nil && linkService.isController` 时调用 `linkService.publishMatchFinished`，**无 else 分支调用 `WatchRecordManager.shared.saveRecord`**。

对比 `WatchTennisScoreView`（第 784-787 行）有 `else { transferLocalFinishedRecordIfNeeded(...) }`。

**风险**：若联动中途断开且 Watch 端独自结束比赛，该场比赛**不会产生任何本地记录**，数据丢失。虽然篮球只能由联动启动，正常情况影响有限，但断线场景需保护。

#### 问题 3（低）：台球/射箭未走 SessionCore 归档通道

黑八、九球、斯诺克、射箭使用本地 `undoStack: [State]` 而非 `ScoreSessionCore`。它们的会话快照**不会**通过 `SessionArchiveRepository` 归档（仅 rally/tennis/basketball 会）。断点续赛通过 `WatchResumeSession.resumedUndoStates` 手动传递。

功能上闭环可用，但与 rally/tennis/basketball 的持久化策略不一致，跨设备恢复能力较弱。

#### 问题 4（低）：TimerCore 未被 Watch 引用

共享包提供了 `TimerCore` 模块，但 Watch 端零引用。不存在 `WatchTimerDetailView`。仅有 `WatchTenSecondChallengeView`（10 秒挑战）这一个含计时的工具，用本地 `Timer` 实现。

**评价**：当前 Watch 无通用倒计时/正计时计分工具需求，但若产品规划需要，目前是空白。

---

## 4. 手机手表联动自检

### 4.1 双向闭环已实现（正面）

| 联动环节 | 实现证据 | 状态 |
| --- | --- | --- |
| 手机发起、手表确认 | `PhoneWatchLinkService.swift` 第 523-615 行 setupRequest（20s 超时）；`WatchLinkService.swift` 第 710-740 行 handleSetupRequest | ✅ |
| 手表计分回传手机 | `WatchLinkService.swift` 第 490-538 行 publishSnapshot；`PhoneWatchLinkService.swift` 第 805-838 行 handleSnapshotFromWatch | ✅ |
| ACK / 重发 | `LinkPendingAckQueue` 3s 重试 / 最多 2 次（`LinkCore.swift` 第 395-466 行） | ✅ |
| 手机接管 | `PhoneWatchLinkService.swift` 第 317-356 行 takeoverByPhone；ACK 携带权威快照 | ✅ |
| 手表夺回 | `WatchLinkService.swift` 第 173-202 行 reclaimRequest；5s 超时自动拒绝 | ✅ |
| 完赛记录回传 | `matchFinished` + `LinkedMatchRecordIngestor.ingest` 唯一落库；落库失败不 ACK | ✅ |
| 修订号门控 | `LinkRevisionGate` 通过 sessionId + revision 判断 newer/duplicate/wrongSession | ✅ |
| outbox 持久化 | 手表 3 个 UserDefaults outbox（terminal/records/usage）；手机 1 个 terminal outbox | ✅ |
| 传输层降级 | 可达时 `sendMessageData`，不可达时 `transferUserInfo`（系统级离线队列） | ✅ |

### 4.2 支持项目（与鸿蒙完全一致）

`AppFeatureFlags.isWatchLinkSupportedProject`（第 24-34 行）：乒乓球、羽毛球、网球、匹克球（均含单双打）、射箭、黑八、九球追分、斯诺克。

篮球比赛和投篮训练明确排除（`SportsSetupDialogView.canStartOnWatch` 返回 false）。

### 4.3 入口控制（良好）

`JifenWatchLinkEntryEnabled` plist 开关（`Info.plist` 第 7-8 行，默认 `true`）控制 9 处入口：Me 页面、开局对话框、九球开局、WatchLinkSettingsView、6 个计分板菜单（射箭/网球/对打/篮球/台球类）。

关 `JifenWatchLinkEntryEnabled` 仅隐藏入口，独立 Watch 计分与协议实现仍保留。

### 4.4 发现的风险（8 个，按严重度排序）

#### 风险 1（高）：缺少心跳与断连超时检测

**鸿蒙**：手表主控每 60s 发 `HEARTBEAT`；手机 follower 180s 无手表消息后发 `STATUS_QUERY(reason=heartbeat_timeout)`；手表主控连续 3 次发送失败后检测手机离线。

**iOS**：**无心跳机制**（grep 确认无 heartbeat/60000）；**无断连超时计时器**（无 180000）；**无连续发送失败计数**；仅依赖 `sessionReachabilityDidChange` 系统回调。

**风险**：当 WCSession 报告 `isReachable = true` 但实际消息投递延迟或丢失时（蓝牙边缘情况），iOS 无法主动检测连接质量下降。用户可能看到「联动中」但实际已断连，直到下次操作发送失败才发现。

#### 风险 2（高）：缺少 CONTROL_INTERRUPTED 自动通知

**鸿蒙**：手表计分页被系统中断时自动发 `CONTROL_INTERRUPTED`，手机收到后可自动 `TAKEOVER_BY_PHONE`。

**iOS**：`LinkMessageKind` 枚举中**无 `controlInterrupted` 项**。手表 `onDisappear` 时仅发 `scoreboardExitedToHome`，但手机端处理是「保持手表为主控」（`PhoneWatchLinkService.swift` 第 964-971 行注释 "Keep the watch as controller"），**不触发自动接管**。

**风险**：手表被系统通知/来电中断后，如果手表进程被杀，手机不知道应该接管，比赛可能卡住。

#### 风险 3（中）：协议版本落后且协商不完整

**鸿蒙**：源码实际为 **v3**（`linkedScoreboardMessage.ts` 第 12-13 行 `LINKED_SCOREBOARD_VERSION = 3`），文档过期为 v2。完整的 `version` / `minSupportedVersion` / `features` 协商。

**iOS**：`LinkProtocol.currentVersion = 1`（`LinkCore.swift` 第 11 行）。仅在 `handleSetupRequest` 中校验 `protocolVersion == currentVersion`，不匹配返回 `setupRejected`。**无 `minSupportedVersion` 和 `features` 协商**。

**风险**：iOS 版本固定为 v1，无法做细粒度能力降级。当前 iOS 与鸿蒙不会跨平台联动，无实际影响，但版本号落后需关注。

#### 风险 4（中）：缺少手动同步积分入口

**鸿蒙**：手机 follower 可主动发起 `STATUS_QUERY(reason=manual_resync)` → 手表回 `STATUS_RESPONSE(canSendSnapshot=true)` → 手机发 `RESYNC_REQUEST` → 手表强制发送最新 `STATE_SNAPSHOT`（5s 超时）。

**iOS**：`LinkMessageKind` 有 `resyncRequest`，但 `PhoneWatchLinkService.swift` **从未发送过** `resyncRequest`。仅在 `handleConnectivityStatusChange` 时发 `statusQuery`，无用户主动触发入口。

**风险**：用户在手机 follower 端发现比分不同步时，iOS 没有「同步积分」按钮可以主动拉取手表最新比分。

#### 风险 5（中）：缺少 NACK 驱动的立即补发

**鸿蒙**：跟随端拒绝应用状态时发 `STATE_APPLY_NACK`，主控收到 NACK 后立即补发当前 pending。

**iOS**：`LinkMessageKind` 有 `negativeAcknowledgement` 枚举，但 grep 确认**全代码库未实际使用**。仅靠 3s 超时重试。

**风险**：状态应用失败时（如项目不匹配、数据损坏），iOS 要等 3s 超时才重试，快速操作场景下可能感知延迟。

#### 风险 6（中）：联动与独立回传双路径潜在重复落库

存在两个落库器：
- `LinkedMatchRecordIngestor`（`WatchLinkMenuSupport.swift` 第 37-123 行）：处理联动会话 matchFinished，recordId 来自 payload
- `WatchStandaloneRecordIngestor`（第 270-343 行）：处理手表独立完赛记录自动回传，recordId 加 "w_" 前缀

两者都调用 `ScoreboardRecordManager.shared.saveScoreboardRecord(record)`。

**风险**：联动会话中手表作为主控时，`WatchRecordManager.saveRecord` 仍会被调用（保存本地记录）并触发 `autoTransferToPhoneIfNeeded`；同时联动 matchFinished 也会落库。两者 recordId 不同（联动用 payload.recordId，独立回传用 "w_" + record.id），**可能导致同一比赛在手机端有两条记录**。

`handleMatchFinishedFromWatch` 落库后 `finishedRecordId` 被设置，但 `handleWatchRecordTransfer` 是独立路径，不受 `finishedRecordId` 保护。

#### 风险 7（低）：缺少 PHONE_CONTROLLER_EXITED_TO_HOME 等控制权交回

**鸿蒙**：`PHONE_CONTROLLER_EXITED_TO_HOME`（手机主控页退出时携带最新 state，把控制权交回手表）；`PHONE_SCOREBOARD_EXITED_TO_HOME`（手机 follower 回首页但保留 session）。

**iOS**：**无此两条指令**。手机退出仅发 `sessionLeft`，直接清除会话。

**风险**：iOS 手机主控退出时直接结束会话，而不是把控制权交回手表。如果用户只是临时切到首页再回来，会话已断。鸿蒙的设计允许更平滑的控制权交接。

#### 风险 8（低）：LinkPendingAckQueue 单条队列覆盖

`LinkPendingAckQueue.pending` 只能存一条（`LinkCore.swift` 第 424 行），`enqueue` 直接覆盖不检查已有 pending。

**缓解**：stateSnapshot 是全量快照（非增量），后一条覆盖前一条语义上可接受——手机端最终会收到最新状态；matchFinished 使用独立的 `terminalPendingAck` 队列，不受影响；revisionGate 的 `.duplicateOrOlder` 仍会回 ACK 触发重试清除。

---

## 5. 与鸿蒙端对比总结

### 5.1 iOS 有意暂缓的服务端能力（鸿蒙有、iOS 没有）

以下能力是 iOS 明确暂缓的范围，不计入缺陷：

| 能力域 | 鸿蒙文件证据 | 说明 |
| --- | --- | --- |
| 账号登录 | `api/authApi.ts` | 华为/微信/邮箱/测试账号登录 |
| VIP/IAP | `api/vipApi.ts` | 购买验证、兑换码、年会员 |
| 权益查询 | `api/entitlementApi.ts` | - |
| WebSocket 房间 | `api/websocketManager.ts` | Controller/Display 双角色 |
| 云同步会话 | `cloudsync/session/CloudSyncSession.ts` | SHARING/IN_GAME 两阶段，5min/10min 空闲超时 |
| 同步码 | `cloudsync/util/CloudSyncCodeFormatter.ts` | 格式化/解析同步短码 |
| 展示端大屏 | `pages/display/DisplayScoreboardPage.ets`（1270 行） | 沉浸式全屏，WebSocket 接收 |
| 用户反馈 | `api/feedbackApi.ts`（806 行）+ 3 页面 | CRUD + 评论 + 点赞 + 举报 + 图片上传 |
| 常用数据云同步 | `api/commonDataApi.ts` | 常用名称/地点云端同步 |
| 比赛同步 | `api/matchApi.ts` | - |
| 客户端配置 | `api/clientConfigApi.ts` | - |
| 数据上报 | `api/reportApi.ts` | - |

**重要**：iOS 当前 `HttpClient` / `WebSocketManager` 是 placeholder，未真实接入。这与暂缓决策一致，但官网条款仍写有 iOS 微信登录、账号注销、云端与在线同步等能力，**必须先修正文案**（这是发布前 P1 阻塞，见 `ios_release_parity_audit_2026-07-23.md`）。

### 5.2 cloudsync 与手机手表联动是两个独立系统

**鸿蒙**：`cloudsync` 模块是纯云端同步（WebSocket 房间 + 同步码 + 展示端），**不包含**手机手表 P2P 联动。手机手表联动通过 `linkedScoreboardSync/` 模块（Wear Engine）实现。

**iOS**：无 cloudsync 对应模块；手机手表联动通过 `LinkCore` + `WatchConnectivity` 实现。

**结论**：两者是不同传输层（云端 vs P2P），产品语义不应混淆。iOS 暂缓的是 cloudsync（云端），手机手表联动（P2P）已实现。

### 5.3 联动协议指令对比

鸿蒙联动协议共 22 条指令，iOS 缺少以下 7 条：

| 缺失指令 | 鸿蒙用途 | iOS 影响 | 严重度 |
| --- | --- | --- | --- |
| `HEARTBEAT` | 主控 60s 心跳 | 无断连检测 | 高 |
| `CONTROL_INTERRUPTED` | 手表中断自动通知 | 手表被杀手机不知情 | 高 |
| `STATE_APPLY_NACK` | 跟随拒绝时立即补发 | 仅靠 3s 超时 | 中 |
| `SETUP_CANCELLED` | 取消开局 | 无独立指令 | 低 |
| `PHONE_CONTROLLER_EXITED_TO_HOME` | 手机退出交回控制权 | 直接 sessionLeft | 低 |
| `PHONE_SCOREBOARD_EXITED_TO_HOME` | 手机 follower 回首页保留 session | 直接 sessionLeft | 低 |
| `WATCH_LEFT` | 手表离开通知 | 仅有 scoreboardExitedToHome | 低 |

### 5.4 鸿蒙端平板/折叠屏适配更完善

| 能力 | 鸿蒙 | iOS |
| --- | --- | --- |
| 设备类型检测 | tablet / 2in1 / foldable | 仅 pad |
| 折叠屏检测 | `isFoldableDevice()` + `isFoldableExpandedState()` | 无 |
| 桌面全屏 | `desktopFullscreenHelper.ts` | 无 |
| 快速开始配置 | PHONE/TABLET/2IN1 三套 | 仅 phone/pad |
| 响应式水平边距 | `getResponsiveHorizontalPadding()` | 各页硬编码 |

**评价**：iOS 无折叠屏/2in1/桌面形态，不需要对齐折叠屏和桌面全屏。但快速开始配置的「大屏专属项」可以考虑补齐。

---

## 6. 问题汇总与优先级

### P0（阻塞，需立即处理）

无。当前代码内已知 P0 崩溃为 0（`ios_release_parity_audit_2026-07-23.md` 已确认）。

### P1（高，建议发布前处理）

| # | 问题 | 模块 | 建议 |
| --- | --- | --- | --- |
| P1-1 | 联动缺心跳与断连超时检测 | 联动 | 增加 60s 心跳 + 180s 断连超时 + STATUS_QUERY，或依赖系统回调 + 显式 UI 提示 |
| P1-2 | 联动缺 CONTROL_INTERRUPTED 自动通知 | 联动 | 监听 `scenePhase` 变化，手表后台时发通知让手机可接管 |
| P1-3 | 官网条款与 iOS 实际能力不一致（外部） | 合规 | 修正官网服务条款/隐私政策中超出 iOS 2.0 实际能力的描述（账号/支付/云同步） |
| P1-4 | 真机联动门禁未完成 | 联动 | 真实 iPhone + Apple Watch 覆盖断连重连/锁屏/后台/杀进程/断网完赛恢复 |

### P2（中，后续增强）

| # | 问题 | 模块 | 建议 |
| --- | --- | --- | --- |
| P2-1 | 5 处计分板用 UIScreen.main.bounds（分屏 Bug） | iPad | 改为 GeometryReader/proxy.size |
| P2-2 | 比赛详情页无 maxWidth 限制 | iPad | 增加 maxWidth 600 + 居中 |
| P2-3 | 联动与独立回传双路径潜在重复落库 | 联动 | 联动会话中抑制 `autoTransferToPhoneIfNeeded`，或落库前检查 recordId |
| P2-4 | 缺手动同步积分入口 | 联动 | 手机 follower 端增加「同步积分」按钮，发 `resyncRequest` |
| P2-5 | 缺 NACK 驱动立即补发 | 联动 | 状态应用失败时发 `negativeAcknowledgement`，主控立即补发 |
| P2-6 | 篮球 Watch 本地结束不保存 WatchRecord | Watch | 增加 else 分支调用 `WatchRecordManager.saveRecord` |
| P2-7 | 协议版本 v1 vs 鸿蒙 v3 | 联动 | 评估是否升级到 v3 并增加 minSupportedVersion 协商 |
| P2-8 | iPad idiom 判定不统一 | iPad | 统一为 `.pad && horizontalSizeClass == .regular` |

### P3（低，可延后）

| # | 问题 | 模块 | 建议 |
| --- | --- | --- | --- |
| P3-1 | HomeTab loadConfig 硬编码非大屏 | iPad | 当前无影响，但适配入口需补齐 |
| P3-2 | 台球/射箭未走 SessionCore 归档 | Watch | 跨设备恢复能力较弱，可统一到 SessionArchiveRepository |
| P3-3 | 缺 PHONE_CONTROLLER_EXITED_TO_HOME 控制权交回 | 联动 | 手机退出直接 sessionLeft，体验差异 |
| P3-4 | StopwatchView 文件位置错位 | 主应用 | 移到 Timer/ 目录或保持现状（功能正常） |
| P3-5 | ToolsTab.swift 死代码 | 主应用 | 删除或保留作 Preview |
| P3-6 | WatchGameType 无篮球 case | Watch | 篮球记录归类缺失映射（当前无入口，影响有限） |
| P3-7 | TimerCore 未被 Watch 引用 | Watch | 当前无需求，保留 |
| P3-8 | 足球/拳击/通用台球/简单计分/多人计分专项自动化较薄 | 测试 | 补专属边界自动化 |

---

## 7. 建议处理顺序

1. **P1-3 / P1-4（外部门禁）**：修正官网条款 + 真机联动回归。这是发布前阻塞项，与代码无关但必须完成。
2. **P1-1 / P1-2（联动语义补齐）**：心跳 + 断连检测 + CONTROL_INTERRUPTED。这是 iOS 联动与鸿蒙最大的语义差距，影响真实场景下的稳定性。
3. **P2-1 / P2-2（iPad 分屏 Bug）**：5 处 UIScreen.main.bounds + 详情页 maxWidth。改动小，收益明显。
4. **P2-3（重复落库防护）**：联动会话中抑制独立回传，或落库前检查 recordId。
5. **P2-4 / P2-5（联动体验）**：手动同步入口 + NACK 立即补发。
6. **P2-6（Watch 篮球落库）**：增加 else 分支保护断线场景。
7. **P2-7（协议版本）**：评估升级到 v3 的成本收益。
8. **P3 系列**：按需处理，不阻塞发布。

---

## 8. 最终判定

- **主应用本地功能**：✅ 可用，23 计分 + 9 计时 + 10 工具与鸿蒙/Android 对齐，无占位页，本地数据闭环完整。
- **iPad 平板布局**：⚠️ 基础到位，3 处 UIScreen.main.bounds 分屏 Bug 需修，详情页缺 maxWidth。
- **Apple Watch 应用**：✅ 12 计分模式 + 投篮训练与鸿蒙对齐；篮球代码残留需明确标注；台球/射箭归档策略不一致可后续统一。
- **手机手表联动**：⚠️ 双向闭环已通，唯一落库已实现；但语义比鸿蒙弱（缺心跳/中断通知/手动同步/NACK），是后续强化重点。
- **有意暂缓项**：✅ 范围明确，账号/VIP/云同步/反馈/展示端均未实现，与决策一致；但官网条款需修正。
- **发布判定**：仍为 **NO-GO**，主要阻塞项是外部 P1（官网条款 + 真机门禁 + 商店门禁），代码侧无 P0。
