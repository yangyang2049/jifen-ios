# iOS TODO 二次确认报告与实施方案

> 复核日期：2026-08-31 ｜ 复核方式：全仓代码逐条验证（非引用历史报告结论）
>
> 结论速览：**11 项待办中，5 项已不成立或已完成（可关闭/归档），1 项描述过时（已实现未接入），1 项与代码矛盾且构成上架合规风险（新增 P0），其余 4 项维持但需修正描述。**

## 一、复核结论总览

| # | 条目 | 原 TODO 记载 | 复核结论 | 证据 |
|---|------|-------------|---------|------|
| 1 | 扫码登录（P0） | 「当前完全没有」 | ❌ **描述过时：已完整实现，但全仓零引用（死代码），仅差入口接入** | `jifen/Features/Account/QRLoginApprovalView.swift`（payload 解析/校验、`/scan`、`/confirm approve\|deny`、DataScanner 相机扫码、手动粘贴兜底）；`Info.plist:24` 已有 `NSCameraUsageDescription` |
| 2 | 会员兑换码与赠卡（P1·不做） | 「零命中」「iOS 不做」 | 🔴 **与代码矛盾：兑换码+礼品卡 UI 与 API 调用已存在，违反既定「不做」决策，构成 App Store 3.1.1 上架风险** | `MembershipView.swift:57-90`（兑换码/礼品卡/我的好友赠卡 Section）；`StoreKitPurchaseManager.swift:142-183`（`/api/vip/redeem-code`、`/api/vip/gift-cards/redeem`） |
| 3 | 记录云同步（P0） | 三端未实现、等后端 | ✅ 维持 | 全仓无记录同步 API 调用 |
| 4 | 篮球日志双时间（P1） | 需补比赛时间+真实时间 | ✅ **部分成立**：`DetailedScoreAction` 已有 `epochMilliseconds`（真实时间）+ `periodNumber`（节次），**缺小节内比赛时间字段** | `BasketballSessionStore.swift:337-375`（落库未写入 `gameTimeSeconds`）；状态字段见 `JifenCore/.../BasketballMatch.swift:73-80` |
| 5 | 记录结果纠错（P1） | 名称笔记已有、改比分未做 | ✅ 维持 | `ScoreboardRecordDetailPage.swift` 无 `editScore/correctScore` 类实现 |
| 6 | 反馈与合规（P1） | 反馈闭环、账号删除「对齐鸿蒙」 | ⚠️ **需改写：反馈模块与账号删除均已存在**，剩余是「对齐差异核验」而非从零实现 | `FeedbackAPI.swift:16-91`（列表/创建/评论/图片/操作/举报全套）；`AccountViews.swift:175`、`SessionStore.swift:172`（删除账号） |
| 7 | 跨端一致性审计（P1） | 未做 | ✅ 维持 | 无 iOS 对照差异表 |
| 8 | 跨端续打胜者失真（P1·留作未来） | shengji 仅读 blob 无回退 | ✅ 维持（记载准确） | `ScoreboardRecord.swift:479-487`（shengji 分支无 extraData 回退；guandan 回退已在 :473-478） |
| 9 | 崩溃风险清理（P1） | `endTime`/`playerCount`/`timerSubscription`/`displayTimer` 强解包 | ✅ **不成立，可关闭** | 全仓对这些符号的 `!` 强解包零命中 |
| 10 | 本地化硬编码（P1） | BoxingScoreboardView / ScoreboardRecordDetailPage | ✅ **不成立，可关闭** | `BoxingScoreboardView.swift:333,342,349` 中文均在 `NSLocalizedString` value 参数内（正确用法）；DetailPage 的 Text/Label/Button 无未本地化中文 |
| 11 | P2 五项 | 见分项 | 3 项已完成可归档，1 项部分完成，1 项维持 | 见下文 |

---

## 二、实施方案（简单在前，复杂在后）

### 第 1 批：直接关闭/归档（零改动）

#### 1.1 崩溃风险清理 —— 关闭
- `record.endTime`、`playerCount`、`timerSubscription`、`displayTimer` 强解包在全仓 grep 零命中，历史上已被修复。
- **动作**：TODO.md 中该条压一行进「归档」，注明「2026-08-31 全仓复核强解包零命中」。

#### 1.2 本地化硬编码 —— 关闭
- 两个目标文件中所有中文字面量均已是 `NSLocalizedString(key, value:)` 形式，符合本地化规范。
- **动作**：归档，注明证据 `BoxingScoreboardView.swift:333-349`、`ScoreboardRecordDetailPage.swift:48-57`。

#### 1.3 P2：Sheet dragIndicator —— 已完成
- `QuickStartEditView.swift:166-168`、`SettingsView.swift:90-94` 均已加 `.presentationDragIndicator(.visible)`。
- **动作**：归档。

