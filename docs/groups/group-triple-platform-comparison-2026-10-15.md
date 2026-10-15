# 小组（Groups）功能三端对比文档

> 生成时间：2026-10-15 08:1x GMT+8（自动化任务，第 2 次运行）；**当日 12:10 人工复核更新（r2）**
> 判定：**iOS 移植进行中、P0 已收口**（五阶段 1–6 全部落地；P0-1~P0-4 已于 10-15 完成并提交，剩余 P1/P2）
> 本文档为**只读分析**产物（r2 仅更新状态与结论，未新增源码改动记录之外的修改）。

---

## 0. 结论摘要（r2 更新）

| 端 | 状态 | 一句话 |
| --- | --- | --- |
| Android | ✅ 权威源 | HEAD `4784819c`（10-14）含直接排赛定型与防刷配额契约；是本轮 1:1 移植的比对基准 |
| HarmonyOS | ✅ 已对齐 10-14 | HEAD `bf12a904`（10-14 14:41）「fix(group): complete direct lineup parity」，同日追平安卓直接排赛；缺的是 429 配额语义与 playback 文案键分叉 |
| iOS | ✅ P0 已收口 | 10-15 提交 `c59a3e84`（22 源文件 + 测试 + 47 语言入库）与 `70ae48e6`（s5 战绩页 5 项缺口 + s6 分享文案对齐 + 9 键 × 47 语言）；**是否需要修改：iOS 剩 P1×6 / P2×5（见 §4），鸿蒙建议补 7 个细分 429 码，安卓无待办（权威源）** |

**iOS 当日进展（r2）：**

- **P0-1 ✅** 小组源码入库：commit `c59a3e84`（124 文件，+29 182 行）——22 个 `Features/Groups` 源文件、3 个单测文件、1 个 UI 测试、47 语言 `group_` 键、pbxproj 测试引用、批次清单 `group-port-20261013.json`。
- **P0-2 ✅** A/B/C/D 拍板记录写入计划文档第三节：A=选项 2（增量移植）、B=选项 2（peer+coaching 完整 1:1）、C=选项 1（429 新契约纳入）、D=先提交再重构（`c59a3e84`）。
- **P0-3 ✅** s5 战绩页 5 项缺口全部落地（commit `70ae48e6`）：`hasRankingError` 错误态+重试、单双打筛选可见性对齐（失败时可切赛制）、胜率 5 场门槛（不足显示「场次不足」）、本人行「（我）」后缀、`group_ranking_empty` 空态（带赛制名）。
- **P0-4 ✅** s6 分享页对齐（同 commit）：海报合成 `GroupInviteCard`（720×920，QR+组名+组号+APP 圆角图标页脚，此前会话已实现，本轮核实与安卓 `buildGroupInviteBitmap` 坐标/配色逐项一致）；按钮文案换用安卓键名（分享邀请/分享二维码）；新增不可加入时「分享小组号」ShareLink；海报合成失败可感知提示；**9 个新键 × 47 语言**（4 个 `group_audit_ui_share_*` + `group_audit_ui_group_number_message` + 4 个排行键，en/zh-Hans/zh-Hant 用安卓权威译文，其余 44 语言 Codex-authored 写入 lproj+catalog）。

**iOS 距「完成」的剩余缺口（P1/P2，见 §4）：**

---

## 1. 三端基线表

| 项 | Android（权威源） | HarmonyOS | iOS |
| --- | --- | --- | --- |
| 仓库路径 | `/Users/yangyang/Desktop/jifenqi/jifen-android` | `/Users/yangyang/Desktop/jifenqi/jifen-hos` | `/Users/yangyang/Desktop/jifenqi/jifen-ios` |
| 分支 | `3.3` | `3.3` | `3.3` |
| HEAD commit | `4784819c` | `bf12a904` | `70ae48e6`（r2） |
| HEAD 日期 / 标题 | 2026-10-14 14:22 · `feat(group): refine direct match scheduling` | 2026-10-14 14:41 · `fix(group): complete direct lineup parity` | 2026-10-04 19:38 · `fix(ios): 深色模式全量审计问题修复` |
| 小组源码位置 | `app/src/main/java/com/douhua/jifen/{screen,ui/components,managers,data/model}/group/`（4 个目录） | `entry/src/main/ets/{pages,components,model,api,managers,helpers,common}/…group/` | `jifen/Features/Groups/`（**扁平**，仅 `Fixtures/`） |
| 源码规模 | **71 个 .kt / 19 337 行** | **77 个 .ets+.ts**（内核 15 050 行 + 页面/组件） | **22 个 .swift / 5 400 行** |
| 工作区未提交改动 | 81 项 | 172 项 | **173 项**，其中 `jifen/Features/Groups/` 全部 `??` 未跟踪 |
| 小组相关 commit | 有（10-13 / 10-14 共 4 个） | 有（10-14 共 3 个） | 有（r2：10-15 `c59a3e84` + `70ae48e6`） |
| 网络端点 | `data/remote/GroupApiService.kt` **59 个 `suspend fun`** | `api/group/GroupRepository.ts` 接口 **67 个方法** | Features/ 全量调用点去重约 **54 条 `/groups/...` 路径** |
| 小组文案键 | **653** 个 `group_*` 键 × **3** 资源限定目录（`values` / `values-zh-rCN` / `values-zh-rTW`） | **598** 个 `group_*` 键 × **7** 资源目录（`base`/`en_US`/`zh_CN`/`zh_HK`/`zh_Hant`/`zh_MO`/`zh_TW`） | **260** 个代码实际引用键 × **47** 个 `.lproj`，缺失 0（全齐全） |
| 端口/哉差异凭据 | `app/src/main/res/values/group_*.xml`（12 个细分文件） | `entry/src/main/resources/*/element/string.json`（每项 2377 键） | `jifen/Resources/*.lproj/Localizable.strings`（每语言 1778 键，其中 `group_` 前缀 327） |

