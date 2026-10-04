# iOS 深色模式与图标全量审计报告

- **日期**：2026-10-04
- **范围**：`origin/main (3.2.1, 0f6423f6)` → `HEAD (3.3, 4303cfa8)` 全部 127 个改动 Swift 文件 + 38 个新增 imageset + 6 个 colorset；工作区干净，无未提交改动
- **方法**：token 层比对 → 机械扫描（hex / Color.white·black / UIColor / colorScheme 分支，共 460+ 命中逐条归类）→ 资源层核对 → 三路并行上下文逐文件审查 → 问题行 git 考古定版本归属

---

## 一、总体结论

| 维度 | 状态 | 说明 |
|---|---|---|
| Token 层 | ✅ | `Theme.swift` 体系完善：`appCardBackground`/`inputFieldBackground`/`accentColor` 等全部双值动态色；`Theme.adaptive`/`tintedFill`/`lightModeShadow` 覆盖一次性场景 |
| 本版本全新 UI | ✅ | 国庆会员弹层、使用提示动画(4 文件)、会员页、投屏连接页、云同步入口主体、38 个 icon_3d_* 图标全部合规 |
| 资源层 | ✅ | 5/6 colorset 有深色变体（LaunchScreenBackground 固定深底为有意设计）；38 个新增 imageset 均为 3D 彩色插画，不 tint、无需深色变体 |
| 问题 | 🔴1 / ⚠️3 / P3 若干 | 集中在反馈社区页与 wrb 白底主题，多数为 3.2.x 遗留、非 3.3 新引入（详见归属标注） |

---

## 二、🔴 P1（深色下不可读）

### 1. 反馈页头像占位：固定浅灰圆底 + 自适应图标色
- **位置**：`jifen/Features/Feedback/FeedbackViews.swift:137-145`（`placeholderGlyph`）
- **现状**：`Circle().fill(Color(hex: "E5E7EB"))` 固定浅灰底 + `Image(systemName: "person.crop.circle").foregroundColor(Theme.textSecondary)`
- **问题**：深色模式下 `textSecondary` 解析为浅灰白，叠在固定浅灰 `#E5E7EB` 上对比 ≈1.3:1，人形图标几乎隐形；浅灰圆在 `#202022` 卡片内也格外刺眼
- **影响面**：3 处引用 —— 列表卡(:572)、详情主卡(:787)、评论行(:1082)
- **归属**：3.2.1 遗留（dc4201e3 引入，反馈社区页本体）
- **建议**：圆底改 `Theme.controlBackground` 或 `Theme.tintedFill(Theme.textSecondary, lightAlpha: 0.12, darkAlpha: 0.16)`

---

## 三、⚠️ P2（明显违和/低对比）

### 1. 乒乓球红黄牌弹窗：wrb 主题下选手名条不可读
- **位置**：`jifen/Features/Scoreboard/Sports/Rally/TableTennisCardsDialog.swift:141-156`（色源 `RallyScoreboardView.swift:629-630`）
- **问题**：弹窗本体固定深色（`scoreboardDialogSurface #2C2C2E`），但选手名条/选中底直接用面板主题色 `palette.left/right` + 固定白字。wrb（白红蓝）主题下 = 白 0.75 亮底 + 白字，对比 ≈1.7:1，几乎不可读
- **归属**：**3.3 新增文件** ✅ 本版本必须修
- **建议**：名条底改固定 `white 0.12~0.2` + 白字，主题色只做描边；或 wrb 下用 `palette.control` 压暗（对比 TeamSection 名称编辑框已有正确兜底）

### 2. 反馈页 + 个人资料页：固定浅琥珀审核横幅
- **位置**：`FeedbackViews.swift:209-223`（3 处引用：列表卡/详情/评论行）、`AccountViews.swift:467-481`
- **问题**：`FEF3C7` 浅奶油底 + `B45309` 深棕字为固定组合，可读但在深色卡片中突兀亮起一条奶油色横幅
- **归属**：均为 3.2.x 遗留
- **建议**：底改 `Theme.adaptive(Color(hex:"FEF3C7"), Color(hex:"3A2E0A"))`，字改 `Theme.adaptive(Color(hex:"B45309"), Color(hex:"FBBF24"))`；两处同款可顺手抽成共用组件

