# jifen_ios 项目 Bug 与优化点报告

按模块梳理后，再拉通「手机 / 手表」与「跨模块」视角，给出可落地的结论与建议。

---

## 一、模块划分与职责

| 模块 | 关键文件 | 职责简述 |
|------|----------|----------|
| **首页 (Home)** | HomeTab, NewGameDialogView, SportsSetupDialogView, QuickStartEditView, SettingsView, BentoCardView, ProToolsSectionView, QuickStartGridView | 快捷入口、新比赛/设置弹窗、快速开始编辑、设置、工具区、最近记录入口 |
| **计分 (Scoreboard)** | ScoreboardTab, ScoreboardTemplate, 各 *ScoreboardView/*Controller, MultiScoreboardView, SimpleScoreboardView, RecordsTab, ScoreboardRecordDetailPage, ScoreboardRecordManager | 计分入口、通用模板、各项目计分、记录列表/详情、记录存储 |
| **计时 (Timer)** | TimerTab, DualPlayerTimerView, DualTimerSetupView, CountUpTimerView, StopwatchView, BasketballCountdownView, TimeoutCountdownView, CubeTimerView | 计时入口、双人/正计时/秒表/篮球/超时/魔方 |
| **预约 (Schedule)** | SchedulePage, CreateBookingPage, BookingDetailPage, LocalBookingManager, BookingNotificationManager | 我的球局列表、创建/详情、本地存储与提醒 |
| **工具 (Tools)** | ToolsTab, FlipCoinView, DiceToolView, WhistleToolView, TenSecondChallengeView 等 | 抛硬币、骰子、哨子、十秒挑战等 |
| **活动/记录 (Activity)** | RecentActivityPage, TimerRecordDetailPage | 最近活动、计时记录详情 |
| **Watch App** | WatchRootView, WatchTabView, WatchHomeTabView, Watch*ScoreView, WatchTimer*, WatchToolsTabView, WatchRecordListView, WatchSettingsView, WatchTheme, WatchRecordManager | 表盘首页/计分/计时/工具/记录/设置 |

---

## 二、手机端 (iOS) 问题与优化

### 2.1 潜在 Bug / 风险

1. **Force unwrap 可能崩溃**
   - `ScoreboardRecordDetailPage`：`record.endTime!`，建议改为 `if let`。
   - `MultiScoreboardView`：`setup.playerCount!`，在玩家数合法范围内使用，建议用 `guard let count = setup.playerCount, (3...9).contains(count)`。
   - `TimeoutCountdownView` / `BasketballCountdownView`：`timerSubscription!` 在 `startTimer()` 内 add 到 RunLoop，若后续逻辑改动可能为 nil，建议 `guard let t = timerSubscription else { return }` 再 add。
   - `CountUpTimerView` / `StopwatchView`：`displayTimer!` 同理，建议 guard 后再 `RunLoop.current.add(...)`。

2. **Timer 未在 onDisappear 清理**
   - **FlipCoinView**：`Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true)` 用于翻转动画，仅在 `progress >= 1.0` 时在闭包内 invalidate；若用户在翻转过程中离开页面，Timer 不会停止，会继续更新 `@State`，可能导致异常或多余计算。建议保存 timer 引用并在 `onDisappear` 中 `timer?.invalidate()`。

3. **dismiss 后回调时机**
   - **NewGameDialogView**：先 `dismiss()`，再 `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` 调用 `onSelect?` / `onTimerGameSelected?`。若 presenting 的 VC 已释放或状态已变，仍会执行回调，存在状态不一致或访问已释放对象的风险。建议：在回调内判断调用方是否仍需该结果，或改为通过 Combine/Notification 在 dismiss 完成后再发事件。
   - **ScoreboardRecordDetailPage**：分享完成回调中直接调 `onDismiss?()`，若页面已 dismiss 可能重复或不符合预期，建议根据「是否仍需通知」做一次判断后再调。

4. **主线程与重活**
   - **ScoreboardRecordsViewModel.refreshRecords()**：在 `DispatchQueue.main.async` 内调用，若内部有较重 IO 或计算会阻塞主线程。建议：在后台队列做加载/解析，仅在更新 `@Published` 或 UI 状态时切回 main。

### 2.2 一致性与体验

5. **Sheet 呈现方式不统一**
   - 多数 sheet：`.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`。
   - **QuickStartEditView**：仅 `.presentationDetents([.large])`，无 drag indicator。
   - **SettingsView** 内部分 sheet（如常用名称）：仅 `.presentationDetents([.large])`，无 drag indicator。  
   建议：需要与「新比赛」等一致体验的 sheet 统一加上 `.presentationDragIndicator(.visible)`。

6. **硬编码文案未本地化**
   - **ScoreboardRecordDetailPage**：`getScoringActionText` 中 `"\(teamName) 得分"`、`"\(teamName) 进球"`、`"\(teamName) +\(points)"` 等为中文硬编码，应改为 `NSLocalizedString` 或已有 key。
   - **BoxingScoreboardView**：`Text("第 \(viewModel.currentRound) 回合")` 建议使用本地化格式串。

7. **主题与裸值**
   - 大量已用 `Theme.xxx`，但仍有裸值：如 `ScoreboardRecordDetailPage` 的 `.padding(24)`、`Color.black.opacity(0.4)`；`SchedulePage` 的 `.padding(32)`、`Color.black`；`WhistleToolView`、`DiceToolView` 等中的 padding/opacity。建议逐步替换为 Theme 中的语义常量，便于后续换肤与统一。

8. **列表与加载状态**
   - **RecordsTab**：使用 `ScrollView` + 遍历，非 `List`；若记录量很大，可考虑 `List` 或分页以利懒加载与复用。
   - 记录/预约/活动等列表未看到统一的「加载中」骨架或 `ProgressView`，若数据来自慢存储或网络，建议增加 loading 状态。

### 2.3 文档与维护

9. **CHANGELOG 条目重复**
   - `CHANGELOG.md` 中「新比赛对话框计分/计时双 Tab」与「新比赛用 dialog 呈现」两条合并成一段，且有一条 bullet 内容为空（仅标题）。建议拆成两条独立条目，避免混淆。

---

## 三、手表端 (watchOS) 问题与优化

### 3.1 潜在 Bug / 风险

1. **“退出应用”行为**
   - **WatchRootView**：`WatchAppExit.exit()` 使用 `WKExtension.shared().rootInterfaceController?.dismiss()`。watchOS 无公开“退出应用” API，此处为尽力而为的 dismiss；若 root 不是 interface controller 或结构变化，可能无效果。建议在文案/交互上明确说明为「返回上一级」而非「完全退出应用」，避免用户期待真正退出。

2. **Timer 与生命周期**
   - Watch 端各计时/动画（WatchTimerDetailView、WatchSetBasedScoreboardView、WatchTenSecondChallengeView、WatchFlipCoinView 等）均在 `onDisappear` 中 invalidate，与 iOS 上 FlipCoinView 未在 onDisappear 清理形成对比；iOS 侧建议对齐。

### 3.2 功能与数据

3. **项目类型差异**
   - iOS：GameCatalog 含足球、排球、拳击、台球、掼蛋、斗地主、多人/简易计分等。
   - Watch：WatchGameType 仅 6 种（乒/羽/网/匹克球/射箭/篮球训练），无棋牌、无多牌/简易计分。属有意精简，但需在产品和文档中说明「手表支持项目」与手机差异。

4. **数据同步**
   - 未发现 WatchConnectivity / WCSession 使用，当前 Watch 与 iPhone 无显式数据同步。若产品需求中有「手机与表数据同步」（如记录、预约），需单独设计与实现。

### 3.3 本地化与一致性

5. **Watch 与 iOS 共用 key**
   - Watch 与 iOS 共用大量 Localizable key（如 `record_not_found`、`menu_undo`、`cancel`、`game_archery` 等）。建议在两边 `.lproj` 中定期核对同一 key 的译文一致，避免同一 key 在手机和表上显示不同。

6. **隐私与退出流程**（已处理：Watch 端已移除独立隐私协议页与 WatchAppExit，启动直接进主界面。）

---

## 四、跨模块拉通

### 4.1 导航与状态

- 首页 → 新比赛 → 设置弹窗 → 计分/计时：依赖 `path`、`pendingScoreboardSetupItem`、`pendingTimerGameType` 等，逻辑集中 in HomeTab / MainTabView。建议：在文档或注释中画一条「新比赛 + 设置 + 跳转」的流程图，便于后续改 Tab 或加入口时保持一致。
- 计分/计时子页返回：已统一为 chevron.left 图标，与 ScoreboardTemplate 一致，无额外问题。

### 4.2 数据与存储

- 计分记录：ScoreboardRecordManager；计时记录：TimerRecordsViewModel / TimerRecordManager；预约：LocalBookingManager；常用名称：CommonNamesManager。各模块边界清晰。建议：若未来做 iCloud 或同步，可抽象一层「存储协议」，便于换实现。
- 预制名称过滤、常用名称不存「红队/蓝队」等已按鸿蒙对齐，无需在本报告中再改。

### 4.3 计分板与模板

- 编辑模式局分 ± 已通过 `applySetsAdjust` 统一派发；发球指示器在编辑模式下隐藏；射箭 contentOverlayProvider 与 isEditMode 已对齐。暂无新增跨模块冲突。
- 若新增计分项目并实现 `adjustSets`，需在 `applySetsAdjust` 中补一行显式 `as?` 调用，避免协议默认实现被误派发（与现有文档一致）。

---

## 五、优先级建议

| 优先级 | 类型 | 项 | 说明 |
|--------|------|----|------|
| P0 | Bug | FlipCoinView Timer 未在 onDisappear 清理 | 用户翻转中离开会继续跑 Timer，建议立即修。 |
| P0 | Bug | NewGameDialogView dismiss 后 asyncAfter 回调 | 可能访问已释放或状态错乱，建议改回调时机或加保护。 |
| P1 | Bug | Force unwrap（record.endTime、playerCount、timerSubscription、displayTimer） | 改为 guard/if let 可降低崩溃风险。 |
| P1 | 体验 | ScoreboardRecordDetailPage / BoxingScoreboardView 硬编码中文 | 本地化后便于多语言与维护。 |
| P2 | 一致 | Sheet 统一加 presentationDragIndicator | QuickStartEditView、SettingsView 内部分 sheet。 |
| P2 | 性能 | ScoreboardRecordsViewModel.refreshRecords 放后台 | 避免主线程卡顿。 |
| P2 | 体验 | 列表 loading/空状态 | 记录/预约/活动等可加 ProgressView 或骨架。 |
| P3 | 文档 | CHANGELOG 拆条与补全 | 新比赛两条拆开、补全空 bullet。 |
| P3 | 优化 | Theme 替换裸值 | 按模块逐步替换 padding/color。 |
| P3 | Watch | 退出文案与隐私策略 | 明确「返回」而非「退出」，并与 iOS 策略一致。 |

---

## 六、总结

- **手机**：最值得先做的是 FlipCoinView 的 Timer 清理、新比赛 dismiss 后回调安全、以及计分/拳击等硬编码文案本地化；其次为 sheet 统一、记录刷新放后台、列表 loading。
- **手表**：逻辑与生命周期相对干净，主要需明确「退出」语义、与 iOS 的隐私/文案一致，以及若要做同步则单独设计 WatchConnectivity。
- **拉通**：模块边界清晰，数据与导航集中在一处；后续新增计分类型或新入口时，注意 applySetsAdjust、新比赛/设置流程和 Theme 的延续即可。

以上结论基于当前代码只读检索与既有 CHANGELOG，具体修改需在开发时逐项落地并补充单测/UI 测试。
