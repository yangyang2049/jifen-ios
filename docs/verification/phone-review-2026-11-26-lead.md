# 手机端未提交改动复审（3.4.3，2026-11-26 10:30 快照，agent: phone-review）

## 0. 范围与说明

- 分支 `3.4.3`，全部改动未提交、无 staged。本报告只审**手机端**（`jifen/`、`jifenTests/`、`jifenUITests/`、`jifen.xcodeproj`），不含手表端与 Localization 表内容审查（§4 只给闸门状态）。
- 基准：`docs/verification/full-uncommitted-review-2026-11-26.md`（03:35 快照）的手机端章节（其 §3、§4）逐条复核。
- **工作区在审查期间仍被并发修改**（`SportsSetupSettingsSection.swift`、`en.lproj/Localizable.strings` 在 10:09 之后仍有编辑），结论以文中标注的读取时点为准。
- 审查代理在验证编译失败时做了一处**最小修复并保留在工作区**：`jifen/Features/Home/Components/SportsSetupSettingsSection.swift:22` 补上缺失的 `@State private var eightBallRaceTipVisible = false`（见 P0-1）。除此之外未改动任何代码。

## 1. 结论摘要

- **编译**：10:00 实测手机 scheme 编译失败（P0-1，缺 @State，exit 65）；补一行修复后 **BUILD SUCCEEDED**。
- **单测**：`jifenTests` **1075 通过 / 2 失败 / 1 跳过**；2 个失败均在 `LocalizationIntegrityTests`（Localization 表范围，见 §4），重点新增套件全绿。
- **UI 测试**：`GroupMatchSetupUITests` 4 例中 `testActivityStartScoringShowsFinalizedSetupForEverySportAndFormat` 两次运行均失败（第二次单跑复现，同一失败点：第二次 launch 后 `group_create` 不出现），判定为该用例自身的顺序/fixture 问题，见 P2-N1。
- **旧问题**：P1-1、P1-2、P1-3 已修复；手机 P2-1~9 中 1/2/4/5/6 已修复或已变化，3/8/9 仍在。
- **删除文件**：`NationalDayCampaign` / `NationalDayMembershipSheet` / `NationalDayCampaignTests` 删除干净，无残留。

## 2. (A) 旧问题复核表

