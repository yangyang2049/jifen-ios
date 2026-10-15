# iOS 小组补齐安卓 4a418f65 → 4784819c 增量（2026-10-14）

权威源：国内安卓 `jifen-android`，HEAD `4784819c`「feat(group): refine direct match scheduling」+ 81 项工作区未提交改动。
对照基线：iOS 现有实现（与安卓 `4a418f65` 逐页对齐，22 个 .swift）。
本文记录阶段 1–6 的移植。仍有本文列出的平台交互偏差，不能据此认定整体已 1:1。

> 2026-10-15 二次复核：修正 s4 日期二次平移、s5 表格/筛选/赛制缓存、s2 已读时间戳等问题；逐项状态与最新验证见 [二次复核与修复记录](ios-android-parity-recheck-2026-10-15.md)。下文原始静态自检只代表当时结果。

| 项 | 值 |
| --- | --- |
| 安卓差异总量（4a418f65 → 工作区，group 目录 + ui/components/group + data） | 34 文件，+2197 / -1284（补丁存于 `build/groups-port-20261014/android-group-delta-full.patch`，7050 行） |
| s2 改动 | 4 个源文件 + 2 个测试 + 47 语言资源 + 44 个 catalog |
| s3 改动 | 3 个源文件 + 3 个测试（**无新增本地化键**，复用既有 9 个键） |
| s4 改动 | 3 个源文件 + 1 个测试（**无新增本地化键**） |
| s5 改动 | 4 个源文件 + 2 个测试 + 47 语言资源 + 44 个 catalog + **47 语言 `group_ranking_title` 格式符修复** |
| s6 改动 | 4 个源文件 + 3 个测试 + 47 语言资源 + 44 个 catalog（二维码 H 级容错 + 中心图标、720×920 邀请卡片、邀请门控对齐、举报标题随状态） |
| 编译/测试验证 | **10-15 已执行通过**：103 项单测/本地化、4 项 iPhone UI、1 项 iPad UI；见二次复核记录。文末限制说明为历史状态 |

---

## 阶段 1：契约 / 网络层 / 文案键（前一轮完成）

- 统一 4 个键名：`timing_mode→activity_timing`、`archived_list_empty→archived_empty`、`no_members→activity_registration_empty`、`home_hint→list_add_title`。
- 47 语言补齐 39 个键（en 取 `values/group_*.xml`，zh-Hans 取 `values-zh-rCN`，zh-Hant 取 `values-zh-rTW`）；新增两个无前缀复数键 `archived_count` / `activity_direct_match_count`（同时进 stringsdict 与 `plural-keys.json`）。
- 顺序模式冲突校验：`GroupTrainingViews.lineupIssue` 新增 `skipsConflicts`，sequence 模式跳过重叠冲突（对齐安卓），由 `GroupScheduleEditor` 与 `GroupActivityViews` 传入。
- 9 条 429 / NOT_COACH 错误键补到其余 45 个语言。

## 阶段 2：通知中心（本轮完成）

安卓真源：`screen/group/notice/GroupNoticeInbox.kt`（ViewModel + 列表 + 顶栏 badge）。

