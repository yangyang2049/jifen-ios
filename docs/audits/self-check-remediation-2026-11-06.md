# 未提交改动自检问题复核与修复报告（2026-11-06）

> 复核对象：`docs/audits/uncommitted-review-2026-11-05.md`（5 个阻断项 + 23 个风险项）与 2026-11-05 全量自检报告里的 P1/P2/P3 清单。
> 方式：**每条先在当前工作树上复核代码**，判定成立才改；不成立的保留证据、不动代码（审计报告是主张，不是事实）。
> 范围：只改 iOS 仓库工作区；未触碰商店 / 发布物 / 他人正在运行的测试批次。

## 一、结论

| 项 | 结果 |
|---|---|
| 复核条目 | 5 阻断 + 23 风险 + 12 小问题 |
| 已修复 | 22 |
| 判定为误报 / 与既有契约一致（未改代码） | 10 |
| 待你决策（未改） | 4 |
| 主 App 编译（Debug-iphonesimulator） | ✅ 0 error |
| 测试 target 编译（build-for-testing） | ✅ 0 error |
| `jifenTests` 全量 | ✅ **1006 通过 / 0 失败 / 1 跳过**（修复前：997 通过 / **3 失败** / 1 跳过） |
| 已删符号残留扫描 | ✅ `jifen` / `jifenTests` / `jifenUITests` 三路径零命中 |
| 打包产物校验 | ✅ 测试 fixture 不再进 app bundle（修复前包内含 `rules-v1.json` 与 `billiards-v2.json`） |
| 本地化 key 矩阵 | ✅ 47 个语言 key 集合完全一致；格式占位符 47×2391 零不一致 |

修复后 `jifenTests` 中此前失败的 3 条全部转绿，且新增/加强的测试一并通过：
`testMinimumClientContractDisablesWrites`、`testLocalizedResourcePairsStayInSync`、`testAuditMultiScoreDuoSafeAreaSnapshots`、
`testPhotoThemeSurvivesWireRoundTripThroughProductionCompactState`、`testFixtureRowsDecodeAsGroupResultsAndRacketRowsStillDecode`、
`testCorruptBilliardsStoreDegradesWithoutThrowing`、`testBilliardsVersionNoticeKeepsAVersionPlaceholder`、`testPhotoScoreHeightNativeSnapshots`、
`testSharedRulesFixtures`。

## 二、P1 阻断项

### 2.1 §5.5 44 个语言缺 33 个 `style_workbench_*` key —— 已修复

- **复核**：47 个 `.lproj` 中仅 en / zh-Hans / zh-Hant 有这 33 个 key；其余 44 个语言 key 集合各缺 33 条（2358 vs 2391），
  `testLocalizedResourcePairsStayInSync` 因此报红。
- **修复**：为 44 个语言补齐 33 个 key。其中 **15 条复用同库已审核译文**（英文源串逐字相同的既有 key，
  如 `style_workbench_theme` ← `scoreboard_style_theme`、`style_workbench_team_name` ← `setup_team_name`、
  `style_workbench_select_photo` ← `group_album` 等，映射表见 §七），其余 18 条按本批次既有约定写英文源串占位。
- **结果**：47 个语言 key 集合完全一致，无重复 key，`plutil -lint` 全通过。
- **仍未消除的交付风险（需翻译战役）**：本次新增的 135 个 key 里，44 个语言仍有 **115 条值为英文占位**
  （含既有 97 条 `billiards_group_*` 等）。这批 key 现在至少不再出现「缺 key」问题，但要在多语言发版前补齐译文。

### 2.2 §6#19 版本号与合同版本 —— 已修复 / 已验证

- **合同版本**：引入单一来源 `GroupContract.version = 2`（`GroupModels.swift`），
  `allows()` / `sport()` / `GroupRepository` 的请求头与两处上限判断全部改为引用它，杜绝「请求头说 2、判断写 1」再次漂移。
  过期的 `GroupPortParityTests.testMinimumClientContractDisablesWrites` 改为断言 `GroupContract.version` 可写、`version + 1` 不可写。
- **跨端核对**：安卓 `HttpClient.kt:81` 对 `/api/groups` 发送 `X-Group-Contract-Version: 2`；
  鸿蒙 `groupBilliards.ts:29` / `RemoteGroupRepository.ts:421` 同样发 `2`，且 `RemoteGroupRepository.ts:357` 用 `> 2` 拦截。
  iOS 升到 2 与两端一致。