| 旧编号 | 旧位置 | 现状 | 当前位置与说明 |
| --- | --- | --- | --- |
| P0-1 WatchLinkIntro 用 .xcstrings 绕过表约定、完整性测试红 | jifen/Resources/WatchLinkIntro.xcstrings | **已修复** | `.xcstrings` 已不存在（`ls jifen/Resources/*.xcstrings` 为空），改为 en / zh-Hans / zh-Hant 三个 `.lproj/WatchLinkIntro.strings`（连同三套 `WatchLinkIntroArtwork-<locale>` imageset）。`LocalizationTestSupport` 只按 `.strings` 读表，现在能打开；`testExplicitLocalizationTablesHaveEnglishFallbackAndMatchingTranslations` 对 WatchLinkIntro 已通过（专用表允许仅部分语言、en 兜底）。pbxproj 为 FileSystemSynchronizedRootGroup，无 WatchLinkIntro.strings 残留引用（pbxproj 中只剩 `WatchLinkIntroLaunchTests.swift` 的 4 处注册，属测试文件）。单测 `WatchLinkIntroPresentationTests`（5 例）+ `WatchLinkIntroArtworkTests`（1 例；MARKETING_VERSION=3.4.4 与 releaseVersion 对齐、未 XCTSkip，真实校验了三套素材 Contents.json 与文件）全部通过。附注：文件名 `WatchLinkIntroLaunchTests.swift` 与实际类名不一致，见 P2-N4。 |
| P1-1 回放弹层多「在手表开始」，误点建交互会话 | ShotTrainingSetupDialogView.swift:44-47 | **已修复** | 新增 `allowsStartOnWatch: Bool`（默认 false）参与 `canStartOnWatch`（ShotTrainingSetupDialogView.swift:35,45-49,54,60）。回放入口 `ScoreboardRecordDetailPage.swift:979-984` 不传该参数 → 回放弹层无手表按钮；唯一传 true 的入口是 HomeTab.swift:1046-1048（首启）。 |
| P1-2 群组「活动排阵开赛」硬编码赛制覆盖小组默认 | GroupMatchSetupSection.swift:44-53（旧） | **已修复** | `GroupMatchSetupBridge.rules(from:sport:base:)` 现以 `var rules = base` 起步（GroupMatchSetupSection.swift:36-41）：羽毛球只重算 pointsToWinSet/pointCap（:43-51），乒乓球只重算分数（:52-57），winByTwo/useRallyScoring 全部继承小组默认；匹克球从草稿取（:74-79）且有并列选项控件。新增 `GroupMatchSetupRulesTests` 5 例（含 testBadmintonPreservesGroupScoringAndDerivesTheCap）全绿。排阵入口仍无净胜两分/每球得分开关，但语义已从「静默改写」变为「保留小组默认值」，摘要行即时展示（:92-102）。 |
| P1-3 乒乓球分数档覆盖后台 ruleOptions | SportsSetupDraft.swift:11 / GroupSupportViews.swift:283 | **已变化（基本修复）** | 群组定稿入口改传 `sportCapability?.ruleOptions?.pointsToWinSet`（GroupForms.swift:164,223-225,235-237）；bridge.draft 在当前值不在服务端档位时写入自定义文本（GroupMatchSetupSection.swift:26-29）。UI 夹具按后台契约给 tableTennis [7,9,11,15]（GroupRepository.swift:826，注释标明对齐后台夹具）。残留边界见 P2-N3。 |
| P2-1 notifyMatchFinished 写 latestRemoteSnapshot 语义混用 | PhoneWatchLinkSession.swift:567 | **仍在（语境变化）** | PhoneWatchLinkSession.swift:567-573 主控端完赛仍写 `latestRemoteSnapshot`。但新代码里它已是完赛状态载体：`linkedResumeDescriptor`（PhoneWatchLinkService.swift:337-345）依赖它维持 GameBar，`leaveSessionIfMatchFinished`（PhoneWatchLinkSession.swift:496-501）改为按 completedMatchIds 判定。消费方均有 sessionId/role 守卫，风险未扩大；保持 P2，建议后续拆出 `lastFinishedSnapshot`。 |
| P2-2 hasLaunchPriority 抑制微信绑定弹层/VIP 卡 | MainTabView.swift:52-58、HomeTab.swift:506 | **已修复** | MainTabView.swift:53 与 HomeTab.swift:506 均改判 `watchLinkIntro?.reservesLaunchPresentation`（= hasLaunchPriority && !wasDismissed，WatchLinkIntroSheet.swift:41）。评分邀请抑制改用 `suppressed:` 参数（jifenApp.swift:556 + AppReviewPrompt.swift:76,86），并删除 NationalDay 门（与删除文件一致）。 |
| P2-3 releaseVersion 与 MARKETING_VERSION 双写 | WatchLinkIntroSheet.swift:16、pbxproj | **仍在** | `releaseVersion = "3.4.4"`（WatchLinkIntroSheet.swift:16）与 pbxproj `MARKETING_VERSION = 3.4.4` 双写。缓解：`WatchLinkIntroArtworkTests` 在版本不匹配时 XCTSkip 并注明（WatchLinkIntroLaunchTests.swift:94-96），不再假绿；但版本一改整条介绍链（弹层+素材校验）静默失效的结构仍在，建议构建脚本注入。 |
| P2-4 羽毛球局数 chip 过滤后不含当前值 | GroupSupportViews.swift:268-271 | **已修复** | GroupSupportViews.swift:268-270（局数）与 :281-283（分数）改为「当前值不在档位时并入选项并排序」。但新定稿赛制区（SportsSetupSettingsSection）的局数 chips 未做同样处理，见 P2-N2。 |
| P2-5 setupDraft 只在 initialize 播种一次 | GroupForms.swift:222 | **已修复** | GroupForms.swift:219-226 新增 `.onChange(of: serverDefaultRules)`：capabilities 迟到时（previous == nil 且用户未自定义）重新播种 setupDraft。 |
| P2-6 训练每投全量同步约 30KB/包 | ShotTrainingScoreboardView.swift:695,902（旧） | **已变化（基本修复）** | 快照改用 `LinkedShotTrainingState` 的 packedShots（Int64 位打包）+ `maxDetailedShots = 2048` 溢出并入 earlierCounts（Packages/JifenCore/Sources/LinkCore/LinkedShotTrainingState.swift:86-113）；新增 `testLargeLinkedTrainingKeepsTotalsWithinWatchConnectivityLimit` 断言编码 < limit/2+2KB。仍是每投全量快照但体积有界、总计不丢。 |
| P2-7 训练草稿写入条件与 scoringLocked 口径不一致 | ShotTrainingScoreboardView.swift:147 vs 940 | **已变化（口径统一为有意设计）** | saveRecord（现 :941）在挂表会话未结束时显式跳过草稿落盘，菜单过滤（:566-570）同样按 scoringLocked 过滤 undo/reset/finish；完赛才落盘。挂表期间进程被杀时手机端依赖 phone_link context 快照恢复、本地无 live 简历，属契约变化，建议在文档注明。 |
| P2-8 官方中断同步逻辑逐行重复 | Tennis 2081 / Rally 2240 | **仍在** | TennisScoreboardView.swift:2080-2112 与 RallyScoreboardView.swift:2236-2268 的 completeOfficialBreak / applyRemoteOfficialBreak / syncOfficialBreakFromState 依旧逐行重复（本次 diff 还同步改了两份）。可延后。 |
| P2-9 音频测试断言 .started 无 CI 兜底 | TimerAndToolOfflineTests.swift:67 | **仍在** | TimerAndToolOfflineTests.swift:60-80 仍断言 playSound/toggleSound == .started。本次模拟器实测通过；无音频输出的 CI 仍有环境性红风险。 |

