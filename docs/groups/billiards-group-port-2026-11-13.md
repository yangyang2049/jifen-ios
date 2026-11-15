# iOS 台球小组内页：按安卓定稿重做（2026-11-13）

基准：安卓 `jifen-android` 定稿（`BilliardsScreens.kt` / `BilliardsEntryScreen.kt`），口径见
`jifen-android/docs/groups/billiards-group-port-spec-2026-11-13.md`。本轮只改 iOS 仓库，未改后端与其它端。

## 结构变化

| 文件 | 说明 |
| --- | --- |
| `Features/Groups/GroupBilliardsViews.swift` | 三个页签重做：概览（信息卡 + 三格统计 + 未完成 + 待上传 + 最新赛果 + 即将开始）、活动（两段 + 活动卡 + 同页场次编排）、战绩（玩法/规则桶 chips + 待确认 + 排行表 + 记录）、赛果卡、底栏、玩法弹层 |
| `Features/Groups/GroupBilliardsEntryViews.swift`（新增） | 两段式第二步的独立页面：玩法/人数、参赛成员（含临时成员）、设置规则、逐人成绩（± 与净积分合计）、底部主操作；支持开赛/补记/编排/修复/作废后更正五种入口 |
| `Features/Groups/GroupBilliardsModels.swift` | `GroupBilliardsRanking` 补 `bucket`；`GroupBilliardsRank` 补 `averagePoints`/`draws` 与派生 `signedPoints`/`averageText`/`qualifiedWinRate`；新增 `GroupBilliardsActivity`（活动 + 台球默认规则） |
| `Features/Groups/GroupBilliardsPersistence.swift` | 待上传队列按「账号 + 小组」过滤（`rows(accountID:groupID:)`）；放弃比赛同时移除可恢复会话 |
| `Features/Groups/GroupDetailView.swift` | 台球页签接入 `safeAreaInset` 底栏；活动/赛果入口接线 |
| `Features/Groups/GroupActivityViews.swift`、`GroupViews.swift` | 台球分支改用新页签，赛果详情入口 |
| `Features/Groups/GroupErrorMessage.swift` | 补 `SESSION_FROZEN` / `ACTIVITY_NOT_COMPLETE` / `RESULT_VOIDED`（复用已复核的 `group_*` 键） |
| `Features/Groups/GroupInvitationLink.swift` | 邀请文案用小组项目名「台球」，不再写成玩法名「普通台球」 |
| `jifenTests/GroupBilliardsTests.swift` | 补 12 项单测（队列按组过滤、放弃清会话、邀请文案、排行派生值等） |

## 与安卓的差异（有意为之）

1. **排行表**：iOS 既有 `GroupRankingTable` 的列是通用的胜/负/平/胜率，台球需要「局分或净积分」单列，
   因此另写 `BilliardsRankingTable`，但沿用同一套排名徽标、头像、右对齐数字与最小列宽。
2. **玩法选择弹层**用 `.sheet` + `presentationDetents`（对齐安卓底部弹层），已验证 DragIndicator。
3. **入口页**用 `navigationDestination` push，标题随模式变化（开赛/补记/编排），返回沿用系统返回。
4. **本地化**：不新增任何 key（47 语种会阻塞），缺文案复用已复核 `billiards_group_*` / `group_*`，
   或用带英文 fallback 的重载 `billiardsText(_:_:)`。
5. **赛果详情**：从赛果卡直接 push `GroupBilliardsResultDetail`，不再依赖外层页面注入 `resultID`。

## 本轮修复的旧问题（P0）

- **待上传队列跨小组串卡**：原来只按账号过滤，A 组待上传会出现在 B 组且能在 B 组被移出队列 → 按小组过滤。
- **放弃比赛后无法再开赛**：原来只清 outbox/source，不清可恢复会话，而开赛用全局未完成会话拦截 →
  放弃时一并 `ResumeSessionRepository().remove(sessionId:)`。