| # | 安卓行为（源码依据） | 本轮 iOS 改动 | 状态 |
| --- | --- | --- | --- |
| 1 | 卡片标题为「组名 · 类型标签」，11 类 kind 文案（`noticeLabel`） | `GroupNotification.label`（`GroupExtendedModels` 内 `nonisolated extension`），fallback 与安卓 en 文案逐字一致 | ✅ |
| 2 | `member_removed` / `join_rejected` 不提供「打开」入口 | `GroupNotification.opensGroup` | ✅ |
| 3 | 一行两个动作：未读→「标已读」，已读→「已读」文本；另加「打开小组」 | `GroupNoticeInbox.noticeRow` 用 `.buttonStyle(.borderless)`，打开前先确认已读 | ✅ |
| 4 | 打开小组 = `navigationDestination` push，进入前标已读 | `.navigationDestination(item: $opened)` + 目标 `.task` 标已读（为此给 `GroupNotification` 补 `Hashable`） | ✅ |
| 5 | 已读回执必须回显同一 notice 且带服务端时间戳，否则报错 | `markNoticeSeen` 用服务端返回对象整行替换；`isReceipt(for:)` 校验；失败抛 `GroupFlowError.invalidReceipt` | ✅ |
| 6 | 已读后丢弃在途读取，防止 badge 被旧响应恢复 | 成功后 `noticeRequest += 1`（沿用既有代次守卫） | ✅ |
| 7 | 加载中底部转圈；错误 + 重试（保留 more 状态）；页尾「更多 / 没有更多」 | 新增 `GroupStore.noticeError` / `noticesLoading`，inbox 渲染加载/错误/页尾三态 | ✅ |
| 8 | 未读 badge 超过 99 显示 `99+` | 列表顶栏 badge 文案 | ✅ |
| 9 | 回到列表页（ON_RESUME）刷新未读 | 既有 `GroupListView.onChange(scenePhase)` 已覆盖 | ✅ 已有 |
| 10 | 分页保留所有已加载页、拒收重复 cursor、分页不抬高未读数 | 既有 `loadNotices` 已覆盖 | ✅ 已有 |
| 11 | 平板内容限宽 `ContentMaxWidth.Groups` | **未做**：iOS 列表页沿用系统 List 宽度，与首页 960 限宽分离 | ⚠️ 已知偏差 |

### 本轮文件

| 文件 | 改动 |
| --- | --- |
| `jifen/Features/Groups/GroupRepository.swift` | 新增 `noticeError` / `noticesLoading`；`loadNotices` 维护加载与独立错误；`markNoticeSeen` 改为校验服务端回执并整行替换；`sessionDidChange` 复位 |
| `jifen/Features/Groups/GroupExtendedModels.swift` | `GroupNotification` 补 `Hashable`；新增 `label` / `opensGroup` / `isReceipt(for:)`；`GroupFlowError.invalidReceipt` |
| `jifen/Features/Groups/GroupSupportViews.swift` | `GroupNoticeInbox` 重写：类型标签 + 标已读/打开小组 + 加载/错误/页尾 |
| `jifen/Features/Groups/GroupViews.swift` | 顶栏 badge 99+ |
| `jifenTests/GroupPortParityTests.swift` | 新增 `testNoticeKindsUseTheAndroidLabelsAndOpenRules`、`testNoticeReceiptMustEchoTheAcknowledgedNotice` |
| `jifen/Resources/*.lproj/Localizable.strings`（47） | 新增 16 个键：`group_notice_open` / `_end` / `_seen` / `_receipt_failed` + 12 类 kind 文案 |
| `scripts/localization/catalogs/*.jsonl`（44） | 同上 16 键，`status=reviewed`，note `Codex-authored group notice parity 2026-10-14` |

键名沿用 iOS 既有 `group_*` 前缀，复用 `group_mark_seen` / `group_read_notices` / `group_load_more` / `group_no_notices`，避免两套命名。en 取自安卓 `values/`，zh-Hans 取自 `values-zh-rCN/`，zh-Hant 取自 `values-zh-rTW/`，其余 44 语言人工撰写并沿用各语言既有「活动 / 加入 / 赛果 / 角色」词汇。
导入脚本：`build/groups-port-20261014/import_notice_keys.py`、`import_notice_error_key.py`。

### 静态自检结果

- 47 语言键集完全一致（1778 键/语言），无重复键，`plutil -lint` 通过。
- zh-Hant 无简体字形残留（新增键简繁均不同），en 无中文。
- 5 个改动 Swift 文件 `xcrun swiftc -parse` 0 error（仅语法，不含类型检查）。

---

## 阶段 3：顶栏菜单 / 冷静期横幅（本轮完成）

安卓真源：`screen/group/detail/GroupDetailScreen.kt` 的 `GroupManagementTopBarMenu` 与 `GroupDissolveBanner`、
`screen/group/GroupDetailViewModel.kt` 的 `isAdmin` / `isOwner` / `canTransferOwnership`。

