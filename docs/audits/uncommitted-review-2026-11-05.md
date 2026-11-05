# 未提交改动全量自检报告（2026-11-05）

> ⚠️ **已被 `uncommitted-review-2026-11-06.md` 取代**：本文 5 个阻断项已于 2026-11-06 凌晨全部修复，当前状态与提交建议请以复核版为准。本文仅保留为历史快照（指纹 `da85474e…`），请勿据此判断当前工作区。

> 状态标记：🔴 阻断（提交前必须修） · ⚠️ 风险（评估后决定） · ✅ 已验证通过
> 审查方式：逐个 diff 阅读 + 两组独立深度代码审查 + 静态交叉验证（脚本/解析器/覆盖率统计）。全程只读，未修改任何业务文件。
> 本报告自身为新增文件（`docs/audits/` 下），属于本次检查产物，提交时需单独决定是否纳入。

---

## 一、结论先行

🔴 **暂不建议提交，也不建议一次性整包提交。**

共 **136 项未提交改动**（89 个已跟踪文件修改 + 47 个新增未跟踪文件），覆盖 4 个相互独立的功能族、51 个本地化文件、工程版本配置和一份 1.3 MB 的分析报告。发现 **5 个阻断项**、**约 20 个风险项**；已验证项约 15 类。

阻断项集中在两处：**计分板照片主题的跨端 wire 编码会丢背景图**、**样式工作台的「恢复默认」状态不自洽**；以及**台球小组的结果解码契约与持久化异常扩散**。此外 44 种语言的工作台文案缺 key、另有 97 个 key 为英文占位，多语言发版不可接受。

⚠️ **另有两项环境/流程限制必须在提交前处理**：Xcode 编译与 XCTest 在本环境无法执行（包解析被沙箱拒绝）；审查期间工作区发生并发写入（87→89 文件、6388→6512 行），最终快照已稳定但仍需提交前复核。

---

## 二、审查范围与快照

| 项目 | 值 |
|---|---|
| 仓库 / 分支 | `jifen-ios` / `3.4.1` |
| HEAD | `15d6e9db feat(ios): 完成3.4.1计分增强、Duo适配与发版检查` |
| 上游 | `origin/3.4.1`，无 ahead / behind |
| 暂存区 staged | 0（全部改动都在 unstaged） |
| 已跟踪修改 | 89 个文件，`+6512 / -209` |
| 新增未跟踪 | 47 个文件，约 1.6 MB（其中 `docs/analytics/2026-10/` 22 个文件 / 1.3 MB） |
| diff 指纹 | `git diff \| sha256` 前 16 位 `da85474e35a811d0`（连续 3 次采样一致，快照稳定） |
| 忽略文件 | 未纳入（`.DS_Store`、`build/`、`.xcresult`、业务授权 docx 等，符合 `.gitignore` 约定） |
| 其他 worktree | `/private/tmp/jifen-zhhant-check`（detached HEAD，标记 prunable）；本次未审查 |
| stash | 3 条历史 stash，未纳入本次范围 |

**并发写入记录**：首次采样为 87 文件 / +6388，随后变为 89 / +6390 → +6501 → +6511 → +6512。期间新增了 `zh-Hans/zh-Hant.lproj/WechatBinding.strings` 两处文案改动，且 `VipCommunity.swift` 曾出现 `|| true // TEMP-VERIFY` 临时逻辑、复核时已移除。最终态 `grep` 确认无 `TEMP-VERIFY`/`FIXME`/`print`/`|| true` 新增残留。

---

## 三、改动全景