> **本地化口径说明**：三端键命名体系不同。Android↔Harmony 的 `group_*` 键名交集 **422**；Android↔iOS 交集仅 **48**，Harmony↔iOS **37**。iOS 刻意采用「`group_` + 短名」体系（见 `GroupModels.swift:16` `groupText`），并非覆盖缺失——代码实际引用的 260 个键在 47 语言中全部存在（缺失 0）。但命名分叉使后续逐键审计成本高，建议维护映射表（见 P2-3）。

---

## 2. 功能矩阵表

图例：✅ 完整 ｜ ⚠️ 部分/有偏差 ｜ 🔴 缺失

| # | 能力 / 屏 | Android | HarmonyOS | iOS | 依据（文件路径） |
| --- | --- | --- | --- | --- | --- |
| 1 | 小组列表 | ✅ | ✅ | ✅ | A `screen/group/list/GroupListScreen.kt`；H `pages/group/GroupListPage.ets`；I `GroupViews.swift:4` `GroupListView` |
| 2 | 归档小组列表 | ✅ | ✅ | ✅ | A 同文件 `ArchivedGroupListScreen`；H `GroupListPage.ets:71` `archivedOnly` + `openArchived()`；I `GroupViews.swift:127` `GroupArchivedListView` |
| 3 | 通知中心（17 类 kind / 已读回执） | ✅ | ✅ | ✅ | A `notice/GroupNoticeInbox.kt`；H `pages/group/GroupNoticePage.ets`；I `GroupSupportViews.swift:97` `GroupNoticeInbox`（阶段 2 完成，含 `isReceipt` 校验） |
| 4 | 详情容器 + 四页签（概览·活动·战绩·成员） | ✅ | ✅ | ✅ | A `detail/GroupDetailScreen.kt:240-274`（0/1/2/3，`groupType=coaching` 时 1 换 `GroupTrainingTab`）；H `GroupDetailPage.ets:212,300` `groupTabIndex`；I `GroupDetailView.swift:116` `Picker` `ForEach(0..<4)`，`:51` coaching 分支 |
| 5 | 概览页签（统计 / 进度 / 下一场） | ✅ | ✅ | ✅ | A `GroupDetailOverviewTab.kt` + `GroupOverviewProgress.kt`；H `GroupDetailPage.ets:1394` `buildOverviewTab()`；I `GroupDetailView.swift:220` `overview(_:)` + `:308` `overviewActions` |
| 6 | 活动页签 / 活动列表 | ✅ | ✅ | ✅ | A `GroupDetailActivitiesTab.kt`；H `:1702` `buildActivityTab()`；I `GroupDetailView.swift:351` `activities(_:)` |
| 7 | 战绩页签 + 排行 | ✅ | ✅ | ✅（r2） | A `GroupDetailRecordsTab.kt`（**本轮 +139/-90，新增 `rankingSection`/`hasRankingError`/单双打筛选**）；H `:381` `rankingsSequence` + `components/GroupRankingTable.ets`；I `GroupDetailView.swift` `rankingSection` —— **10-15 `70ae48e6` 已补齐 5 项**：hasRankingError 错误态+重试、单双打筛选可见性、胜率 5 场门槛（`group_ranking_insufficient_matches`）、本人行 meSuffix、`group_ranking_empty` 带赛制名空态。残留差异：iOS 排行一次只持当前赛制数据（安卓双份常驻），用 `!recordsEmpty || rankingError` 门控近似等价；排行表为行式布局而非安卓横向滚动表格 |
| 8 | 成员页签（含移除成员分片） | ✅ | ✅ | ✅ | A `GroupDetailMembersTab.kt` + `GroupRemovedMembersSection.kt`；H `:379,480` `loadRemovedMembers()`；I `GroupDetailView.swift:487` `members(_:)` + `removedMembers`（`Repository.swift:236`） |
| 9 | 建组（校验 / 名称候选） | ✅ | ✅ | ✅ | A `create/GroupCreateScreen.kt` + `GroupCreateValidation.kt` + `GroupNameCandidates.kt`；H `GroupCreatePage.ets`；I `GroupViews.swift:240` `GroupCreateView` + `:290` `GroupCreatedView` |
| 10 | 加入 / 邀请链接 / QR / deep link | ✅ | ✅ | ⚠️ | A `join/GroupJoinScreen.kt` + `share/GroupShareScreen.kt` + `GroupInvitation.kt` + `GroupInvitePolicy.kt`（4 条 URI，含自定义 scheme `jifenqi://`）；H `GroupJoinPage.ets` + `helpers/groupInvitationLink.ts`；I `GroupQRViews.swift:7/172/186` + `GroupInvitationLink.swift` — **未注册 `jifenqi://` 自定义 scheme**（计划 §4 记录的有意偏差） |
| 11 | 活动创建 / 编辑 | ✅ | ✅ | ✅ | A `activity/GroupActivityCreateScreen.kt`（create+edit 双态）；H `GroupActivityPage.ets`；I `GroupActivityViews.swift:4,90` |
| 12 | **直接排赛**（`activityType=direct`，`POST /direct-lineups`） | ✅ | ✅ | ✅ | A `GroupActivityLineupScreen.kt:164` + `ViewModel:226`；H `RemoteGroupRepository.ts:1005`；I `GroupRepository.swift:54` `createDirectLineup` + `GroupActivityViews.swift:267` `GroupDirectScheduleView` |
| 13 | **两种时间模式**（`sequence` 顺序 / `estimated` 预计） | ✅ | ✅ | ✅ | A `ViewModel:119` `MutableStateFlow("estimated")`，direct 默认 `sequence`；H `MockGroupRepository.ts:1090` sequence 偏移、`GroupTypes.ts` `GroupActivityTimingMode`；I `GroupRepository.swift:6` `timingMode = "estimated"`，`GroupTrainingViews:140` `skipsConflicts` + `GroupScheduleEditor` Picker |
| 14 | 对阵编排 lineup（含冻结/-conflict 校验） | ✅ | ✅ | ⚠️ | A `GroupActivityLineupScreen.kt`（+475）；H `GroupActivityLineupPage.ets`；I `GroupScheduleEditor.swift:3,8` —— **3 处已知偏差**（单页 vs 安卓两步、`dateOnly` vs 日期+时间、校验 3 档 vs 安卓 5 档），见 delta 文档阶段 4 第 11–13 条 |
| 15 | 赛果录入 / 补记（manual result） | ✅ | ✅ | ⚠️ | A `result/GroupResultEntryScreen.kt`（**+104/-163**）+ `GroupResultScoreControls.kt`（**+98/-56**）；H `GroupResultPage.ets`（1040 行）；I `GroupForms.swift:5` `GroupMatchEditor` + `GroupActivityViews.swift:202,207,211` `manual_result`（补记可用）——**录分控件未跟安卓重写**（缺 `GroupQuickResultColumn` / `GroupResultNumericField` 等价物与 10 个 `group_entry_*` 键） |
| 16 | 赛果确认 / 作废 / 权限确认 | ✅ | ✅ | ✅ | A `GroupResultReviewActions.kt` + `GroupResultPermissions.kt`（+19 `groupResultHistory`/`groupResultTasks`/`taskIds`）；H `managers/group/groupResultReconciler.ts`；I 路径 `"/results/\(id)/confirm"`、`"/void"`（`GroupActivityViews` / `GroupDetailView`），纯函数 `GroupExtendedModels.swift:221` `confirmation`、`:231` `confirmationTasks` |
| 17 | 排行 / 个人战绩（`'group_member_results'`） | ✅ | ✅ | ✅ | A `result/GroupMemberResultsViewModel.kt` + `detail/GroupBrowseScreens.kt`；H `GroupMemberResultsPage.ets` + `GroupRankingTable.ets`；I `GroupRepository.swift:275` `loadRankings` + `GroupViews.swift:372` `GroupMemberResultsView` |
| 18 | 分享页 / 邀请评价 | ✅ | ✅ | ✅（r2） | A `share/GroupShareScreen.kt`（**+144/-22， canvas 海报 + APP 图标 + 品牌 footer + `generateGroupQr`**）；H `GroupSharePage.ets`（291 行）；I `GroupQRViews.swift` `GroupShareView` + `GroupInviteCard`（720×920 海报：绿头带 #EEF8EF、标题 #173D21 38pt、组号 #487853、QR 550×550、页脚扫码提示 + 圆角 App 图标 40pt + 品牌名，坐标/配色照搬安卓）+ `GroupQRCode`（纠错等级 H、中心烤入圆角图标）。**10-15 `70ae48e6` 补齐**：按钮文案对齐安卓键名（`group_audit_ui_share_invitation/_qr/_number`）、不可加入时「分享小组号」（`group_audit_ui_group_number_message`）、合成失败提示（`group_audit_ui_share_failed`）。残留差异：iOS 用系统 `ShareLink`（无失败 toast 语义）、完整邀请文案（`group_invitation_intro_*`/`group_share_message`，含按项目分类的 intro）未移植，当前分享内容为「链接+组名+组号」 |
| 19 | 举报（组预览 / 组内） | ✅ | ✅ | ⚠️ | A `detail/GroupReportForm.kt`（+9/-7，新增 `group_cancel`）+ `components/group/GroupFeedback.kt`（+20/-20）；H `components/GroupReportDialog.ets` + `GroupJoinReportDialog.ets`；I `GroupPreviewReportView.swift`（组预览举报完整）+ `GroupTrainingViews.swift:237` `GroupReportView` ——**缺安卓 s6 两处微调** |
| 20 | 训练组（`groupType=coaching`） | ✅ | ✅ | ✅ | A `training/GroupTrainingPlanScreen.kt` + `GroupTrainingTab.kt` + `GroupMemberActionPolicy.kt` coaching 分支；H `GroupTrainingPlanPage.ets`（**1377 行**）+ `coaching` 41 处引用；I `GroupTrainingViews.swift:3` `GroupTrainingTab`、`:209` Editor、`:215` Leave + `training-plans`/`training-sessions/leave` 端点 |
| 21 | 权限矩阵（成员动作 / 加入可用性 / 赛果权限） | ✅ | ✅ | ✅ | A `GroupMemberActionPolicy.kt` + `GroupJoinAvailability.kt` + `GroupResultPermissions.kt` + 单测 `GroupRoleScenarioMatrixTest.kt`；H `model/group/GroupActivitySessionPolicy.ts` + `isManager`/`isCoach`；I `GroupExtendedModels.swift:213-251`（`manager`/`coach`/`canManageMember`/`confirmation`/`canScore`/`canInvite`）+ `GroupManagementMenu.entries`（12 组身份×状态组合已用独立 `swiftc` 程序跑通） |
| 22 | 顶栏管理菜单 + 冷静期横幅 | ✅ | ✅ | ✅ | A `GroupDetailScreen.kt` `GroupManagementTopBarMenu` / `GroupDissolveBanner`；H `GroupEditInfoDialog.ets`；I `GroupDetailView.swift:161` `menuAction` + `:176` `dissolveBanner`（阶段 3 完成，顺带修了「归档组无法恢复」的既有 bug） |
| 23 | 编辑冲突审查（revision conflict） | ✅ | ✅ | ✅ | A `screen/group/GroupEditConflictReview.kt`（36 行）；H `components/GroupEditInfoDialog.ets` + `GroupListActionsDialog`；I `GroupActivityViews.swift:23,51-75`（「Load latest version」/「Keep my edits」双选）+ `GroupCaptureRoot.swift:57` `inventory-edit-group-conflict` |
| 24 | 离线队列 / 幂等 / 退避重试 | ✅ | ✅ | ✅ | A `managers/group/GroupUploadManager.kt`（`receiptMutex`/`syncMutex`/`syncPending`/`deferRetry`/`repair`/`discard`/`abandonLocalRecord`）；H `groupUploadQueue.ts`（206 行，自带 `idempotencyKey`）+ `groupPendingWrites.ts` + `groupConnectivityRetry.ts` + `RemoteGroupRepository.ts:417` `Idempotency-Key` 头；I `GroupLocalPersistence.swift:86-160`（`enqueue`/`markUploaded`/`markFailure`/`updateRetry`/`finishUpload`）+ `GroupRepository.swift:378` `Task.sleep` 退避 + `key:` 幂等参数 |
| 25 | 本地化覆盖（键数 × 语言数） | ✅ 653×3 | ✅ 598×7 | ✅ **260×47（最全）** | 见 §1 基线表；iOS `GroupModels.swift:16` `groupText("\(key)")` → `NSLocalizedString("group_"+key)`，47 语言缺失率 0 |