| # | 安卓行为（源码依据） | 本轮 iOS 改动 | 状态 |
| --- | --- | --- | --- |
| 1 | 顶栏 ⋯ 是锚定 `DropdownMenu`（原先是 bottom sheet） | iOS 一直用 `.toolbar(.topBarTrailing) { Menu }`，本身就是顶栏 | ✅ 已有 |
| 2 | 条目按身份显隐，自管理组与危险操作之间插 `HorizontalDivider`（条件 `(isAdmin && !archived) \|\| isOwner`） | `GroupManagementMenu.entries` 统一产出条目序列（含 `.divider`） | ✅ |
| 3 | 编辑资料：`isAdmin && !readOnly` | 同（readOnly = `status != active`，等价安卓 `GroupStatuses.isReadOnly`） | ✅ |
| 4 | 转让：`isOwner && canTransfer`，`canTransfer = isOwner && status ∈ {active, archived}` | `GroupManagementMenu.canTransfer`；**此前 iOS 只挡 `dissolving`，归档/已解散态仍会给入口** | ✅ 修复 |
| 5 | 归档 / 恢复是同一枚开关：`isOwner && !dissolving`，内容按 `archived` 取 restore / archive | `entries` 内 `readOnly ? .restore : .archive` | ✅ |
| 6 | 解散：`isOwner && !dissolving && !archived` | `canDissolve`；**此前 iOS 缺 `!archived`，归档小组里会多出「解散小组」** | ✅ 修复 |
| 7 | 撤销解散：`isOwner && dissolving` | 同 | ✅ |
| 8 | 退出：`!isOwner`（管理员也能退） | 同（但见第 11 条偏差） | ✅ |
| 9 | 举报对所有身份开放（含组长），红字 | 同，且始终排在菜单末尾 | ✅ |
| 10 | 解散 / 退出 / 举报统一红字（`ToolWhistleRed`） | `Entry.isDestructive` → SwiftUI `role: .destructive` | ✅ |
| 11 | 菜单按钮 `enabled = !mutating` | `GroupStore.mutating`（`perform` 内计数器，支持并发写），Menu 整体 `.disabled(store.mutating)` | ✅ |
| 12 | 原「刷新状态」菜单项被移除，改为 `PullToRefreshBox` | iOS 一直有 `.refreshable { await reload() }` | ✅ 已有 |
| 13 | 冷静期横幅：橙色圆角底 + 组长文案居左 / 组员居中 + 组长就地「撤销解散」 | iOS `dissolveBanner` 已是该形态 | ✅ 已有 |
| 14 | `mutating` 时才显示顶部 `LinearProgressIndicator` | **未做**：iOS 用按钮 disabled + 弹层内 `ProgressView` 承载，不在导航栏下挂进度条 | ⚠️ 已知偏差 |
| 15 | 非成员（只读预览）也显示「退出小组」 | **未做**：iOS 对 `role == nil` 只保留举报，不给退出入口 | ⚠️ 已知偏差 |
| 16 | 归档组点「恢复」由 VM 直接执行、不再弹二次确认 | **未做**：iOS 一律走 `GroupManagementView` sheet 二次确认，符合 iOS 惯例 | ⚠️ 已知偏差 |

### 本轮文件

| 文件 | 改动 |
| --- | --- |
| `jifen/Features/Groups/GroupExtendedModels.swift` | 新增 `GroupManagementMenu`：纯值语义的条目策略（`entries` / `canTransfer` / `canDissolve` / `Entry.isDestructive` / `Entry.titleKey`） |
| `jifen/Features/Groups/GroupRepository.swift` | 新增 `mutating` + `mutationCount`，在 `perform` 内增减、`sessionDidChange` 内复位 |
| `jifen/Features/Groups/GroupDetailView.swift` | 顶栏菜单改为遍历 `menuPolicy.entries`；新增 `canManage`（刻意不带 `isActive`）与 `menuAction` |
| `jifenTests/GroupPortParityTests.swift` | 新增 3 项：`testManagementMenuEntriesFollowTheAndroidIdentityAndStatusGates`（12 组合全表）、`testManagementMenuGatesTransferAndDissolveByStatus`、`testManagementMenuMarksDestructiveEntriesAndOmitsTheDividerTitle` |