### 3. MenuDialog：固定深色弹层未强制 dark 环境，绿色双口径
- **位置**：`jifen/Features/Scoreboard/Shared/MenuDialog.swift:487`
- **问题**：弹层整体固定 `#202124` 但没有像 GameOverDialog 那样 `.environment(\.colorScheme, .dark)`；内部 `Theme.primary` 浅色模式解析为 `#4CAF50`，而同弹层确认态写死 `Color(hex:"4CAF50").opacity(0.55)`——两处绿在深色模式下不一致（`#30D158` vs `#4CAF50`）
- **归属**：3.3 触碰文件
- **建议**：补 dark env（与 GameOverDialog 对齐），或统一写死绿色

---

## 四、P3（轻微/一致性）

| # | 位置 | 问题 | 归属 |
|---|---|---|---|
| 1 | `ScoreboardLaunchView.swift:129-135` | 比赛时间胶囊「白字 + 黑 0.32 底」悬浮任意主题面板，wrb 白面板下对比 ≈1.6:1 | 遗留(2.1) |
| 2 | `TwoSideScoreboardScaffold.swift:490-500` + `ScoreboardTemplate.swift:420-487` | chrome 圆钮「黑 0.25 + 白 icon」压 wrb 白面板对比 ≈1.6:1，按钮形同隐身 | 遗留 |
| 3 | `GameOverDialog.swift:251` | 项目 3D 图标原色渲染压固定深色 `#2C2C2E` 面板，浅色场景插画与深底衔接略突兀（非不可读） | 3.3 触碰 |
| 4 | `BentoCardView.swift:7/27` | 潜伏缺陷：默认参数 `gradientColors=[Theme.surface,...]`（自适应）配固定白字标题，未来调用者用默认值即白字白底；另 :37 阴影未用 `Theme.lightModeShadow` | 遗留 |
| 5 | `ScoreboardRecordDetailPage.swift:212/216/285/442/765` | `.green`/`.orange` 字面色未走 token（`Theme.positiveText`/`warningText` 现成），深色下与 `accentColor #30D158` 色系不统一 | 遗留 |
| 6 | `CreateBookingPage.swift:248/444` + `CommonPlacesManagementView.swift:195` | 固定 `Theme.primaryDark #248A3D` 无深色变体，深色下图标/大图标偏暗发闷；建议 `Theme.accentColor` 或 adaptive | 遗留 |
| 7 | `CloudSyncEntryView.swift:340-347` | 短码输入框底与父卡同色（白上白/#202022 上 #202022），仅 26% 描边区分，建议改 `Theme.inputFieldBackground` | 3.3 新增页 |
| 8 | `MembershipView.swift:758` | 勾选绿写死 `#30D158`，浅色模式与 accent `#4CAF50` 不一致（非深色问题） | 3.3 触碰 |
| 9 | `FeedbackViews.swift` 状态徽章白字压 `22C55E/F59E0B` 彩底 | 对比 ≈2.2:1 偏低，但两模式一致、与安卓对齐，非深色特有 | 遗留 |
| 10 | `WhistleToolView.swift:108/148` | 固定 Material 绿/红描边与 token 绿色值不一致，同屏色差 | 遗留 |

---

## 五、✅ 明确核查通过项（本版本重点）

| 区域 | 文件 | 结论 |
|---|---|---|
| 国庆会员弹层 | `NationalDayMembershipSheet.swift`（新） | 1:1 固定浅色海报设计，根节点 `.background(Color.white)` 兜底，深浅两模式安全 |
| 使用提示动画 | `UsageHintAnimation/` 4 文件（新） | 固定暗场 `#12151B` + 亮色元素，无随主题残留 |
| 投篮训练 | `ShotTrainingScoreboardView.swift` | 固定暗场 + `ShotTrainingZonePalette` 唯一口径 |
| 掼蛋/升级 | `Guandan/ShengjiScoreboardView.swift` | 无直接取色，按钮走 palette.foreground + wrb control 兜底 |
| 会员页 | `MembershipView.swift` | 全 token |
| 头像裁剪 | `AvatarCropView.swift` + `AccountViews:1078` | 固定黑底裁剪页，`presentationBackground(.black)` 配套，自洽 |
| 投屏连接页 | `CastConnectionView.swift` | 全 token + `tintedFill` 正确写法，可作参照 |
| 云同步分享弹层 | `CloudSyncEntryView:742-905` | 固定深色弹层规范内 |
| 图标资源 | 38 个 `icon_3d_*`（新）+ `AppCatalogIcon.swift`（新） | 3D 彩色插画原色渲染，不依赖深浅色 |
| colorset | 6 个中 5 个有深色变体 | `LaunchScreenBackground` 固定深底为有意设计 |
| 强制深色 | `MultiScoreboardView:1017`、`GameOverDialog:312` | 合法手法 |
| 头部绿卡 | `HomeHeaderView.swift`（改） | `Theme.primary` 底 + 白字白点，两模式可见 |
| 相机角标 | `AccountViews:1164-1177` | 固定白圆 + 深灰图标 + 描边，照片上标准徽章 |
| 魔方计时 | `CubeTimerView.swift` | 整页固定黑底 + 霓虹绿数字，意图明确 |
| 棋钟 | `DualPlayerTimerView.swift` | 固定黑白棋类设计 |

