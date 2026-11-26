# 未提交改动全量审查（3.4.3 工作区，2026-11-26 03:35 快照）

## 0. 快照与范围

- 分支 `3.4.3`，工作区 **278** 条未提交条目，**无 staged**；`197 files changed, +7858 / −3563`。
- 剔除手机端 Localization（另一个 agent 在途）后，本次实审 **135** 个路径：手机端 ~87、手表端 51、联动层 27。
- **本报告不评价** `jifen/Resources/*.lproj/Localizable.strings`、`scripts/localization/**`、`jifenWatch Watch App/Resources/*.lproj/**`。
- 快照之后的工作区仍有变动（如 `BasketballSessionStore.swift` 在快照前才变脏），结论以本次读到的内容为准。

## 1. 结论摘要

| 层 | 结论 | 阻塞项 |
| --- | --- | --- |
| 手机端 | 可上线，1 个入口越界（P1-1） | 无 |
| 手表端 | 可上线，2 处可见布局/命中区回归 | 无 |
| 联动层 | 结构比旧版更稳（重试、ACK、retired session 三个洞都补了） | 无 |
| 测试闸门 | 两端编译通过；手机 1072 例通过、**1 套件红**；手表 7 套件全绿 | **P0-1 本地化完整性** |

**必须改（本迭代）**：P0-1；P1-1（训练回放误入联动）、P1-2/P1-3（群组赛制口径与后台契约）、P1-4（手表写库失败静默丢记录）。
**可随后续小版本**：P1-5、P1-6 与全部 P2。
**因 Localization 跳过**：手机 50 个 `Localizable.strings`、`scripts/localization/**`、手表 `*.lproj`。P0-1 中第 3 例失败属于该在途工作，不计入本次改动。

## 2. 构建与测试（本次实测）

| 命令 | 结果 |
| --- | --- |
| `xcodebuild -scheme jifen build`（iOS Simulator, Debug） | **BUILD SUCCEEDED** |
| `xcodebuild -scheme 'jifenWatch Watch App' build`（watchOS Simulator, Debug） | **BUILD SUCCEEDED** |
| `xcodebuild test -only-testing:jifenTests` | 1072 例通过，`LocalizationIntegrityTests` 3 例失败 |
| `xcodebuild test -only-testing:'jifenWatch Watch AppTests'` | 7 套件全部通过 |

新增的 `GroupMatchSetupRulesTests`、`GroupMatchSetupUITests`、`WatchLinkIntroLaunchTests`、`WatchLinkedSetupConfirmDeadlineTests` 均已正确注册并实际执行；工程用 `PBXFileSystemSynchronizedRootGroup`，新 Swift 文件/图片/`.xcstrings` 无需手改 pbxproj（实测编译通过即证明已入包）。

## 3. P0

### P0-1 新增 `WatchLinkIntro.xcstrings` 绕过仓库本地化表约定，完整性测试红

- 位置：`jifen/Resources/WatchLinkIntro.xcstrings`（新增）、`jifen/Features/Home/Components/WatchLinkIntroSheet.swift:95,101,112`、`jifenTests/Support/LocalizationTestSupport.swift:60-75`
- 现象：仓库里额外语言表都用 `*.lproj/*.strings`（`QRScan.strings`、`ScoreVoice.strings`、`VIPCommunity.strings`、`ParticipantIdentity.strings`），`LocalizationTestSupport` 也只按 `.strings` 读表。新增表用 `.xcstrings`，于是：
  - `testEveryStaticLocalizationKeyExistsInItsTarget`：`未能打开文件 "WatchLinkIntro.strings"，因为它不存在`
  - `testExplicitLocalizationTablesHaveEnglishFallbackAndMatchingTranslations`：同一原因