**顺带修掉一个 iOS 既有行为 bug**：原菜单把 `writable`（含 `group.isActive == true`）套在转让 / 恢复 / 撤销解散上，
导致从「已归档小组」列表进入详情后，**「恢复小组」按钮是 disabled 的，组长无法把自己的小组恢复回来**。
现在状态门控只由条目显隐负责，可用性只判断离线 / 未登录 / 功能开关（`canManage`）。

### 静态自检结果

- 把 `GroupManagementMenu` 单独抽出成可执行脚本，用 `swiftc` 真编译真跑，12 种「身份 × 状态」组合输出与预期表逐条吻合
  （`owner`: `active→edit,transfer,archive,│,dissolve,report` / `archived→transfer,restore,│,report` /
  `dissolving→cancelDissolve,│,report` / `dissolved→restore,│,report`；
  `admin/active→edit,│,leave,report`，只读态无分隔线；`member→leave,report`；非成员→`report`）。
- 3 个改动 Swift 文件 + 测试文件 `xcrun swiftc -parse` 0 error（仅语法，不含类型检查）。
- 无新增本地化键：菜单 9 个键（`group_edit_profile` / `_transfer` / `_archive` / `_restore` / `_cancel_dissolve` / `_dissolve` / `_leave` / `_report` / `_settings`）在 47 语言中均已存在。

---

## 阶段 4：直接排赛编辑页（本轮完成）

安卓真源：`screen/group/activity/GroupActivityLineupScreen.kt`(+475)、`GroupActivityLineupViewModel.kt`(+193)、
`GroupActivityCreateScreen.kt`(+107)；新端点 `POST /direct-lineups`。

| # | 安卓行为（源码依据） | 本轮 iOS 改动 | 状态 |
| --- | --- | --- | --- |
| 1 | 改直接排赛日期时 `setDirectDate` 把所有场次整体平移 delta | `GroupDirectScheduleDraft.date` 在两种模式中统一平移所有场次；提交时才执行一次 `anchored`（10-15 更正，原 sequence 重排会二次平移） | ✅ 修复 |
| 2 | 提交时 `directActivityAnchor` 把过去时间推到 `now + 60s`，并把同一 shift 应用到所有场次 | `GroupTrainingValidation.anchored`（返回「活动开始时间 + 平移后的场次」），`submit` 直接用它组包 | ✅ 修复 |
| 3 | 时间双模式（sequence 按顺序 / estimated 预计时间），sequence 时跳过重叠冲突 + 不按时间重排 | s1 已落地（skipsConflicts）；`reorder` 内 `guard timingMode == "estimated"` | ✅ 已有 |
| 4 | `setTimingMode` 在有已冻结场次（已开赛 / 已有结果）时不许改 | `GroupScheduleEditor` 时间模式 Picker `.disabled(sessions.contains { $0.frozen == true })` | ✅ 修复 |
| 5 | `activityType=direct` + 标题可空（服务端按日期自动生成） | iOS 标题选填 + 自动生成 hint，提交空串 | ✅ 已有 |
| 6 | direct 活动候选人是全部活跃成员，无需报名 | `GroupScheduleEditor.members` 对 `isDirect` 取全部活跃成员；直接排赛页同理 | ✅ 已有 |
| 7 | direct 默认 `timingMode=sequence`、`sessionMinutes=30`、预填 1 个空场次 | iOS 直接排赛页默认 sequence + 30 分钟 + 预填 1 场 | ✅ 已有 |
| 8 | 切赛制时清空所有座位（`setDirectFormat`） | `.onChange(of: format)` 重置 `memberIDs` | ✅ 已有 |
| 9 | `createDirectLineup` 端点与 `GroupDirectLineupBody` | s1 已落地 | ✅ 已有 |
| 10 | **删除排赛草稿本地持久化**（`ActivitySavedDraft` / `persist()` / `decodeActivitySavedDraft` 全删） | iOS 排赛状态是内存态，本来就无草稿要删 | ✅ 无需改动 |
| 11 | 直接排赛是「活动信息页（下一步）→ 排对阵页」两步 | **未做**：iOS 是单页（活动信息 + 时间模式 + 场次），信息全集一致 | ⚠️ 已知偏差 |
| 12 | direct 活动信息页只选日期（`dateOnly`），时间取创建时的默认值 | **未做**：iOS 的 `DatePicker` 同时给日期与时间，是安卓能力的超集 | ⚠️ 已知偏差 |
| 13 | 保存前校验 5 档（conflict / member_limit / sessions / duplicate / incomplete） | iOS 3 档（`lineup_conflict` / `lineup_member_limit` / `lineup_invalid`），粒度不同但都拦得住保存 | ⚠️ 已知偏差 |

