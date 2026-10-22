# 小组功能三端独立核验（安卓 / 鸿蒙 / iOS）

> 核验时间：2026-10-15 19:xx GMT+8 · 类型：**以当前工作区源码为准的独立核验**（未修改任何生产代码）
> 契约真源：`jifenqi-backend/api-server`
> 核验端：`jifen-android`(Kotlin+Compose) · `jifen-hos`(ArkTS) · `jifen-ios`(SwiftUI)
> 前置：`jifen-android/docs/2026-10-15-group-cross-end-audit.md`（F1–F5）· `jifen-hos/docs/groups/cross-end-group-audit-2026-10-15.md`（F6–F10）· `jifen-ios/docs/group-cross-end-audit-remediation-2026-10-15.md`（修复轮）
>
> **本报告不采信上述文档的结论**，全部以源码重查；文档声称的修复逐条独立复核。

---

## 0. 结论摘要

| 端 | 状态 | 一句话 |
| --- | --- | --- |
| Android | ✅ 权威源 | HEAD `2504fe36`（10-15 14:48「收口 3.3 小组体验并修复批量已读」）；16 项未提交（8 项 group） |
| HarmonyOS | ✅ 已对齐 | HEAD `db4bb679`（10-15 14:47）；**160 项未提交（55 项 group）** |
| iOS | ✅ 已对齐 | HEAD `66c2cc55`（10-15 14:47）；66 项未提交（18 项 group） |

**核心结论：三端功能面无缺口（0 项 🔴）。** F1–F10 十条审计发现**全部真实落地**（逐条独立复核见 §3）。剩余的只是**结构性/有意差异**（命名体系、语言数、目录分层、分享形态），不构成功能缺失。

**三端均存在未提交的小组改动**——10-15 的 F6–F10 修复 + 3.3 收口遗留尚未 commit，这是当前最需要在意的工程风险。

---

## 1. 三端基线（2026-10-15 工作区实测）

| 项 | Android | HarmonyOS | iOS |
| --- | --- | --- | --- |
| 分支 | `3.3` | `3.3` | `3.3` |
| HEAD | `2504fe36` 10-15 14:48 | `db4bb679` 10-15 14:47 | `66c2cc55` 10-15 14:47 |
| 提交主题 | 收口 3.3 小组体验并修复批量已读 | 收口 3.3 界面与小组改进并修复批量已读 | 同左 |
| 小组源码位置 | `screen/group/` + `ui/components/group/` + `managers/group/` + `data/model/group/`；契约在 `shared-model/.../model/group/GroupContract.kt` | `pages/group/` + `model/group/` + `api/group/` + `managers/group/` + `helpers/` | `jifen/Features/Groups/`（**扁平**，27 文件） |
| 源码规模 | **72 `.kt` / 19 663 行**（+ shared-model 590 行） | **79 文件（ets+ts） / 18 259 行** | **27 `.swift` / 6 365 行** |
| 页面数 | 16 个 Screen/Composable | 12 个 Page + 26 组件 | 约 25 个 View（同文件多视图） |
| 未提交改动 | 16 项（**8 项 group**） | **160 项（55 项 group）** | 66 项（18 项 group） |
| 端点口径 | `GroupApiService.kt` **59 个 `suspend fun`** | `GroupRepository.ts` 接口 **67 方法** / Remote 实发 **64 请求** | `GroupRepository.swift` 去重 **58 条路径** |
| `group_` 文案键 | **661** × 3 目录（values / zh-rCN / zh-rTW，三集全等） | **609** × 7 目录（base/en_US/zh_CN/zh_HK/zh_Hant/zh_MO/zh_TW，全等） | **357** × **47** 语言（与 en 逐目录全等，0 差异） |
| 跨端审计文档 | `docs/2026-10-15-group-cross-end-audit.md`（未跟踪） | `docs/groups/cross-end-group-audit-2026-10-15.md`（未跟踪） | `docs/group-cross-end-audit-remediation-2026-10-15.md`（未跟踪） |