**矩阵统计（r2）：Android 25/25 ✅ ｜ HarmonyOS 25/25 ✅ ｜ iOS 21 项 ✅、4 项 ⚠️（#10 自定义 scheme 有意不注册、#14 编排 3 处偏差、#15 录分控件未跟安卓重写、#19 举报两处微差）、0 项 🔴。**

---

## 3. 各端差异清单

### 3.1 iOS 缺什么（相对安卓 10-14）

按 `docs/groups/ios-android-parity-delta-2026-10-14.md` 阶段划分，**阶段 1（契约/文案/错误码）、2（通知中心）、3（顶栏菜单/冷静期）、4（直接排赛）已完成**，阶段 5–6 未开始。

**s5 — 赛果与排行（P0，✅ 10-15 `70ae48e6` 已收口排行部分）**

| 安卓真源改动 | 增量 | iOS 现状（r2） | 状态 |
| --- | --- | --- | --- |
| `detail/GroupDetailRecordsTab.kt` | +139/-90 | `GroupDetailView.swift` `rankingSection` 已补齐 5 项：① `hasRankingError` 错误态（当前赛制失败显示错误+重试；任一赛制失败时筛选仍可见可切换）；② 胜率 5 场门槛 `group_ranking_insufficient_matches`（对齐安卓 `winRate.takeIf { games >= 5 } ?: insufficientText`）；③ 单双打筛选 `group_filter_singles`/`group_filter_doubles`；④ 本人行 meSuffix `group_ranking_me_suffix`（对齐安卓 `GroupRankTable.meSuffix`）；⑤ `group_ranking_empty` 空态带赛制名 | ✅ |
| `result/GroupResultScoreControls.kt` | +98/-56 | `GroupForms.swift:5` `GroupMatchEditor`（195 行）+ `GroupModels.swift` `terminalSet`/`validResult`；核实 en 仅存 `group_entry_a_wins`/`_b_wins`，**其余 8 个 `group_entry_*` 键缺失** | 🔴 P1-1 |
| `result/GroupResultEntryScreen.kt` | +104/-163 | 录入走 `GroupMatchEditor` sheet；**7 个 `group_rule_*` 键全部缺失**（`group_rule_cap_none` 等） | 🔴 P1-2 |
| `result/GroupResultPermissions.kt` | +19 | `GroupExtendedModels.swift` `confirmationTasks`/`resultHistory` 语义接近 | ⚠️ P1-5 需逐行核对过滤口径 |
| `result/GroupResultDraft.kt` | +9/-13 | iOS 录分无草稿 | ✅ 无需改动 |
| 删除 `result/GroupResultFormDraft.kt` | -全文件 | iOS 无此文件 | ✅ 无需改动 |

