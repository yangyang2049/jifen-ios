# 手表端全量检查报告（含手机联动 / UI / 数据层）

- 日期：2026-11-24
- 范围：`jifenWatch Watch App/`（App 入口、Views、Scoreboard、Tools、Components、Managers、Models、Info.plist）、共享层 `Packages/JifenCore/Sources/LinkCore/`（含 ScoreCore/RecordCore 引用面）、手机端联动层 `jifen/Core/Link/`、手机端联动入口与设置（`SportsSetupWatchSessionLauncher`、`SportsSetupDialogView`、`AppFeatureFlags`、`WatchLinkSettingsView`、`WatchLinkMenuSupport`、`HomeTab` 续赛条）、7 个手机端计分板的联动接线抽查、`jifen.xcodeproj` 手表 target 配置、手表测试套件。
- 方法：全量通读联动协议与状态机 + 检索式扫描 25k 行（强解包、Timer/Task 清理、硬编码中文、本地化键、WCSession 限额点）+ 实际构建与单测验证。
- 原始证据（构建/测试日志、xcresult）存放在受管批次 `~/Library/Developer/jifen-ios-test-artifacts/runs/20261124T023559575699Z-watch-link-fullcheck-20261124/`，**随批次保留期（14 天滚动清理）过期**，本报告只保留结论与文件:行号。

## 结论摘要

手表端整体架构成熟：联动协议（correlated request / authority epoch / durable outbox / revision gate / catch-up 握手 / 常用名称双向同步）设计完备，7 类计分板的发布-跟随-回收模式一致，本地化三语零缺键，无 try!/as!、无 asyncAfter、无未取消的 Timer。但发现 **1 个 P0 功能回归、3 个 P1 问题**，其中九球计分板当前"所有计分按钮无响应"，测试套件已经用 2 个失败用例把这颗雷标了出来。

---

## P0 — 手表端九球（追分）计分板全部计分按钮静默失效

**根因链**：
1. ScoreCore 引擎在 `553d0b48`（2026-10-25「九球新规则」）把 `NineBallChaseState.initial()` / `init()` 的默认 `ruleVersion` 改为 **2**（`Packages/JifenCore/Sources/ScoreCore/s2/SpecializedScoreboards.swift:269,300`）。
2. v2 下 reducer 明确拒绝旧意图：`case .chaseEvent: guard next.ruleVersion == 1 else { return .rejected(state:, reason: "Rule v2 requires a transfer event") }`（`SpecializedScoreboards.swift:405-407`）；v2 应走 `.chaseTransfer`。
3. 手机端已随迁移改造（`NineBallChaseScoreboardView.swift:1341-1342`：v1 才发 `.chaseEvent`，否则走 transferContext + `.chaseTransfer`），**手表端没有迁**：`WatchNineBallScoreView.swift:262` 只发 `apply(.chaseEvent(player:kind:))`，事件面板含 normalWin / foul / bigGold / smallGold / goldenNine / ballInHand。
4. 手表端所有初始状态都是 v2：视图默认 `initialState ?? .initial()`（`WatchNineBallScoreView.swift:62`）、本地开局 `WatchSetupPayloadMapper.nineBallState`（`WatchSetupModels.swift:510-516`）、手机联动开局（`SportsSetupWatchSessionLauncher.swift:137-143` 也用默认 v2）。
5. `apply()` 对 rejected 结果静默返回（`WatchNineBallScoreView.swift:298-308`），用户看不到任何提示。

**实际表现**：手表九球计分板（本地开局、默认开局、手机联动主控三种路径）上 普通胜/犯规/大金/小金/金九/自由球 全部点不动；分数、局数、完赛判断全部失效。

**测试证据（本轮实测）**：手表单测 103 用例中 2 个失败，正是这颗雷：
- `testNineBallFoulAwardsOpponentForTwoPlayersAndDeductsForGroups`（`WatchSportsSetupTests.swift:367`）：`XCTAssertEqual failed: ("0") is not equal to ("2")` / `("0") is not equal to ("-2")` —— v2 状态下 `.chaseEvent(foul)` 被拒，分数未动。
- `testSpecializedProjectorsKeepMissFoulAndParticipantIdentity`（`WatchSportsSetupTests.swift:1241`）：`("nil") is not equal to Optional(...foul)` 等 —— reducer 拒绝后 events 为空，投影器无输出。