| # | 改动族 | 主要文件 | 规模 | 状态 |
|---|---|---|---|---|
| 1 | 计分板样式工作台（全屏重做、手机/投屏预览、全屏预览） | `ScoreboardStyleEditOverlay.swift`（+456/-34）、`ScoreboardStyleEditorController.swift`、`ScoreboardAppearance.swift` | 大 | 🔴 2 项阻断 + 多项风险 |
| 2 | 照片主题（JPEG 背景、dim / panelOpacity、撤销） | 新增 `ScoreboardPhotoTheme.swift`、`scoreboard_event_background` 资源 | 大 | 🔴 跨端链路阻断 |
| 3 | 发球指示器运动图标 + 篮球纳入 V2 | `ServeTriangleIndicator.swift`、`ExternalDisplayView.swift`、`Basketball/Rally/Tennis/*View.swift`、4 个新 SVG | 中 | ⚠️ |
| 4 | 跨端 wire 编解码 | `DisplayStateWireCodec.swift`、`ScoreboardDisplayState+Compact.swift`、`ScoreboardDisplayStyle.swift` | 小 | 🔴 见 §5.1 / ⚠️ 见 §6 |
| 5 | 台球小组 v2（5 种玩法、活动/场次、离线 outbox、handoff） | 新增 `GroupBilliards{Models,Persistence,Views}.swift`、`Fixtures/billiards-v2.json`、`GroupBilliardsTests/UITests`；改 `Group{Models,Repository,Views,DetailView,ActivityViews}.swift` | 大 | 🔴 2 项阻断 + 多项风险 |
| 6 | VIP 社群入口与二维码 | 新增 `VipCommunity.swift`、3 个 `VIPCommunity.strings`；改 `HomeTab/MainTabView/MembershipView/AppReviewPrompt` | 中 | ⚠️（功能完整，语言覆盖有限） |
| 7 | 记录页滚动数字 | 新增 `RollingRecordStatistic.swift`；改 `RecordsTab.swift` | 小 | ✅（真机手感待验收，见 `TODO.md`） |
| 8 | 本地化 | 47 个 `Localizable.strings`（各 +107 / 中英 +142）、3 个 `VIPCommunity.strings`、2 个 `WechatBinding.strings` | 大 | 🔴 覆盖不足 |
| 9 | 工程与版本 | `project.pbxproj`（+2 测试文件、`3.4.1→3.4.3`、`84→86`）、`AGENTS.md`、`TODO.md` | 小 | ⚠️ |
| 10 | 测试 | 5 个单测文件改动 + 2 个新测试文件 + `FullAppScreenshotUITests.swift`（+161） | 中 | ⚠️ 弱断言 / 未同步 |
| 11 | 文档与数据 | `docs/analytics/2026-10/`（22 文件）、`docs/verification/group-billiards-2026-11-04.md` | 大 | ✅ 数据完整 / ⚠️ 体积与跨仓链接 |

---

## 四、独立验证结果

| 检查项 | 方法 | 结果 |
|---|---|---|
| 空白/冲突标记 | `git diff --check` | ✅ 0 错误 |
| Swift 语法 | `xcrun swiftc -frontend -parse` 对全部 45 个新增/修改 Swift 文件 | ✅ 45/45 通过（仅语法，非类型检查） |
| strings 语法 | `plutil -lint` 全部 49 个改动的 `.strings` | ✅ 全部 OK，无重复 key |
| 本地化 key 覆盖 | 解析 `en.lproj` 新增 135 个 key × 47 语言矩阵 | 🔴 33 个 `style_workbench_*` key 仅中/英存在；44 语言有 102 个 key 但其中 97 个值与英文完全相同 |
| pbxproj 完整性 | diff 逐段核对 | ✅ 两个新测试文件四处登记齐全；主 target 使用 `PBXFileSystemSynchronizedRootGroup`，新 Swift/资源无需手写条目 |
| 新增资源 | 6 个 `Contents.json` JSON 解析 + 5 SVG / 1 JPG 文件头 | ✅ 全部合法（JPG 1280×960，无异常）；`background.jpg` 236 KB |
| 敏感信息 | 密钥/凭据正则 + 新增 Swift 文件调试标记扫描 | ✅ 无 API key / 私钥 / token；无新增 `print`、`TEMP-VERIFY`；`docs/analytics` 含 GA4 `propertyId 555327954` 与内部控制台链接（业务标识，公开仓库需评估） |
| 白字规范（本次新增 AGENTS.md 规则） | 逐个主操作按钮核对 | ✅ 样式工作台保存按钮显式 `.foregroundStyle(.white)`；🔴 台球 UI 未落实（见 §6） |
| 编译 / 单元与 UI 测试 | `xcodebuild -project ... -list` / 拟跑 build | 🔴 **未能执行**：`Could not resolve package dependencies: sandbox-exec: sandbox_apply: Operation not permitted`，加免沙箱环境重试仍失败，属 Xcode/SwiftPM 嵌套沙箱环境限制，非代码问题 |
| 报告数据可复现 | `build_report.py` 静态检查 | ✅ 内建 assert（11,221 次访问 / 64,627 事件 / 943 与 4,189 行交叉明细）与 `source-manifest.json` SHA-256 清单；未实际重跑以免写入文件 |
| 工作树稳定性 | 连续 3 次 `git diff` 指纹 | ✅ 最终快照稳定 |