- 影响：发版前的本地化闸门红，与另一 agent 的 Localization 改动无关、不会被其修复。
- 建议：把 `WatchLinkIntro` 导出为各 `.lproj/WatchLinkIntro.strings`（与 `QRScan` 同路），或让 `LocalizationTestSupport` 支持 `.xcstrings` 解析；二者取一即可，不要同时留两套来源。
- 附注：同批第三例 `testLocalizedResourcePairsStayInSync`（en/ar key 集不一致、ar 缺 `tab_tools`）属 Localization 在途工作，归该 agent。

## 4. 手机端

### P1-1 记录回放弹层多了「在手表开始」，误点把回放变成只读跟随页

- 位置：`jifen/Features/Home/Components/ShotTrainingSetupDialogView.swift:44-47,136-150`；复用点 `jifen/Features/Records/ScoreboardRecordDetailPage.swift:979`
- 现象：`canStartOnWatch` 只判 feature flag，没有「本入口是否允许」开关；同一个弹层既用于首页/计分页首启，也用于记录回放。回放时点手表按钮会真的建交互式会话，`startReplay` 带 `linkedWatchSessionId` 进入 `ShotTrainingScoreboardView`，`scoringLocked` 为真 → 回放不可计分，还留下一条无用会话。
- 建议：弹层加 `allowsStartOnWatch: Bool = true`，回放入口传 `false`。

### P1-2 群组「活动排阵开赛」硬编码赛制，覆盖小组默认

- 位置：`jifen/Features/Groups/GroupMatchSetupSection.swift:44-53`
- 现象：羽毛球强制 `winByTwo = true`、`useRallyScoring = true`；乒乓球强制 `useRallyScoring = true`（`winByTwo` 继承 base）。而：
  - 小组默认 `useRallyScoring = (sport == .pickleball)`，羽毛球为 **false**（`jifen/Features/Groups/GroupRepository.swift:813`）
  - 「直接开赛 / 补记」入口仍暴露「净胜两分」「每球得分」开关（`jifen/Features/Groups/GroupSupportViews.swift:289-292`）
  - 排阵区本身不提供这两个控件
- 影响：同一小组两条开赛入口算分口径不同；小组默认被静默改写且赛内无法改回，公告摘要与实际提交值随之漂移。
- 建议：bridge 继承 `base.winByTwo`/`base.useRallyScoring`，或把两个开关补进共享赛制区并同步下调 `GroupRulesFields`。

### P1-3 乒乓球分数档覆盖后台 `ruleOptions`

- 位置：`jifen/Features/Home/Models/SportsSetupDraft.swift:11`（`pingpongPointPresets = [7,9,11,15]`）、`jifen/Features/Groups/GroupSupportViews.swift:283`、后台契约 `jifen/Features/Groups/GroupRepository.swift:823`（`pointsToWinSet: [7,11,15,21]`）
- 影响：客户端可提交 9 分（不在后台白名单，若校验即 `invalid_rules`），21 分档位消失。本机预约页（`CreateBookingPage.swift:497`）用同一常量，但无后台契约约束。
- 建议：群组侧以 `options.pointsToWinSet` 为准，仅做增量补齐。

### P2（手机）

1. `notifyMatchFinished` 把主控端自己的完赛快照写进 `latestRemoteSnapshot`（`jifen/Core/Link/PhoneWatchLinkSession.swift:567`），语义被混用；当前靠各页 `isFollower` 守卫兜住，将来新页面容易误用。
2. `MainTabView.swift:52-58`、`HomeTab.swift:506` 用 `hasLaunchPriority`（启动期恒真）做抑制条件：介绍页被关掉后，本次启动的微信绑定升级弹层与 VIP 社群邀请卡都不再出现。建议改判 `!wasDismissed`。
3. `WatchLinkIntroPresentation.releaseVersion` 与 pbxproj `MARKETING_VERSION` 双写（当前都 3.4.4 对齐）；版本号一改整条引导链连同素材校验静默失效。
4. 羽毛球局数 chip 过滤后可能不含当前值 7，显示未选中但提交 7（`GroupSupportViews.swift:268-271`）。
5. `GroupForms.swift:222` 的 `setupDraft` 只在 `initialize()` 播种一次，capabilities 迟到时用占位默认值冒充小组默认。
6. 训练每投全量同步（快照含 `packedShots` 上限 2048 + 全量动作，单包约 30KB，`ShotTrainingScoreboardView.swift:695,902`），长训练会积压 durable 队列。
7. 训练草稿写入条件与 `scoringLocked` 口径不一致（`ShotTrainingScoreboardView.swift:147 vs 940`）。
8. 官方中断同步逻辑在 `TennisScoreboardView.swift:2081` 与 `RallyScoreboardView.swift:2240` 逐行重复。
9. `TimerAndToolOfflineTests.swift:67` 断言真实音频播放 `.started`，无音频输出的 CI 会环境性红。