- **版本号**：`MARKETING_VERSION 3.4.3`（2 处）、`CURRENT_PROJECT_VERSION 86`（2 处）内部一致；
  安卓 `versionName 3.4.3`、鸿蒙 `3.4.3`，跨端对齐，跳过 3.4.2 属发版计划，未见不一致。
  文案里的版本号已改为占位符（见 2.4）。

### 2.3 §5.1 照片主题在真实跨端链路丢背景图 —— 已修复

- **复核**：`DisplayStateWireCodec.encodeAppearance` 先 `style.themeCode = appearance.theme`（扁平主题，照片主题下是 `default`），
  再 `if style.themeCode != "event_background" { style.backdrop = nil }` → V2 的 `event_background` 被覆盖、背景图被清空。
  解码侧 `appearance.style = style` 又被 `!style.panels.isEmpty` 门控。生产链路确认为
  `ScoreboardDisplayState(compactState:)` → `CloudSyncSession.publish` → `encode`，而原往返测试走 `ScoreboardDisplayAppearance(snapshot:)` 绕开了它。
- **修复**：以 `style.themeCode` 为权威（扁平字段反过来跟随 style，而不是覆盖它），只有「有效主题确实不是照片主题」才丢弃 backdrop；
  解码侧把 style / theme / font / 倍率与颜色映射移出 panels 门控。
- **回归测试**：新增 `testPhotoThemeSurvivesWireRoundTripThroughProductionCompactState`，用 `ScoreboardDisplayState(compactState:)`（真实链路）构造，
  encode → JSON 往返 → decode，断言 wire 主题、style themeCode 与 backdrop 的 imageData/dim/panelOpacity 全部存活；对旧代码会在 4 处失败。

### 2.4 §5.2 工作台「恢复默认」状态不自洽 —— 已修复

- **复核**：`canResetDraft` 拿实时字号与 `elementMultipliers == nil` 的默认基准比结构体，而 `updateElementMultiplier` 会把 nil 展开成全量字典，
  两者永不相等 → 重置后按钮不置灰；`beginPreview()` 的 `guard previewPreference == nil` 还会保留陈旧预览，
  `applyPreview` 在 `resetRequested == false` 时把残留倍率写回持久化。
- **修复**：`canResetDraft` 改为按解析后的倍率语义比较（无 session 直接 false）；`resetDraft()` 收敛到单一路径 `resetPreview(preferences:)`，
  清掉陈旧预览并让 `applyPreview` 移除持久化的字号键。
- **测试**：新增带真实 `ScoreboardTypographySession` 的 3 个用例（重置后置灰、保存后不残留倍率、取消保留已存字号）。

### 2.5 §5.3 台球结果 `GroupResult` 解码契约不自洽 —— 已修复

- **复核**：`init(from:)` 在 `sport == .billiards` 分支**之前**无条件 `decode(format)`，并统一 `decode([GroupSeat])`；
  而台球行的编码路径会省略 nil 的 `format`、座位是 participantId/position。实测：按 fixture 形状解码抛 `keyNotFound "format"`，
  补上 format 后接着抛 `keyNotFound "side"`。爆炸半径确实覆盖个人记录（`PersonalGroupRecords` + `GroupRepository.results` 无台球特判）。
- **修复**：把 `format` / `participants` 下沉到分支内；台球行走 `GroupBilliardsRow(from:)`，
  `format` 用 `decodeIfPresent` 并按 `participantMode` 兜底，座位由 `GroupBilliardsSeat.groupSeat(individual:)` 合成；球拍项目保持严格但容忍缺键。
- **测试**：新增用例直接读磁盘上的真实 `billiards-v2.json` 6 条台球行解码为 `GroupResult` 并断言规则/结果/座位/赛制与 encode→decode 往返，另断言网球行仍可解码。

### 2.6 §5.4 台球持久化异常扩散到全部记分记录保存 —— 已修复

- **复核**：`ScoreboardRecordManager` 的 `try GroupBilliardsPersistence.shared.annotate(...)` 位于保存主路径的 `do/catch` **之外**，
  而 `read()` 在「文件存在但解码失败」时直接 throw → 任何一条（含非台球）记录都存不下。