**s6 — 分享 / 举报（P0–P1，分享部分 ✅ 10-15 `70ae48e6` 已收口）**

| 安卓真源改动 | 增量 | iOS 现状（r2） | 状态 |
| --- | --- | --- | --- |
| `share/GroupShareScreen.kt` | +144/-22 | 海报合成 `GroupInviteCard` 已在（720×920，`UIGraphicsImageRenderer`，坐标/配色照搬安卓）；10-15 补齐 5 键 `group_audit_ui_share_invitation/_qr/_number/_failed` + `group_audit_ui_group_number_message` × 47 语言（安卓实为 4 个 `share_*` 键，第 5 键为页脚语义所需的 `group_number_message`）；不可加入时可分享小组号文案。**仍缺**：完整邀请文案（`buildGroupInvitationText` 等价物 + `group_invitation_intro_generic/_cards/_ball/_sport`、`group_share_message`、`APP_DOWNLOAD_URL` 附文） | ⚠️ P1（邀请文案） |
| `detail/GroupReportForm.kt` | +9/-7 | `GroupTrainingViews.swift:237` `GroupReportView` | ⚠️ 缺 `group_cancel` 独立取消态（P1-6） |
| `components/group/GroupFeedback.kt` | +20/-20 | 未见 iOS 对应文件 | ⚠️ 需确认评价/反馈组件（P1-6） |