**键名交集（精确统计）**：Android↔Harmony **429** ｜ Android↔iOS **70** ｜ Harmony↔iOS **53**。
iOS 刻意采用 `group_<短名>` 体系（`GroupModels.swift:16` `groupText`），**不是覆盖缺失**——代码实际消费的键在 47 语言中全部存在。

---

## 2. 功能矩阵（页面级，三端对照）

图例：✅ 已实现 ｜ ⚠️ 实现方式有差异 ｜ 🔴 缺失

| # | 能力 | Android | HarmonyOS | iOS |
| --- | --- | --- | --- | --- |
| 1 | 小组列表 | ✅ `GroupListScreen` | ✅ `GroupListPage` | ✅ `GroupListView` |
| 2 | 归档列表 | ✅ `ArchivedGroupListScreen` | ✅ `GroupListPage` archivedOnly | ✅ `GroupArchivedListView` |
| 3 | 建组（校验/名称候选） | ✅ `GroupCreateScreen` | ✅ `GroupCreatePage` | ✅ `GroupCreateView` |
| 4 | 加入 / 扫码 / 预览 | ✅ `GroupJoinScreen` | ✅ `GroupJoinPage` | ✅ `GroupJoinView`+`GroupScannerView` |
| 5 | 详情四页签容器 | ✅ `GroupDetailScreen` | ✅ `GroupDetailPage`(3030 行) | ✅ `GroupDetailView`(634 行) |
| 6 | 概览页签 | ✅ `GroupDetailOverviewTab` | ✅ `buildOverviewTab` | ✅ `overview()` |
| 7 | 活动页签（peer） | ✅ `GroupDetailActivitiesTab` | ✅ `buildActivityTab` | ✅ `activities()` |
| 8 | 战绩页签 + 排行 | ✅ `GroupDetailRecordsTab` | ✅ `buildRecordsTab`+`GroupRankingTable` | ✅ `results()`+`GroupRankingTable` |
| 9 | 成员页签 + 已移除分片 | ✅ `GroupDetailMembersTab` | ✅ `buildMembersTab` | ✅ `members()` |
| 10 | 活动创建/编辑/详情 | ✅ `GroupActivityCreateScreen`+`GroupActivityDetailScreen` | ✅ `GroupActivityPage` | ✅ `GroupActivityCreateView`+`GroupActivityView` |
| 11 | 直接排赛 | ✅ `GroupActivityLineupScreen(newDirect)` | ✅ `GroupActivityLineupPage` | ✅ `GroupDirectScheduleView` |
| 12 | 对阵编排 | ✅ 同上 | ✅ 同上 | ✅ `GroupScheduleEditor`+`GroupActivityLineupEditor` |
| 13 | 录分 / 补记 | ✅ `GroupResultEntryScreen`+`GroupResultScoreControls` | ✅ `GroupResultPage` | ✅ `GroupMatchEditor`+`GroupResultScoreControls` |
| 14 | 赛果详情 / 确认 / 作废 | ✅ `GroupResultDetailScreen` | ✅ `GroupResultDetailPage` | ✅ `GroupResultDetailView`+`GroupRemoteResultView` |
| 15 | 个人战绩 | ✅ `GroupMemberResultsScreen` | ✅ `GroupMemberResultsPage` | ✅ `GroupMemberResultsView` |
| 16 | 分享（号码/QR/链接） | ✅ `GroupShareScreen`（**海报**） | ⚠️ `GroupSharePage`（**纯 QR**） | ✅ `GroupShareView`（**海报**） |
| 17 | 通知中心 + 批量已读 | ✅ `GroupNoticeInbox` | ✅ `GroupNoticePage` | ✅ `GroupNoticeInbox` |
| 18 | 训练组页签（coaching） | ✅ `GroupTrainingTab`+`GroupTrainingPlanScreen` | ✅ `buildTrainingTab`+`GroupTrainingPlanPage`(1378 行) | ✅ `GroupTrainingTab`+`GroupScheduleEditor` |
| 19 | 举报（组内 / 预览） | ✅ `GroupReportDialog`+`GroupReportForm` | ✅ `GroupReportDialog`+`GroupJoinReportDialog` | ✅ `GroupReportView`+`GroupPreviewReportView` |
| 20 | 顶栏管理菜单 + 冷静期 | ✅ `GroupManagementTopBarMenu`+`GroupDissolveBanner` | ✅ 顶栏 + `GroupListActionsDialog` | ✅ `GroupManagementMenu`+`GroupManagementView` |
| 21 | 权限矩阵 | ✅ `GroupMemberActionPolicy`+`GroupJoinAvailability`+`GroupResultPermissions` | ✅ `GroupActivitySessionPolicy`+`GroupParity` | ✅ `GroupPermissions`(`GroupExtendedModels`) |
| 22 | 离线队列 / 幂等 / 退避 | ✅ `GroupUploadManager`（双 Mutex） | ✅ `groupUploadQueue`+`groupPendingWrites`+`groupConnectivityRetry` | ✅ `GroupLocalPersistence`+`GroupRepository.sync` |
| 23 | 批量报名编辑 | ✅ `GroupActivityRegistrationSheet` | ✅ `GroupActivityPage` | ✅ `GroupRegistrationEditor` |
| 24 | 待上传修复入口 | ✅ `GroupUploadManager.repair` | ✅ `groupUploadQueue.repairGroupUpload` | ✅ `GroupUploadRepairView` |
| 25 | 本地化覆盖 | ✅ 661×3 | ✅ 609×7 | ✅ **357×47** |