---

## 五、🔴 阻断项（提交前必须修）

### 5.1 照片主题在真实跨端 wire 链路丢失背景图

| 证据 | 说明 |
|---|---|
| `DisplayStateWireCodec.swift:116-117` | `style.themeCode = appearance.theme` 把正确的 `event_background` **覆盖成全局主题**；紧接着 `if style.themeCode != "event_background" { style.backdrop = nil }` **清空背景图** |
| `ScoreboardAppearance.swift:1612` + `ScoreboardTheme` 枚举（`:6`起） | 枚举无 `event_background` case，`ScoreboardTheme(rawValue: profile.themeCode)` 返回 nil → 回落 `preferences.scoreboardTheme` |
| `RallyScoreboardView.swift:2625`、`Tennis:1655`、`Basketball:659` | 构造 `LocalScoreboardDisplayState` 时仍传 `themeID: appearance.theme.rawValue`（全局主题） |
| `ScoreboardDisplayState+Compact.swift:8` | 本次只把 `init(snapshot:)` 的 theme 改为 `profile.themeCode`；生产链路走 `:109 init(compactState:)` |
| `ScoreboardStyleV2ModelTests.swift:331` | 往返测试用 `ScoreboardDisplayAppearance(snapshot:)` 构造，**绕过了 `compactState → encode` 真实路径**，因此测不出该问题 |

- **影响**：本机外接屏（`ExternalDisplayView.swift:574` 读 `style?.themeCode`）能显示照片主题；但云端/跨端同步（安卓、鸿蒙、另一台 iOS）收到的帧里 theme 被改写、backdrop 被清空，照片主题完全丢失。
- **建议**：`encodeAppearance` 以 `style.themeCode` 为准（或先同步扁平 `appearance.theme`），不要覆盖；并补一条**用 `ScoreboardDisplayState(compactState:)` 构造再 encode→decode** 的照片主题往返测试。

### 5.2 样式工作台「恢复默认」状态不自洽，且不清持久化字号

| 证据 | 说明 |
|---|---|
| `ScoreboardStyleEditorController.swift:35-38` | `canResetDraft` 的字号基准是 `ScoreboardTypographyPreference.default(font:.default).resolved(for:)`，其 `elementMultipliers == nil` |
| `ScoreboardStyleEditorController.swift:91-100` | `resetDraft()` 走 `beginPreview()` + `updateFont(.default)` + 逐个 `updateElementMultiplier(1, ...)` |
| `ScoreboardAppearance.swift:1474-1483`（`resolved`）| 保留 `elementMultipliers`；`:1559-1567`（`updateElementMultiplier`）在 nil 时展开成全量字典 → 重置后非 nil，与基准必然不等 → **点完重置按钮仍不置灰** |
| `ScoreboardAppearance.swift:1538` / `:1580-1592` | `beginPreview()` 有 `guard previewPreference == nil`，已有预览不会被清空；`applyPreview` 在 `resetRequested == false` 时执行 `setScoreboardTypography`，把残留倍率写回持久化 |
| `ScoreboardStyleEditorControllerTests.swift` | 所有用例都 `open(typographySession: nil)`，新增的 session 分支**零覆盖** |