- **修复**：`read()` 改为不抛错并在解码失败时隔离坏文件（改名为 `.corrupt-<ts>-<rand>`）后返回兜底值；
  `annotate` 不抛错（读/编码失败回落原记录，与同目录 `GroupLocalPersistence` 既有写法一致）；主路径去掉 `try`。happy path 行为不变。
- **测试**：新增用例破坏 sources/outbox/rules 三个文件后断言 `annotate` 回落、各读取接口返回空而不抛错、坏文件被隔离一次，随后同一 store 能自愈（可再次保存）。

## 三、P2 / P3 修复项

| # | 位置 | 处理 |
|---|---|---|
| P2-4 真实链路 | `DisplayStateWireCodec` | 修复 + 新增 `compactState` 往返测试（见 2.3） |
| P2-5 / #16 绿钮白字 | `GroupBilliardsViews.swift:84,115` | 补 `.tint(Theme.primary).foregroundStyle(Theme.textOnPrimary)`；顺带修既有同类问题 `WechatBindingView.swift:518`（该文件不在本次改动集内，为满足新增规范一并修正） |
| P2-6 工作台字体 tab 门控 | `ScoreboardStyleEditOverlay.swift` | 恢复 HEAD 的 `capabilities.supportsFont` 门控（tab 列表 + `onChange`）。**注**：全仓 `supportsFont` 恒为 true，属潜在防御，无线上行为变化 |
| P2-7 / §5.5 `ok` key | `ScoreboardStyleEditOverlay.swift:326` | `String(localized: "ok")` → `"got_it"`（`Localizable.strings` 47/47 有此 key；`ok` 只存在于 ParticipantIdentity / VIPCommunity 两张专用表） |
| P2-8 `GroupBetaSportTags` | `GroupViews.swift:228` | **误报，未改**。安卓 `shared-model/.../GroupContract.kt` 的 `GroupSports.ALL` 含 `billiards` 且正是同一提示卡的默认运动清单，改成 `.racketSports` 反而破坏三端一致 |
| P2-9 Duo 快照 88 vs 86 | `ScoreboardDisplayTests.swift` | 复核确认 HEAD 上同样失败（环境/运行时基准，非本次引入）。原断言假设 `safeAreaInsets` 增量恒等于 `additionalSafeAreaInsets`；实测窗口基准 2pt（2+86=88），且一旦施加过非零 inset，归零后 UIKit 仍报上一次的值。改为「首个场景断言 基准+请求 精确值、其余场景断言请求的 inset 确实生效」，仍能在 inset 未生效时失败 |
| P3 版本号写死 | 47 个 `Localizable.strings` + `GroupViews.swift:386` | 文案里的 `3.4.3` 改为 `%@`，运行时用 `CFBundleShortVersionString` 填充；新增 `testBilliardsVersionNoticeKeepsAVersionPlaceholder` 钉住占位符并禁止再写死版本 |
| P3 fixture 进包 | `jifen/Features/Groups/Fixtures/` | 移到 `jifenTests/Fixtures/`（两个测试改用 `#filePath` 从磁盘读）；已核对无任何 app 代码读取它们，且打包产物确认包内不再有这两个 JSON |
| P3 `GroupFormat.title` | `GroupModels.swift:19` | `.individuals` / `.mixed` / `.unsupported` 原本都回落 "Doubles"，改为按用例给兜底文案 |
| P3 受让方显示 | `GroupBilliardsViews.swift` | 摘要原本透出内部 ID `p0`/`p1`，改为与 Picker 一致的 1 起序号；无法解析时保留原值 |
| P3 重赛半应用 | `BilliardsScoreboardView.swift` | 把可能抛错的 `inheritSource` 提到 `beginNewMatch()` 之前，失败即原状态返回（与另外三个台球视图一致） |
| P3 篮球面板白字 | `BasketballScoreboardView.swift:418` | `controlColor` 由写死白字改为 `resolvedAutoTextHex(forSlot:)`（== 安卓 `resolvedAutoTextColor`）；默认主题仍为固定白字 |
| P3 发球指示器隐藏方式 | `TennisScoreboardView.swift` | 由 `.opacity(0)` 改为条件移除，与 Rally / TwoSideScoreboardScaffold 统一（避免不可见节点留在无障碍树） |
| P3 全页重算 | `RallyScoreboardView.swift` | 抽出 `RallyPhotoDisplayObserver` 薄壳单独观测投屏输出，记分板本体不再 `@ObservedObject` 持全局单例 |
| §6#10 死代码/静默失效 | `ScoreboardStyleEditOverlay.swift` | 删除已不可达的整条链（工具条/调色板/模态面板/跨槽位文字色传播提示/旧首次提示），2283 → 1591 行；保留仍被引用的 `topControlsReservedHeight`、`capabilities.sideElementKeys`。**注意**：文字色传播提示与旧工作台首次提示是「删除」而非「恢复」 |
| §6#11 `.id()` 硬切 | `ScoreboardStyleEditOverlay.swift` | 去掉 `.id(workbenchTab + draft.themeCode)`，切 tab/主题不再重建 ScrollView |
| §6#12 解码侧造值 | `DisplayStateWireCodec.swift` | 缺失 Optional 保持 nil（不再填 `false`/"arrow"），present 值语义不变，round-trip 稳定 |
| §6#13 `nameFontCode` 默认 | `ScoreboardAppearance.swift:544,618` | 不再写死 `"default"`：nil = 跟随全局计分字体（与既有 profile 解码结果一致），并把测试断言改为 `XCTAssertNil` |
| §6#15 照片主题性能/手势 | `ScoreboardPhotoTheme.swift`、`ScoreboardStyleEditOverlay.swift` | 关掉每帧 base64 校验（改无分配字符集检查）、图片解码与降采样移出主线程（可取消）、滑块不再触发重解码、照片手势补 touchGuard、badge 不再写死 pingpong |
| §6#17 弱断言 | `ScoreboardDisplayTests.swift` | 现有实现已含真实像素扫描与几何断言（绿字存在、左右半场都有、行带高度受限）；仅修正一处与实现不符的陈旧注释 |
| §6#18 CC BY-SA 署名 | `ScoreboardStyleEditOverlay.swift:726` | 去掉常量 URL 的强制解包 + 无障碍标识；补齐部分署名（创作者 + 许可 + 许可链接）与「原始作品 URI 仍缺」的登记（见 §五） |
| §6#20 fixture 入包 | 同上 | 同 P3 fixture 项 |
| §6#21 `VipCommunityAvailability.enabled` | `VipCommunity.swift:12` | **未改，建议保留**（见 §五） |

