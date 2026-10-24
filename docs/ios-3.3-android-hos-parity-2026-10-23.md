# iOS 3.3 提版：安卓 / 鸿蒙近两日小改动可抄性核对

日期：2026-10-23。范围：`jifen-android`（分支 `3.3`，含未提交工作区 149 个文件）与
`jifen-hos`（分支 `3.4`，`6c64024a7` + `adf40b2d8` 两个提交），逐项对照 `jifen-ios` 当前工作区。

结论先说：**真正值得抄的只有批次 A 两处**；批次 B 按产品决定不做，批次 C 三项经实测**全部不需要做**
（C1 缺整条计数链路、C2 iOS 已天然严格、C3 队列语义不同不能照搬）。
另有一个必须先解决的前置问题——微信绑定所依赖的服务端接口目前不存在。

> **执行状态（2026-10-23 晚）**：A1、A2 已实现并编译通过；B 不做；C1/C2/C3 均不做，理由见批次 C。

---

## 一、已落地的改动

### 批次 A｜纯配色 / 纯 token，零逻辑风险 ✅ 已实现

| # | 改动 | 来源 | iOS 落点 | 现状差异 |
| --- | --- | --- | --- | --- |
| A1 | 实心红底操作统一白字 | 鸿蒙 `adf40b2d8`（`ui/actionColor.ts`）；安卓 `ui/theme/ActionForeground.kt` + `AppActionColors` | `jifen/Core/Theme/Theme.swift` `actionForeground(on:UIColor,appearance:)` | **原为黑字**。`#FF3B30` 亮度对比：黑 5.92 : 白 3.55，原算法必然选黑 |
| A2 | 小组多行说明文案行高 | 鸿蒙 `GroupLineHeight = {caption:18, body:22, bodyLarge:24}`；安卓 `GroupTypography.captionLineHeight` | `jifen/Features/Groups/GroupFormComponents.swift` `GroupTypography.LineHeight` | 原只有字号 token，没有行高 token |

**A1 实际实现**（照抄安卓判据，不照抄数值）：

```swift
// Theme.swift
if appearance == .light && green > red && green > blue { return .white }
// 实心红底在深浅模式都用白字；浅红提示底与橙黄警告仍走对比度计算
if isSolidRedAction(red: red, green: green, blue: blue) { return .white }
```

`isSolidRedAction` 与安卓 `hsv.s >= 0.4 && (hsv.h <= 15 || hsv.h >= 345)` 同口径：高饱和 + 红区色相。
没有复用 `ScoreboardStyleColorMath.colorToHsv`，因为它吃的是 hex 字符串，而这里拿到的是已解析的 RGB 分量；
在 `Theme` 内直接算 HSV 可以避免一次不必要的字符串往返。

判据实测结果（`swift` 直接跑）：

| 期望白字 | 期望黑字（不受影响） |
| --- | --- |
| `FF3B30` `EF4444` `FF6B6B` `E5484D` `FF5252` `D32F2F` `B42318` `F44336` | `FF9800` `F59E0B` `FFD600` `FFC107` `F97316` `FFE0E0` `4CAF50` `30D158` `007AFF` |

随之变白字的调用点（6 处，均为红底实心按钮）：
`CustomDialogs.swift:236`（确认弹窗默认 `#FF3B30`）、`DualPlayerTimerView.swift:550`（退出）、
`TableTennisCardsDialog.swift:113`（确认判负）、`AccountViews.swift:929`（注销账号）、
`TenSecondChallengeView.swift:107`、`FullscreenBarrageView.swift:419`（红色色板上的文字）。

不改的：`GroupSupportViews.swift:712`（已显式 `textOnPrimary`）、`GroupAlignedActionStyle`（破坏性操作用浅底红字，不是红底）。

**A2 实际实现**：新增 `GroupTypography.LineHeight`（caption 18 / body 22 / bodyLarge 24），
并加 `.groupLineHeight(.caption|.body)` 修饰器。因为 SwiftUI 的 `lineSpacing` 是**额外**行距，
内部按目标行高减去字体自带行高换算（12pt 系统字体约 14.13pt，14pt 约 16.49pt），避免写死近似值。
已应用到 `GroupNotice`、`GroupNoticeEmptyState`、`GroupEmptyCard` 三处会换行的说明文案；
单行标签不动，避免无谓布局变化。