- **建议**：重置统一走 `resetPreview(preferences:)` 或显式把 `previewPreference` 设为 `.default(...)`；`canResetDraft` 比较解析后的倍率而非结构体原值；补带真实 `ScoreboardTypographySession` 的测试，断言重置后 `canResetDraft == false` 且保存后偏好被清除。

### 5.3 台球结果走 `GroupResult` 解码时字段契约不自洽

| 证据 | 说明 |
|---|---|
| `GroupBilliardsModels.swift:164-173` | `GroupResult.init(from:)` 无条件 `decode(GroupFormat.self, forKey:.format)` 与 `decode([GroupSeat].self, forKey:.participants)`，两者均**非可选** |
| `GroupBilliardsModels.swift:136-145` | 台球行 `format: GroupFormat? = nil`、`GroupBilliardsSeat.side/seat` 可选；`:201` encode 在 `billiards != nil` 时直接输出整条 `GroupBilliardsRow`，format 为 nil 时不写 key |
| `Fixtures/billiards-v2.json` | 6 条台球 fixture **全部没有 `format` 字段**，participants 用 `participantId/position` 而非 `side/seat` |
| `PersonalGroupRecords.swift:88` + `GroupRepository.swift:83-89` | 个人记录对所有小组调用 `repository.results()` 返回 `GroupPage<GroupResult>`，**没有台球特判**（特判只在 `loadDetail`） |
| `GroupBilliardsTests.swift:35` | 手工构造 row 时显式补 `format:.individuals / side / seat`，恰好掩盖真实服务端数据 |

- **影响**：台球小组的个人记录解析抛 `keyNotFound`，可能连带所有小组的个人记录刷新失败；本地缓存若含 `billiards != nil` 的 `GroupResult` 也会整体解码失败。
- **建议**：`format`/`participants` 改容错解码（`decodeIfPresent` + 默认值）或为台球行提供独立解码入口；补「真实 v2 JSON → `GroupResult`」契约测试。

### 5.4 台球持久化故障扩散到全部记分记录保存

| 证据 | 说明 |
|---|---|
| `ScoreboardRecordManager.swift:597` | 把原本不抛错的 `GroupLocalPersistence.shared.annotate(input)` 改为 `try GroupBilliardsPersistence.shared.annotate(...)`，且位于 `do { try store.save(record) ... } catch`（`:615-625`）**之外** |
| `GroupBilliardsPersistence.swift:11-14` | `read()` 在「文件存在但解码失败」时直接 `throw`，无容错、无降级 |
| `GroupBilliardsPersistence.swift:31-35 / :59-66` | `annotate()` 与 `finish()` 都经该 `read`；三个持久化结构无 `schemaVersion`/迁移；`rules.json` key 为 `accountID + ":" + groupID`，含 `:` 的 ID 会串键 |

- **影响**：`sources.json` / `outbox.json` 一旦因升级或写入异常解码失败，**任何一条（含非台球）记分记录都无法保存**，且 outbox 永久读不出、无法自愈（`sync()` 只把错误写进 `store.error`）。
- **建议**：`annotate` 改为不抛错（内部 `try?` 降级返回原 record）；`read` 解码失败时返回 fallback 并隔离坏文件；加 schemaVersion 与迁移；把 `try` 从保存主路径移除。

### 5.5 多语言本地化覆盖不足（发版阻断）