**修复建议**：手表视图按 `state.ruleVersion` 分派（v1 → `.chaseEvent`；v2/v3 → transferContext + `.chaseTransfer`，参考手机端实现）；或在手表侧固定用 v1 开局（若产品确认手表只支持旧规则，则把 `.initial(ruleVersion: 1)` 写进 `WatchSetupPayloadMapper.nineBallState` 与联动 setup 构造，并恢复两个测试的语义）。修复后重跑手表单测确认 103 全绿。

---

## P1-1 「在手表开始」白名单三层不一致：5 个项目 UI 放行、服务层必拒（误导性报错 + 双端死代码）

同一份"哪些项目能手机发起手表联动"在三处定义，互不一致：

| 层 | 位置 | 项目集 |
|---|---|---|
| UI 开关（显示按钮） | `AppFeatureFlags.isWatchLinkSupportedProject`（`jifen/Core/AppFeatureFlags.swift:52-67`） | **17 项**：四类球拍单双打 + 射箭 + 黑八/追分/斯诺克 + **毽子/壁球/桌上足球/足球/五人制足球**（注释称对齐鸿蒙 18 项） |
| 启动器（构造 Setup） | `SportsSetupWatchSessionLauncher.start`（`jifen/Features/Home/Services/SportsSetupWatchSessionLauncher.swift:120-172`） | 同上 17 项，足球/毽子/壁球/桌上足球都会构造快照 |
| 服务闸门（真正放行） | `PhoneWatchLinkService.phoneInteractiveStartSupported`（`jifen/Core/Link/PhoneWatchLinkSession.swift:572-583`） | **仅 12 项**（无毽子/壁球/桌上足球/足球/五人制足球），且被 `PhoneWatchLinkServiceTests.testPhoneCanStartExactlyTheTwelveSupportedWatchScoreboards`（`jifenTests/PhoneWatchLinkServiceTests.swift:350-364`）钉死 |
| 手表校验 | `WatchLinkSession.isValidLinkedSetup`（`jifenWatch Watch App/Models/WatchLinkSession.swift:552-...`） | **仅 12 项**（rally 分支只有乒/羽/匹克，无毽子/壁球/桌上足球；无 football case） |

**实际表现**：用户选足球/五人制足球/毽子/壁球/桌上足球 → 设置弹窗显示「在手表开始」→ `startInteractiveSession` 在 `PhoneWatchLinkReliability.swift:27-30` 直接抛 `watchUnavailable` → 弹窗红字显示 **「Apple Watch 未连接，请打开手表端全能计分器后重试。」** ——与真实原因（项目未放行）完全无关的误导性错误。

**连带死代码（双端都已写好但不可达）**：
- 手表：`WatchScoreboardRoute(linkedSetup:)` 的 football/football5v5/shuttlecock/squash/foosball 分支（`WatchScoreboardRoute.swift:111-129`）、`LinkedSetupConfirmCopy` 的对应文案（`WatchRootView.swift` 末段）、`WatchRootView.rallyRuleSet/isRallyGameType` 对三项目的支持、`WatchFootballScoreView.linkedState` 参数。
- 手机：`FootballScoreboardView.swift:371,385` 的 `syncWatch` / `notifyMatchFinished`、接管 ACK 里 football 快照分支缺失（`PhoneWatchLinkMessageHandling.handleAck` 只认 rally/tennis/eightBall/nineBall/snooker/archery）。
- 手机端足球板还有完整的回收/接管/完赛接线（`FootballScoreboardView.swift:250-420`）——全部悬空。

**修复建议**（二选一，需产品确认）：① 若要放行 5 项目：同步改 `phoneInteractiveStartSupported` + `isValidLinkedSetup`（补 football case）+ 更新 12 项钉死测试 + 补 takeover ACK 的 football 快照接受；② 若暂不放行：把 `AppFeatureFlags.isWatchLinkSupportedProject` 收回 12 项，让 UI 与服务一致，删/注释死代码。当前状态（UI 承诺、服务拒绝）最差。

## P1-2 绿色实底按钮黑字 — 违反 AGENTS.md「Action Button Foregrounds」规则