### 批次 B｜小组选中态对比度 — 按产品决定**不做**

原清单建议改 `GroupRegistrationEditor` 的选中态（浅绿底+深字 → 实底绿+白字）。
iOS 现状「浅底 + 深字」本身可读，这是设计口径统一而非缺陷修复，本版跳过。

### 批次 C｜小交互补齐（**已逐项核实，结论：全部不做**）

| # | 改动 | 来源 | 核实结论 |
| --- | --- | --- | --- |
| C1 | 常用名称显示使用次数 `×N` | 鸿蒙 `SavedNamesPage.ets` | **不做**。见下 |
| C2 | `Retry-After` 严格解析 | 安卓 `ApiRetryPolicy.kt` | **不需要**。iOS 已天然严格，见下 |
| C3 | WS 队列 flush 失败即停 | 安卓 `MatchWebSocketManager.kt` | **不做**。iOS 队列语义不同，见下 |

#### C1：不是「加一行 Text」，而是缺整条计数链路

原判断「`useCount` 字段已有，只需加一行 Text」是**错的**。实测：

- `CommonDataCloudSyncManager.noteNameUsed(_:type:)` / `notePlaceUsed(_:)` 是全仓库**唯一**会递增 `useCount` 的地方，
  而这两个方法**没有任何调用点**（`grep -rn "noteNameUsed\|notePlaceUsed" jifen` 只命中定义本身）。
- 服务端 `commonDataSync.ts` 对 `useCount` 只做 `Math.max(existing, incoming)` 合并，**没有独立递增接口**；
  数值完全由客户端上报。客户端不递增 → 这个值永远是 0。
- 安卓端有完整链路：`recordUsage` 在 `EditCommonNamePicker` / `CardGameSetupDialog` / `SportsSetupScreen` /
  `CreateBookingViewModel` 共 5 处被调用。**但安卓列表页 `CommonNameCard` 本身不显示次数**（`CommonNamesScreen.kt:458-528` 无 `useCount` 引用）。
- 只有鸿蒙 `SavedNamesPage.ets` 显示，且它的 `CommonName` 结构体自带 `useCount` 字段。

结论：要显示次数，得先补「选中常用名称 → 记录使用 → 同步」这条链路（安卓 5 个入口 + iOS 对应位置），
再改 UI。这不是小改动，而且**只有鸿蒙一端在显示**，不构成跨端一致性问题。建议放到 3.4 随常用数据一起做。

#### C2：iOS 的 DateFormatter 本来就拒绝尾随字符

安卓要加 `isLenient=false` + `position.index != raw.length`，是因为 `SimpleDateFormat` 默认宽松。
iOS 不存在这个前提，实测（`swift` 直接跑 `APIClient.swift` 里同一个 formatter 配置）：

```
"Wed, 21 Oct 2026 07:28:00 GMT"        -> 2026-10-21 07:28:00   ✅
"Wed, 21 Oct 2026 07:28:00 GMT junk"   -> nil                   ✅ 已拒绝
"Wed, 21 Oct 2026 07:28:00 GMT extra"  -> nil                   ✅ 已拒绝
"Wed, 21 Oct 2026 07:28:00 GMTX"       -> nil                   ✅ 已拒绝
```

`DateFormatter.date(from:)` 要求整串匹配，尾随字符直接返回 nil。现有 `NetworkResilienceTests` 已覆盖
`nil / "" / "not-a-date" / "NaN" / "inf" / "1e999"`。**无需改动。**

#### C3：iOS 的离线队列语义与安卓不同，改法不能照搬

安卓改的是「flush 时一次失败就停止，剩余整批保留」，因为它的 `sendEnvelope` 会**递归入队**，
逐个重发失败项会让顺序错乱。

iOS 不存在这个结构：`MatchWebSocketManager.flushQueue()` 先整体 `removeAll` 再逐个 `sendEnvelope`，
而失败是在**异步 completion** 里回调 `enqueuePending`。也就是说：

- 真正的顺序保护已经由 `WsOfflineQueuePolicy` 完成——`.appendOrdered` 类事件（控制权交接、开始比赛）
  按发生顺序补发，`.replaceSnapshot`（比分快照）只留最新一帧，`.dedupeSameType`（结束/离开）留最后一条。
- 快照类事件**本来就应该**被新帧覆盖，不需要保序；真正需要保序的事件在队列里已经是 append 顺序。