### 本轮文件

| 文件 | 改动 |
| --- | --- |
| `jifen/Features/Groups/GroupTrainingViews.swift` | `GroupTrainingValidation` 新增 `shiftAll` / `anchored` 两个纯函数 |
| `jifen/Features/Groups/GroupActivityViews.swift` | `GroupDirectScheduleView`：改日期整体平移；`submit` 用 `anchored` 让活动与场次同源 |
| `jifen/Features/Groups/GroupScheduleEditor.swift` | 时间模式 Picker 在有冻结场次时禁用 |
| `jifenTests/GroupPortParityTests.swift` | 新增 2 项：`testDirectScheduleMovesTheActivityAndItsMatchesTogether`、`testDirectScheduleDateChangesShiftEverySessionByTheSameDelta` |

无新增本地化键（直接排赛页结构上不允许删掉最后一场，`sessions.isEmpty` 分支不会命中）。

### 静态自检结果

- 把 `shiftAll` / `anchored` 抽出成可执行脚本用 `swiftc` 真编译真跑，8 条断言全绿
  （未来时间不动 / 过去时间推到 now+60s 且场次整体平移 / 场间 1800s 间隔保持 / 平移 1 天 / 零位移与 NaN 位移不动）。
- 3 个改动 Swift 文件 `xcrun swiftc -parse` 0 error。

---

## 阶段 5：赛果与排行（本轮完成）

安卓真源：`detail/GroupDetailRecordsTab.kt`(+229/-…)、`result/GroupResultEntryScreen.kt`(+267/-…)、
`result/GroupResultScoreControls.kt`(+154)、`result/GroupResultDraft.kt`(+22)、删除 `result/GroupResultFormDraft.kt`(-40)。
iOS 侧 s1 已落地 `GroupPermissions.confirmationTasks` / `resultHistory` / 待确认段 / 排行表格，
本轮补齐剩下的行为差。