**工程结构类（P1）**

- `Core/`、`Models/`、`Network/`、`Store/` 四层目录**未落地**（计划第五节要求）；当前 22 个 .swift 全部平铺，最大的 `GroupCrossPlatformFixture.swift`（540 行，测试夹具）与业务文件混放。
- `jifen/Features/Groups/` 22 个文件**全部 `??` 未跟踪**：与其他会话并行作业时极易丢改动。
- 本机 CLI 无法做真编译（Swift 宏插件服务器 `sandbox_apply: Operation not permitted`），阶段 1–4 只做过 `xcrun swiftc -parse` 语法检查 + 纯函数抽取后 `swiftc` 真跑，**全量类型检查尚未做过**。

### 3.2 鸿蒙缺什么（相对安卓 10-14）

| 项 | 状态 | 依据 |
| --- | --- | --- |
| 429 配额语义 | ⚠️ 仅 1 处 HTTP 层兜底 | `RemoteGroupRepository.ts:466` `if (statusCode === 429) { ... throws 'RATE_LIMITED' }` —— 只有 1 个通用码，**无安卓 7 个细分 429 码**（`CREATE_GROUP_DAILY_LIMIT`/`JOIN_DAILY_LIMIT`/`PENDING_REQUEST_LIMIT`/`JOIN_REQUEST_DAILY_LIMIT`/`RESULT_GROUP_DAILY_LIMIT`/`RESULT_SUBMITTER_DAILY_LIMIT`）与独立文案。iOS 反而已在 `GroupErrorMessage.swift` 补齐全部 8 个码 **`+JOIN_REQUEST_COOLDOWN`**。 |
| 训练组 coaching | ✅ 完整 | `GroupTrainingPlanPage.ets` 1377 行 + `coaching` 41 处引用 + `groupType` 双分支（`coaching`/`peer`）；**代码量领先 iOS**（iOS coaching 也已实现，但计划 B 项尚未正式拍板） |
| 文案键体系 | ✅ 最接近安卓 | `group_*` 键与安卓交集 **422**（iOS 仅 48） |
| 直接排赛 | ✅ 已追平 | HEAD `bf12a904`（10-14 14:41）晚于安卓 HEAD（14:22）19 分钟，标题即「complete direct lineup parity」 |
| 端点契约 | ✅ 67 个接口方法（多于安卓 59） | `api/group/GroupRepository.ts` |
| 深浅色语言 | ⚠️ 仅 7 个资源目录 | 相对 iOS 47 语言，覆盖明显更窄（但这是平台/市场差异，非缺陷） |