| 证据 | 说明 |
|---|---|
| 47 个 `.lproj`；`en` 新增 135 个 key | 44 个语言缺 33 个 `style_workbench_*` key（含 `photo_failed` / `image_advice`）；仅 en / zh-Hans / zh-Hant 有 |
| `ScoreboardStyleEditOverlay.swift:326,329,562,654,658,662...` | 用 `String(localized: "style_workbench_*")`，**无 `value:` 兜底** → 缺 key 时界面直接显示 `style_workbench_title` 等原始标识符 |
| 44 语言其余 102 个新增 key | 其中 **97 个值与英文原文逐字相同**（如 `ar/ja/de/ru` 的 `billiards_group_start = "Start match"`），属英文占位而非翻译 |
| `VIPCommunity.strings` | 只有 3 种语言，但 `vipCommunityText` 带 `value:` 兜底 → 其他语言显示英文而**非空白**（可接受但需明确） |

- **影响**：工作台在 44 种语言下基本不可读；台球小组文案在非中英语言下为英文。
- **建议**：要么补齐 33 个 key 与 97 个译文，要么本版明确「工作台/台球仅中英」并在代码里加英文兜底 + CI 加 key 一致性检查。

---

## 六、⚠️ 风险项

| # | 位置 | 问题与影响 | 建议 |
|---|---|---|---|
| 1 | `jifenTests/GroupPortParityTests.swift:1035,1373` | 两处仍用 `GroupSport.allCases`（现含 `.billiards`），其中 `:1035` 会把台球塞进 `pickleballRules` 并断言 `GroupMatchRules` 往返相等，而 `GroupModels.swift:239` 的 `isValid` 已限制 `supports(sport)` → **全量单测很可能失败**；`GroupContractTests.swift` 已改 `.racketSports`，此处漏改 | 同步改 `.racketSports` 并跑全量 `jifenTests` |
| 2 | `GroupViews.swift:228` | `GroupBetaSportTags` 默认值 `allCases` 会多出一个台球标签 | 显式传 `.racketSports` |
| 3 | `GroupModels.swift:4-17` | `GroupSport/GroupFormat` 未知值映射 `.unsupported` 读取安全，但 encode 仍写 `"unsupported"` → 回写丢原始值；`.unsupported.gameType` 回落 `.billiards` 可能误导启动；`GroupFormat.title` 对 `individuals/mixed` 显示 "Doubles" | 保留原始 rawValue；补 title 文案 |
| 4 | `GroupRepository.swift:75` + `GroupModels.swift:189` | 所有 `/api/groups` 请求统一加 `X-Group-Contract-Version: 2`，`minClientContractVersion` 上限 1→2，影响**全部既有球拍小组** | 确认服务端 v2 向后兼容并做旧小组回归 |
| 5 | `GroupBilliardsPersistence.swift:47-52,136,145-149` | `add` 去重不检查 `done`（更正/重赛后无法再入队、outbox 无限累积）；失败行只在白名单错误码内可修复，`sync(force:)` 仅台球 Tab 手动触发 → **失败队列不自动自愈** | 去重加 `!done`；按错误码区分可重试/需修复/终止 |
| 6 | `GroupBilliardsViews.swift:234,310-330` | 「更正」生成全新 `sessionID`，不继承原 `clientSessionId/clientRecordId` → 可能重复提交而非作废原记录 | 沿用原幂等键或走后端 correct 接口 |
| 7 | `GroupBilliardsViews.swift:88-99,199-200,341-342` | handoff / 恢复存在死状态：残留 source 映射不到 live session 时既不显示也不可 abandon，同时 `unfinished` 全局阻塞开新局 | 列出不可恢复 source 并允许强制 abandon |
| 8 | `GroupBilliardsModels.swift:22-51` | `validate()` 用 `Set(object.keys).isSubset(of: keys)` 严格限制 config key，`engineRuleVersion` 固定 `==3` → 后端新增可选字段即全部拒绝 | 忽略未知 key，版本用 `>=` 能力协商 |
| 9 | `GroupBilliardsPersistence.swift:105` + `Models.swift:117` | tournament 缺 `chaseRoundNumber` 时 `racks=0`，被判非 terminal → 合法对局变 `RULES_REVIEW_REQUIRED` | 确认九球记分板总写入该字段，或按 early_stop 处理 |
| 10 | `ScoreboardStyleEditOverlay.swift`（body 重写后） | `topControls`/`paletteEntry`/`modalPanel`/`textColorPropagationPrompt` 等约 10 处成死代码；`textColorPropagationRequest` 仍被赋值但 UI 与倒计时已被删 → **文字色跨槽位传播提示静默失效** | 恢复提示或整条链路删除 |
| 11 | `ScoreboardStyleEditOverlay.swift:450,478` | `.id(workbenchTab + draft.themeCode)` 每次切 tab/主题重建 ScrollView + 动画整体移除 → 硬切、滚动位置丢失（与项目"硬切视为 BUG"约定冲突） | 去 `.id()`，补 `.animation` |
| 12 | `DisplayStateWireCodec.swift:413-414,445-447` | 解码侧对缺失 Optional 填 `false`/`"arrow"`（编码侧省略）→ Equatable 不等、可能触发无谓刷新；`appearance.style = style` 被 `!style.panels.isEmpty` 门控，panels 为空帧丢照片主题 | 缺失字段保持 nil；把 style 赋值移出门控 |
| 13 | `ScoreboardAppearance.swift:541,607` | 新默认 `nameFontCode = "default"` 使队名强制系统字体，不再跟随 TypographySession 全局字体；UI 只暴露 3/6 种字体（`Overlay.swift:560`） | 明确「默认」语义并补齐字体选项 |
| 14 | `ExternalDisplayView.swift:2069...` + `Overlay.swift:450` | 照片主题下 tab 只有 theme/background，但新增十余处 `.styleElementSelectable` 落在不渲染的 `templateBody` 上 → 点选元素能力不可达 | 明确照片主题可编辑范围 |
| 15 | `ScoreboardPhotoTheme.swift:10-36,128,231-259` | `normalized()` 每次解码 base64 校验，Slider 每帧触发；`.task(id:)` / 选图 `Task{}` 在 MainActor 同步解码与降采样 → 拖动掉帧、大图卡顿；DragGesture 的 `onTap/onUndo/onSubtract` 未判 touchGuard；badge 硬编码 `pingpong` | 后台编解码；Slider 松手才提交；补手势守卫 |
| 16 | `GroupBilliardsViews.swift:84,115,289,427` vs `AGENTS.md:11` | 主操作用 `.buttonStyle(.borderedProminent)` + `.tint(Theme.primary)`；`Theme.swift:115-131` 确认 primary 为绿色（#4CAF50/#30D158），但**整个文件没有一处 `foregroundStyle`**，与本次同时新增的「实心绿按钮必须白字」规范直接冲突 | 显式 `.foregroundStyle(Theme.textOnPrimary)` 或改 `GroupAlignedActionStyle` |
| 17 | `ScoreboardDisplayTests.swift:8-35` | 注释声称检查绿色像素与卡片边界，实际只有 `XCTAssertEqual(image.size, size)` 一个断言；`FullAppScreenshotUITests.swift` 用 `waitForExistence(timeout:1)` 做否定断言，每次白等 1 秒 | 补几何/像素断言或修正注释；改用 `!exists` |
| 18 | `ScoreboardStyleEditOverlay.swift:663` | `Link("Photo by KeepActive.com.au · CC BY-SA 4.0", ...)` 只链许可证文本，缺作品名、原始来源与修改说明，不满足 CC BY-SA 4.0 署名要求；且对常量 URL 用 `!` | 补齐署名与来源，可选绑定 URL；确认 ShareAlike 与 App Store 分发的合规边界 |
| 19 | `project.pbxproj:805,833,863,891` + 文案 | `MARKETING_VERSION 3.4.1→3.4.3`、`CURRENT_PROJECT_VERSION 84→86`，但当前分支为 `3.4.1`；`group_billiards_create_notice_message` 与 `GroupBilliardsUITests.swift:30` 硬编码 `3.4.3` | 确认有意发版准备；版本号改为从 `CFBundleShortVersionString` 读取 |
| 20 | `jifen/Features/Groups/Fixtures/billiards-v2.json` | 位于 app 源码树下，会随 `fileSystemSynchronizedGroups` 打进正式包；而 `GroupBilliardsTests.swift:8-9` 用 `#filePath` 从源码磁盘读取，根本不依赖 bundle → 测试数据污染生产包 | 移到 `jifenTests/Fixtures/` 或显式排除 |
| 21 | `VipCommunity.swift:12` / `AppReviewPrompt.swift:6,82+` | `VipCommunityAvailability.enabled` 初始 `true`，会员页可能短暂显示未启用的入口；`requestedThisLaunch` 一次置 true 后本次启动不再复位，若 StoreKit 限流未真弹评分仍会压制 VIP 弹窗 | 默认改 false / 加加载态；核对互斥时序 |
| 22 | `docs/verification/group-billiards-2026-11-04.md:3` | 链接指向 `../../../jifen-android/docs/...`（仓库外的兄弟目录），单独 clone 本仓库会断链 | 改绝对文档链接或把关键结论内联 |
| 23 | `docs/analytics/2026-10/`（22 文件 / 1.3 MB） | `source-manifest.json` 与 `index.html` 含 GA4 `propertyId 555327954` 和 `analytics.google.com` 内部探索链接；`README.md` 已声明无个人级标识、CSV 为聚合数据 | 确认仓库可见性；若公开仓库，评估是否移除内部控制台链接 |