- **邀请文案「普通台球小组」**：改用 `group_sport_billiards`。
- **取消活动一键直达、无确认无理由**：改为确认框 + 原因输入。
- **离线/缓存态按钮仍可点**：`writable` 补 `!store.cached`，活动与审核入口在缓存态收起。
- **台球新增错误码缺本地化**：补齐三个业务码映射。
- **民间追分补记无 ± 切换**：入口页加 ± 按钮与「净积分合计」实时提示（不为 0 时红字）。

## 验证

```
xcodebuild -project jifen.xcodeproj -scheme jifen -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/jifen-port-dd build
→ ** BUILD SUCCEEDED **

xcodebuild -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,id=2288EE35-8652-45B4-AC75-807DB83823EB' \
  -derivedDataPath /tmp/jifen-port-dd test -only-testing:jifenTests/GroupBilliardsTests
→ Executed 12 tests, with 0 failures — ** TEST SUCCEEDED **
```

`jifenUITests/GroupBilliardsUITests` 里两处旧断言已按现行文案与 iOS 26 返回键暴露方式修正
（版本提示按钮改为「取消 / 继续」，返回改用重启应用回到列表）。

## 已知未完成 / 风险

- 未在真机上逐项点过（模拟器构建 + 单测通过，UI 测试需设备/模拟器跑完整链路）。
- 台球写操作仍不刷新父级 `GroupDetailCache`，小组列表上的活动/赛果计数可能滞后（与安卓行为一致）。
- 创建活动的默认规则在活动编辑器内配置；若要求与安卓完全一致（独立规则页）可再拆一层。

---

# 2026-11-14 更新：一步式开赛 / 补记配置页

基准：安卓 `jifen-android` 分支 3.4.3 定稿 `8366294c`（`feat(android): 台球小组「开始计分」改一步式配置页并统一卡内控件配色`）。
口径文档：

- `jifen-android/docs/groups/billiards-group-port-spec-2026-11-13.md`（顶部 2026-11-14 更新说明：第 2 节「两段式」已被取代）
- `jifen-android/docs/groups/billiards-entry-demo-audit-2026-11-14.md`（版式与可点区审计）
- 版式件：`BilliardsSetupLayout.kt` / `BilliardsInlineSetup.kt` / `BilliardsEntryScreen.kt`
- 行为契约：`BilliardsGroupLayoutUiTest.startFlowOpensInlineSetupPage`

本轮只改 iOS 仓库，未改后端、未改安卓仓库。

## 一、结构变化

| 文件 | 说明 |
| --- | --- |
| `Features/Groups/GroupBilliardsEntryViews.swift` | 重写为**一步式配置页**：顶部 4 个玩法组 chip（可横滑）、九球页内分段（民间追分 / 比赛积分）与人数分段、座位 + 成员胶囊、唯一带标题的「规则设置」折叠卡、补记字段、单一吸底主操作；删除旧的两段式「第一步玩法 + 第二步设置规则」结构 |
| `Features/Groups/GroupBilliardsModels.swift` | 新增 `GroupBilliardsGroup`（`nine_ball` / `eight_ball` / `snooker` / `standard`，前端玩法组，提交前还原成后端变体）与 `GroupBilliardsFamily`；`GroupBilliardsRules` 补 `group` / `family` / `defaults(for:family:count:)` / `converting(to:count:)`；`GroupBilliardsVariant` 补 `hasAdjustableRules` |
| `Features/Groups/GroupBilliardsViews.swift` | 删除玩法选择 `.sheet`、`BilliardsSheet.variant`、`BilliardsVariantPicker`；底栏「补记赛果 / 开始计分」直接进配置页；作废 / 取消活动 / 放弃本场改为**弹窗内联报错**（`BilliardsPrompt` + `BilliardsPromptDialog`）；次按钮 / 徽章 / 席位块 / 输入位改为白底 + 1px 描边 |
| `Features/Groups/GroupInlineMatchRoster.swift` | `GroupMemberPoolLayout` 由文件私有改为模块内可见，台球成员胶囊复用同一套换行节奏 |
| `jifenTests/GroupBilliardsTests.swift` | 补 2 项单测：玩法组 / 后端变体换算、切玩法与切族后规则仍然合法（共 14 项） |
| `jifenUITests/GroupBilliardsUITests.swift` | 两段式断言按一步式改写：不再等 `billiards_pick_next`，改为校验 4 个玩法组 chip、页内分段，以及普通台球不出规则设置 |