`WatchTheme.accent = 0x30D158`（绿）。以下均为实底绿色 + 显式黑前景（`Color.black` / `.foregroundStyle(.black)`），按项目规则 Save/Confirm 类必须显式白字，且不得依赖自动对比度：

| 位置 | 性质 | 行 |
|---|---|---|
| `WatchRootView.swift:288` | 联动确认弹层「接受」（Confirm 类） | `.foregroundStyle(.black)` + accent 底圆钮 |
| `WatchCommonNamesView.swift:338` | 名称编辑 sheet「保存」（Save 类） | `Color.black` + accent 胶囊 |
| `WatchSportsSetupView.swift:70` | 设置页「开始」主按钮 | `.foregroundStyle(.black)` + accent 胶囊 |
| `WatchCommonNamesView.swift:144` | 「立即同步」按钮 | `Color.black` + accent 胶囊 |
| `WatchPhoneLinkView.swift:129` | 「测试连接」按钮 | `Color.black` + accent 胶囊 |
| `WatchCommonNamesView.swift:126,176` | 待同步计数徽章、类别选中态（绿底黑字） | 同对比度问题 |

关联但非按钮：`WatchFootballScoreView.swift:347` 半场徽章 stage 1 用 `0x22C55E` 绿底 + 黑字。

**建议**：手表端大量按钮绕过共享组件（手机端约定为白字），逐处显式 `.foregroundStyle(.white)`；可顺手抽一个 `WatchPrimaryActionButton` 防再犯。

## P1-3 WCSession 65,536 字节上限下的三个体量风险（长局/多记录场景必然触发）

WatchConnectivity 对 `sendMessageData`、`sendMessage`、`transferUserInfo`、`updateApplicationContext` 均有 65,536 字节上限。当前链路无任何裁剪：

1. **实时快照携带全量动作历史**：手表 `publishSnapshot`（`WatchLinkSession.swift:206-233`）与手机 `sendSnapshotIfController`（`PhoneWatchLinkReliability.swift:85-140`）的 stateSnapshot 信封都带 `mergedDetailedActions`（按动作 id 并集、只增不减，`WatchLinkSession.swift:532-541`）。`DetailedScoreAction` 单条约 300-700B JSON（`RecordCore.swift:76-110`，20 余字段），~130-160 个动作即达 64KB → `sendRealtime`/`publishLatestSnapshot` 开始报错，比分停同步并弹「联动失败」。羽毛球/乒乓球 3 局长局（每分一动作 + 局末/换发）可触达。
2. **待传记录打包发送**：`sendPendingWatchRecords` 把队列里所有记录 encode 进一条 `sendMessage`（`LinkCore.swift:1447-1460`；手表 `respondToCatchUpRequest` / `flushPendingWatchRecords` 同样全量打包）。每条记录含 `detailedActions` 可达 10-50KB，积压 ≥2-3 条后合计超限 → 发送失败无拆包 → **记录回传从此永久卡住**（每次 flush 仍超限）。
3. **完赛消息走 transferUserInfo**：`matchFinished` 也带全量 `mergedDetailedActions`（`WatchLinkSession.swift:338-380` / `PhoneWatchLinkSession.swift:495-560`），超限后 `enqueueDurable` 一直抛错 → durable outbox 无限重试、记录不落手机。

**建议**：实时快照只带增量或尾部 N 条动作（接收端已有按 id 并集合并逻辑，天然支持增量）；`sendPendingWatchRecords` 逐条发送或按字节分块；超长完赛动作考虑分片上传。同时给 encode 后的字节加一道 `>60KB` 的断言/埋点，避免静默失败。

---

## P2 — 数据层