---

## 六、建议修复顺序

1. **P1** FeedbackViews 头像占位圆（1 行底色改动，观感收益最大）
2. **P2** TableTennisCardsDialog wrb 名条（3.3 新增，发布前应修）
3. **P2** 两处琥珀横幅统一 adaptive（一次改动收口两文件）
4. **P2/P3** MenuDialog 补 dark env 统一绿色
5. P3 批量：`.green/.orange` → token、`primaryDark` → accentColor、BentoCardView 默认参数、chrome 圆钮 wrb 加深

> 归属提示：P1 与多数 P3 为 3.2.x 遗留问题（本轮全量扫描顺带发现），只有「乒乓球红黄牌弹窗 wrb 名条」「MenuDialog 绿色口径」「BentoCardView 阴影」等少数条目与 3.3 改动直接相关。3.3 全新页面（国庆/动画/投屏/会员/38 图标）深色适配质量很高，无一处违规。

---

## 七、修复记录（二次确认后落地）

### P1 / P2

| # | 位置 | 改动 | 状态 |
|---|---|---|---|
| P1 | `FeedbackViews.swift:137-145` | 圆底 `E5E7EB` → `Theme.tintedFill(Theme.textSecondary, lightAlpha: 0.12, darkAlpha: 0.16)`；深色对比由 ≈1.3:1 → 3.6:1，3 处引用（列表卡/详情主卡/评论行）一次收口 | ✅ |
| P2-1 | `TableTennisCardsDialog.swift:130-208` | 名条字色改为**按合成底色 WCAG 相对亮度自动取黑/白**（`nameStripTextColor`/`compositeOverDialogSurface`/`readableTextColor`）。保留面板色辨认度，且同时兼容用户自定义面板色（V2 样式配置）；选中描边同步跟随字色，wrb 下不再白描边压白底。wrb 对比 ≈1.6:1 → ≈12.8:1 | ✅ |
| P2-2 | `Theme.swift` + `FeedbackViews.swift:204-225` + `AccountViews.swift:467-481` | 新增 `Theme.moderationNoticeBackground/Text` 双值 adaptive（底 `FEF3C7`→`3A2E0A`、字 `B45309`→`FBBF24`），两文件共用同一 token；深色下对比 ≈8.0:1 | ✅ |
| P2-3 | `MenuDialog.swift:281, 407` | 补 `.environment(\.colorScheme, .dark)`（对齐 GameOverDialog），弹层内动态色不再随系统外观跳；`confirmBackground` 由写死 `#4CAF50@0.55` 改 `Theme.accentColor.opacity(0.55)`，与 `.tint(Theme.primary)` 同源，两种绿收敛为一种 | ✅ |

### P3

| # | 位置 | 改动 | 状态 |
|---|---|---|---|
| 1 | `ScoreboardLaunchView.swift:135` | 胶囊底 `black 0.32` → `black 0.55`（wrb 白面板下白字 ≈2.2:1 → ≈4.75:1） | ✅ |
| 2 | `TwoSideScoreboardScaffold.swift:490` + `ScoreboardTemplate.swift:426/466/486` | chrome 圆钮底 `Color.black.opacity(0.25)` → `appearance.palette.chrome`（该 token 此前已定义但无人使用；wrb 为 `black 0.72`，其余主题 ≈0.28~0.9，行为等价或更优） | ✅ |
| 4 | `BentoCardView.swift:5-10, 40` | 取消误导性默认值 `gradientColors = [Theme.surface, Theme.surface]`（改必传，两处调用均已显式传参）；阴影 `homeButtonShadow` → `Theme.lightModeShadow(0.2)` | ✅ |
| 5 | `ScoreboardRecordDetailPage.swift:212/216/285/442/765` | `.green`/`.orange`/`Color.green` → `Theme.positiveText`/`Theme.warningText`（5 处） | ✅ |
| 6 | `CreateBookingPage.swift:248/444`、`CommonPlacesManagementView.swift:197`、`SchedulePage.swift:48` | 图标类 `Theme.primaryDark` → `Theme.accentColor`（4 处） | ✅ |
| 7 | `CloudSyncEntryView.swift:340` | 短码输入框底 `appCardBackground` → `Theme.inputFieldBackground` | ✅ |
| 8 | `MembershipView.swift:758` | 协议勾选 `Color(hex:"30D158")` → `Theme.accentColor`（浅色对比 ≈1.9:1 → ≈2.8:1） | ✅ |
| 10 | `WhistleToolView.swift:103/108/143/148` | 短哨卡 `.systemGreen`/`#4CAF50` → `Theme.accentColor`；长哨卡 `.systemRed`/`#F44336` → `Theme.toolWhistleRed`，消除同屏色差 | ✅ |