| # | 安卓行为（源码依据） | 本轮 iOS 改动 | 状态 |
| --- | --- | --- | --- |
| 1 | 排行榜按 section 独立记错：`sectionErrors[SINGLES_RANK/DOUBLES_RANK]` | 新增 `GroupStore.rankErrors`，键为 `rankKey(group, format)`；`loadRankings` 成功清、失败写；不再污染 `error` / `detailErrors` | ✅ |
| 2 | 榜空且加载失败：显示「加载失败」+ `GroupPillButton` 重试（`vm.load(force = true)`） | `rankingSection` 三态：有榜 → 表格；失败 → `GroupEmptyCard` + 重试（`loadRankings`）；无数据 → `group_ranking_empty` | ✅ |
| 3 | 榜空且无错：居中显示 `group_ranking_empty`（带赛制名），且不画筛选 chips | 10-15 更正：两赛制任一有榜或有错误即显示筛选 chips；所选赛制为空则显示带赛制名空态，不能用比赛记录是否为空代替 | ✅ |
| 4 | 明细行是占位：`hasDetailInput()` 为假时只按总分校验，展开明细不算错 | `GroupInputValidation.scoredDetails(includesSets:sets:)`；`GroupMatchEditor.validManualResult` 与 `submit()`、修复上传页同步改用 | ✅ |
| 5 | 快捷比分按「A 胜 / B 胜」两列展示（`GroupQuickResultColumn`） | `GroupMatchEditor.quickScores` 两列 + 选中态，`group_entry_a_wins` / `group_entry_b_wins` | ✅ |
| 6 | 删除录分草稿持久化（`GroupResultFormDraft` / `groupResultDraftEntryKey` / `saveResultDraft`） | iOS 录分表单是内存态 `@State`，**本来就无草稿**，无需下线 | ✅ 已对齐 |
| 7 | 删除改动明细前的二次确认与「恢复分数」（`removesDetailInputFrom` / `recovery` / `retainRecovery`） | iOS 无等价弹窗 | ✅ 已对齐 |
| 8 | 规则摘要只给匹克球显示封顶（羽毛球封顶是衍生值） | iOS 摘要不含 `pointCap` | ✅ 已对齐 |
| 9 | 待确认只列「我能确认的」，他人待确认留在比赛记录（`groupResultTasks` / `groupResultHistory`） | s1 已落地，本轮补单测 | ✅ 已有 |
| 10 | 规则 chips 分组灰底块 `RulesChipsGroup`、展开箭头变上箭头、去掉「完成」按钮 | **未做**：iOS 规则编辑是系统 sheet（`GroupRulesEditor`），已有分区与完成按钮，属控件层差异 | ⚠️ 已知偏差 |
| 11 | 日期选择器 `dateOnly=true`、`latestDate=今天`、无快捷日期 | iOS `DatePicker(in: ...Date())` 含时间，是超集（与 s4 同一条） | ⚠️ 已知偏差 |
| 12 | 安卓两列快捷比分只放 `a > b` 与 `b > a`，**平局比分被漏掉** | iOS 保留平局单独一行（`group_result_draw`） | ⚠️ 有意偏差（修安卓回归） |

### 顺带修掉的真实崩溃：`%1$s` 在 Swift 里必崩

安卓 `String.format` 用 `%1$s` 表示字符串，Swift 的 `String(format:)` 把 `%s` 当**C 字符串**读取，
传入 Swift `String` 会段错误（实测 `exit 139`）：

```swift
String(format: "%1$s leaderboard", "Singles")   // ← SIGSEGV
String(format: "%@ leaderboard", "Singles")     // ← OK
String(format: "%1$d matches", 3)               // ← OK（%d + Int 安全）
```

`group_ranking_title` 是 s1 从安卓 XML 整段搬来的，47 个语言全写成 `%1$s`，
**打开小组战绩页就会崩**。本轮把 47 个 lproj 的该键统一改成 `%@`，
并在 `LocalizationIntegrityTests` 加防回归断言 `testLocalizableValuesNeverUseCStringPlaceholders`，
禁止任何 `Localizable.strings` 值只含 `%s`（不含 `%@` / `%d`）。

### 本轮文件

| 文件 | 改动 |
| --- | --- |
| `jifen/Features/Groups/GroupRepository.swift` | 新增 `rankErrors` + `rankKey`；`loadRankings` 独立记错；`sessionDidChange` 清空 |
| `jifen/Features/Groups/GroupDetailView.swift` | `results()` 拆出 `rankingSection(_:recordsEmpty:)` 三态；`uploads` 提前复用 |
| `jifen/Features/Groups/GroupExtendedModels.swift` | `GroupInputValidation.scoredDetails` |
| `jifen/Features/Groups/GroupForms.swift` | `scoredDetails` 校验；`quickScores` 两列 + `quickButton` |
| `jifen/Features/Groups/GroupSupportViews.swift` | 修复上传页明细校验同步 |
| `jifenTests/GroupPortParityTests.swift` | `testSetDetailsAreOptionalPlaceholdersUntilAScoreIsEntered`、`testRankingFailureIsScopedPerGroupAndFormat`、`testResultHistoryKeepsOtherPeoplesPendingResults` |
| `jifenTests/LocalizationIntegrityTests.swift` | `testLocalizableValuesNeverUseCStringPlaceholders` |
| `jifen/Resources/*.lproj/Localizable.strings`（47） | 修 `group_ranking_title` 格式符；新增 `group_ranking_empty` / `group_entry_a_wins` / `group_entry_b_wins` / `group_result_draw` |
| `scripts/localization/catalogs/*.jsonl`（44） | 同上 4 键，`status=reviewed`，note `Codex-authored group result parity 2026-10-15` |