**统计：Android 25/25 ✅ ｜ HarmonyOS 24 ✅ + 1 ⚠️（#16 纯 QR）｜ iOS 25/25 ✅ ｜ 🔴 0 项。**

---

## 3. F1–F10 审计链独立复核（逐条重查源码）

> 这是本次核验的核心：三个仓库各自宣称修复的项，逐条回源码验证。

| 项 | 声明 | 独立复核结果 | 证据（本次实查） |
| --- | --- | --- | --- |
| **F1** 鸿蒙乒乓球默认局制 3→5 | 已修 | ✅ **属实** | `jifen-hos/.../model/group/GroupRules.ts:47` `defaultBestOf: 5`（同文件 badminton :35 / pickleball :59 / tennis :71 均为 3，仅乒乓球为 5，与后端 `capabilities.ts:44` 一致） |
| **F2** iOS 取消原因补 300 上限 | 已修 | ✅ **属实** | `GroupActivityPolicy.swift:10` `value.utf16.count <= cancelReasonMax`（`cancelReasonMax=300`，`:7`） |
| **F3** 鸿蒙举报原因收敛为单一入口 | 已收敛 | ✅ **属实** | `GroupRules.ts:77` 导出 `GROUP_REPORT_REASONS`（7 项）；`GroupReportDialog.ets:44`、`GroupJoinReportDialog.ets:96` 均 `import` 后 `ForEach`，副本已删 |
| **F4** 鸿蒙补统一只读判断 | 已收敛 | ✅ **属实** | `GroupTypes.ts:40` `isReadOnlyStatus`；全仓 **73 处**调用；`pages/group/` 内已无内联 `status === 'active'` |
| **F5** 三端成员名上限解耦 | 已加常量 | ✅ **属实** | Android `GroupContract.kt:136` `GROUP_MEMBER_NAME_MAX = 24`（`:268` 使用）；iOS `GroupExtendedModels.swift:263` `value.utf16.count <= maximum`（maximum=24）；鸿蒙 `GroupRules.ts:82` |
| **F6** iOS 举报状态显式映射 | 已修 | ✅ **属实** | 新增 `GroupStatusText.swift:40-43` 四态 switch（含 `processing` 兼容）；`GroupPreviewReportView.swift:15` 已改用 `current.statusLabel`；4 键 × 47 语言存在 |
| **F7** iOS 计数口径收敛 UTF-16 | 已修 | ✅ **属实（且有保留项）** | 三处已改 `utf16`：`GroupTrainingViews.swift:141`（地点/备注 80/200）、`:177`（场地名 16）；**有意保留 2 处 scalar**：`GroupExtendedModels.swift:283`（小组名，后端标量规则）、`GroupActivityPolicy.swift:18`（活动标题 40，后端标量）——与后端口径一致，非漏扫 |
| **F8** iOS 补号码位数区间 | 已修 | ✅ **属实** | `GroupModels.swift:158-159` `groupNoMinLength/groupNoMaxLength`（可选）+ `:161` `groupNumberLengths`（兜底 6…8）；`formatted` 已改为**仅 6/8 位分组**（`:272` `guard number.count == 6 || number.count == 8`） |
| **F9** iOS 引入显式状态映射 | 已修 | ✅ **属实** | `GroupStatusText.swift` 覆盖 group/activity/result/report/trainingSession/leaveNotice 六族；`ScoreGroup/GroupActivity/GroupResult/GroupReportStatus` 均加 `statusLabel` 扩展；未知值回落本地化 `unknown` 而非原文 |
| **F10** 「训练组仅教练确认」下沉三端 | 已修 | ✅ **属实** | 鸿蒙 `GroupParity.ts:73` `if(group?.groupType==='coaching' && (me.role!=='owner' \|\| group.isCoach===false))return 'read_only'`；安卓 `GroupResultPermissions.kt:69` 新增 `isCoaching/isCoach` 参数 + `:71` `if (!groupActive \|\| (isCoaching && !isCoach)) return READ_ONLY` + `:72` owner authority 加 `!isCoaching` 前置；iOS `GroupExtendedModels.swift` confirmation 同步 |