补充核对项：`zh-Hans/zh-Hant.lproj/WechatBinding.strings` 的两处「安卓、鸿蒙 → 其他设备」文案改动，与 `en.lproj` 的 `"other devices"` 语义一致 ✅，但属审查期间新增，建议确认是否属于本批次。

---

## 七、✅ 已确认正确（抽查通过）

| 项 | 结论 |
|---|---|
| Codable 版本兼容 | `ScoreboardDisplayStyle.swift:26-29` 新增 4 字段均为带默认值 Optional，旧 wire 缺字段不报错；`version == 2` 门控保持 |
| dim / opacity | `ScoreboardPhotoTheme.swift:19-20` 与 `Overlay.swift:654,658` Slider 范围逐字一致，NaN/±Inf 有回落并有测试 |
| 换边映射 | `ScoreboardPhotoTheme.swift:270,302` 的 `logical0` 异或映射四种组合正确，swapped 场景有测试 |
| 资源与 API 引用 | `ScoreboardServeSymbol.asset` 引用的 8 个 imageset 全部存在；新增 EnvironmentKey / `ScoreboardNameFont` / `.synchronizedDisplay` 等均已定义；45 个 Swift 文件语法解析全通过 |
| 投屏照片分支 | `ExternalDisplayView.swift:574-609` 隐藏 topChrome 与 badge/card 图层，避免与 photoScene 重复绘制 |
| 台球零和与幂等 | `GroupBilliardsModels.swift:95` 用 `Int64` 判零和并有反向断言；`GroupBilliardsSync` 用 `Idempotency-Key` + 账号/会话双重校验，`NSRecursiveLock` + `.atomic` 写 |
| 身份与安全 | `VipCommunityConfig.validatedURL` 严格限制 `https://work.weixin.qq.com/gm/<alnum>` 且禁 user/port/query/fragment；含 StoreKit 凭据校验；`weixin://` 已在 Info.plist 声明；全程无凭据/个人信息 |
| 本地化其余部分 | 台球相关 102 个 key 在抽查的 en/zh-Hans/zh-Hant/de/ja/ar/fr/es-ES/ko 中 key 均存在（值多为英文占位，见 §5.5）；3 个 `VIPCommunity.strings` 各 20 个 key 完全一致；`groupText` 带 `value:` 兜底 |
| 评分/社群互斥 | `AppReviewPrompt.swift` 增加 `Task.yield()` 与 `VipCommunityAvailability.shared.isPresenting` 判断，避免两个弹窗同时争抢 |
| 记录滚动数字 | `RollingRecordStatistic.swift` 首次 1.2s / 后续 0.35s、reduceMotion、布局期取消后强制 final、999→1000 进位宽度、`accessibilityLabel` 始终为最终值，`TODO.md` 已登记真机验收 |
| 工程登记 | 两个新测试文件 `PBXBuildFile → PBXFileReference → group → Sources` 四处齐全；主 target 自动同步，无需手写 |
| 调试残留 | 工作区最终态无 `TEMP-VERIFY` / `FIXME` / `print` / `|| true` 新增；`git diff --check` 干净 |
| 分析数据 | `build_report.py` 内建总量 assert + `source-manifest.json` SHA-256 清单；`firebase-analytics-console.md` 明确不上传用户正文/业务 ID/投屏码 |