### 手机端已核对无问题

`NationalDayCampaign`/`NationalDayMembershipSheet`/`NationalDayCampaignTests` 删除干净：pbxproj 的 BuildFile、FileReference、Group 三处同步移除，全仓库无残留符号。`AnyCodable` 补 Int64/Float 分支与 `watchSyncTime` 改用 `Int` 自洽。`MenuDialog` 的 `item.confirming` 白字符合仓库绿色按钮规范。`SoundManager` 并发/generation/delegate 保活无回归。

## 5. 手表端

### P1-4 完赛写库失败被静默吞掉

- 位置：`WatchRecordManager.swift:51-52`（`@discardableResult` 返回 Bool）；丢弃返回值的调用点：`WatchFootballScoreView.swift:1074`、`WatchRallyScoreView.swift:1187`、`WatchTennisScoreView.swift:1209`、`WatchNineBallScoreView.swift:818`、`WatchSnookerScoreView.swift:663`、`WatchArcheryScoreView.swift:812`、`WatchEightBallScoreView.swift:252`、`WatchBasketballTrainingView.swift:662`
- 现象：写盘失败后照样 `resumeStore.clear()` 并弹「比赛结束」。
- 影响：记录静默丢失且无法续玩恢复。新联动路径（`WatchLinkedRecordIngestor`）已有 `reportPersistenceError`，这些本机路径没有。
- 建议：统一处理 `false` → 不清续玩 + 失败提示，复用计数器的 `showSaveFailure`。

### P1-5 竖板训练格：`.offset` 在 `.background` 之前

- 位置：`WatchBasketballTrainingView.swift:399-403`
- 现象：整格（含背景与命中区）从 y=16 开始，屏幕顶部 16pt 只剩黑底且不可点；「未中」格比「命中」格少 16pt 可见高度。
- 建议：背景铺满整块，只对内部内容做 `.padding(.top, 16)`。

### P1-6 运动设置数字宫格命中区降到 36×36

- 位置：`WatchSportsSetupView.swift:530-570`（`SetupChipMetrics.side = 36`，行高 36、间距 8），调用点 `:405-415`
- 影响：局数/每局分数最常连点，低于 watchOS 44pt 建议，误触会把错误规则带进记分板。
- 建议：视觉保持 36，用 `.padding(4).contentShape(Rectangle())` 补到 44pt 命中区。

### P2（手表）

1. 相对时间 0–59 秒显示未来时态（`WatchRecordListView.swift:131-146`：`minutes == 0` 仍传 `minute: 0` → `in 0 min.`/`0分钟后`）。
2. 计数器保存成功不再 `dismiss()` 也无提示（`WatchCounterView.swift:174-180`），与「结束并保存」文案矛盾。
3. 射箭休息层未传 `isReadOnly`（`WatchArcheryScoreView.swift:125-133` 对比 `WatchRallyScoreView.swift:268-270`）；且只读态无本地关闭出口，手机丢了 `officialBreakState = nil` 时遮罩永久停留。
4. `WatchResumeActions.xcstrings` 同样偏离 `.strings` 约定（手表无对应测试守护，暂未红）。

### 手表端已核对无问题