### 明确保留（有意不修，附依据）

| 位置 | 保留理由 |
|---|---|
| `CreateBookingPage.swift:495/499`（提醒时间选中胶囊 fill/stroke） | 该底色承载**白字**，`primaryDark #248A3D` 对白字 4.4:1；换成 `accentColor` 会掉到 3.5:1，属对比度驱动而非遗留疏漏 |
| `BookingDetailPage.swift:177`（"复制预约"文字 tint） | 同为文字色，`primaryDark` 对 `controlBackground` 4.0:1，换 `accentColor` 降至 3.1:1 |
| `QuickStartGridView.swift:88`（`[primary, primaryDark]` 渐变） | 渐变需要比 primary 更暗的第二色；`primaryDark` 在深色下仍偏暗属该用法所必需 |
| `GameOverDialog.swift:251`（3D 图标原色渲染） | 报告原判「非不可读」，属插画与深底的衔接观感，非缺陷 |
| `FeedbackViews` 状态徽章（白字压彩底 ≈2.2:1） | 两模式一致、与安卓对齐，非深色特有 |
| `ScoreboardStyleEditOverlay.swift:743/1285`、`SnookerScoreboardView:574`、`CubeTimerView:219`、`ScoreboardExternalDisplayView:2255` 的 `black 0.28~0.82` | 语义为**遮罩层**而非 chrome 圆钮，与第 2 项不同类，不可一起替换 |

### 本轮暴露的审计缺口（待定夺）

chrome 圆钮写死 `Color.black.opacity(0.25)` 的实际范围**远大于报告圈定的 2 个文件**，以下同样会在 wrb 主题下让按钮隐身（均为同一 token 的一行替换）：

| 文件 | 行 |
|---|---|
| `RallyScoreboardView.swift` | 1714（编辑态三目）、1755（`chromeButton` 默认参数——羽毛球/乒乓/网球/匹克球主计分板） |
| `BasketballScoreboardView.swift` | 354 |
| `NineBallChaseScoreboardView.swift` | 243 / 265 / 282 |
| `DoudizhuScoreboardView.swift` | 493 / 515 / 548 |
| `MultiScoreboardView.swift` | 394 / 409 |
| `ShotTrainingScoreboardView.swift` | 457 |

> 其中 `RallyScoreboardView` 覆盖面最大（wrb 是 Rally 家族的可选主题）。本轮未一并改动的原因：一是超出报告圈定范围，二是当前环境无法编译验证，批量改动缺少回归兜底。**建议先按本提交建立可编译基线，再一次性把 `black 0.25` 收口成 `palette.chrome`。**

### 验证状态

- ✅ 16 个改动文件全部 `swiftc -parse` 通过（0 语法错误）
- ✅ 旧色值残留自检：`E5E7EB` 仅剩注释；`FEF3C7`/`B45309` 仅剩 Theme token 定义（`HomeUtils` 的 `#B45309` 为象棋渐变，无关）
- ✅ `BentoCardView` 两处调用均显式传 `gradientColors`，取消默认值无破坏
- 🔴 **未完成编译验证**：当前会话环境禁止应用限制型 sandbox profile（仅 `(allow default)` 可应用），导致 Swift 宏插件服务器 `swift-plugin-server` 始终返回 malformed response，任何含 `@State`/`@Observable` 的文件都编不过（报错文件包含未触碰的 `PreferencesManager.swift`、`CustomDialogs.swift`，可判定为环境问题而非改动引入）。需在 Xcode 或常规终端环境复验。