## 四、判定为误报 / 与既有契约一致（未改代码）

| 条目 | 证据 |
|---|---|
| §6#1 `GroupPortParityTests` 会因 `GroupSport.allCases` 含台球而失败 | 全量跑实测通过；断言对台球同样成立 |
| §6#2 `GroupBetaSportTags` 多出台球标签 | 安卓 `GroupSports.ALL` 含 `billiards`，同一提示卡同源清单（见 §三 P2-8） |
| §6#5 outbox 去重忽略 `done`、失败队列不自愈 | `done` 即「非复活」墓碑语义，本仓库既有测试 `GroupBilliardsTests` 明确断言 `finish(discard:true); add(row)` 后 outbox 仍为空；同目录 `GroupLocalPersistence` 用同一语义。更正/重赛会换新 id，不会撞墓碑 |
| §6#6 「更正」不继承原 `clientSessionId/clientRecordId` → 可能重复提交 | 后端 `api-server/src/lib/groups/billiards.ts:76-108`：以 `gameId`（或 `clientSessionId`）定位同一场，`old.status==='voided'` 时写 `correctedFromResultId`；未作废且成绩不同则返回 409 而不是新建。iOS 更正路径确实带上原 `gameId`，故按契约正确 |
| §6#8 `validate()` 限制 config key + `engineRuleVersion == 3` 过严 | 与后端契约逐条一致：`billiardsRules.ts:19` 为 `z.literal(3)`，`:54` 对 nine_ball 系列强制 `engineRuleVersion === 3`，且要求 required key 齐全。放宽会变成「客户端接受、服务端 422」 |
| §6#9 tournament 缺 `chaseRoundNumber` 被判非终局 | 两个九球记录写入方都必写该字段，更正/迁移也保留 `extraData`；前提不可达（agent 已逐路径核对） |
| §6#22 验证文档跨仓链接会断 | 这是全仓既有约定：`docs/groups/README.md:124,129`、`docs/implementation/participant-identity-2026-10-24.md:26,27,68` 等同样链接兄弟目录。单独 clone 断链属仓库级文档策略，不应只在本次新增文件上单点修改 |
| §6#3 `ScoreboardBackdrop.image` 已成死代码 | 仍被 `ScoreboardPhotoBackground` 的 `.task(id:)` 调用（`ScoreboardPhotoTheme.swift:152` 的 `source.image`） |
| §6#23 analytics 含凭据 | `docs/analytics/2026-10/` 复扫无密钥/token/私钥、无邮箱等个人标识；命中的 "password" 全部是聚合 CSV 里的 `password_login_page` 事件名。仅含 GA4 账号/媒体资源 ID 与内部探索链接，属发布范围决策（见 §五） |
| P3 `GroupBilliardsViews` 记忆规则用 `accountID ?? ""` | 未登录时 `rememberRules` 从不以空账号写过，读不到即回落默认规则，结果与显式 guard 等价 |