导航/路由状态机（`exitScoreboard(sessionId:)` 按「是否已发布完赛」分流、完赛弹窗、二次确认倒计时）自洽；`WatchLinkedSetupConfirmationView` 的 deadline 兜底口径（`LinkedSetupConfirmDeadline`）与新增测试一致；`WatchLinkedRecordIngestor` 的投影字段与手机端 `LinkedMatchRecordIngestor` 对齐。

## 6. 联动层（手机 ↔ 手表）

### 已修好的三个真实洞（本次改动的主要价值）

1. **完成消息的 ACK 键错了**：`PhoneWatchLinkSideChannels.swift:52-70` 现在回传 `payload.id`（手表原始 id），此前回传手机归一化后的 id，导致手表 pending 队列清不掉、反复重推。
2. **主控端完赛未真正落盘**：`notifyMatchFinished` 把 `terminalOutbox.enqueue` + `persistTerminalOutbox` + `persistContext` 提到同步段，再异步 `enqueueDurable` + 可达时 `sendRealtime`（`PhoneWatchLinkSession.swift:557-590`、`WatchLinkSession.swift:320-380` 同构），进程被杀不再丢完赛消息。
3. **会话已结束后的迟到重试无处可去**：新增 `LinkRecordSession` / `LinkRetiredRecordSessions`（`LinkCore.swift:733-809`），两侧 `handleMatchFinishedFromWatch/FromPhone` 改为「活会话 → retired 会话」两级接受，并对重复 `matchId` 直接重发 ACK。
4. 附带修正：`clearPendingWatchRecords` 在不可达时改走 `transferUserInfo` 兜底（`LinkCore.swift:1725-1740`），手表 `didReceiveUserInfo` 已接 `onClearPendingRequest`（`:1799`）；`WatchConnectivityTransport.status` 未激活时返回中性值，不再触发 `WCSession has not been activated` 警告。

### P2（联动）

1. **版本门与新增 case 未同步**：`LinkProtocol.currentVersion` 仍是 1，但 `LinkedScoreboardSnapshot` 新增了 `basketballTraining`。手机新/手表旧混跑时旧端解码失败并静默丢弃 `matchFinished`，且不会 ACK → 旧端无限重试。建议随协议新增 case 升 `currentVersion` 或在解码失败时回 ACK+诊断。
2. **retired 会话只接受 generation ≤ 记录值**（`LinkCore.swift:759-763`）：手表「再来一场」递增 generation 后，若该会话已 retired，完赛消息没有接受路径 → 无法 ACK、无限重试、记录到不了手机。需真机确认 rematch 是否可能发生在 retired 会话里；若能，放宽为「同 sessionId 且 generation ≥」并保留 `completedMatchIds` 去重。
3. `LinkRetiredRecordSessions` 只增不减（仅 `clear()` 清空），条目随时间线性增长并常驻 UserDefaults；建议加 N 天/session 数上限。
4. 同一「未中/命中」在两端用了不同 key：手机 `shot_training_miss/made`（`WatchLinkMenuSupport.swift:260-268`），手表 `watch_training_miss/made`（`WatchLinkService.swift:641-643`）。语义相同、翻译需各自维护，容易一语言里只剩一侧。

### 两端一致性核对（通过）

- 联动支持项目白名单三处一致：`AppFeatureFlags.isWatchLinkSupportedProject`、`PhoneWatchLinkService.phoneInteractiveStartSupported`、`WatchLinkSession.isValidLinkedSetup`（含本次新增 `basketballTraining`）。
- 训练记录投影一致：双方都是 `队名=未中/命中`、`final=missed/made`、`setScore=0`、`totalScoreChanges=attempts`、`detailedActions` 由 `LinkedShotTrainingState.detailedActions(endingAt:)` 生成、`rate` 公式同源（`ShotTrainingCounts`）。
- 手机 `handleMatchFinishedFromWatch` 加了 `role == .phoneController` 守卫（`PhoneWatchLinkSession.swift:522`），跟随端不再自己发完赛 → 双记录风险消除。

## 7. 未提交产物处置建议