### 3.3 安卓独有 / 领先

1. **排赛编辑校验 5 档**（`conflict` / `member_limit` / `sessions` / `duplicate` / `incomplete`）；iOS 只做 3 档（`lineup_conflict`/`lineup_member_limit`/`lineup_invalid`），鸿蒙未见独立 5 档。
2. **两步式直接排赛**（活动信息页 → 排对阵页）；iOS 压缩为单页。
3. **7 个细分 429 错误码 + `JOIN_REQUEST_COOLDOWN` 24h 冷却**：安卓为契约定义方，鸿蒙只到 `RATE_LIMITED`，iOS 反而跟得最全。
4. **`GroupUploadManager` 双 Mutex 架构**（`receiptMutex` 收条、`syncMutex` 同步 + `scheduleWake` 定时唤醒 + `deferRetry` 指数退避 + `repair`/`repairSubmission` 修复通道），是当前最完整的离线语义实现。
5. **自定义 scheme deep link**（`jifenqi://groups/join?groupNo=`）—— iOS 有意不注册（只接 `jifenqi.com` / `iscoreboard.live` HTTPS 域名 + Associated Domains）。
6. **海报式分享**（canvas 合成 + APP 品牌页脚）—— iOS 已于 10-15 对齐（`GroupInviteCard`），鸿蒙待确认是否需要同款海报（当前为纯 QR 分享）。
7. 底蕴：**71 个 kt 文件 19 337 行**，是 iOS（5 400 行）的 3.6 倍。

---

## 4. 行动建议（供次日上午处理）

### P0（✅ 全部完成，2026-10-15）

| # | 动作 | 状态与凭据 |
| --- | --- | --- |
| P0-1 | 先把未跟踪的小组源码提交上去 | ✅ commit `c59a3e84`（124 文件，+29 182/-4）：22 个 `Features/Groups` 源文件 + 3 单测 + 1 UI 测试 + 47 语言 + pbxproj 测试引用 + 批次清单。提交前复查：`jifen/**/*.swift` 最近 30 分钟无写入（仅 `jifenTests/GroupPortParityTests.swift` 为本工作流文件） |
| P0-2 | 拍板 A/B/C/D 四项 | ✅ 已写入 `.trae/documents/ios-group-1to1-port-plan.md` 第三节：A=选项 2、B=选项 2、C=选项 1、D=先提交再重构（`c59a3e84`） |
| P0-3 | 补齐 s5 战绩页签 5 项缺口 | ✅ commit `70ae48e6`：`GroupDetailView.swift` `rankingSection` 逐条落地（错误态+重试 / 筛选可见性 / 5 场门槛 / meSuffix / 带赛制名空态），4 个新键 × 47 语言 |
| P0-4 | 补 s6 分享海报 | ✅ commit `70ae48e6`：海报合成 `GroupInviteCard` 核实已在（720×920，与安卓逐项一致）；按钮文案对齐安卓键名；新增「分享小组号」与合成失败提示；5 个新键 × 47 语言（脚本 `scripts/localization/group_s5_s6_keys_20261015.py`，可重跑幂等） |

> r2 复核结论：P0-4 原判「无海报合成」有误——`GroupInviteCard` 在晨检之后、本轮之前已由前一工作会话补上；本轮核实其与安卓 `buildGroupInviteBitmap` 的尺寸（720×920）、头带（#EEF8EF / 176px）、标题（38pt #173D21）、组号（25pt #487853）、QR（85,195 起 550×550）、页脚（27pt #5F6B64 + 圆角图标 40pt + 品牌名 25pt #2B332E）逐项一致，无需重做。