**结论：F1–F10 全部真实落地，无回退、无"文档声称但代码未改"。**

---

## 4. 仍存在的差异（全部为结构性/有意，非缺陷）

| # | 差异 | Android | HarmonyOS | iOS | 性质 |
| --- | --- | --- | --- | --- | --- |
| D1 | **分享形态** | 720×920 品牌海报 + APP 图标（`buildGroupInviteBitmap`） | **纯二维码**（`GroupSharePage.ets` 无位图合成） | 720×920 品牌海报（`GroupInviteCard`） | ⚠️ 唯一的功能面不对等；鸿蒙侧待决策 |
| D2 | 自定义 scheme deep link | 注册 `jifenqi://groups/join` | 仅 HTTPS | 仅 HTTPS（`jifenqi.com`/`iscoreboard.live`） | 有意差异（iOS/鸿蒙按地区区分国内/国际域名） |
| D3 | `group_` 键命名体系 | 661 个长名（`group_audit_ui_*`…） | 609 个（近安卓） | 357 个短名（`group_<短>`） | 命名分叉；语义覆盖需人工映射（交集仅 70/53） |
| D4 | 语言覆盖 | 3（zh 双体 + default） | 7 | **47** | 市场/平台差异 |
| D5 | 目录结构 | 分层（screen/ui/managers/model） | 分层（pages/model/api/managers） | **扁平** 27 文件平铺 | 工程结构差异，不影响契约 |
| D6 | 端点方法数 | 59 | 67 接口 / 64 请求 | 58 路径 | 计数口径不同（鸿蒙含能力目录拆分），实际覆盖一致 |

> D1 是唯一"用户可见且三端不一致"的项：安卓/iOS 分享出去是一张带品牌页脚的邀请卡，鸿蒙分享出去是二维码图片。既有对比文档已记录该差异并标注"鸿蒙待确认是否需要同款海报"，**至今未决**。

---

## 5. 独立核验过程中排除的"伪问题"

