# 下一版本（3.5）跨端 TODO

日期：2026-11-26 · 范围：iOS 为主，涉鸿蒙一项 · 状态：**待排期，下周版本**
上游依据：`docs/ios-3.4.4-changes-and-test-plan-2026-11-26.md` 与 2026-11-26 四仓对照审计

---

## 1. App 分享邀请闭环（iOS 从零新建）

**来源**：谷歌安卓已有完整实现（`jifen-android-google`），国内安卓、鸿蒙、iOS 都没有。

| 参考实现 | 位置 |
| --- | --- |
| 触发与准入策略 | `jifen-android-google/app/src/main/java/com/douhua/jifen/screen/me/AppSharePrompt.kt`（150 行） |
| 弹窗 UI | `.../ui/dialog/AppShareInviteDialog.kt:75`（羽毛球对拉动画 + 49 地区文案） |
| 与评分/活动互斥 | `.../screen/home/HomeTabScreen.kt:310-335` |
| 偏好格式 | `app_share_prompt_state_v1`（JSON：usage_days / completed_records / last_action_ms / outcome / dismissals / completion_baseline） |
| 单测 | `app/src/test/java/com/douhua/jifen/screen/me/AppSharePromptTest.kt` |

**准入规则（照抄，不要重新发明）**
- 使用 ≥ 5 个不同自然日，且完成 ≥ 8 局有效比赛；
- 冷却：分享过 90 天、拒绝 2 次及以上 30 天、其它 14 天；
- 拒绝满 3 次且从未分享 → 永久不再弹；
- 每次冷却后还需再完成 ≥ 3 局（`completion_baseline` 差值）；
- 只在首页主按钮触发，且与评分邀请、会员活动、微信绑定弹层互斥（同一时刻只弹一个）。

**iOS 落地要点**
- 状态机与 `AppReviewPrompt.requestsReviewOnEligibleLaunch(suppressed:)` 同构，复用同一「一次性弹层闸门」，避免两套互斥逻辑打架；
- 分享内容走 `UIActivityViewController`，链接文案按 47 语种；国内简中指向 jifenqi.com，其它指向 iscoreboard.live（与「关于页」域名口径一致）；
- 偏好键新建，勿复用 `AppReviewPrompt` 的键。

**验收**：5 天 / 8 局前不弹；拒绝 3 次后不再弹；分享后 90 天不弹；与评分邀请、会员活动、微信绑定三者互斥；杀进程重启后状态不丢。

**估时**：3–4 人日（含 47 语种文案、单测、真机走查）。

---

## 2. 麻将玩法（iOS 从零重新做）

**来源**：安卓已有完整实现（国内与谷歌同源），iOS 全仓 `Mahjong|麻将` 0 命中，需要整套重建。

**安卓的表面积**（`jifen-android`，31 个文件 / 478 处引用）

| 模块 | 文件 | 规模 |
| --- | --- | --- |
| 计分板 | `screen/score/mahjong/MahjongScoreScreen.kt` | 198 处引用，含点格记账、印章、局程 |
| 开局设置 | `screen/score/setup/MahjongSetupDialog.kt`(80) + `MahjongSetupEditors.kt`(41) | 自定义局程、玩家、座位 |
| 结算与弹窗 | `MahjongV4Dialogs.kt`(18)、`MahjongSettlementPresentation.kt`(10)、`MahjongSeatChangeDialog.kt`(12) | 中途换人、结算展示 |
| 记录展示 | `screen/records/MahjongRecordDisplay.kt`(26)、`ScoreboardDetailRecapBuilder.kt`(8) | 记录详情/分享卡 |
| 投屏/显示端 | `display/ui/DisplaySurfaceModels.kt`(9)、`DisplayOutputCapabilities.kt`(2) | 投屏版式 |
| 入口 | `ScoreTabScreen.kt`(10)、`HomeQuickStartComponents.kt`(9)、`HomeTabScreen.kt`(8)、`ScoreRouteRegistry.kt`(5) | 首页/计分页/路由 |

**iOS 落地顺序建议**
1. `ScoreCore` 先落规则内核（局程、点格记账、结算公式、中途换人）+ 单测——参考 `Packages/JifenCore/Sources/ScoreCore/s2/SpecializedScoreboards.swift` 的现有写法；
2. `GameType.mahjong` + `ScoreboardKernelRegistry` 注册 + `catalog` 排序（注意 `ScoreboardCatalogTests` 会断言项目顺序与图标打包）；
3. 计分板 UI 复用现有「多人大分格」骨架（`MultiScoreboardView` 的格子与分页），另写点格记账层；
4. 记录投影必须写扁平字段（`mahjongLedger` / `mahjongSetup`），不要只写 `stateSnapshot` blob——否则安卓读不出（同「跨端续打 blob↔flattened」那条架构级缺口）；
5. 投屏/扩展屏版式与 `DisplayStateWireCodec` 字段；
6. 文案三套（en / zh-Hans / zh-Hant）+ `LocalizationIntegrityTests` 键集合断言。

**风险**
- 麻将是中国市场玩法，海外版是否上架需产品确认（App Store 中国区可上，其它区可配置隐藏）；
- 记录格式一旦定错，跨端续打不可逆，必须在写码前先定 wire 字段；
- 工作量最大的一项，建议单独立项而不是塞进 3.5。

