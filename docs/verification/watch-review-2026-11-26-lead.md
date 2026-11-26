# 手表端全量未提交审查（watch-review-2026-11-26-lead）

- 审查时间：2026-11-26 10:20–10:45 (Asia/Shanghai)，分支 `3.4.3`，全部改动未提交。
- 范围：`jifenWatch Watch App/`（含 Components/Scoreboard/Tools/Views/Models/Managers/Resources/Assets）+ `jifenWatch Watch AppTests/` + `jifenWatch Watch AppUITests/` 的 git diff 与未跟踪新文件；联动层只看手表侧收发逻辑。不含 iPhone 端 `jifen/` 与 Localization 文案内容（他人负责）。
- 上游报告：`docs/verification/full-uncommitted-review-2026-11-26.md`（今日 03:35），其手表端结论见该报告 §1 表格、§5（P1-4/P1-5/P1-6/P2 手表四项）。
- 实测产物：批管理 run `~/Library/Developer/jifen-ios-test-artifacts/runs/20261126T021117076322Z-watch-review-2026-11-26-lead`（unit-tests/WatchAppTests.xcresult、uitests/WatchDialogConsistency.xcresult；原始证据属外部可过期项）。

## (A) 旧报告手表端问题复核

| 旧编号 | 旧位置 | 结论 | 当前位置与现状 |
|---|---|---|---|
| P1-4 完赛写库失败被静默吞掉 | WatchRecordManager.swift:51-52 + 8 处丢弃返回值 | **已修复（超出建议）** | 新增 `WatchResumeSessionStore.saveFinishedRecord`（Models/WatchResumeSession.swift:318-346）：先把记录暂存进 `watch_pending_local_finish_records` 再落库，失败返回 false 并在下次启动重试（WatchRootView.swift:136 `retryPendingFinishedRecords`）。全部完赛路径改为走该入口并在失败时弹「无法保存/重试」alert（`watchFinishSaveFailure` 修饰符，Components/WatchScoreboardComponents.swift:1256）：WatchFootballScoreView.swift:1036/1081、WatchRallyScoreView.swift:1198、WatchTennisScoreView.swift:1220、WatchNineBallScoreView.swift:819、WatchSnookerScoreView.swift:664、WatchArcheryScoreView.swift:827、WatchEightBallScoreView.swift:253、WatchBasketballTrainingView.swift:670；计数器独立路径 WatchCounterView.swift:175-178 有 `showSaveFailure`。联动路径的本地落库由 `prepareLocalFinishedRecord`（Models/WatchLinkSession.swift）+ 重发前补写（Models/WatchLinkReliability.swift:145-152）守住，ACK 只在本地记录已落库后才清 outbox 并 markSynced（Models/WatchLinkMessageHandling.swift:134-149），并有完整单测覆盖（testWatchCanStartNextMatchWithEarlierTerminalStillAwaitingACK 等 5 个新联动持久化用例）。 |
| P1-5 竖板训练格 .offset 在 .background 之前 | WatchBasketballTrainingView.swift:399-403 | **已修复** | offset 现在只作用于格内内容（Tools/WatchBasketballTrainingView.swift:400），背景与命中区随 `frame`/`background`/`contentShape(Rectangle())` 铺满整格（:401-413），顶部 16pt 恢复可点，且「未中」「命中」格可见高度一致。 |
| P1-6 运动设置数字宫格命中区 36×36 | WatchSportsSetupView.swift:530-570 | **已修复** | `numberChip` 外层补 `frame(44×44)+contentShape`（Views/WatchSportsSetupView.swift:565-584，SetupChipMetrics.minimumHitSide=44 :5-9），行高同步 `adaptiveOptionRow(height: 44)`（:489，调用点 :408）。残余：文字 `setupChip`（:540-561，让局/人数/名称等 chips）仍是 36pt 视觉高、无 44pt 补偿（非回归，旧值 38pt 反而略降，见 B-P2-2）。 |
| P2-1 相对时间 0–59 秒显示未来时态 | WatchRecordListView.swift:131-146 | **已修复** | `minutes == 0` 改用 `.named` 风格（:139-141），不再出现 "in 0 min./0分钟后"。 |
| P2-2 计数器保存成功不再 dismiss 也无提示 | WatchCounterView.swift:174-180 | **已变化（按新设计定案）** | 新 `WatchCounterSession.finish`（Tools/WatchCounterView.swift:10-46）：保存成功把数字就地清零并重置计时，留在本页继续；成功反馈=触觉 `.finish`，失败有 alert。「留在本页」已被注释为有意设计并由新 UI 测试 `WatchCounterUITests.testFinishSavesAndResetsCountInPlace` 守护。旧「与文案矛盾」的抱怨随文案与新交互口径一并收口。 |
| P2-3 射箭休息层未传 isReadOnly / 只读态无本地退出 | WatchArcheryScoreView.swift:125-133 | **已修复（做法不同）** | 射箭改为 `if let restState, !scoringLocked` 直接在锁定态隐藏休息层（Scoreboard/WatchArcheryScoreView.swift:125），并在 `scoringLocked` 变化时清空（:178-180）；显示时本地 继续/撤销 按钮始终可用。Rally/Tennis 则按旧建议走 `isReadOnly`（WatchScoreboardComponents.swift:531+；WatchRallyScoreView.swift:268-283）并新增 `OfficialBreakState` 双向映射同步手机端。 |
| P2-4 WatchResumeActions.xcstrings 偏离 .strings 约定 | — | **已收口（有意采用 xcstrings）** | 现为单键 `watch_resume_confirm_discard` 的字符串目录，47 个 locale 全部有译文（见 D 检查）；手表无对应完整性守护测试的残余风险见 B-P2-4。 |