为避免误报，以下曾疑似但不成立的项一并记录（均为工具口径所致）：

- **iOS `group_pending_approval` / `group_reject` 疑似缺失 → 实为存在**（`en.lproj:1663/1677`）。首次用 `grep 'group_pending\|group_reject'` 判"无"，是 **macOS BSD grep 的 BRE 不支持 `\|` 交替**造成的假阴性；改用 `grep -E` 后两个键都在。此坑在前置文档中已有记录，本次再次踩中。
- **iOS `group_first_to` / `group_advantage` / `group_timed` 缺失 → 无影响**：后端 `capabilities.ts:81-84` 下发的取值域只有 `["best_of","play_all"]` 与 `["regular","tiebreak_only"]`，对应的 `group_best_of` / `group_play_all` / `group_regular` / `group_tiebreak_only` **四个键 iOS 全有**，不会回落到原文。
- **iOS `GroupViews.swift:27` 的 `groupText(..., request.status)` → 非动态键兜底**：首参是字面量三元式（`pending_approval`/`reject`），第二参才是 fallback，符合显式映射要求。

---

## 6. 建议

| 优先级 | 项 | 端 | 说明 |
| --- | --- | --- | --- |
| **P0** | 三端小组改动提交 | Android / HarmonyOS / iOS | 三端各有未提交 group 改动（8 / 55 / 18 项）。鸿蒙 160 项总量中含大量非小组改动，**建议按目录分批提交**（`git status --short \| grep -i group`），避免与并行会话冲突丢改动 |
| P1 | 决定鸿蒙分享是否补海报（D1） | HarmonyOS | 三端唯一功能面不对等；若产品要求"分享出一张牌"，则需在 ArkTS 侧做 OffscreenCanvas/pixelMap 合成 |
| P2 | 建立三端键名映射表（D3） | 文档 | iOS 357 ↔ 安卓 661 ↔ 鸿蒙 609；当前交集仅 70/53，每次 parity 审计都要人工对齐词义 |
| P2 | 防回归断言 | 三端 | ① `getSportCapability('table_tennis').defaultBestOf == 5`（防 F1）；② `Features/Groups/**` 内 `unicodeScalars.count` 白名单守卫（防 F7）；③ 代码拼接键必须存在于全部 locale（防 F6） |

---

## 7. 可复现凭据

```bash
# 三端基线
for d in jifen-android jifen-hos jifen-ios; do (cd /Users/yangyang/Desktop/jifenqi/$d && \
  git rev-parse --abbrev-ref HEAD && git log -1 --pretty='%h %ad %s' --date=format:'%F %R' && git status --short | wc -l); done

# 文案键精确统计（python，见本报告 §1）：Android 661×3 / Harmony 609×7 / iOS 357×47
# F1 复核
grep -n 'defaultBestOf' jifen-hos/entry/src/main/ets/model/group/GroupRules.ts   # :47 = 5
# F4 复核
grep -rn 'isReadOnlyStatus' jifen-hos/entry/src/main/ets | wc -l                  # 73
# F10 复核
sed -n '69,73p' jifen-android/app/src/main/java/com/douhua/jifen/screen/group/GroupResultPermissions.kt
sed -n '72,73p' jifen-hos/entry/src/main/ets/model/group/GroupParity.ts
# D1 复核
grep -nE 'pixelMap|OffscreenCanvas|Canvas' jifen-hos/entry/src/main/ets/pages/group/GroupSharePage.ets   # 仅二维码
grep -nE 'UIGraphicsImageRenderer|720' jifen-ios/jifen/Features/Groups/GroupQRViews.swift                # 有海报
```

---

## 8. 变更说明

本次**未修改任何生产代码**，仅新增本报告。
所有行号为 2026-10-15 工作区快照；三端均有在途未提交改动，核验以工作区当前内容为准。
未执行：三端编译、真机冒烟、真实服务端写入、折叠屏回归。