---

## 八、提交前执行清单（建议按顺序）

| # | 动作 | 验收标准 |
|---|---|---|
| 1 | 重新 `git status -sb` + `git diff --stat`，确认并发写入已结束、范围与本报告快照一致 | 89 + 47，或明确新增差异已复核 |
| 2 | 修 §5.1 照片主题 wire 覆盖 / backdrop 清空 | `compactState → encode → decode` 往返测试通过 |
| 3 | 修 §5.2 `resetDraft` / `canResetDraft` 与持久化字号 | 带 session 的测试断言重置后按钮置灰且偏好被清 |
| 4 | 修 §5.3 `GroupResult` 容错解码 | 用 `Fixtures/billiards-v2.json` 原始 JSON 解码通过 |
| 5 | 修 §5.4 `annotate` 不抛错 + 坏文件容错 | 模拟 `sources.json` 损坏后，非台球记录仍可保存 |
| 6 | 处理 §5.5 本地化 | 33 个 key 补齐或明确兜底策略；97 个英文占位有交付决策 |
| 7 | 同步 `GroupPortParityTests` 两处、修实心绿按钮白字、处理 `GroupSport.allCases` 默认值 | 无规范冲突 |
| 8 | **在本机 Xcode 跑全量 `jifenTests` + 关键 UI 测试**（本环境无法执行） | 全绿；重点 `GroupPortParityTests`、`ScoreboardStyleV2ModelTests`、`GroupBilliardsTests` |
| 9 | 真机/归档验证 bundle 资源 | 3 个 `VIPCommunity.strings` 与 6 个新 imageset 在正确 `.lproj` / asset catalog 内；确认 fixture 是否误入包 |
| 10 | 版本号 / 文案 / 跨仓链接 / analytics 入库范围决策 | 与发版计划一致 |
| 11 | 按主题拆分提交（建议 4 组：样式工作台与照片主题、台球小组、VIP 与记录、文档与本地化），每组中文 commit summary | 每组可独立回滚、可独立验证 |

---

## 九、未验证项与环境限制

1. **未执行编译与 XCTest**：`xcodebuild` 在本环境（含免沙箱重试）均因 `sandbox-exec: sandbox_apply: Operation not permitted` 无法解析 SwiftPM 依赖。已用 `swiftc -frontend -parse` 覆盖 45 个 Swift 文件的语法检查，但**类型检查、链接、运行时行为均未验证**。
2. **未做真机 / 模拟器 UI 运行验证**，因此动画丝滑度、深浅色、大屏适配、照片选图性能等只有静态代码证据。
3. **未验证打包产物**：`VIPCommunity.strings` 与新增 assets 是否进入 bundle 只能靠 Xcode 自动同步推断。
4. **未重跑 `build_report.py`**（避免写入文件）；报告与源 CSV 的一致性依据内建 assert 与 SHA 清单静态确认。
5. **审查期间存在并发写入**；本报告基于 `da85474e35a811d0` 快照，行号与结论以该时刻为准。
6. 未纳入：忽略文件、3 条历史 stash、`/private/tmp/jifen-zhhant-check` worktree、其他仓库（安卓/鸿蒙）的对应改动。