## 五、未处理 / 待你决策

1. **`docs/analytics/2026-10/`（22 文件 / 1.3 MB）是否入库**：内容为聚合业务分析，无个人级标识；但含 GA4 账号/媒体资源 ID（`a254588017p555…`）与内部探索链接。仓库远端为 `github.com:yangyang2049/jifen-ios.git`，匿名访问返回 200（疑似公开）。**若公开，建议剥离内部控制台链接后入库**；剥离会牺牲 `build_report.py` 的可复现性，故未擅自修改。
2. **`VipCommunityAvailability.enabled` 默认 `true`**：现状是 fail-open——配置未拉到/拉取失败时仍显示入口，点击后由流程回「暂不可用」。改成默认 `false`（fail-closed）会在离网/慢网下让功能入口消失。两者各有取舍，属产品决策，未改。
3. **§6#7 handoff / 恢复死状态**：本组内每个本地 source 在总览里都渲染了「继续 + 放弃」两个按钮，故「不可放弃」这半条在当前代码上不成立；「`unfinished` 阻塞开新局」是刻意的并发保护，其逃生口依赖记分板自身的恢复流程与「陈旧未完成会话」策略，属恢复会话生命周期的产品决策，超出本次改动集范围。
4. **§6#14 照片主题下元素选择不可达**：照片主题 tab 只有 theme/background，而 `.styleElementSelectable` 仍落在不渲染的 `templateBody` 上。需要先明确「照片主题可编辑范围」这一设计口径。
5. **CC BY-SA 署名仍缺原始作品 URI / 版权声明行**：代码侧已做能做的部分，其余需版权方信息；已登记 `TODO.md`。
6. **`.ddzRetro` 名牌未纳入复古绿字修复**：`doudizhuSlotTextColors` 只把主分标为手动绿（`4CAF50`，与主题 `foregroundHex` 的 `00FF00` 不同），其余元素走 AUTO → 黑底白字。是否按 `.retro` 一并处理属设计确认项。

> 说明：`docs/audits/self-check-remediation-2026-11-06.md`（本文件）是本次检查产物，是否入库请单独决定。

## 六、证明与证据

```sh
# 编译（主 target）
xcodebuild -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/jifen-egwftqixeblfcjgeickwopmwemnl build

# 测试 target 编译 + 全量单测
xcodebuild build-for-testing  ...（同上参数）
xcodebuild test -only-testing:jifenTests -resultBundlePath <batch>/unit-tests-final.xcresult \
  -project jifen.xcodeproj -scheme jifen -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/jifen-egwftqixeblfcjgeickwopmwemnl
```

- 测试证据批次：`~/Library/Developer/jifen-ios-test-artifacts/runs/20261105T163902601170Z-selfcheck-remediation-2026-11-06/`
  （`unit-tests-final.xcresult` = 1006 通过 / 0 失败 / 1 跳过；`logs/` 含编译与两轮单测日志、`tree-*.txt` 含工作区指纹）。
  外部证据按 `AGENTS.md` 的保留策略到期清理，本报告只引用结论。
- 残留扫描：对本次删除的符号（`paletteEntry`、`modalPanel`、`textColorPropagationPrompt`、`StyleTextColorRequest`、
  `runPropagationCountdown`、`applyPropagation`、`styleEditUsageHint`、`usageHintShownKey`、`collapsedPaletteButton`、
  `paletteExpanded`、`panelCard/panelHeader/panelTitle/elementPanelTitle/fontPanel/themePanel`、`surfaceBackground`、
  `scoreboard_style_edit_usage_hint_v1_shown`）在 `jifen`、`jifenTests`、`jifenUITests` **逐路径**检索（本环境 shell `grep`
  多路径时只搜第一个路径，因此没用 `grep -r`），零命中；仅保留仍被引用的 `topControlsReservedHeight`。