### P1（本周到账）

| # | 动作 | 具体文件 |
| --- | --- | --- |
| P1-1 | **录分控件重写**（对齐 `GroupResultScoreControls.kt` +98/-56） | `jifen/Features/Groups/GroupForms.swift:5` `GroupMatchEditor` → 抽 `GroupQuickResultColumn` / `GroupResultNumericField`；补 10 个 `group_entry_*` 键 |
| P1-2 | **规则胶囊组**（对齐 `GroupResultEntryScreen.kt` +104/-163） | 同上文件，新增 `RulesChipsGroup`；补 7 个 `group_rule_*` 键 |
| P1-3 | **目录分层落地**（计划第五节） | 把 `jifen/Features/Groups/` 拆为 `Core/`、`Models/`、`Network/`、`Store/`、`Screens/`、`Components/`。`jifen` target 用 `PBXFileSystemSynchronizedRootGroup`，**新增 .swift 无需改 pbxproj**；但 `GroupCrossPlatformFixture.swift`（测试夹具）建议移出到 `jifenUITests` 或保留同名目录 |
| P1-4 | **真编译验证**（本机 CLI 不可行） | 在 Xcode 或允许嵌套沙箱的终端执行：`xcodebuild -project jifen.xcodeproj -scheme jifen -destination "platform=iOS Simulator,id=86871B65-E0ED-4FBD-9F93-F3FB6246A895" -derivedDataPath build/groups-port-20261014/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build`。**不要加 `CODE_SIGNING_ALLOWED=NO`**（Keychain `-34018` 假失败） |
| P1-5 | **核对 `GroupResultPermissions` 口径** | 安卓 `groupResultHistory`/`groupResultTasks`/`taskIds` vs iOS `GroupExtendedModels.swift:231-238` `confirmationTasks`/`resultHistory`，逐条比对 `filteredGroupRecords` 过滤规则 |
| P1-6 | **补全 s6 举报微差** | `GroupTrainingViews.swift:237` `GroupReportView`：确认 `group_cancel` 与 `GroupFeedback` 等价物（安卓 `GroupFeedback.kt` +20/-20） |
| P1-7 | **补完整邀请文案**（r2 新增，安卓 `buildGroupInvitationText`） | iOS 分享当前只有「链接+组名+组号」；安卓分享文本含按项目分类的 intro（`group_invitation_intro_generic/_cards/_ball/_sport`）+ `group_share_message` 模板 + `jifenqi.com/download` 下载链接，图片分享还带同一份附文。落点：`GroupInvitationLink.swift` 旁新增 `GroupInvitationText` 构造器 + `GroupShareView` 两个 ShareLink 的 message；约 6 键 × 47 语言 |

### P2（有档期再做）

| # | 动作 | 具体文件 |
| --- | --- | --- |
| P2-1 | 消除「排行何时算 insufficient」的语义歧义（写单测固定） | `jifenTests/GroupPortParityTests.swift` 新增 `testRankingRequiresMinimumMatches` 等 |
| P2-2 | 决定是否需要注册 `jifenqi://` 自定义 scheme | `jifen.xcodeproj` → Info → URL Types。当前有意不注册，若市场/运营需要扫码拉起需重开决策 |
| P2-3 | **建立三端键名映射表** | iOS 260 个 `group_<短名>` ↔ Android 653 个 `group_*` ↔ Harmony 598 个 `group_*`。当前 iOS↔Android 键名交集仅 48，后续每次 parity 审计都要人工词义对齐，成本高 |
| P2-4 | 平板限宽 `ContentMaxWidth.Groups` | `GroupListView` 沿用系统 List 宽度，与首页 960 限宽分离（delta 文档阶段 2 第 11 条已知偏差） |
| P2-5 | 顶栏 `mutating` 进度条、非成员「退出小组」入口、归档组二次确认 | delta 文档阶段 3 第 14–16 条已知偏差，均为「iOS 惯例优先」的有意设计，需用户确认是否保留 |

---

## 5. iOS 待拍板 4 项的现状与推荐