1. **记录全量 blob 存 UserDefaults**：`WatchRecordManager` 500 条上限、每次保存全量重编码（`WatchRecordManager.swift:31-56`）。单条记录含 `actions: [WatchScoreAction]`（动作级分数/局分/时间戳），500 条可达数 MB，watchOS UserDefaults 的容量与写入性能都按小对象设计，建议迁移到文件（Application Support）或 SQLite，至少下调上限。
2. **syncStates 超限粗暴清空**：`saveSyncStates` 在 `count > maxRecords*2` 时直接 `trimmed = [:]`（`WatchRecordManager.swift:96-103`）——所有记录的「已同步」状态一瞬全丢，随后重复推送。建议按时间裁剪。
3. **记录列表主线程解码 + loading 永不显示**：`WatchRecordListView.loadRecords` 同步调用 `getSummaries()`（首载解码全量 blob）并同步置 `loading=false`（`WatchRecordListView.swift:96-101`），"加载中"分支实际不可达；记录多时首屏卡顿。建议后台解码（手机端 `ScoreboardRecordsViewModel` 已按此改造）。
4. **每次得分都全量编码续玩包**：各板 `onStateChanged → Task { await persistResumeSession() }`（如 `WatchRallyScoreView.swift:314-317`），bundle 含 events/timeline/undoFrames，长局内写放大 O(n²)。建议 debounce（如 1-2s）或只在暂停/切后台时落盘。
5. **counter 记录口径不一**：`WatchGameType.counter` 注释「仅手表本地保存，不回传手机」（`WatchGameType.swift:32-35`）；实际只挡了自动同步（`WatchCounterView.swift:150` `transferToPhone: false`），记录详情页仍显示「同步到手机」（`WatchRecordDetailView.swift:81-84` 只排除 basketballTraining），且手机端 `mapGameType("counter")` 会落库为 `.counter` 记录（`WatchLinkMenuSupport.swift` 摄取段 + `Types.swift:70` 手机确有该类型）。行为可用但与注释/鸿蒙口径冲突，需产品拍板：要么详情页对 counter 隐藏同步入口，要么改注释承认可回传。

## P3 — 小问题与观察

1. `LinkControlRetryQueue` 单槽：连续快照会顶掉未 ACK 的旧快照（新快照语义上取代旧快照，可接受），但 `LinkSessionStateMachine.pendingAcknowledgementIds` 只增不减（仅内存，量级小）。可在 `beginNextMatch`/`endSession` 顺手清空。
2. `forceAuthority(to:kind:)` 忽略 `kind` 参数（`LinkCore.swift` `_ = kind`）——三种转移类型枚举实际归一为 forcedPhoneTakeover，建议删参数或留注释。
3. 静默超时窗口：`handleSetupRequest` 解码失败（如新版本手机发来未知 snapshot kind）直接 `return false`，手表无任何应答 → 手机干等 20s 报「等待手表确认超时」。protocolVersion/capabilities 校验只在解码成功后进行；建议解码失败也回 `setupRejected`（前向兼容对旧端更友好）。
4. `WatchLayout` 大量 `WKInterfaceDevice.current().screenBounds` 重复调用（每帧多次），可缓存到 `static let`。
5. `WatchRootView.linkedSessionId(for:)` 两个分支返回同一值（`WatchRootView.swift` 末段），可简化。
6. 手表 target 配置本身无问题：`WKCompanionAppBundleIdentifier=com.douhua.jifen.ios`、`WKRunsIndependentlyOfCompanionApp=YES`、`WKSupportsAlwaysOnDisplay`、`MARKETING_VERSION=3.4.4` 与手机一致；「计分时常亮」通过 `isLuminanceReduced` 黑幕遮罩实现（`WatchScoreboardComponents.swift:4-25`），依赖系统 AOD 而非 extended session，符合普通 App 的能力边界。

## 二次确认与修复记录（同日）

逐条复核后已全部修复并回归验证（本节追加于同日修复轮；修复后 JifenCore 包 305 测试全绿，手表/手机端验证结果见文末）。

**复核补充**：P1-2 除报告所列 6 处外，复核又发现 `WatchSportsSetupView` 的 setupChip 选中态（:525）与自绘 Toggle 旋钮（:494）同样绿底黑字；P1-2 中提及的足球半场徽章经对比度核算（黑字对 0x22C55E 约 9:1）不属于违规，保留不动。