| 路径 | 建议 |
| --- | --- |
| `docs/verification/{group-match-setup-2026-11-25, watch-counter-finish-2026-11-25, watch-nineball-ui-2026-11-24}/` | 与既有 evidence pack 同规格，建议提交；`group-match-setup` 15 张/2.4M 偏重，按 AGENTS 只留必要截图 |
| `docs/demos/watch-link-sheet-*.{html,png}`、`docs/demos/watch-match-finish-options.html`、`demo/watch-basketball-score-proposals.html` | 设计稿/对比稿，非发布物料；若要留档建议进 `docs/demos` 并说明来源 |
| `docs/watch-basketball-evaluation-2026-11-26.md` | 评估文档，可与代码同批提交 |
| `scripts/compose_watch_link_intro_artwork.py`、`compose_watch_promo_video.py`、`generate_watch_nineball_ui_report.py` | 素材生成脚本，建议提交（`WatchLinkIntroLaunchTests` 依赖前者的产物约定） |
| `.zwork/artifacts/**` | 本地工具缓存，勿提交（当前未跟踪、未被 ignore 覆盖，注意别误 add） |

## 8. 建议修复顺序

1. P0-1 本地化表落地 → 让 `LocalizationIntegrityTests` 回绿（否则无法发版）。
2. P1-1 回放弹层禁用手表入口（一行开关）。
3. P1-2 / P1-3 群组赛制口径：先定「以小组配置为准」还是「以本机 Setup 为准」，再统一两入口与后台白名单。
4. P1-4 手表写库失败处理（8 处，机械改动）。
5. P1-5 / P1-6 手表可见回归。
6. 联动 P2-1 / P2-2 需要真机验证后再定。

## 9. 复审收尾与待办

以[手机端复审](phone-review-2026-11-26-lead.md)和[手表端复审](watch-review-2026-11-26-lead.md)为准。保留黑八「抢局」提示的状态声明和 10:09 更新的两个文案键。手机 47 张主语言表对齐键和格式占位符，复用同义的现有译文，繁体缺项补齐，其余缺项先使用英文回退。

手表投篮训练保存失败后，选择重试会保留原完赛信息。选择取消会继续当前训练并移除那次尚未保存的完赛请求。如果联动完赛已经落盘，则显示完赛结果并继续等待对端确认。手表射箭 UI 测试在滚动前处理旧会话遗留的「联动失败」提示。

收尾验证通过手机构建与单测（1078 通过、1 项按需运行的 APNs 探测跳过）、手表构建与单测（135 通过）、手表 UI 冒烟（射箭平局完赛及两个投篮训练用例，3 通过）和 LinkCore 负载校验（6 通过）。本轮射箭重跑未再次弹出联动错误。手表 47 个语言及地区的覆盖与共享译文检查通过。原始结果保存在仓库外的 `20261126T025404141889Z-final-review-remediation` 批次，按保留策略过期。

| 待办 | 范围 |
| --- | --- |
| 手机开赛测试夹具 | 修复小组定稿 UI 测试第二次启动时夹具未就绪的问题，恢复完整验证覆盖。 |
| 手机小组定稿赛制 | 回填不在预设内的局数，检查服务端未返回 `ruleOptions` 时的分数档。 |
| 手机维护项 | 收敛联动介绍版本配置，统一测试文件命名，合并网球和 Rally 的官方中断逻辑，评估无音频输出环境的测试行为。 |
| 手表交互 | 扩大文字选项的命中区域，为网球及 Rally 只读休息层补失联时的退出方式。 |
| 手表测试 | 增加本地化完整性守护，将截图、素材捕获用例设为按需执行。 |
| 联动完赛状态 | 评估从 `latestRemoteSnapshot` 拆出完赛快照。 |
| 联动已退出会话 | 真机验证退出会话后「再来一场」的完赛接收路径，制定已退出会话的回收上限。 |
| 翻译 | 用本地译文替换手机主语言表里本批补齐的英文回退。 |
