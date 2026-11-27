# iOS 3.4.4（89）版本改动清单与测试建议

日期：2026-11-26 · 分支 `3.4.3`（工作区 9 个文件未提交）

## 0. 版本边界

> 本次复核：当前工作区（含 9 个未提交文件）`xcodebuild -scheme jifen -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**（2026-11-26 11:44）；单测与 UI 测试未在本轮重跑，最近一次全量记录为手机 1078 通过 + 1 跳过、手表 135 通过。

| 项 | 值 |
| --- | --- |
| 上一版（已提审冻结） | 3.4.3 (86)，停在 `0389aaf4`（2026-11-20） |
| 本次版本 | **3.4.4 (89)**，`MARKETING_VERSION = 3.4.4`、`CURRENT_PROJECT_VERSION = 89`（手机 + 手表 4 处配置一致） |
| 提交范围 | `f14d2491` … `90be5b88`（2026-11-24 → 11-26）共 6 个提交 + 工作区未提交 |
| 改动规模 | 462 个文件，+92,012 / −3,456；手机 140、手表 223、脚本 53、测试 25、工程 3 |
| 一句话 | 手表 App 重新上线 + 19 项手机↔手表联动 + 小组活动排阵开赛定稿 + 足球/投篮训练口径统一 |

> 3.4.3 之前（台球小组一步式开赛、升级打 A、繁体台湾用语、投屏字号）已在 3.4.3 提审版本内，本清单不含。

## 1. 手机端

| # | 模块 | 改动（用户可见） | 关键实现 | 验证重点 |
| --- | --- | --- | --- | --- |
| 1 | 首启引导 | 3.4.4 首次启动展示「手机手表 · 双端计分」一次性介绍页；展示期间不叠微信绑定升级、不弹保存失败告警与评分邀请 | `WatchLinkIntroPresentation`（`WatchLinkIntroSheet.swift:6`，`watch_link_intro_seen_3.4.4`）、`MainTabView.canPresentWatchLinkIntro:44`、`jifenApp.alertUnlessWatchLinkIntro:480` | 只弹一次；跳过/关闭后微信与评分弹层恢复；素材随语言切换 |
| 2 | 开赛入口 | Setup 主按钮拆成「开始 + ⌚」，首次出现 4.8 秒引导气泡；15 类项目可推到手表 | `SportsSetupWatchSessionLauncher.swift:6`、`linkedScoreWatchStartGuide`（`SportsSetupDialogView.swift:16`，键 `linked_score_watch_start_guide_popup_shown_v1`） | iPhone 有、iPad 无；未开旗（Info.plist=false）全隐藏 |
| 3 | 设置 | 新增「手表联动」页：配对/安装/可达三态、刷新、三组使用说明与排障文案 | `WatchLinkSettingsView.swift:4`（`WatchLinkUsageTab`）、`SettingsView.watchLinkCard:327` | 三态文案真实反映 WCSession 状态；刷新不卡死 |
| 4 | 首页 | 续赛条支持手表会话：⌚ 徽标 +「双端/手表主控 · 已连接」，放弃需二次确认 | `UnfinishedGameSummary.init(linked:)`（`UnfinishedGameBarView.swift:7`）、`Source.linked`、`HomeTab.loadUnfinishedRecord` | 手表中途退出后仍可恢复；放弃只清手机侧 |
| 5 | 冲突与接管 | 双端同时改动弹「两端都改了」Toast；接管前全局确认；强制接管 | `ScoreboardLaunchView.simultaneousEditNotice:438`、`jifenApp` 的 `linked_score_force_takeover`、`MenuDialog` 新增 resync/takeover/endLink | 接管后 authorityEpoch 递增、旧端快照被拒 |
| 6 | 小组 | 活动排阵「开始计分」复用本机赛制页（经典/打满、局数、分数、封顶摘要、匹克球两枚计分方式） | `GroupMatchSetupBridge` + `GroupMatchSetupSection.swift:11/113`、`GroupMatchRules.apply(to:)` | 摘要行与实际提交值一致；冻结场次只读 |
| 7 | 小组（未提交） | 小组规则档位改回本机预设，不再读后台 `ruleOptions` | 删除 `GroupSetupSelection.pointPresets` / `SportsSetupDraft.initialize(groupPointPresets:)`；`GroupRepository.swift:826` 夹具改 `[17,19]` 作哨兵 | **提交前必须重跑构建与 GroupMatchSetup* 用例** |
| 8 | 小组 | 台球小组选人改统一成员弹层；计分面板高度贴内容，小屏不再溢出 | `GroupMatchMemberPickerSheet`、`presentationDetents([.height(...)])`（`GroupBilliardsEntryViews.swift`） | 40mm 级小屏 + 键盘态 |
| 9 | 篮球 | 菜单重组：换边归工具组、去掉哨声项、新增「自动蜂鸣」（默认开） | `BasketballMenuItemPolicy`（`BasketballScoreboardView.swift:5`）、`BasketballSessionStore.mainClockExpires:212`、键 `basketball_auto_buzzer_enabled` | 老用户升级即会响；加时同帧不重复响 |
| 10 | 足球 | 进球行显示比赛分钟 `53′ / 45+2′`；终场后比赛钟停止累计 | `FootballViewModel.snapshotAnnotation`、`FootballClockAnnotation`、`ScoreCore.FootballGoalMinute`、`endGame()` 内 `clockSession.pause()` | 补时口径、五人制半场、记录 `duration` 不再增长 |
| 11 | 拍类 | 手机可跟随手表比分，跟随期本地锁定；结束弹窗提示「再来一场请到手表操作」 | `RallySessionStore.applyAuthoritativeState:496`、`TennisScoreboardView.linkScoringLocked:173` | 跟随→接管切换；本地撤销被拦 |
| 12 | 台球/射箭 | 接受手表快照、接管、断链三类动作，菜单项与拍类统一 | `attachPage` / `latestRemoteSnapshot` / `pendingTakeoverApplication` 三段 `onChange`、`WatchLinkMenuSupport.extraItems` | 九球 3-4 人棋盘快照不丢开球人 |
| 13 | 菜单 | 仅在分享中出现「结束同步」并二次确认；计分锁定时 resync/takeover/endLink 仍可点 | `MenuDialog.swift:221/753`、`ScoreboardMenuActionPolicy` 白名单 | 非分享态无此入口；确认按钮白字 |
| 14 | 提示 | 锁定提示改「当前由手表计分」；手表发起时不再自动弹使用提示 | `ScoreboardTemplate` 菜单分支、`ScoreboardUsageHintAutomaticPresentationPolicy` | 首局手表发起无小红点/无浮层 |
| 15 | 样式 | 最近使用色保位、新色追加末尾（上限 6）；字号标题合并「文字大小（左右相同）」；自由编辑提示改 2.5 秒底部浮层 | `mergeRecentStyleColor`（`ScoreboardStyleEditOverlay.swift:187`）、`ScoreboardExternalDisplayView.animateIdleClock:572` | 旧 6 色数组被重排/截断后的显示 |
| 16 | 记录 | 手表来源记录打 `syncFrom=watch`；定宽整数/浮点不再丢值；足球/五人制/投篮不显示 0 局分 | `AnyCodable.encode`（`ScoreboardRecord.swift:1300`）、`WatchLinkMenuSupport.dropsSetScore:471` | 历史记录仍可打开；来源标识正确 |
| 17 | 运营 | 国庆会员活动整体下线，评分邀请与社群邀请互斥 | 删除 `NationalDayCampaign*` / `NationalDayMembershipSheet` / 测试；`AppReviewPrompt.requestsReviewOnEligibleLaunch(suppressed:)` | 首页无活动位；评分仍按频次弹 |
| 18 | 工具 | 掐秒挑战目标可选 1/3/5/10 秒；工具页固定 10 项；哨声/蜂鸣可重复点击停止；球局卡一键开赛；小组空态给「创建/加入」；关于页加反馈社区、FAQ 7→10 | `TenSecondChallengePolicy`、`ProToolsSectionView.HOME_TOOL_IDS:10`、`SoundManager` 改 `@Observable` | 静音设置下不启动播放；旧偏好归一为 10 秒 |
| 19 | 本地化 | 47 语种补齐联动/赛制/九球词条；新增 `WatchLinkIntro.strings`（en/zh-Hans/zh-Hant）；五人制统一为「五人制足球 / 5×5 Football」 | zh-Hans +297 键、改 9 个既有值 | 键集与占位符闸门；繁体台湾用语 |
| 20 | 数据 | 清除本地数据新增「临时手表联动状态」分类（只清手机侧，不发 leave 给手表） | `LocalDataResetCoordinator.swift:11,29`、`LocalDataResetComposition.swift:39` | 清完仍在手表上的会话不会被误删 |

## 2. 手表端

| # | 模块 | 改动 | 关键实现 | 验证重点 |
| --- | --- | --- | --- | --- |
| 1 | 应用本体 | Apple Watch App 首次随包上线：4 页签（工具/计分/记录/设置），默认停「计分」；`WKRunsIndependentlyOfCompanionApp=YES` | `WatchTabView.swift:6-30`、`WatchRootView` | 独立使用（不配对手机也能记分/存记录） |
| 2 | 首页 | 18 个胶囊入口；长按置顶（最多 2，超限提示）；九球先选 2/3/4 人、投篮训练先选 1/2/3 分/自由 | `WatchHomeTabView.swift:4-26/315-430` | 置顶满额提示；有续赛时浮条占首行 |
| 3 | 新增项目 | 足球 / 五人制足球（半场 5–90 分钟、1H/2H/加时、伤停补时、底部时钟胶囊、五人制手动开表） | `WatchFootballScoreView.swift`、`WatchFootballState.swift`、复用 `FootballMatchClockSession` | 到点琥珀色、点胶囊进下一半场、平局二选一 |
| 4 | 新增项目 | 毽子（3 局 21）、壁球（5 局 11）、桌上足球（3 局 5，决胜局净胜 2 分 + 封顶） | `WatchRallyScoreView` 复用 + `WatchSetupModels.swift:119-360` | 默认值与手机口径一致 |
| 5 | 九球 | 3-4 人：四分屏、二级选「付分人/继续击球人」、开球人球杆图标与长按切换、让杆一步直达 | `WatchNineBallScoreView.swift`、`ic_snooker_cue` 复用 | 40/42mm 顶部两格避开系统时钟 |
| 6 | 斯诺克 / 黑八 | 斯诺克局数 1–99（12 档 + 自定义）；黑八抢局档 [3,5,7,13] + 让局，旧档位保留显示 | `WatchSetupModels.swift:267`、`eightBallRackValues(including:)` | 旧存档档位不丢 |
| 7 | 投篮训练 | 竖版「未中/命中」格 + 命中率 `N/M=P%`；顶部 16pt 恢复可点；结束写六类合计 | `WatchBasketballTrainingView.swift:399-413` | 竖版命中区、模式与续玩文案 |
| 8 | 计数器 | 整屏点击 +1；「结束」保存后数字归零留在本页（触感反馈），失败弹 alert | `WatchCounterSession.finish`（`WatchCounterView.swift:10-46`） | 失败保留计数与计时，可重试 |
| 9 | 工具 | 抛硬币（内置 mp3）、随机数（1–10/1–100 + 20 条历史）、十秒挑战（目标 1/3/5/10）、计数器 | `Tools/*.swift` | 十秒结束音 `ten_second_end` 资源缺失→回落系统 click |
| 10 | 记录 | 500 条上限、单文件原子写；同步三态（已同步/等待同步/未同步）；自动同步开关（默认开）+ 手动「同步到手机」 | `WatchRecordManager.swift:15-78`、`WatchRecordDetailView.swift:305-363` | 手机 ACK 后状态翻转；关闭自动同步后仅手动 |
| 11 | 续玩 | 浮条 + 关闭钮 3 秒内联「确认放弃」；得分 750ms 防抖；完赛记录先暂存再落库，失败下次启动重试 | `WatchResumeGameBar.swift:88-130`、`WatchResumeSession.swift:318-380` | 离开页面自动收起；进程被杀后记录仍在 |
| 12 | 设置/关于 | 常用名称、联动、振动、声音、常亮、局间休息、自动同步、布局、使用说明、反馈、联系我们、（仅中文）微信群、关于 | `WatchSettingsView.swift:28-104`、`WatchSupportQRCodeView.swift:3-87` | 简中走 jifenqi.com、其他语言走 iscoreboard.live |
| 13 | 排版 | 7 类计分板队名字号统一、横竖两套排版、3D 图标（20/22pt）、40/42/46/49mm 走查 | `WatchCatalogIcon.swift`、`WatchTheme.swift` | 小屏溢出、命中区（文字 chip 仍 36pt） |
| 14 | 本地化 | 47 个 lproj × 381 键 + `WatchResumeActions.xcstrings`（47 locale）；zh-Hant 由脚本生成 | `scripts/localization/gen_watch_zh_hant.mjs`、`watch_coverage.py` | 手表 target 无完整性单测守护（缺口） |
| 15 | 清理 | 移除手表隐私协议页与「退出」流程；隐私清单只声明 UserDefaults | `PrivacyInfo.xcprivacy` | 审核问询时的口径 |

## 3. 手机 ↔ 手表联动

| # | 模块 | 改动 | 关键实现 | 验证重点 |
| --- | --- | --- | --- | --- |
| 1 | 覆盖范围 | 联动白名单 12 → **19**：新增足球、五人制、毽子、壁球、桌上足球（单/双）、投篮训练；九球放开 2–4 人，毽子团体赛仍禁 | `PhoneWatchLinkSession.phoneInteractiveStartSupported:604`、`AppFeatureFlags.isWatchLinkSupportedProject:52`、`WatchLinkSession.isValidLinkedSetup:662`（三处必须一致） | 三处白名单漂移（有单测钉死） |
| 2 | 会话模型 | controller / follower / shared 五角色；`matchGeneration` 区分「再来一场」；shared 用 revision 奇偶编码写者（偶数手表、奇数手机） | `LinkCore.swift:28/57/104/1337`、`LinkSessionStateMachine:1220` | 共编不乱序、不依赖设备时钟 |
| 3 | 传输 | 四通道：实时 `sendMessage`、`applicationContext` 兜底帧、`transferUserInfo` 终态队列、侧通道（记录/常用名） | `WatchConnectivityTransport:1605`、`PhoneWatchLinkSideChannels` | 蓝牙/WiFi 切换、手表离腕、手机后台 |
| 4 | 可靠性 | 完赛消息先同步落盘再发送；LZFSE 压缩 + 超限裁剪动作历史 | `PhoneWatchLinkSession.notifyMatchFinished:582`、`LinkFinishedEncoding`（4KB 触发、2MB 上限） | 进程被杀后重启仍能补发 |
| 5 | 可靠性 | retired 会话接收迟到完赛；重复 `matchId` 直接重发 ACK 不重写记录 | `LinkRecordSession` / `LinkRetiredRecordSessions`（`LinkCore.swift:824-915`） | 「再来一场」后旧完赛仍能到达 |
| 6 | 缺陷修复 | 记录 ACK 回传手表原始 id（此前回手机归一化 id，手表队列清不掉、反复重推） | `PhoneWatchLinkSideChannels.swift:51-72` | 手表 pending 归零 |
| 7 | 容量 | `applicationContext` 与常用名共享 64KB：快照剥离 `detailedActions`，实时帧 >60KB 折半丢最旧动作 | `LinkEnvelopeEncoding.applicationContextData:1073-1103` | 长训练/长局不撑爆；状态不丢 |
| 8 | 兜底 | `clearPending` 手机不可达时改走 `transferUserInfo`；未激活不再触发 WCSession 警告 | `LinkCore.swift:1854/1924` | 重新配对后自动清 pending |
| 9 | 记录回传 | 手表完赛/训练记录入手机库，幂等（重复 matchId 不重复写），失败保留未 ACK 让对端重试 | `LinkedMatchRecordIngestor`、`PhoneWatchLinkMessageHandling:379` | 手机写库失败后重试成功即只 1 条 |
| 10 | 常用名称 | 手机→手表快照（schema 2）+ 变更批次（每批 50）+ 用量回传 | `WatchSideChannelSync.swift`、`CommonNamesManager` | 手表 50 条上限、24 字截断 |
| 11 | 中断提示 | 手表进后台发 `watchBackgrounded`，手机显示「建议接管计分」 | `LinkMessageKind.watchBackgrounded` | 来电/Siri 中断后提示出现并可一键接管 |
| 12 | 未修风险 | `LinkProtocol.currentVersion` 仍为 1，但快照新增 `basketballTraining`：新手机 + 旧手表混跑时旧端解码失败、不 ACK、对端无限重试 | `LinkCore.swift:10/188` | **发版前决策：升版本号或解码失败回 ACK** |

## 4. 底层 / 基础设施

| # | 模块 | 改动 | 关键实现 | 验证重点 |
| --- | --- | --- | --- | --- |
| 1 | 工程 | 新增 `jifenWatch Watch App` target（`com.douhua.jifen.ios.watchkitapp`）+ `Embed Watch Content`；新增两个共享 scheme | `project.pbxproj:135-143`、`xcshareddata/xcschemes/*` | 归档包内含 `Watch/jifenWatch Watch App.app` |
| 2 | 版本 | 手机/手表 4 处配置统一 3.4.4 (89) | `project.pbxproj` | 手机与手表版本号一致 |
| 3 | 共享包 | `Package.swift` 平台加 **watchOS 10**；`RealtimeSync.swift` 整包 `#if !os(watchOS)` | `Packages/JifenCore/Package.swift` | macOS/iOS/watchOS 三平台编译 |
| 4 | LinkCore | 新增 `LinkedFootballState`、`LinkedShotTrainingState`（Int64 位打包 ≤2048 投）、`LinkFinishedEncoding`、`LinkRecordSession`、`LinkEnvelopeEncoding`、`WatchConnectivityTransport`（+1976 行） | `Packages/JifenCore/Sources/LinkCore/` | 载荷安全、ACK 队列、压缩往返 |
| 5 | ScoreCore | 新增 `FootballGoalMinute`（`45′` / `45+2′` / 五人制按半场）与 `FootballClockAnnotation` 编解码，手机与手表共用 | `ScoreCore/FootballGoalMinute.swift` | 补时与五人制换算 |
| 6 | 关闸 | Info.plist `JifenWatchLinkEntryEnabled = true`：审核期可不发版关掉所有手表入口 | `Info.plist:47`、`AppFeatureFlags.watchLinkEntryEnabled:28` | 改 false 后入口全消失、编译不受影响 |
| 7 | 隐私 | 手表 `PrivacyInfo.xcprivacy` 只声明 `UserDefaults / CA92.1`，无收集、不追踪 | `jifenWatch Watch App/PrivacyInfo.xcprivacy` | 与 App Store 隐私问卷一致 |
| 8 | 偏好 | 新增 `basketball_auto_buzzer_enabled`(true)、`ten_second_target_seconds`、`linked_score_watch_start_guide_popup_shown_v1`、`unoScoreboardStyle*`、手表 7 个 `watch_*`；旧 `phone_link_*_v1` 由 cleanup marker 一次性清除 | `PreferencesManager.swift:77`、`WatchPreferences.swift` | 升级安装不残留旧键 |
| 9 | 埋点 | 新增 `watch_link_start` / `watch_link_result`（success/timeout/rejected/failed/notReachable）/ `watch_link_page` / `scoreboard_menu_action` | `AppAnalytics.swift:30-36` | 与安卓/鸿蒙事件口径 |
| 10 | 音频 | `SoundManager` 改 `@Observable`，`playSound/toggleSound -> SoundPlaybackOutcome`，加播放代次与代理回收 | `SoundManager.swift:13` | 静音下不启动；连点不叠音 |
| 11 | 数据重置 | 新增 `.watchLinkState` 分类，只清手机侧 context/outbox/retired，不发 leave 给手表 | `LocalDataResetCoordinator.swift:11` | 清完手表独立记录仍在 |
| 12 | 测试基建 | `PhoneWatchLinkServiceTests` 首次登记进 target（此前 24 例从未执行）；新增 4 个测试类 | `project.pbxproj:93/223` | 确认所有新用例真实执行 |
| 13 | 工具链 | 新增 `watch_coverage.py`（`--check` 可做 CI 门）、`export_watch_keys.py`、`gen_watch_zh_hant.mjs`、`compose_watch_link_intro_artwork.py`、`compose_watch_promo_video.py`、`generate_watch_nineball_ui_report.py` | `scripts/`（本批 53 文件） | `watch-keys.json` 已与当前 381 键不同步，重新导出后再当依据 |
| 14 | 审核 | 内嵌手表 Bundle ID 被历史构建锁定（改名触发 ITMS-90477）→ 只能用 `watchkitapp`；App Store Connect 需补手表截图与描述 | `docs/verification/watch-transfer-2026-10-27/README.md` | 版本页截图、审核备注需覆盖手表功能 |

## 5. 自动化测试建议

### 5.1 现有闸门（发版必跑）

| 层 | 命令 | 期望 |
| --- | --- | --- |
| 共享核心 | `cd Packages/JifenCore && swift test` | 324 项全过（Swift Testing 307 + XCTest 17；含 LinkPayloadSafety、LinkPendingAckQueue、LinkedFootballSnapshot、FootballGoalMinute） |
| 手机单测 | `xcodebuild test -project jifen.xcodeproj -scheme jifen -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:jifenTests` | 1078 通过、APNs 探测 1 项跳过 |
| 手机 UI | 同上改 `-only-testing:jifenUITests/MainFlowUITests` / `GroupMatchSetupUITests` / `GroupBilliardsUITests` / `ZhHantSmokeUITests` | 全过（注意 `GroupMatchSetupUITests` 8 连发用例此前不稳定） |
| 手表单测 | `-scheme 'jifenWatch Watch App' -only-testing:'jifenWatch Watch AppTests'`（只传 destination，别传 `-sdk`） | 135 通过 |
| 手表 UI | `-scheme jifenWatchUITests -only-testing:'jifenWatch Watch AppUITests/WatchDialogConsistencyUITests'` | 7 通过（无配对设备时需先处理系统「联动失败」alert） |
| 本地化 | `jifenTests/LocalizationIntegrityTests` + `python3 scripts/localization/watch_coverage.py --check` | 47 语种键集、占位符、专用表一致 |
| **多人计分发布门禁** | `python3 scripts/verify_multi_score_release.py --simulator <iPhone-UDID>` | 2026-11-26 在 iPhone 模拟器复验 3.4.4 (89)，源码为 `02e8b8f1` 加当前工作区未提交变更，3 例通过，0 失败，0 跳过。最终候选源码定版后以该 checkout 的门禁结果为准。 |
| 四机型 | `./run_automation_four_destinations.sh` | iPhone/iPad × iOS 18/26 全过 |
| 归档 | `xcodebuild archive` + `-exportArchive`（app-store-connect） | 包内手机/手表均 3.4.4 (89)、签名严格校验通过、无 ITMS 拒绝 |

#### RevenueCat 周末会员发布检查

- 主 App 的 Debug 和 Release 共用 `Configuration/RevenueCat.xcconfig` 中的 App Store 公钥。Debug 可用 `xcodebuild` 的 `JIFEN_REVENUECAT_SDK_KEY` 构建参数替换成 Test Store 公钥。Release 运行时只接受 App Store 公钥。3.4.4 (89) 的 Release 模拟器包检查已通过。
- 已发布 `weekend_lifetime` 的 Paywall。使用 App Store 公钥读回确认，iOS 3.4.4 匹配到 `weekend_membership`，返回单一 `$rc_lifetime` 套餐、`iscoreboard_lifetime_vip` 商品和 `weekend_membership: true`。iOS 3.4.3 保留 `default` 回退。活动仍按上海时间周五至周日展示，可选的活动时间窗使用成对的 Unix 秒数。[RevenueCat 投放规则](https://app.revenuecat.com/projects/f6314102/targeting/SHE1hQ6_M7)
- 2026-11-26 已公开同步隐私披露。官网简中、繁中和英语政策均更新至 2026.11.26，新增 RevenueCat 购买历史和账号标识符条目。App Store 的公开隐私标签已确认购买历史和用户 ID 均与用户身份关联。购买历史用于 App 功能和分析，用户 ID 已增加 App 功能用途。[官网隐私政策](https://jifenqi.com/privacy) [App Store 产品页](https://apps.apple.com/us/app/id6759768784)
- 针对性单测共 51 例通过，含完整的 `LocalizationIntegrityTests`、活动投放、SDK 公钥校验、许可对账和 StoreKit 回归。App Store 和 Test Store 弹窗 UI 共 3 例通过，Test Store 验证了没有购买记录时的恢复提示。真机购买和恢复已有购买仍待验收。原始证据在本机测试产物批次 `20261126T133309653401Z-revenuecat-audit-fix` 和 `20261126T140501348084Z-multi-score-release`，按测试产物保留规则到期清理。

### 5.2 建议补的自动化（本批缺口）

1. **手表本地化完整性单测**：手表 target 目前没有对应 `LocalizationTestSupport` 的键位/占位符校验，漏翻不会红。
2. **`WatchLinkSettingsView` UI 用例**：三态（已配对/未安装/不可达）+ 刷新。
3. **足球进球分钟渲染用例**：`ScoreboardRecordDetailPage` 的 `53′ / 45+2′` 无自动化覆盖。
4. **协议版本门用例**：`currentVersion` 从 1 升到 2 后，旧端解码失败必须回 ACK + 诊断（否则无限重试）。
5. **retired 会话上限用例**：`LinkRetiredRecordSessions` 只增不减，需加 N 天/条数上限并测。
6. **捕获型 UI 套件加 `XCTSkip` 环境门**：`WatchPromoVideoCaptureUITests` / `WatchIntroArtworkCaptureUITests` / `WatchFullMatrixUITests` 目前全量跑会生成大量 keepAlways 截图。
7. **拆分 `GroupMatchSetupUITests` 的 8 连发用例**：连续第二次 `launch()` 后 fixture 未就绪（已两次复现），建议拆成独立方法或加就绪重试。
8. **无音频 CI 兜底**：`TimerAndToolOfflineTests` 断言真实播放 `.started`，无声卡环境会环境性红。

### 5.3 手动测试（按优先级）

**P0 · 联动主链路（必须真机两台）** —— 本版最大空白：至今没有做过双端 WCSession 端到端验证。

| 场景 | 步骤 | 期望 |
| --- | --- | --- |
| 首次联动 | 手机 Setup 点 ⌚ → 手表弹确认（20s 倒计时）→ 接受 | 两端进入同一场；手机显示跟随、手表为主控 |
| 双方计分 | 手表加分 → 手机加分 → 手表再加分 | 两端分数一致、动作历史合并、无重复记录 |
| 接管 | 手机菜单「接管计分」→ 手表菜单「手表接管」 | 权限转移单向生效，旧主控变只读并提示 |
| 断链重连 | 手表飞行模式 30s → 关闭；手机切后台 1min | 恢复后自动补快照；>60s 不看丢分 |
| 完赛回传 | 任一端口「结束比赛」 | 只落 1 条记录；手表 pending 归零；两端都退出会话 |
| 再来一场 | 完赛后立刻「再来一场」 | generation+1，旧迟到快照被拒，新场正常 |
| 旧手表混跑 | 用 3.4.3 手表 + 3.4.4 手机 | **预期会失败**：确认失败形态可接受（需先做 §5.2-4） |
| 记录回传 | 手表本地完赛（未联动）→ 手机记录页 | 出现「来自手表」记录；局分不为 0:0 |
| 训练联动 | 手机投篮训练开在手表 → 打 20 投 → 结束 | 命中率与合计一致；长训练不超 64KB |

**P1 · 手机端**

- 3.4.4 首启只弹一次介绍页；关闭后再启动不弹，微信升级弹层与评分邀请恢复。
- Setup ⌚ 按钮：iPhone 有、iPad 无；首次气泡 4.8s 收起且不再出现；九球选 2/3/4 人、毽子团体时不出现。
- 首页续赛条：手表会话显示 ⌚ 与「手表主控 · 已连接」；放弃需二次确认。
- 小组活动排阵开赛：四项目 × 单双打，摘要行与实际提交一致；未提交的小组档位改动（乒乓 7/9/11/15）必须复验。
- 篮球自动蜂鸣：默认开、主计时归零响一次、加时不重复；关闭后不再响。
- 足球：进球行分钟、补时 `45+2′`、终场后记录时长不再增长。
- 菜单：非分享态无「结束同步」；分享中二次确认；锁定态 resync/takeover 可点。
- 样式工作台：最近色保位、字号标题、浮层提示、投屏跟随字号倍率。
- 清除数据：新增「临时手表联动状态」，清完手表上的独立记录不受影响。

**P1 · 手表端**

- 40/42/46/49mm 全部首页、Setup、七类计分板走查（重点：顶部避开系统时钟、竖排底栏、命中区）。
- 九球 3 人与 4 人：四分屏、付分人/继续击球人、开球人切换、让杆。
- 足球/五人制：半场切换、补时卡片、平局二选一、完赛后「再来一场」。
- 投篮训练：竖版顶部 16pt 可点、四模式、续玩恢复。
- 计数器：结束即保存并归零留页；保存失败可重试。
- 记录：同步三态、自动同步开关、手动同步、500 条上限淘汰。
- 续玩：关闭钮 3s 内联确认放弃；离开页面自动收起。
- 关于/支持：简中 jifenqi.com、其他语言 iscoreboard.live；微信群二维码仅中文。
- 系统语言切繁中/英/日，抽 5 屏确认无简中泄漏与截断。

**P2 · 底层与发布**

- 升级安装（3.4.3 → 3.4.4）：旧偏好键迁移、旧记录可打开、旧续玩可恢复。
- 归档包检查：`Watch/jifenWatch Watch App.app` 存在、Bundle ID `watchkitapp`、手机与手表版本号一致、隐私清单齐全。
- App Store Connect：3.4.4 版本页补手表截图与描述；审核备注说明手表可独立使用。
- 安装体积与启动时间对比 3.4.3（手表 Bundle 新增 223 个文件）。

## 6. 发版前必须收口

1. 工作区 9 个未提交文件（小组赛制改回本机预设）构建 + `GroupMatchSetupRulesTests` / `GroupMatchSetupUITests` 复跑。
2. 协议版本门（§3-12）决策：升 `currentVersion` 或解码失败回 ACK，否则跨版本会死循环重试。
3. 联动真机端到端至少跑通 §5.3 P0 前 6 项。
4. 手表 UI 捕获型套件加 `XCTSkip`，避免被全量测试误跑。