导入脚本：`build/groups-port-20261014/import_result_keys.py`（源语言取安卓 `values/` `values-zh-rCN` `values-zh-rTW`，导入时把 `%1$s` 归一成 `%@`）。

### 静态自检结果

- `scoredDetails` 抽成可执行脚本 `swiftc` 真编译真跑，4 条断言全绿（未开明细 / 开了但无行 / 有行 / 未开但有行）。
- 47 语言键集完全一致（1782 键/语言）、无重复键；`plutil -lint` en / zh-Hans / zh-Hant 全 OK。
- 4 个改动 Swift 文件 + 2 个测试文件 `xcrun swiftc -parse` 0 error。

---

## 阶段 6：分享 / 举报（本轮完成）

| 安卓真源 | 增量 | iOS 落点 |
| --- | --- | --- |
| `share/GroupShareScreen.kt` | +166 | `GroupQRViews.swift` |
| `detail/GroupReportForm.kt` | +16 | `GroupPreviewReportView.swift` |
| `components/group/GroupFeedback.kt` | +28 | `GroupDetailView.swift`（`GroupSectionTitle`） |

### 逐条对照

| # | 安卓行为 | iOS 原状 | 现在 |
| --- | --- | --- | --- |
| 1 | 二维码纠错级别 `ErrorCorrectionLevel.H`（30% 容错） | `correctionLevel = "M"`（15%） | 改 `"H"` |
| 2 | 把圆角 App 图标烤进二维码位图（边长 18%，白色圆角衬底） | 无中心图标 | 新增，屏上预览与导出卡片同源 |
| 3 | 导出 720×920 邀请卡片（浅绿标题块 + 二维码 + 左下说明 / 右下品牌） | 只分享裸二维码图 | 新增 `GroupInviteCard`，分享按钮改出卡片 |
| 4 | 小组名与小组号合成一个居中标题块（号为 secondary） | 名 / 二维码 / 号 三行分离 | 合并居中块 |
| 5 | `canInviteToGroup`：status 严格 active、policy 黑名单 `!= closed`、availability 黑名单四类、满员不可邀 | status 容忍 nil、policy 与 availability 都是白名单 | 全部对齐安卓 |
| 6 | 已有举报时标题为「Update report」 | 恒为「Report group」 | 按 `current == nil` 切换 |
| 7 | `GroupSectionArrow` 触控目标 48dp | 箭头按钮无最小触控区 | 44pt + `contentShape`，图标 tint 改 `textSecondary` |

### 代码落点

- `GroupQRViews.swift`
  - `GroupQRCode.image`：`correctionLevel` 改 `"H"`，末尾叠加圆角 App 图标；新增 `appIcon`
    （优先 `AppLogo` 资源，回退 `CFBundleIcons~ipad` / `CFBundleIcons` 的主图标文件名）。
  - 新增 `GroupInviteCard`：常量照搬 `buildGroupInviteBitmap`；`baseline(centeringTextOf:at:)`
    把安卓的 baseline 语义换算成 UIKit 的顶边坐标。
  - `GroupShareView`：名 + 号合成居中块；卡片在 `.task` 里生成一次（不进 body）。
- `GroupExtendedModels.swift`：`GroupPermissions.canInvite` 改黑名单语义，缺字段按安卓 DTO 默认值兜底。
- `GroupPreviewReportView.swift`：导航标题随已有举报状态切换。
- `GroupDetailView.swift`：`GroupSectionTitle` 的导航箭头加 44pt 最小触控区。