**估时**：15–25 人日（不含投屏版式细化）。

---

## 3. 开源许可页（iOS + 鸿蒙）— ✅ 2026-11-26 已实现

**现状**：安卓有「关于页 → 开源许可」入口（`OpenSourceLicensesActivity`）；iOS 与鸿蒙**都没有**。

| 端 | 现状证据 |
| --- | --- |
| iOS | `jifen/**/*.swift` grep `License` → 0 命中；关于页只有反馈/FAQ/隐私 |
| 鸿蒙 | `entry/src/main/ets` grep `开源|License` → 0 命中；资源里只有一张 CC BY-SA 图片来源署名 |

**为什么必须做**：iOS 引入了 teko 与 seven-segment 两款 OFL 字体（`jifen/Core/…/FontRegistrar.swift:17`、`ScoreboardAppearance.swift:1382,1399`），OFL 要求随分发保留版权与许可声明；照片主题还带 CC BY-SA 4.0 图片来源署名。缺这一页属合规风险，不是体验问题。

**已落地的做法**（不引第三方合规 SDK，纯文本自建，与安卓同一套「丢 txt 就出现」）

| 端 | 文件 | 说明 |
| --- | --- | --- |
| iOS 页面 | `jifen/Features/Me/OpenSourceLicensesView.swift` | `LicenseCatalog` 枚举包内 `license-*.txt`，等宽字体原样展示，可选中复制 |
| iOS 文本 | `jifen/Resources/licenses/license-*.txt`（4 个） | teko-OFL / seven-segment-OFL / lucide / scoreboard-backgrounds |
| iOS 入口 | `SettingsView.swift` AboutUsView 内新增一行 | 值驱动 `NavigationLink(value: AboutRoute.openSourceLicenses)` |
| iOS 守门 | `jifenTests/OpenSourceLicensesTests.swift`（6 例） | 字体↔许可、背景图↔署名、47 语种键、bundle 压平后仍可读 |
| 鸿蒙 页面 | `entry/src/main/ets/pages/me/OpenSourceLicensesPage.ets` | `getRawFileListSync('licenses')` 枚举 + 静态兜底清单 |
| 鸿蒙 文本 | `entry/src/main/resources/rawfile/licenses/`（6 个） | 原有 lucide / mahjong_winds ×2，本轮补 teko / seven-segment / backgrounds |
| 鸿蒙 入口 | `pages/me/AboutUsPage.ets` + `main_pages.json` | 关于页新增「开源许可证」行 |

**两个必须记住的坑**

1. **Xcode 会把 `Resources/licenses/` 压平到 bundle 根目录**（实测 `jifen.app/teko-OFL.txt`），
   子目录不会保留。所以 iOS 侧统一加 `license-` 前缀、按前缀在 bundle 根枚举，
   `LicenseCatalog.bundleFilePrefix` 就是这个约定；新增文本必须带前缀。
2. **关于页不能用闭包式 `NavigationLink { 页面 }`**。`SettingsView.swift:459` 有注释记录过：
   闭包 push 的页面会和网页 item push 抢同一条栈，返回时被一起退掉。本轮改用
   `NavigationLink(value:)` + `navigationDestination(for: AboutRoute.self)`。

**验证**：iOS `BUILD SUCCEEDED` + `OpenSourceLicensesTests` 6/6 通过；鸿蒙 `assembleHap`
BUILD SUCCESSFUL，HAP 内确认含 6 个 `resources/rawfile/licenses/*.txt`，
`verify_i18n_resources.mjs` / `verify_string_references.mjs` / `audit_design_tokens.mjs` 均通过。

**标题本地化**：iOS 47 语种、鸿蒙 7 套语言包各加 2 个键（`about_open_source_licenses`、
`open_source_licenses_title`）。译文直接取谷歌安卓已审校的 `values-*` 对应词条，
只有 Odia 缺条目、按同类印度语系拼写补的，建议人工复核一条。

---

## 4. 小组「发起活动」表单：iOS 按安卓 1:1 照抄（已定）

**决定**：1:1 照抄安卓（＝鸿蒙现有样子），不做半对齐。分析与逐行对照见 `docs/group-activity-form-analysis-2026-11-26.md`，可视化对比见 `docs/demos/group-activity-form-compare-2026-11-26.html`（同名 `.png`）。

**为什么要抄**：字段集合、校验、文案、接口本来就一致，差别只有两类纯视觉差异——①字段名在框外独占一行 vs 框内 placeholder + 行尾问号；②「标签 + 描边输入框 + 白卡片」vs「48 填充块 + 行首图标 + 行尾箭头、不分组」。功能差异为 0。另外 iOS 内部本来就两套（台球用系统 `Form`，其它球类用 `GroupAlignedField`）。

**必做配套**：逐行补 `accessibilityLabel`（填完后字段名不可见）；系统 `Form` 换自绘滚动容器后自己接管键盘避让与 iPad 宽度上限。

**范围**：只改小组活动这一张表单，不动 `CreateBookingPage`。

**估时**：6.5 人日（骨架 1.5 + 重排 1.5 + 台球并入 1 + 无障碍键盘 1.5 + 测试截图 1）。