## 3. (B) 新发现问题

### P0（必须改）

**P0-1 `eightBallRaceTipVisible` 未声明，手机 scheme 编译失败（已当场修复，修复必须保留）**
- 位置：`jifen/Features/Home/Components/SportsSetupSettingsSection.swift:567,571,583`（引用）；:22（本次审查补上的声明）。
- 现象：10:00 实测 `xcodebuild -scheme jifen build` exit 65，3 处 `cannot find 'eightBallRaceTipVisible' in scope`。03:35 旧报告时该文件还能编译，说明快照之后有人改了黑八「抢局」设置区但未做编译验证。
- 影响：整个手机端无法构建、无法出包。
- 处置：已补 `@State private var eightBallRaceTipVisible = false`（:22）并复验 BUILD SUCCEEDED。**该一行修复必须随本批提交**。另注意 10:09 的并发编辑把键名从 `eight_ball_race_label/help` 改为 `eight_ball_race_to/eight_ball_race_help_detail`（后者已存在于语言表），提交前需与该改动一起复核。

### P1（本迭代该改）

**P1-N1 本地化完整性闸门仍红：watch-link 词族只进了 en/zh-Hans 两张表，其余 45 个语言缺键**
- 位置：`jifenTests/LocalizationIntegrityTests.swift:881`（`testEveryStaticLocalizationKeyExistsInItsTarget`；10:20 定向复跑失败，45 个语言表报缺键）。
- 缺键族（~90 键，均为本次手机端新 UI 引用）：`linked_score_*`（takeover/reject/force_takeover/setup_exit_*/watch_reclaim_*/start_on_watch 等）、`watch_sync_*`、`watch_set_end_format`、`game_over_new_game_on_watch`、`clear_data_category_watch`（引用点：UnfinishedGameBarView、WatchLinkMenuSupport、PhoneWatchLinkService、jifenApp、WatchLinkSettingsView、TwoSideScoreboardScaffold、各计分页）。
- 影响：发版闸门红；45 个语言用户在未完成比赛条、联动菜单、设置页看到兜底文案。键族由本次手机端 UI 引入，决策权在手机端 owner。
- 建议：二选一——(a) 把该词族迁入专用表（如 `WatchLink.strings`，en + zh-Hans/zh-Hant 人工译文即可，与 `QRScan`/`WatchLinkIntro` 同路；专用表允许其余语言回退 en，测试即绿）；(b) 由 Localization agent 给 45 张表补英文兜底。不要让 Localizable 主表长期 en/zh-Hans 与其余 45 表键集不一致。
- 附带：`testLocalizedResourcePairsStayInSync` 亦红——ar 缺 `home_all_items`，en↔ar 键集差 259 个（HEAD 时 271，本次净收敛 12 个：linked_score_accept/control_timeout/error_title/persistence_failed/phone_started_scoreboard/reject/sync_timeout/takeover、tab_tools、watch_link_title、watch_sync_hero_title、eight_ball_race_to 已补入 ar）。其余归 Localization 在途工作收口。