若照搬安卓的「失败即停」，反而会让快照类事件在弱网下卡住整条队列。**收益不明确，不做。**

> 补充：这一条我在第一版清单里判断得过快，把「两端同名类」当成了「同构逻辑」。实际是两套不同的队列设计，
> 不能因为方法名像就照抄。

---

## 二、已经对齐、不需要抄（避免重复劳动）

两端这两天做的这些，iOS 早就有了，且实现口径一致：

| 安卓 / 鸿蒙改动 | iOS 对应实现 | 位置 |
| --- | --- | --- |
| `SetupInputCorrection` 静默夹取，取消红字报错 | 已完整移植（含 `oddSetsCorrectionApplied` 与开赛 toast） | `SportsSetupDraft.swift:575`、`SportsSetupDialogView.swift:212` |
| 移除「已移出成员」折叠开关，默认展开 | iOS 一直是常展开 | `GroupDetailView.swift:723,804` |
| 拒绝入组申请去掉二次确认 | iOS 一直直接执行 | `GroupDetailView.swift:701` |
| 取消活动原因改为可选（`cancel_reason_optional`） | iOS 已是可选 | `GroupActivityViews.swift:247`、`GroupActivityPolicy.swift:9` |
| 报名截止跟随开始时间（分钟精度） | iOS 用 `Calendar` 比较到 `.minute` | `GroupActivityPolicy.swift:20` |
| 小组资料「最后保存生效」，只提交改动字段 | iOS `GroupProfileFields.changes(from:)` | `GroupManagementView.swift:8` |
| 举报图片证据（最多 3 张、2MB、JPG/PNG） | iOS 已实现同等能力 | `GroupEvidenceReportSheet.swift` |
| 举报错误码映射（`REPORT_VERSION_CONFLICT` / `IMAGE_*` / `NOT_FOUND`） | iOS 映射表已含全部同码 | `GroupErrorMessage.swift:8-30` |
| VIP 页矮屏隐藏 hero logo + 购买栏顶部渐变 | iOS `showLogo: viewport.height >= 700` + 28pt 渐变 | `MembershipView.swift:46,670` |
| 帮助问号图标改次要灰 | iOS 一直 `Theme.textSecondary` | `CustomDialogs.swift:40` |
| 微信登录入口跟随中文（不看地区） | iOS `WechatLoginPolicy.supports(language:)` | `WechatAuthProvider.swift:10` |
| 401 刷新与会话 revision 绑定 | iOS 已按 revision 隔离 | `APIClient.swift:252,319` |
| 浅色主题绿底白字（`AppActionColors.lightPrimaryForeground`） | iOS `actionForeground` 的 green>red 分支 | `Theme.swift:146` |

## 三、平台专属，iOS 不适用

- 投屏发现退避重建（`castDisplayManager.ts` / `castDiscoveryProbe.ts`）——AVSession 服务重启自愈，iOS 无对应 API。
- 应用推荐本地缓存与原子发布（`appRecommendationCache.ets`）——iOS 无该模块。
- 手表联动增量日志 / 分包 / ACK（`linkedStateJournal.ts`、`wearEngineLink.ts`）——iOS 无 watchOS target。
- 倒计时 / 秒表 DTO 的 `@SerializedName`（安卓 R8 混淆问题）、`AndroidManifest` 权限与启动恢复——平台构建差异。
- 小组举报证据的 `ImageSource/PixelMap` 释放、`photoAccessHelper` 选图——鸿蒙图像栈特有。
- 商店上传脚本（`store_api.py`）、各渠道隐私整改——发布流程差异。

---

## 四、微信绑定：功能本身的前置阻塞（必须先决策）

核对结论：**服务端目前没有绑定接口**。`api-server/src/routes/auth.ts` 的 auth 路由全集为
`register/email`、`login/email`、`login/harmony`、`login/wechat`、`login/wechat-miniprogram`、
`login/huawei`、`login/huawei-android`、`upload-avatar`、`logout`、`refresh`、
`profile/platform-sync`、`profile`（GET/PUT/PATCH）、`me`——**没有 `POST /api/auth/bind/wechat`**。