### 本轮文件

| 文件 | 改动 |
| --- | --- |
| `jifen/Features/Groups/GroupQRViews.swift` | 二维码 H 级 + 中心图标、`GroupInviteCard`、分享页布局 |
| `jifen/Features/Groups/GroupExtendedModels.swift` | `canInvite` 门控对齐 |
| `jifen/Features/Groups/GroupPreviewReportView.swift` | 举报标题 |
| `jifen/Features/Groups/GroupDetailView.swift` | section 箭头触控区 |
| `jifenTests/GroupPortParityTests.swift` | +3 项（邀请门控、卡片尺寸、二维码模块尺寸） |
| `jifen/Resources/<47 个 lproj>/Localizable.strings` | +4 键 |
| `scripts/localization/catalogs/<44 个>.jsonl` | +4 行 |
| `build/groups-port-20261014/import_share_keys.py` | 新增（一次性导入脚本） |

### 静态自检结果

| 检查 | 结果 |
| --- | --- |
| 47 语言键集一致（1786 键/语言） | ✅ 无差异、无重复键 |
| `plutil -lint`（en / zh-Hans / zh-Hant / ja） | ✅ OK |
| 新增键格式符安全（`group_` 值无 `%s` / `%1$s`） | ✅ 0 处 |
| 卡片布局常量自洽（独立脚本真编译真跑） | ✅ 9/9 PASS |
| 5 个改动 Swift 文件 `swiftc -parse` | ✅ 0 error |
| 并发会话（30 分钟内 `jifen/` 写入） | ✅ 无 |

> 卡片布局验证脚本覆盖：二维码完整落在卡片内且在标题块下方、品牌图标不越界、
> 文案列宽 470px 足够、footer 文本视觉中心精确落在 y=842。
> UIKit 位图渲染本身无法在 macOS 上跑，需 Xcode 编译后真机/模拟器验证。

### 已知偏差（有意保留）

| 偏差 | 原因 |
| --- | --- |
| 分享用系统 `ShareLink` 而非 `UIActivityViewController` | iOS 原生交互；安卓的 `shareGroupQr` 走 FileProvider 是平台特定实现 |
| 无 `group_share_message` 五段式邀请文案 | iOS 分享 URL + 图片已覆盖核心链路；该模板 5 占位符 × 47 语言风险过高 |
| 保留「复制小组号」按钮 | 安卓对应「分享小组号」；复制是 iOS 惯例且更实用 |
| `GroupReportForm` 按钮统一改用 `AppActionButton` 未移植 | 属 Compose 控件层重构，iOS 已有自己的按钮样式体系 |

## 验证交接（10-14 历史状态；10-15 已实际编译和测试）

本机 CLI 的 Swift 宏插件服务器报 `sandbox-exec: sandbox_apply: Operation not permitted`
（连带 `swift-plugin-server produced malformed response`），任何含 `@State` / `@Observable` 的文件都无法类型检查，
全量 `xcodebuild` 还在 Scoreboard 批次触发 `Assertion failed: (isConcrete())` 的 swift-frontend 崩溃。
因此**编译与测试需在允许嵌套沙箱的终端或 Xcode 中执行**：

```sh
# 编译
xcodebuild -project jifen.xcodeproj -scheme jifen \
  -destination "platform=iOS Simulator,id=86871B65-E0ED-4FBD-9F93-F3FB6246A895" \
  -derivedDataPath build/groups-port-20261013/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

# 小组单测 + 本地化
xcodebuild -project jifen.xcodeproj -scheme jifen \
  -destination "platform=iOS Simulator,id=86871B65-E0ED-4FBD-9F93-F3FB6246A895" \
  -derivedDataPath build/groups-port-20261013/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -only-testing:jifenTests test
```

注意：不要加 `CODE_SIGNING_ALLOWED=NO`（Keychain 会报 `-34018` 假失败）。