| 编号 | 修复 | 位置 |
|---|---|---|
| P0 | 手表九球按 `state.ruleVersion` 分派：v1 → `.chaseEvent`，v2/v3 → `.chaseTransfer`（小金/让杆的就地解析为“下一位玩家”），事件面板改用 `state.scoringKinds`；投影器把 `.chaseTransferred` 改为与 chaseApplied 同口径（动作码 `nine_ball_<kind>`、行动者 delta、handoff 记状态变化），详情页补 handoff 文案；两个失败用例钉住 v1 语义并新增 v2 回归用例 | `WatchNineBallScoreView.swift`、`WatchScoreAction.swift`、`WatchRecordDetailView.swift`、`WatchSportsSetupTests.swift` |
| P1-1 | UI 项目开关收拢到与服务层白名单一致的 12 项（足球/毽子/壁球/桌上足球待两端协议完整支持后逐项放行），删除已不可达的毽球团队分支；新增 `testWatchLinkUIProjectGateMatchesServiceWhitelist` 双向一致性守护 | `AppFeatureFlags.swift`、`jifenTests/PhoneWatchLinkServiceTests.swift` |
| P1-2 | 8 处绿实底元素改显式 `.white`（确认/保存/开始/立即同步/测试连接/徽章/类别选中/chip/toggle 旋钮） | `WatchRootView.swift`、`WatchCommonNamesView.swift`、`WatchSportsSetupView.swift`、`WatchPhoneLinkView.swift` |
| P1-3 | LinkCore 新增：`LinkEnvelopeEncoding`（超限按最旧动作减半裁剪至 60KB）、`LinkPendingRecordChunking`（待传记录 ≤55KB 分批）、`LinkEnvelopeHead`、`payloadTooLarge` 错误 + 五个传输方法硬限额守护（把原生崩溃变为 Swift 错误）；实时快照/完赛/接管/回收/强制接管全部接入裁剪；手表待传记录 flush/追赶响应按单条裁剪；手机端单条记录入库后确认清理手表队列 | `LinkCore.swift`、`WatchLinkSession.swift`、`WatchLinkMessageHandling.swift`、`WatchLinkSideChannels.swift`、`PhoneWatchLinkSession.swift`、`PhoneWatchLinkReliability.swift`、`PhoneWatchLinkSideChannels.swift` |
| P2-1 | 记录存储从 UserDefaults blob 迁到 Application Support JSON 文件（原子写、串行队列、首次启动自动迁移旧数据）；同步状态字典改为按现存记录修剪，替换“超限全清” | `WatchRecordManager.swift` |
| P2-3 | 记录列表改后台加载摘要（新增 `loadSummaries(onComplete:)`），加载状态真实可见 | `WatchRecordListView.swift` |
| P2-4 | 续玩落盘 750ms 防抖（内存即时更新，`clear/consume` 取消待写，切后台 `flushPendingWrite` 强制落盘） | `WatchResumeSession.swift`、`WatchRootView.swift` |
| P2-5 | 计数器记录详情页隐藏「同步到手机」，`transferPayload` 拒绝 counter（与注释/鸿蒙口径一致） | `WatchRecordDetailView.swift`、`WatchRecordManager.swift` |
| P3 | `pendingAcknowledgementIds` 在 `beginNextMatch/endSession` 清空；解码失败的 setupRequest 回 `setupRejected`（消灭 20s 静默超时）；`WatchLayout` 缓存屏幕宽度（15 处查询→1 次）；`linkedSessionId(for:)` 简化；`forceAuthority` 补注释 | `LinkCore.swift`、`WatchLinkMessageHandling.swift`、`WatchTheme.swift`、`WatchRootView.swift` |

**评估后暂缓**：P2-2 的 500 条上限下调与 per-record 分片上传（需产品定上限与兼容策略）、P1-1 的“解锁 5 项目”（手表端足球计分发布链路尚缺，见下）——保留为后续项。

**二次确认新增发现（修复轮内发现并处理）**：

1. **`jifenTests/PhoneWatchLinkServiceTests.swift` 从未加入 jifenTests target**（`project.pbxproj` 的显式文件列表无此文件，构建产物 strings 验证不含该类）——手机端联动的 24 个用例（含 12 项白名单钉死用例）此前从未真正执行过；`run_automation_four_destinations.sh` 因此实际空跑。已把文件挂入 target 并重跑全类。
2. 上述用例首次执行暴露两个过期用例：`testQuickStartLayoutUsesTwoSlotsForCompactAndThreeForRegularWidth` 断言旧的三槽策略（产品已改为全窗口双槽 `HomeModels.swift:214`），已改写为双槽口径；`testStartupRecordLoadersRunOnlyWhenRequestedAndCoalesce` 在冷模拟器上 500ms 轮询过紧，放宽到 2s。