## 二、行为契约逐条自检

| 契约 | iOS 落地 |
| --- | --- |
| 概览底栏直接进配置页，无玩法弹层 | `actionBar` 里两个按钮直接 `entry = .init(mode:)`；`BilliardsSheet` 只剩 `activityEditor`，`BilliardsVariantPicker` 与 `billiards_pick_next` 已删除 |
| 页内一排 4 个玩法组 chip，可横滑 | `projectRow`（`ScrollView(.horizontal)`，标识 `billiards_variant_chip_nine_ball` / `_eight_ball` / `_snooker` / `_standard`） |
| 进页预选本机上次开过的玩法，没有则九球 | `prepare()` 读 `GroupBilliardsPersistence.rememberedRules`，`group = remembered.group`；无记录时用 `request.variant` 或九球默认值 |
| 九球民间 / 比赛积分是页内分段 | `familySegment`（`billiards_family_folk` / `billiards_family_tournament`），切族走 `rules.converting(to:count:)`，锦标赛固定 2 人 |
| 除「规则设置」外无小标题 | 页面无「项目 / 人数 / 参赛成员」标题；座位区、成员胶囊、补记成绩都直接排版 |
| 玩法没有的项整块不渲染 | 非九球不出分段；非九球民间不出人数分段；普通台球整块「规则设置」不出现（`hasAdjustableRules == false`） |
| 规则设置唯一带标题且可折叠 | `GroupSectionTitle(billiards_group_rules)` + 折叠卡：摘要一行 + `billiards_rules_toggle`（chevron 旋转），展开见 `BilliardsRuleDetailFields` |
| 两人 A 方 / B 方两列，三四人纵向带序号 | `seatsBlock`：`count == 2` 两列（列头 A / B，座位徽标 A1 / B1），否则纵向 1 / 2 / 3 / 4 |
| 成员胶囊一排、可换行、无身份标签 | `memberChips`（`GroupMemberPoolLayout`），不写「我 / 队员」；已入座者在胶囊上标座位号 |
| 空位是加号图标 + 占位文案 | 空位渲染 SF Symbol `plus` 圆底 + `billiards_group_select`（不再放文字符号） |
| 补记只多出成绩 / ± / 净积分 / 已完成局数 / 提前结束 / 时间 | `scoreSection` 仅在 `mode == .manual` 渲染；民间出 ± 与 `billiards_net_total`（不为 0 时主按钮禁用）；锦标赛出「已完成局数」；非民间 / 普通台球出「提前结束」；日期 `DatePicker` |
| 底部只有一个主操作，未选齐禁用并显示「选择第 N 位参赛者」 | `footer` 单按钮；`ctaTitle` 在 `!ready` 时用 `billiards_group_choose_member`（含第 N 位） |
| 冻结场次只读 | chip 与座位 `.disabled`、不出成员胶囊；规则改为 `billiards_rules_summary` 纯文本，无 chevron 与「调整」入口 |
| 编排页标题是「编排场次」 | `title` 按模式取 `group_edit_lineup`（编排场次）/ `billiards_group_manual`（补记成绩）/ `group_copy_start_score`（开始计分） |
| 三个弹窗的失败信息显示在弹窗内部 | `BilliardsPromptDialog` 自带 `billiards_prompt_error` 行；失败时保留弹窗、只写该行，不再写被盖住的页面 banner |
| 开赛先关配置页再进计分板 | `start()` / `resume` 路径均先 `finish()`（`onDone()` + `dismiss()`）再 `onStart(...)` |
| 「金九」统一为「黄金九」 | iOS 既有文案本来就是「黄金九」（`billiards_group_golden_nine` / `billiards_group_golden` / `nine_ball_golden_nine`），全仓库无「金九」残留 |