### P2（可延后）

**P2-N1 `GroupMatchSetupUITests` 的 8 连发用例两次运行均失败（自测用例缺陷，非产品代码缺陷）**
- 位置：`jifenUITests/GroupMatchSetupUITests.swift:11-19`（单测体循环 8 次 launch）与 :96-98（launch 断言）、:161-162（tap 断言）。
- 现象：两次运行（全套 10:14、单跑 10:30）同一失败模式：第 1 个 launch（badminton/doubles）正常走完，**第 2 个 launch（badminton/singles）后 `group_create` 按钮 20s 内不出现**，随后 `group_card_ui-group` 等不到、app 被终止报 "is not running"。同批另 2 个用例（各 1 次 launch）通过，走同一条 launch/openActivityMatchSetup 路径。
- 分析：连续第 2 次 `XCUIApplication.launch` 后首页 fixture 未就绪（首次会话遗留状态或第二次启动走冷路径），测试自身缺 fixture 就绪等待；不构成对被审产品代码的拦截，但**该新增 UI 用例当前不可用作验收**。
- 建议：拆成 8 个独立测试方法，或在 launch() 里对 `group_create`/`group_card_ui-group` 增加就绪重试；先在干净模拟器（erase）复跑确认。

**P2-N2 定稿赛制区局数 chips 不回填当前值**
- 位置：`SportsSetupSettingsSection.swift:928-975`（matchCompletionPresets chips 与自定义输入切换）、对照已修复的 `GroupSupportViews.swift:268-270`。
- 现象：小组默认局数不在预设（如 badminton best_of=2、play_all=5）时，chip 全部未选中、自定义输入框为空，但提交值仍是 2/5——用户看不出当前生效值。建议在 bridge.draft 里像 customPointsText 一样给 customMaxSetsText 回填。

**P2-N3 ruleOptions 缺失时定稿入口回落本地档位**
- 位置：`SportsSetupSettingsSection.swift:687-688`（`groupPointPresets ?? draft.pointPresets(for:)`）。
- 现象：`sportCapability?.ruleOptions?.pointsToWinSet` 为 nil（capabilities 缺 ruleOptions 但 supportsCustomRules=true）时，乒乓球回落 [7,9,11,15]，其中 9 可能不在后台白名单；提交端只有 `rules.isValid` 无白名单校验。概率低（usesSharedSetup 已要求 capabilities 存在）。建议回落时仅用 defaultRules.pointsToWinSet 单档兜底。

**P2-N4 测试文件名与实际类名不一致**
- 位置：`jifenTests/WatchLinkIntroLaunchTests.swift`（内含 `WatchLinkIntroPresentationTests` + `WatchLinkIntroArtworkTests`）。任务/文档按 "WatchLinkIntroLaunchTests" 引用会找不到对应类，改名或加文件头说明。

**P2-N5（继承旧报告联动 P2）retired 会话仍无上限、主控端 retired 的「再来一场」仍无接受路径**
- 位置：`Packages/JifenCore/Sources/LinkCore/LinkCore.swift` `LinkRetiredRecordSessions` / `LinkRecordSession.accepts`。
- 现状：本次新增 `removeConfirmedSession`（手表 sessionLeft 且 handle/epoch 匹配时移除）与 retire 去重，增长压力缓解；但仍无数量/天数上限。`accepts` 对 generation> 仍要求 `allowsPeerNextMatch == true`（仅跟随端 retirement 满足）——主控端 retired 会话若手表「再来一场」，完赛消息仍无接受路径，需真机确认（与旧报告联动 P2-2 同源）。