旧报告「手表端已核对无问题」段落中的路由状态机、deadline 兜底（`LinkedSetupConfirmDeadline`）、`WatchLinkedRecordIngestor` 投影字段与手机端对齐 —— 本次复核仍然成立，且本轮补齐了对应单测。

## (B) 新发现问题

### P0

无。

### P1

无。逐文件审阅了 43 个修改文件与 7 个新 Swift 文件/资源组；重点核实过的可疑点均排除：

- 完赛消息 64KB 上限：`publishMatchFinished`（Models/WatchLinkSession.swift:305-380）超限时 `LinkFinishedEncoding.encode`（Packages/JifenCore/Sources/LinkCore/LinkFinishedEncoding.swift）先 LZFSE 压缩、再回退 `LinkEnvelopeEncoding.encodedData` 的动作历史裁剪，不会出现「长局永远发不出完赛」的回归。
- 旧端兼容：watch 侧对旧手机发来的 `basketballTraining` setup 显式拒绝（Models/WatchLinkMessageHandling.swift:75-78，有单测）；retired 会话对 generation 更大的迟到完赛接受口径（LinkRecordSession.accepts，LinkCore.swift:798-805）与「再来一场」路径有端到端单测（testNextPhoneFinishCanArriveBeforeSnapshotAndRetiredSessionDoesNotReopen）。
- 启动时 `handleApplicationContext` 被移入 `isActivated` 分支（Models/WatchLinkService.swift:244-247）不会丢迟到上下文：`WatchConnectivityTransport.activationDidCompleteWith`（LinkCore.swift:1825-1832）会触发 `deliverApplicationContextIfNeeded` 重放。
- 双击撤销进球（WatchFootballScoreView.swift:730-755）在完赛后不可达：`interactionsEnabled` 含 `!isFinished`（:1185-1191）。
- 完赛 undo 只在 finalize 之前可达（finalize 各视图都先把 `finishUndoAvailable` 置 false），不会出现「保存后又 undo 再保存产生重复记录」。
- 绿色按钮白字规则：本轮新增的 solid green/绿系按钮（完赛「再来一场」`Color(hex:0x008336)`、训练「再来一次」`WatchTheme.successGreen`、斯诺克「下一局」、休息层「继续」、设置页「开始」`glassProminent`+白 label、联动确认 ✓）全部显式 `.foregroundStyle(.white)`，符合 AGENTS.md 规则。

### P2