#### 1.4 P2：refreshRecords 后台线程 —— 已完成
- `ScoreboardRecordsViewModel.swift:78-110`：加载已在 `DispatchQueue.global(qos: .userInitiated)` 执行，主线程仅收 UI 更新。
- **动作**：归档。

#### 1.5 P2：Watch「返回/退出」文案 —— 已完成
- Watch 端无「返回」字样，统一使用「退出」（`watch_exit` / `exit`，`WatchScoreboardComponents.swift:489`、`WatchBasketballTrainingView.swift:385`、`zh-Hans.lproj/Localizable.strings:87-88`）。
- **动作**：归档。

### 第 2 批：小改动（局部代码，1-2 个文件）

#### 2.1 P2：列表 loading 与空状态 —— 部分完成，补齐活动列表
- **现状**：记录列表已有 loading+空状态（`RecordsTab.swift:310-315, 679-689`）；预约列表已有空状态（`SchedulePage.swift:18-21`，本地数据源无需 loading）。
- **方案**：仅核活动列表（若为网络数据源，补 `isLoading && items.isEmpty` 时 `ProgressView`、`!isLoading && items.isEmpty` 时空状态文案），模式照抄 RecordsTab。
- **验收**：弱网/空数据下三个列表均有反馈，无白屏。

#### 2.2 篮球日志补小节内比赛时间字段
- **现状**：`BasketballSessionStore.swift:337-375` 落库 `DetailedScoreAction` 时写 `epochMilliseconds`（真实时间）与 `periodNumber`，但 `gameTimeSeconds`（小节内比赛钟）未写入。
- **方案**：
  1. 在 `DetailedScoreAction`（`JifenCore`）增加可选字段 `gameClockSeconds: Int?`（命名以安卓/鸿蒙落库字段为准，动手前先取安卓侧实际字段名对齐，避免三端分叉）；
  2. `BasketballSessionStore` 构造动作处传入 `state.gameTimeSeconds`；
  3. 旧记录解码兼容：可选字段自然兼容，无需迁移。
- **验收**：新打一场篮球，检查记录 JSON 中每个动作同时含节次、比赛钟秒数、真实时间戳；旧记录可正常打开。

### 第 3 批：中等改动（需接线/决策确认）

#### 3.1 扫码登录接入入口（原 P0 第一条的真实剩余工作）
- **现状修正**：实现已 100% 存在（含相机权限声明），只是 `QRLoginApprovalView` 全仓零引用，用户不可达。
- **方案**：
  1. 在「我的」页（`MeTab` 对应结构）设置区添加入口：已登录时显示「扫码登录网页版」（`NavigationLink { QRLoginApprovalView() }`），未登录隐藏；
  2. 入口图标建议 `qrcode.viewfinder`，与鸿蒙/安卓入口位置对齐（对照安卓 MeTabScreen）；
  3. 若设备不支持 DataScanner（`DataScannerViewController.isSupported == false`），入口仍可进（视图内部已自带手动粘贴兜底）；
  4. 实机验证扫码 → 确认登录 → 网页端登录成功的完整链路（接口实测）。
- **TODO.md 修改**：该条改写为「扫码登录已实现（`QRLoginApprovalView.swift`），剩余：我的页入口接入 + 实机链路验证」。
- **验收**：真机扫 `jifenqi.com/auth/qr#sid=...&st=...` 二维码 → 显示设备名 → 点「确认登录」→ 网页端登录成功；点「拒绝」→ 网页端提示拒绝。

#### 3.2 反馈与合规 —— 改写为差异核验
- **现状修正**：反馈闭环（创建/评论/图片/举报/操作全套 API + 视图）与账号删除均已存在。
- **方案**：
  1. 对照鸿蒙端逐项核对：反馈入口位置、图片上传限制、账号删除的确认流程文案与冷静期提示是否一致；
  2. 核对隐私政策文案与 Data Safety 声明是否覆盖相机（扫码登录用）；
  3. 差异项列清单后逐条补齐，预计为文案级小改。
- **TODO.md 修改**：该条改写为「反馈/账号删除已实现，剩余：与鸿蒙逐项差异核验 + 隐私文案覆盖相机权限」。

#### 3.3 🔴 兑换码与礼品卡合规风险处置（本轮最重要新发现）
- **现状**：TODO 决策为「iOS 不做」（App Store Guideline 3.1.1：外部兑换码解锁会员权益违反 IAP 规则），但代码中兑换码/礼品卡完整 UI 与 `/api/vip/redeem-code`、`/api/vip/gift-cards/redeem` 调用均已存在。**若以此状态提审，有被拒风险。**
- **方案（按既定决策执行删除）**：
  1. `MembershipView.swift`：删除「兑换码」「礼品卡」「我的好友赠卡」三个 Section（:57-90），保留 IAP 商品列表、协议 Toggle、恢复购买；
  2. `StoreKitPurchaseManager.swift`：删除 `redeemCode`(:142)、`redeemGiftCard`(:159)、`loadGiftCards` 及 `giftCards`/`giftCardEligible` 状态(:37-38, :179-183)；
  3. 服务端赠送权益不受影响（后端直发，客户端无入口即合规）；
  4. 检查 `VipGiftCard` 等类型引用，一并清理。