- 打包校验：`find <DerivedData>/Build/Products/Debug-iphonesimulator/jifen.app -name '*.json'` 为空——
  修复前 `rules-v1.json` / `billiards-v2.json` 在包内。
- 本地化校验：47 语言 × 2391 key 集合一致、无重复 key、`plutil -lint` 全通过、格式占位符零不一致。

## 七、`style_workbench_*` 复用译文映射（15 条）

| 新 key | 复用来源 key |
|---|---|
| `style_workbench_title` | `scoreboard_style_edit` |
| `style_workbench_theme` | `scoreboard_style_theme` |
| `style_workbench_background` | `scoreboard_style_background` |
| `style_workbench_font` | `menu_font` |
| `style_workbench_cast` | `display_connection_tab_cast` |
| `style_workbench_settings` | `settings` |
| `style_workbench_select_photo` | `group_album` |
| `style_workbench_score_font` | `font_selection_title` |
| `style_workbench_name_default` | `scoreboard_font_default` |
| `style_workbench_match_title` | `match_title` |
| `style_workbench_team_name` | `setup_team_name` |
| `style_workbench_player_name` | `setup_player_name` |
| `style_workbench_main_score` | `scoreboard_font_metric_main_score` |
| `style_workbench_set_score` | `match_completion_sets` |
| `style_workbench_game_score` | `tennis_game_score` |

其余 18 条（`reset` / `free` / `phone` / `full_preview` / `back` / `current` / `available` / `photo` /
`restore_photo` / `dim` / `opacity` / `name_font` / `name_rounded` / `name_serif` / `server_visible` /
`set_game_score` / `photo_failed` / `image_advice`）写英文源串占位，待翻译战役补译文。

## 八、并发写入说明（重要）

复核期间工作区存在**另一个正在运行的会话/任务**在并发写入，非本报告作者所为。已记录到的写入：

| 时间 | 文件 | 说明 |
|---|---|---|
| 00:10 起 | `…/runs/20261105T161042749991Z-style-workbench-palette/`（曾带 `.active`，含 fail…fail5） | 他人正在运行的测试批次，本报告未触碰其 marker；该批次随后由所有者自行收尾（00:56 时只剩 `.run.json`） |
| ≤00:24 | `ScoreboardAppearance.swift`（`genericSlotTextColors` 的 `.retro` 手动绿字）、`ScoreboardStyleV2ModelTests.swift`（`testRetroThemeKeepsGreenTextInsteadOfAutoContrastWhite`） | 用 00:24 的备份比对确认：这两处**先于**本次复核已存在。该测试的「用户报告」措辞我无法独立证实，但其描述的行为有独立证据——`docs/verification/audit-remediation-2026-10-25/ios-final.log` 里 `THEME[retro] … fg=00FF00` 紧接 `resolvedText t0=FFFFFF` |
| 00:32:47、00:51–00:54 | `jifenUITests/FullAppScreenshotUITests.swift` | 他人编辑（本报告作者只改过其中一处注释） |
| 00:49:41 | `GroupRepository.swift:465` | 他人把版本闸门文案改为 `groupText("error_update_required", …)`；已核对 `group_error_update_required` 在 47 个语言中齐全，且 `GroupErrorMessage.swift:69` 用同一 key，属正确改动 |
| 00:5x | 新增 `docs/audits/cross-platform-parity-2026-11-06.md` | 他人产物，未触碰 |

**影响**：最终一轮验证（`unit-tests-final.xcresult`，00:51:36 起，diff 指纹 `e7194fce…`，结束 `f844dfc1…`）期间只有 UI 测试文件被他人改动，
`jifenTests` 的结果不受影响；但**在此之后任何写入都会使上述验证失效**，提交前请重跑一次全量单测确认。
截至 00:56 该并发写入仍在继续（`FullAppScreenshotUITests.swift` 再次被改动），因此**本报告的验证结论绑定于指纹 `f844dfc1…`**。

## 九、建议的后续动作