## 三、本仓库相对安卓的差异（有意为之）

1. **玩法组 chip 文案**：安卓用 `billiards_group_nine_ball` / `game_type_*`；iOS 不新增 47 语种键，
   九球复用已复核的 `schedule_billiards_nine_ball`，其余三项直接用 `GameType.displayName`（`game_eight_ball` / `game_snooker` / `game_billiards`）。
2. **规则族分段文案**：用计分板设置页同一对已复核键 `nine_ball_folk` / `nine_ball_tournament`（安卓用同语义的 `nine_ball_rule_family_*`），
   不再出现第二个「民间追分 / 锦标赛积分」长标签。
3. **规则块标题**：安卓 `group_rules_title`（规则设置）；iOS 复用已复核的 `billiards_group_rules`（比赛规则），语义相同。
4. **座位侧标签**：安卓用 `group_seat_side_a/b`（A 方 / B 方）；iOS 直接用字母 A / B 加座位徽标 A1 / B1，
   与既有 `GroupInlineMatchRoster` 同一套编号，不需要新文案。
5. **确认弹窗**：iOS 用自绘 `BilliardsPromptDialog`（`overlay`，支持弹窗内联报错）；安卓是 Material AlertDialog。
   `.alert` 在 iOS 上点按钮必关闭，无法把失败信息留在弹窗里，所以换成自绘弹窗。
6. **空位占位文案**：安卓 `group_inline_select`（选人），iOS 复用 `billiards_group_select`（请选择）。
7. **玩法组预填粒度**：安卓按组保存 `SportsSetupResult`（`BilliardsUploads.launch`）；iOS 本机只保存一份
   「该小组最近一次规则」，因此切到别的玩法组时用该玩法默认值，切回上次玩法组时才恢复原规则。

## 四、验证

```
xcodebuild -project jifen.xcodeproj -scheme jifen -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/jifen-port-dd build
→ ** BUILD SUCCEEDED **

xcodebuild -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,id=8F997E02-451E-49CC-A84F-85FB2766ACB1' \
  -derivedDataPath /tmp/jifen-port-dd test \
  -only-testing:jifenTests/GroupBilliardsTests -only-testing:jifenTests/LocalizationIntegrityTests
→ Executed 52 tests, with 0 failures（台球 14 + 本地化 38）— ** TEST SUCCEEDED **

xcodebuild -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,id=8F997E02-451E-49CC-A84F-85FB2766ACB1' \
  -derivedDataPath /tmp/jifen-port-dd test -only-testing:jifenUITests/GroupBilliardsUITests
→ Executed 2 tests, with 0 failures — ** TEST SUCCEEDED **
```

UI 测试按一步式改写后真正跑通，并顺带发现一个实现问题：把 `accessibilityIdentifier` 挂在
`HStack`（玩法族分段 / 座位区 / 成员胶囊）上会让标识符向下覆盖子按钮的标识符，
导致 `billiards_family_folk` / `billiards_seat_2` 查不到；已改为只在叶子控件上挂标识符。

模拟器说明：需求给的 `2288EE35-8652-45B4-AC75-807DB83823EB`（iPhone Duo）与列表里其它 iPhone 的
设备数据已从磁盘删除（`Unable to boot device because it cannot be located on disk`），
本轮用 `xcrun simctl create 'jifen-billiards-test' iPhone 16 / iOS 26.5` 新建一台跑测试，未删除/改动既有模拟器。

## 五、已知风险 / 未覆盖

- 冷启动、账号切换、真机大字号下的手动点检仍未做（模拟器上的 UI 测试已跑通，真机未点）。
- 灰卡片内「白底 + 1px 描边」只覆盖台球入口页与台球页签的次按钮 / 徽章 / 席位块 / 输入位，未做全 App 扫描式改造。
- 玩法组预填只保存一份规则（见上「差异 7」），若要与安卓逐组记忆完全一致，需要把 `rules.json` 的键扩成「账号 + 小组 + 玩法组」。