| 项 | 计划原文 | 现状（本次核查） | 推荐选择 | 理由 |
| --- | --- | --- | --- | --- |
| **A. 现有未提交实现如何处置** | 选项 1 从零重写 / 选项 2 增量移植 delta / 选项 3 折中 | 22 文件 5400 行全部 `??` 未跟踪；**阶段 1–4 已用选项 2 的思路实际落地并自检通过**（`GroupPortParityTests.swift` 已新增单测）；剩余差距仅在 s5/s6 | **选项 2（增量移植）** | 现有实现已逐页对齐安卓 10-12、有 69 个既有单测 + 本轮新增单测，网络层/持久层/邀请链接/提醒可直接复用；从零重写会丢掉已验证的四阶段成果 |
| **B. 是否纳入训练组 coaching** | 选项 1 只做 peer / 选项 2 peer + coaching 完整 1:1 | **代码已具备 coaching**：`GroupTrainingViews.swift`（258 行，含 TrainingTab/Editor/Leave/Report）、`GroupTrainingNoticesView.swift`（86 行）、`GroupTrainingModels.swift`，端点 `training-plans`、`training-plans/{id}/cancel`、`training-sessions/{id}/leave`、`leave-notices`、`training-notices` 全部就绪 | **选项 2（纳入）** | 已经写完了，不纳入反而要删代码；且鸿蒙 coaching 亦已完整（1377 行），不纳入会造成三端都不一致 |
| **C. 是否纳入后端 429 与 `JOIN_REQUEST_COOLDOWN` 新契约** | 选项 1 纳入 / 选项 2 后续补 | **阶段 1 已落地**：`GroupErrorMessage.swift` 已映射全部 7 个 429 码 + `JOIN_REQUEST_COOLDOWN` → `group_join_cooldown`；9 条错误键已补到 45 个语言 | **选项 1（纳入，并反向对齐鸿蒙）** | iOS 已跑在安卓和鸿蒙前面；鸿蒙只有 `RATE_LIMITED` 兜底，建议同步补 7 个细分码 |
| **D. 未跟踪文件与 47 语言文案的工程处置** | 是否先 stash / 备份 | 22 个 .swift + 测试 + 47 个 `.lproj` 的 `group_` 键（每语言 327 条前缀键）全部未跟踪；工作区共 173 项改动。**最近 30 分钟内 `jifen/**/*.swift` 无写入**，无并行会话冲突迹象 | **立即提交，不要 stash** | stash 会加大丢失与混淆风险；47 语言文案已对齐（每语言 1778 键一致，`plutil -lint` 通过），提交后可安全进入 P1-3 的目录重构。检出后建议 `git tag groups-port-phase1-4` 作为回滚点 |

---

## 附：本次核查的方法与凭据来源

- 所有 ✅/⚠️/🔴 结论均由下列只读操作产出，可复现：
  - `git status --short`、`git log -5 --pretty=…` / `git rev-parse --abbrev-ref HEAD`（三端）
  - `find … -name "*.swift" | wc -l` + `-exec cat {} + | wc -l`（iOS）；`find … -name "*.kt"`（Android）；`find entry/src/main/ets`（Harmony）
  - `find jifen -name "*.swift" -mmin -30`（最近写入检测 → **0 命中**）
  - `grep -cE "suspend fun" GroupApiService.kt` → 59；`grep -cE "^\s+[a-zA-Z]+\(" GroupRepository.ts` → 67；iOS 全 `Features/` 去重路径 → 54
  - 键集差分：Android `values*/group_*.xml` 653 / Harmony `resources/*/element/string.json` 598 / iOS 代码引用 260（`groupText()` + `NSLocalizedString()` union），两两 `comm` 交集 48 / 422 / 37
  - delta 补丁：`build/groups-port-20261014/android-group-delta-full.patch`（405 852 字节），本次用脚本按 `diff --git` 切片提取了 `GroupDetailRecordsTab.kt`、`GroupResultScoreControls.kt`、`GroupResultEntryScreen.kt`、`GroupShareScreen.kt`、`GroupReportForm.kt`、`GroupFeedback.kt`、`GroupResultPermissions.kt`、`GroupResultDraft.kt` 的 hunk 头、新增符号与新增 `R.string.*` 键
- 前置文档：`docs/groups/ios-android-parity-2026-10-13.md`（旧基线）、`docs/groups/ios-android-parity-delta-2026-10-14.md`（阶段 1–4 实况）、`.trae/documents/ios-group-1to1-port-plan.md`（计划 + A/B/C/D）
- **未做**任何源码 / 工程文件写入；文档本身落在 `docs/groups/` 下。

---

<!-- 2026-10-15 08:1x 首次生成：判定「进行中、未完成」，功能矩阵 25 行（iOS 16 ✅ / 8 ⚠️ / 0 🔴），P0 共 4 条、P1 共 6 条、P2 共 5 条 -->
<!-- 2026-10-15 12:10 r2 人工复核更新：P0-1~P0-4 全部完成（commit c59a3e84 / 70ae48e6），矩阵改为 iOS 21 ✅ / 4 ⚠️ / 0 🔴；P0-4 原判「无海报合成」更正为已在；新增 P1-7 完整邀请文案；鸿蒙待办 = 7 个细分 429 码；安卓 = 权威源无待办 -->