## 验证记录

- 构建：`xcodebuild -project jifen.xcodeproj -scheme "jifenWatch Watch App" -destination 'generic/platform=watchOS Simulator'`（复用 `jifen-watch-audit` DerivedData）→ **BUILD SUCCEEDED**（修复轮内随测试再次编译，含手机端宿主 App）。
- 手表单测：watchOS Simulator（Apple Watch Series 12 46mm）**104 用例全绿（exit=0）**，含新增 v2 回归用例与修正后的续玩持久化用例；修复前基线为 103 例中 2 失败（即 P0）。
- JifenCore 包测试：**305 用例全绿**（含新增 `LinkPayloadSafetyTests` 4 例：裁剪保序、限额内直通、单条超大归零、分块语义）。
- 手机端目标用例：`PhoneWatchLinkServiceTests`（首次真正入 target 执行）**24 用例全绿（exit=0）**，含新增 `testWatchLinkUIProjectGateMatchesServiceWhitelist`。
- 本地化：手表代码 310 个 key 在 en / zh-Hans / zh-Hant 三表 0 缺失。
- 静态扫描：手表目录 `try!` / `as!` 0 命中；`Text("中文")` 硬编码 0 命中；修复后手表端绿实底元素黑字 0 残留（仅剩黑底遮罩与白底黑字按钮、足球徽章黑字非按钮）。初版报告曾称 `asyncAfter`/`scheduledTimer` 0 命中，经复核不准确：存量代码存在 `asyncAfter`×4 与一次性 `scheduledTimer`×1（UI 延迟/撤销倒计时场景，均为本轮改动之前的历史代码，`git diff` 确认非本轮引入），本轮未将其列为问题，仅更正此前的扫描结论。
- 原始证据（修复后手表两轮测试日志与 xcresult、手机端目标用例日志与 xcresult）：修复轮批次 `~/Library/Developer/jifen-ios-test-artifacts/runs/20261124T031122391571Z-watch-fixes-verification-20261124/`；修复前的首轮审查证据（含 `watch-build.log`）在批次 `…20261124T023559575699Z-watch-link-fullcheck-20261124/`。批次保留期到期后过期。

## 自检记录（修复轮之后追加）

修复完成后按发送链路逐点复核，发现并修复两类遗漏：

1. **发送层裁剪存在缺口（已补）**：`setupRequest` 信封的 payload 就是 `LinkedScoreboardSetup`（内嵌 detailedActions），接管场景下可能超限，但此前只在具体调用点裁剪；ACK 等经 `sendReportingError` 转发的信封也无兜底。现 LinkCore 新增 `LinkEnvelopeEncoding.encodedData(_:)` 泛型分派入口（按 payload 类型自动裁剪 setup/完赛/ACK/接管四类），手机 `sendEnvelope`、手表 `send`、手机 setupRequest interactive、手表探测/常用名称两处小信封全部改为统一入口；Link watch/connectivity 目录不再有裸 `JSONEncoder().encode(envelope)` 发送点（`LocalPeerRoomManager` 为 Multipeer 通道，不属 WCSession 限额范畴）。同时传输层硬限额守护（`payloadTooLarge`）确保任何未来新增信封类型超限时抛 Swift 错误而非原生崩溃。
2. **升级迁移路径核验（无问题）**：记录存储迁移读取 `WatchPreferences.shared.data(forKey:)`，经与原实现比对（`UserDefaults.standard` 同键 `watch_scoreboard_records`、`WatchPreferences` 无键名转发、默认 `.standard` 同一 suite），旧数据可被正确迁移，不存在升级丢记录风险。

## 建议修复顺序

1. P0 手表九球 v2 意图分派（一处视图改动 + 测试转绿）。
2. P1-3 三个 64KB 体量点（增量动作 / 逐条发送 / 完赛分片），属于"用户打久了必坏"的定时炸弹。
3. P1-1 白名单三层对齐（先定产品口径再动代码，5 项目联动是现成能力的"最后一公里"）。
4. P1-2 绿底黑字按钮逐处改白（低风险、直接对齐既有项目规则）。
5. P2/P3 按排期消化。