1. 按 §五 决策 analytics 入库范围与 VIP 入口 fail-open/fail-closed。
2. 安排 33+97 条英文占位 key 的翻译战役（本次只解决了「缺 key」）。
3. 明确 `.ddzRetro` 名牌配色口径与照片主题可编辑范围。
4. 补齐 CC BY-SA 的原始作品 URI / 版权声明行后再发版。
5. 提交前确认并发写入已停止，并重跑 `jifenTests` 全量。

## 十、二次复核（2026-11-06 14:xx，独立重跑）

对 §二 / §三 / §四 逐条在当前工作树上重新取证（不直接采信上文结论），并重跑全量回归：

| 复核项 | 结果 |
|---|---|
| `jifenTests` 全量重跑（14:28 起，`unit-tests.xcresult`） | ✅ **1011 通过 / 0 失败 / 1 跳过**（共 1012 项） |
| 47 语言 key 矩阵（自写脚本重算） | ✅ 2392 key 全一致；占位符按「类型计数」比对 **0 不一致** |
| 打包产物 `find jifen.app -name '*.json'` | ✅ 空（fixture 确已移出 app target） |
| 已删符号残留（13 个符号 × `jifen`/`jifenTests`/`jifenUITests`） | ✅ 零命中 |
| §2.1 33 个 `style_workbench_*` | ✅ 47 语言齐备 |
| §2.2 合同版本单源 | ✅ `GroupContract.version = 2`，沙盒/仓库/上限判断同源 |
| §2.3 照片主题往返 | ✅ 生产链路用例存在且全绿 |
| §2.4 工作台重置 | ✅ `canResetDraft` 走语义比较，`resetDraft` 单一路径 |
| §2.5/§2.6 台球解码与坏文件隔离 | ✅ `read()` 隔离 `.corrupt-*`、`annotate` 不抛错，主路径已无 `try` |
| §三 P2/P3（绿钮白字、`got_it`、`%@` 占位、`.id()`、`nameFontCode`、受让方序号、重赛前置、篮球色、网球指示器、Rally 观察者） | ✅ 逐处命中，且 `3.4.3` 在 47 语言中零硬编码 |
| §四 误报 10 条 | ✅ 逐条重新取证，结论与上文一致（安卓 `GroupSports.ALL` 含 `billiards`、后端更正按 `gameId`、`z.literal(3)`、`ScoreboardBackdrop.image` 仍被 `source.image` 使用等） |

### 10.1 本次新发现并修复的真实回归（上文未覆盖）

**`0413b8aa`（10:55，把图片上限放宽到 200,000）会击穿后端实时帧上限。**

`REALTIME_MAX_PAYLOAD_BYTES` = 512KB，而投屏帧里**每个参与者各带一份完整 `displayState`**
（`RemoteSyncController.mapDisplayStateToParticipants`；安卓同构，其
`RemotePhotoThemePayloadTest` 明确断言「doubles must exercise four complete metadata copies」）。
双打 4 份 × 200,000 字符 = 800,000，实测整帧 **811,868 字节 > 524,288**，服务端 `ws`
会以 1009（message too big）**关闭连接** —— 不是图片降级，而是整条投屏断掉。

处置：把上限收回 90,000（与安卓 `SCOREBOARD_BACKGROUND_MAX_DATA_LENGTH`、鸿蒙
`scoreboardStyle.ts` 一致），并保留 `imageDataCharacterLimit` 常量承载「按最坏一帧倒推」的口径说明；
同时新增 `testLargestPhotoImageKeepsDoublesFrameWithinBackendPayloadBudget`，用**真实映射**把整帧
字节数和「4 份副本都带图」一起钉死。该用例在 200,000 下实测报红（811,868），回到 90,000 后转绿。

> 注：`0413b8aa` 与网站端 `512ad73` 是同一批「1080p 清晰度」改动，网站端上限也是 200,000。
> 网站是**接收端**，放宽上限本身不产生超帧，故未改；三端发送侧统一 90,000。

### 10.2 仍未消除的交付风险（与上文一致，未改）

- 44 个语言仍有英文占位译文，需翻译战役。
- §五 的 4 项产品决策与 CC BY-SA 署名缺口保持原状。
- `docs/analytics/2026-10/` 已在 `8b908d8e` 入库（22 文件），是否保留/剥离控制台链接仍待决策。