1. **训练完赛保存失败后棋盘静默锁死（无反馈）** — Tools/WatchBasketballTrainingView.swift:571 置 `finishSavePending = true` 后，非联动路径保存失败（:670-674 `guard resumeStore.saveFinishedRecord(record) else { showRecordSaveFailure…; return }`）与联动路径发布失败（:578-582）都不会复位该标志；`addShot`/`undo`/`reset` 的 guard（:512、:526、:534）从此静默拦截一切输入，用户只能靠重开菜单再点「结束训练」触发重试才能解锁，期间无任何提示。影响：保存失败 + 用户点「取消」关掉重试 alert 后，训练页像死机。建议：alert 取消时复位 `finishSavePending`，或改用 `savedRecordID == nil` 作为唯一门闩。
2. **setupChip（文字选项）命中区未同步补到 44pt** — Views/WatchSportsSetupView.swift:540-561：让局说明、人数、名称等文字 chip 仍为 36pt 高、无 44pt 外扩命中区（本轮反而从 38pt 视觉降到 36pt）。与 P1-6 的修复口径不一致；手表上属低频选项，故记 P2。建议同 numberChip 加 `frame(44)+contentShape`。
3. **Rally/Tennis 只读休息遮罩无本地退出出口**（旧 P2-3 第二半在 rally/tennis 的残余）— Components/WatchScoreboardComponents.swift `WatchRestOverlay` 的 `isReadOnly` 分支只渲染计时器、无按钮；跟随端若手机中途失联（快照停更），遮罩将一直停留，唯一出口是菜单里「手表接管」（requestReclaim）。有逃生门但依赖用户发现。建议：只读态超时后自动淡出或加一个极小的关闭入口。
4. **手表本地化完整性无守护测试** — `WatchResumeActions.xcstrings` 与 47 个 lproj 现在完全自洽（见 D），但手表 target 没有类似手机端 `LocalizationTestSupport` 的键位完整性测试；后续往 watch Localizable.strings 加键漏翻不会红。建议在 Watch AppTests 里补一个与手机端同口径的最小校验。
5. **捕获型 UITests 缺 skip 守护** — WatchPromoVideoCaptureUITests、WatchIntroArtworkCaptureUITests、WatchFullMatrixUITests 按 doc comment 只应显式 `-only-testing` 调用，但代码无 `XCTSkip`/环境开关；任何人跑 `test -only-testing:'jifenWatch Watch AppUITests'`（或全量 test plan）都会把它们跑起来，产生数十张 keepAlways 截图并显著拉长时长。建议在 setUp 里按环境变量 XCTSkip。

### 顺带核对（不计问题）

- WatchTabView 重新打开分页圆点（`.automatic`，Views/WatchTabView.swift:25-30）——注释给出 46/49mm 6pt 安全区实测依据，属有意回归，本轮构建+UI 冒烟未见异常。
- 黑八「抢局」档位改为 [3,5,7,13]（Models/WatchSetupModels.swift:267）：旧存档值通过 `eightBallRackValues(including:)`（Views/WatchSportsSetupView.swift:207）保留显示，与乒乓 `.pingpongPointOptions` 同口径，无「旧档位消失」问题。
- WatchRecordDetailView 恢复投篮训练「同步到手机」（Views/WatchRecordDetailView.swift:31）：手表侧 payload 构造与幂等单测齐备；手机端能否正确摄取该记录属于手机代理审查范围，需与其结论对齐。
- WatchCounterSession 在保存失败时保留计数/undo/startTime（有单测 testCounterFailedSaveKeepsCountUndoAndStartTimeUntilRetry）。

## (C) 构建/测试实测