同时 `/api/auth/me` 的返回体（`profileUserPayload`）里没有 `loginProvider`，也没有 `identities` /
`boundProviders`；`realNameProvider` 只在登录建号时写入 `User` 表，且 `me` 的 `select` 里
`realNameProvider: true` 拿到了但 `profileUserPayload` 没有透出。**客户端现在无法判断「当前账号是不是微信登录」，
也无法判断「是否已绑微信」**。

因此绑定功能需要三步，缺一不可：

1. **服务端**：新增 `POST /api/auth/bind/wechat`（需 auth），用现有 `exchangeWeChatOAuthToken` 换 unionid，
   校验 `identity(provider="wechat", providerId=unionid)` 是否已属于别的 user；已属于他人 → `409 wechat_already_bound`，
   已属于自己 → 幂等成功，否则在该 user 下插入 identity。**响应不得签发新 token**（否则会把当前登录顶掉）。
2. **服务端**：`/api/auth/me` 增加 `loginProvider`（取该 user 最早的 identity provider，或登录时记录的主 provider）
   与 `boundProviders: ["apple","wechat"]`。客户端据此决定是否显示入口。
3. **客户端**：`AppUser` 增加两个字段（`decodeIfPresent`，老服务端不返回时为 nil → 一律不显示入口，安全降级）。

在这三步落地前，iOS 端能做的只有登录页的微信登录（已完成）与 Demo 确认。**提审版本若只上微信登录、不上绑定，
是安全的**；绑定功能不要半上线，否则用户点了没反应比没有入口更糟。

> 补充：`WechatLoginPolicy.supports` 目前只放行中文界面。若绑定入口也沿用这一条，则非中文用户的 Apple 账号
> 永远无法绑定——这与「各端都能用微信登录」的目标冲突。建议绑定入口**不限语言**（微信本来就在各端可用），
> 只保留「未安装微信则不显示」。

---

## 五、执行顺序（已按 2026-10-23 决定更新）

1. ✅ 批次 A1（红底白字）+ A2（行高 token）——已实现，主 target 编译通过，新增单测见
   `jifenTests/ActionForegroundTests.swift`。
2. ⏭ 微信登录收尾：确认 `Info.plist` 的 URL Scheme / Universal Link 与开放平台一致，真机走通一次授权回调。
3. ⏸ 绑定功能：**先确认服务端三步的排期**。若今天给不出接口，本版只上微信登录，绑定入口整块不渲染。
4. ❌ 批次 B、C 全部不做（B 按产品决定；C 三项经实测均无必要）。

## 六、本批改动的验证边界

**已完成**

- `xcodebuild build`（iPhone 17 Pro 模拟器，Debug）通过。
- `jifenTests/ActionForegroundTests` 6 项全部通过：红底白字（浅/深）、橙黄与浅红不受影响、浅色绿底白字、
  中性色与蓝色对比度、`isSolidRedAction` 判据、行高换算非负。
- 红/黄判据另用独立 `swift` 脚本逐个色值跑过（白字 8 个 / 黑字 9 个），与单测互相印证。
- **模拟器实机截图确认**：注销账号页的实心红底按钮已由黑字变为白字（浅色模式），深色模式确认外观切换生效
  （`jifen-v2.appAppearanceMode=dark`）。
- 过程中发现并修正了测试自身的一处错误期望：`007AFF` 的黑字对比 5.23 > 白字 4.02，本来就该是黑字，
  第一版期望写成了白字。已改为黑字并加注释说明原因。

**未完成（提审前需补）**

- 小组页行高改动的视觉回归：`.groupLineHeight` 会影响 `GroupNotice` / `GroupNoticeEmptyState` /
  `GroupEmptyCard` 三处的列表密度，需要在长文案（中文 + 德语等长语言）下目视确认没有挤压或截断。
- 真机走查：模拟器截图不能替代真机，尤其红底按钮在户外亮度下的观感。
- 其余 4 个红底调用点（确认弹窗、退出计时、确认判负、十秒挑战、弹幕色板）未逐一截图，
  但它们的取值路径与已截图的一致，且单测已覆盖对应色值。

**未做**

- `jifenUITests` 全量回归：本次未改交互路径，只改颜色与行距。用于截图的临时探针测试已删除，
  `project.pbxproj` 已恢复到不含该文件的状态（`plutil -lint` 通过）。

**过程中清理的东西**

- 临时 UI 探针 `jifenUITests/RedActionContrastProbeUITests.swift` 已删除，工程文件中 4 处引用一并移除。
- 模拟器外观已复位为 light。