## 4. (C) 构建 / 测试实测

- 批次：`~/Library/Developer/jifen-ios-test-artifacts/runs/20261126T015742265260Z-phone-review-2026-11-26`（`test_artifacts.py new-run phone-review-2026-11-26 --active`）；DerivedData 复用 `~/Library/Developer/Xcode/DerivedData/jifen-phone-check`，全部 xcodebuild 输出/-resultBundlePath 显式指向批次目录。
- 构建：
  - 10:00 `xcodebuild -scheme jifen -destination 'generic/platform=iOS Simulator' build` → **FAILED**（exit 65，P0-1，3 error；`build-jifen2.log`）。
  - 10:01 补一行修复后 → **BUILD SUCCEEDED**（`build-jifen3.log`）。
- `xcodebuild test -only-testing:jifenTests`（iPhone 17 Pro 模拟器，10:02-10:03）：**1075 通过 / 2 失败 / 1 跳过**（`jifenTests.xcresult`）。
  - 失败：`LocalizationIntegrityTests.testEveryStaticLocalizationKeyExistsInItsTarget`、`testLocalizedResourcePairsStayInSync`（P1-N1）。首次运行时 en/zh-Hans 还缺 3 个 eight_ball_race_* 旧键；10:09 并发编辑把键改名（race_to/help_detail，表中已有）后，10:20 定向复跑确认 en/zh-Hans 已过、仅剩 45 语言缺 watch-link 词族 + en↔ar 键集差。
  - 通过：`GroupMatchSetupRulesTests`（5）、`PhoneWatchLinkServiceTests`（含 takeover/context/retired/large-payload 新用例）、`ScoreboardMenuConfirmStateTests`、`ShotTrainingTests`（含 linked/standalone 记录投影与包体积用例）、`TimerAndToolOfflineTests`、`WatchLinkIntroPresentationTests`（5）、`WatchLinkIntroArtworkTests`（1）。跳过 1 例为 `GroupPushAPNsProbeTests`（无 APNs 环境）。
- `xcodebuild test -only-testing:'jifenUITests/GroupMatchSetupUITests'`：4 例 2 过 2 失败（`groupmatch-uitests.xcresult`）；随后单独复跑 `testActivityStartScoringShowsFinalizedSetupForEverySportAndFormat` 仍失败且同一失败点（第 2 次 launch 后 fixture 未就绪）——判定为用例自身缺陷（P2-N1），非产品代码回归。
- 批次收尾：`python3 scripts/test_artifacts.py finish <batch> --failed`（存在未解失败，按 AGENTS 规则留证）。

## 5. (D) 删除文件残留检查

- `jifen/Features/Membership/NationalDayCampaign.swift`、`NationalDayMembershipSheet.swift`、`jifenTests/NationalDayCampaignTests.swift` 三个删除干净：
  - `grep -rn 'NationalDay' jifen jifenTests jifenUITests jifen.xcodeproj Packages` → **零命中**；
  - pbxproj 的 BuildFile / FileReference / Group 同步移除；
  - 唯一引用点 `AppReviewPrompt` 的 `NationalDayCampaignReviewGate.blocksReviewToday()` 守卫一并删除，改为 `requestsReviewOnEligibleLaunch(suppressed:)`（AppReviewPrompt.swift:76,86,101），与社群邀请卡的互斥逻辑保留。
- 结论：删除无残留，活动日不弹评分邀请的行为按设计移除。

## 6. 处置建议（手机端 owner）

1. **保留 P0-1 的一行修复**（SportsSetupSettingsSection.swift:22），并在提交前与 10:09 的键名并发改动一起复核、跑一次构建。
2. 对 P1-N1 做词族迁移/补翻决策并同步 Localization agent——这是当前唯一的红闸门。
3. P1-1/P1-2/P1-3 已闭环，无需再动；P2-N2/P2-N3 建议随下次触规定稿赛制区时顺手修；P2-N1 修复 UI 用例后再作为验收证据。