| 命令 | 结果 |
|---|---|
| `xcodebuild -scheme 'jifenWatch Watch App' build`（watchOS 27.2 Simulator, Debug，专用 DerivedData `jifen-watch-review-lead`） | **BUILD SUCCEEDED** |
| `xcodebuild test -only-testing:'jifenWatch Watch AppTests'`（同 destination，-resultBundlePath 指向批管理 run） | **TEST SUCCEEDED：132 tests, 0 failures**（WatchLinkServiceTests 79、WatchSportsSetupTests 37、WatchScoreboardFlowTests 3、WatchRecordCacheTests 10、WatchLinkedSetupConfirmDeadlineTests 3 均绿，含全部新增联动持久化/训练路由/竞速口径用例） |
| `xcodebuild test -only-testing:'jifenWatch Watch AppUITests/WatchDialogConsistencyUITests'`（scheme `jifenWatchUITests`） | **6/7 通过，1 失败**：`testArcheryFinishUsesSharedTieLayout` 连续两次在 `tapSportTile("射箭")` 滚动辅助处断言失败（WatchDialogConsistencyUITests.swift:49）。失败时导出的 UI 层级（批管理 run 内 `uitests/WatchDialogConsistency-archery-retry.xcresult`）显示独立 watch 模拟器上系统 WCSession 弹出「联动失败 / 尚未安装配对设备版App。」alert（源：WatchRootView.swift:57-69 的 lastLinkErrorMessage alert，触发链 WatchLinkService.swift:204 `onSendError`；报错文案是 WCSession 系统本地化错误描述，仓库内无该文案），遮住首页滚动容器，导致「射箭」tile 始终不可点击。同 run 内斯诺克/足球/本地化等 6 个用例（同样走 tapSportTile 前缀路径）全部通过。**定性：测试基建/环境问题（无配对 iPhone 的独立手表模拟器 + 该用例无 dismiss 弹层步骤），非产品代码缺陷**；建议 `dismissResumeBarIfNeeded` 同步处理「联动失败」alert，或为此用例注入已配对启动参数。 |
| （说明）新增捕获型套件 `WatchCounterUITests` / `WatchFullMatrixUITests` / `WatchIntroArtworkCaptureUITests` / `WatchPromoVideoCaptureUITests` | 未执行（按任务上限只挑 1 个 UI 套件）；注意这批文件无 XCTSkip 守护（见 B-P2-5）。 |

备注：`-sdk watchsimulator` 与 `-destination` 同传会触发本机 Xcode 的链接器 filelist 指向 `Debug-iphonesimulator` 产品路径的错配（Build input files cannot be found），只用 `-destination` 即可复现成功构建；这是环境坑，不是代码问题，建议脚本统一只传 destination。

## (D) 新资源 / xcstrings / lproj 与 pbxproj 同步检查

- **pbxproj**：手表 target 使用 `PBXFileSystemSynchronizedRootGroup`（共 6 处），新增 Swift 文件、imageset、xcstrings、lproj 目录、新测试文件均**无需**手改 pbxproj；本次构建成功即证明已入包。pbxproj 本次 diff 仅新增 `WatchLinkIntroLaunchTests.swift`（iPhone 端 jifenTests 目标，非同步目录，已正确登记 BuildFile/FileReference/Group/Sources 四处）。
- **WatchResumeActions.xcstrings**：存在（`jifenWatch Watch App/Resources/WatchResumeActions.xcstrings`），sourceLanguage=en，单键 `watch_resume_confirm_discard`，47 个 locale（ar…zh-Hant）译文齐全；`WatchResumeGameBar` 以 `tableName: "WatchResumeActions"` 正确引用。
- **各语言 lproj**：Resources 下 47 个 *.lproj 全部存在且均含 `Localizable.strings`（其中 45 个整目录为本次新增，en/zh-Hans/zh-Hant 为修改）。键位完整性实测：en 377 键，其余 46 语言与 en **0 缺失 / 0 多余**。47 个 lproj 同时都有 `InfoPlist.strings`（en/zh-Hans 已跟踪，其余 45 个为新增未跟踪，成套一致）。
- **EmptyStateCourt.imageset**：存在（`Assets.xcassets/EmptyStateCourt.imageset/`，empty_state_court.pdf + Contents.json，`preserves-vector-representation` + `template` 渲染意图），与 `WatchEmptyStateCourtIcon`（Components/WatchCatalogIcon.swift:99-114）的 template 用法匹配；asset catalog 目录式发现无需 pbxproj 登记。
- **watch_coin_tails.svg**：已修改且资产被 `WatchFlipCoinView` 以 `.scaleEffect(x:1, y:-1)` 修正背面竖直镜像，引用一致。
- **未跟踪清单核对**：任务书列出的全部新文件均存在于 git status 未跟踪列表（Components/WatchLinkedSetupConfirmationView.swift、Resources/WatchResumeActions.xcstrings、45+2 个 lproj、EmptyStateCourt.imageset、5 个测试文件），无遗漏、无孤儿文件。

## 结论

手表端本次改动整体质量高于上一轮报告时的状态：旧报告的手表端 P1-4/P1-5/P1-6 与四项 P2 全部闭环（或按新设计收口），并新增了大量联动持久化单测。未发现 P0/P1；5 项 P2 中仅训练页保存失败锁死（B-P2-1）建议本迭代顺手修掉，其余可入 backlog。