- **TODO.md 修改**：该条改为「⚠️ 2026-08-31 复核发现代码已实现兑换码/礼品卡，与『不做』决策矛盾；已按决策移除客户端入口（证据：文件:行）」。
- **验收**：会员页仅剩 IAP 方案 + 恢复购买；全仓 `redeem` / `giftCard` 在 `jifen/` 源码目录零命中（文档除外）；编译通过。

### 第 4 批：大改动（架构级，保持等待/分批）

#### 4.1 记录结果纠错（改最终比分与重算）
- **方案**：
  1. 详情页增加「纠错」入口（仅 `status == .finished` 记录显示）；
  2. 弹窗改最终比分/积分，提交后本地重写记录的比分字段并标记 `corrected: true`（revision 语义与云同步同批定，先本地字段预留）；
  3. 重算胜负：改分后重走 `resolvedWinnerIdentity` 的比分回退路径刷新胜者展示；
  4. 涉及 blob 的记录：不改 `stateSnapshot`（blob 保持原样，纠错只覆盖展示层字段），避免破坏续打一致性。
- **验收**：改分后列表/详情/分享图比分与胜者一致；续打不受影响。

#### 4.2 跨端续打 / 胜者失真（shengji 回退）
- **维持留作未来**：确认 `ScoreboardRecord.swift:479-487` shengji 仅读 blob。触发前提是记录云同步落地，当前用户无「iOS 读安卓记录」路径，维持不立项。
- **届时方案**（与云同步同批）：仿照 guandan 的 `guandanFinalWinner` 回退（:473-478），shengji 在安卓侧摊平 `shengjiFinalWinner`（"left"/"right"）进 extraData，iOS `case .shengji` 增加 extraData 回退分支；同时给 `isReliableForResume` 闸门增加「无 blob 且非本端记录则不显示继续比赛按钮」的保护。

#### 4.3 iOS 跨端一致性对照审计
- **方案**：按安卓 `docs/2026-08-28-cross-platform-diff/` 同一方法四线对照（计分板容器 / 规则与设置 / 记录列表 / 记录详情与分享），产出同格式差异表并入主表。建议在兑换码清理与扫码入口完成后执行，避免审计对象包含即将删除的代码。

#### 4.4 比赛记录多端云同步
- **维持等后端**：记录同步 API 不存在，iOS 无前置工作可做。API 落地后须同批处理：字段名与覆盖规则三端共用、扁平 extraData 键规范（BUG-1）、blob↔flattened 续打闸门（见 4.2）。

---

## 三、TODO.md 修改清单（直接可执行）

1. **P0 扫码登录条目改写**：删除「当前完全没有」段落，改为「已实现（`QRLoginApprovalView.swift`，含 /scan 与 /confirm 状态流、相机权限），剩余：我的页入口接入 + 实机链路验证」。
2. **P1 兑换码条目改写**：由「零命中·不做」改为「⚠️ 代码已实现与决策矛盾，须移除 `MembershipView.swift:57-90` 与 `StoreKitPurchaseManager.swift:142-183` 客户端兑换入口（3.1.1 合规）」。
3. **P1 崩溃风险条目**：移入归档（零命中证据）。
4. **P1 本地化硬编码条目**：移入归档（均已 NSLocalizedString 包裹）。
5. **P1 反馈与合规条目改写**：注明反馈闭环与账号删除已实现，剩余为鸿蒙差异核验与隐私文案。
6. **P2 三条移入归档**：dragIndicator、refreshRecords 后台线程、Watch 文案统一。
7. **P2 loading 条目改写**：仅剩活动列表待补（记录/预约已完成）。
8. **P1 篮球日志条目细化**：明确「已有时钟基础设施（`BasketballSessionStore.swift:280-324` anchor 机制），剩余仅在 `DetailedScoreAction` 增加 `gameClockSeconds` 字段并落库，字段名先对齐安卓」。

## 四、建议执行顺序

```
第 1 批归档（零风险） → 3.3 兑换码合规清理（上架阻塞项，优先） → 3.1 扫码入口接入
→ 2.2 篮球日志字段 → 2.1 活动列表空状态 → 3.2 反馈差异核验 → 4.1 记录纠错
→ 4.3 跨端审计 → 4.2 / 4.4 等后端与云同步同批
```
