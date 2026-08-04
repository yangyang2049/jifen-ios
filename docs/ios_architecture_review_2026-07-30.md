# iOS 项目架构与文件组织审查报告

> 审查日期：2026-07-30 | 范围：`jifen-ios` 全量

---

## 一、总体评价

**架构骨架是合理的。** `Core` / `Features` 两层分离 + `JifenCore` Swift Package 的 6 模块设计，跟 Android 的 `shared-core` 和鸿蒙的模块化方式是同一个方向。MVVM 模式在计分板模块应用一致。

问题集中在三个层面：
1. **部分文件放错了位置**（目录层级混乱）
2. **大量薄包装器/控制器有相近代码，可以泛化**
3. **个别巨型文件欠拆分、个别微型文件欠合并**

总体改进不算大手术，以局部调整为主。

---

## 二、目录层级总览

```
jifen-ios/
├── jifen/                         # 主工程 (~140 .swift)
│   ├── jifenApp.swift
│   ├── ContentView.swift
│   ├── Core/                      # 基础设施 (26 文件)
│   │   ├── Analytics/             # 友盟
│   │   ├── Components/            # 共享 UI
│   │   ├── Legal/                 # 法律合规逻辑
│   │   ├── Link/                  # Watch ↔ iPhone 联动
│   │   ├── Managers/              # 全局 Manager
│   │   ├─�� Theme/                 # 主题
│   │   ├── AppFeatureFlags.swift  # ⚠️ 裸放
│   │   ├── AppReviewPrompt.swift  # ⚠️ 裸放
│   │   └── Utils.swift            # ⚠️ 裸放
│   ├── Features/                  # 业务模块 (~110 文件)
│   │   ├── MainTabView.swift
│   │   ├── Activity/              # 计时记录历史
│   │   ├── Home/                  # 首页 Tab
│   │   │   └── components/        # ⚠️ 小写命名
│   │   ├── Legal/                 # 首次启动法律页
│   │   ├── Me/                    # 我的 Tab
│   │   ├── Records/               # 记录 Tab
│   │   ├── Schedule/              # 预约
│   │   ├── Scoreboard/            # 计分板核心
│   │   ├── Shared/                # GameCatalog
│   │   ├── Timer/                 # 计时 Tab
│   │   └── Tools/                 # 工具 Tab
│   └── Resources/                 # MP3 37个扁平放 / TTF / 本地化
│
├── jifenWatch Watch App/          # Watch 端 (~47 .swift)
├── Packages/JifenCore/            # 6 模块 Swift Package (~28 .swift)
├── Pods/                          # CocoaPods
├── jifenTests/                    # 单元测试 (11 .swift)
├── jifenUITests/                  # UI 测试 (6 .swift)
├── docs/                          # 文档
└── scripts/                       # 自动化脚本
```

---

## 三、问题清单

### P0 —— 架构级别问题

> 无真正阻塞性问题。以下是应优先处理的。

---

### P1 —— 应处理的结构问题

#### 3.1 Core/ 目录有裸放文件，缺少子目录分类

| 文件 | 建议位置 |
|------|----------|
| `Core/Utils.swift` | → `Core/Utilities/Utils.swift` 或移到已有目录 |
| `Core/AppFeatureFlags.swift` | → `Core/Config/AppFeatureFlags.swift` |
| `Core/AppReviewPrompt.swift` | → `Core/Managers/AppReviewPrompt.swift` |

**理由**：三层目录下，子目录和 .swift 文件平级放置违反分层约定。Android/shared-core 和鸿蒙都不会这样混放。

**改动量**：3 个文件移动 + 更新 import（如果有跨模块引用）。

---

#### 3.2 `Features/Home/components/` 用了小写命名

```
Features/Home/components/    ← 应该改为 Components/
```

所有其他目录都是 PascalCase（`Models/`、`Views/`、`Shared/`），唯独这里用小写。这是 iOS/Swift 社区约定，也是项目自身的一致约定。

**改动量**：1 次重命名 + Xcode project file 更新。

---

#### 3.3 Legal 模块拆在两个地方

```
Core/Legal/LegalConsent.swift        # 同意状态管理逻辑
Features/Legal/FirstLaunchLegalScreen.swift  # 首次启动法律页面
```

逻辑放在 Core、UI 放在 Features 是合理的分层，但两处都叫 "Legal" 容易混淆。建议：

- `Core/Legal/` → 保持不动（或改成 `Core/LegalConsent/`）
- `Features/Legal/` → 移到 `Features/Home/` 或 `Features/Shared/` 下面，因为首次启动页本质是启动流程的一部分，不是独立功能模块。

**改动量**：1 个文件移动。

---

#### 3.4 Controller 类大量薄包装，可以消除

以下 4 个 Controller 类都是 24 行左右，仅 `gameType` 和 `scoringOptions` 不同：

| 文件 | 行数 | 差异 |
|------|------|------|
| `SimpleScoreboardController.swift` | 24 | gameType: .simpleScore |
| `BoxingScoreboardController.swift` | 24 | gameType: .boxing |
| `BilliardsScoreboardController.swift` | 25 | gameType: .billiards |
| `FootballController.swift` | 24 | gameType: .football |

**建议**：删除这 4 个文件，改为在 `BaseScoreboardController` 上加一个静态工厂：

```swift
// BaseScoreboardController.swift
static func forGameType(_ gameType: GameType, scoringOptions: [Int] = []) -> BaseScoreboardController {
    BaseScoreboardController(config: ScoreboardControllerConfig(
        gameType: gameType,
        enableRecording: true,
        enableScreenshot: true,
        enableUndo: true,
        maxHistorySize: 50
    ))
}
```

**改动量**：删除 4 个文件 ~100 行，改调用处约 4 处。

---

#### 3.5 5 个 Rally 计分板包装视图几乎一样，可以泛化

| 文件 | 行数 |
|------|------|
| `BadmintonScoreboardView.swift` | 44 |
| `PingPongScoreboardView.swift` | 57 |
| `PickleballScoreboardView.swift` | 58 |
| `VolleyballScoreboardView.swift` | 51 |
| `FoosballScoreboardView.swift` | 57 |

它们的模式完全相同：
1. 接收 `initialSetup` → 拆出 `isDoubles`
2. 构造 `RallyScoreboardView(...)` 传参
3. 差异只在 `gameType` / `rules` / `openingServer` / 默认名称

**建议**：在 `RallyScoreboardView` 同级增加一个参数化的包装器（或直接在 `ScoreboardTemplate` 里处理），消除这 5 个文件。

**改动量**：删除 5 个文件 ~267 行，改调用处（GameCatalog / Home 跳转逻辑）。

---

#### 3.6 3 个 SessionStore 大量重复

`RallySessionStore`��414行）/ `TennisSessionStore`（441行）/ `BasketballSessionStore`（323行）共享 `send` / `undo` / `applyAuthoritativeState` / `mergeRemoteActions` / `persistSnapshot` / `flush` / `persistRecord` 方法签名和大部分实现。

**建议**：抽取泛型基类 `SessionStore<T>` 或协议扩展，将公共逻辑提升，子类只提供 `reducer` 和 `state` 类型。

**改动量**：中等，需要仔细测试回归。建议放在 iOS 2.1 迭代里做。

---

#### 3.7 `saveGameRecordInRealTime` 在 7 个文件中重复

出现在：`SimpleScoreboardView`、`BoxingScoreboardView`、`BoxingViewModel`、`BilliardsScoreboardView`、`FootballViewModel`、`FootballScoreboardView`、`ArcheryScoreboardView`。

包含了 hasProgress 检查、winner 判断、`ScoreboardRecord` 构建的相同逻辑。

**建议**：提取为 `BaseScoreboardController` 或共享工具协议中的一个方法。

**改动量**：7 个文件各删 15-20 行。

---

#### 3.8 `applyDefaultNamesIfNeeded` 字符级完全一致，重复 2 次

`SimpleScoreboardView.swift` 和 `BilliardsScoreboardView.swift` 里完全一样。

**建议**：提取到 `commonDefaults` 工具或基类。

---

### P2 —— 可优化但非阻塞

#### 3.9 小文件合并建议

| 文件 | 行数 | 建议合并到 |
|------|------|----------|
| `FlipCoinTypes.swift` | 15 | → `FlipCoinView.swift` |
| `PointsTableStorage.swift` | 25 | → `PointsTableModels.swift` |
| `CommonNamesBatchParser.swift` | 28 | → `CommonNamesManager.swift` |
| `ContentView.swift` | 18 | → 内联到 `jifenApp.swift` |
| `UIViewControllerExtensions.swift` | 27 | → `Core/Utils.swift` |

**改动量**：删除 5 个文件，合并内容。

---

#### 3.10 巨型文件拆分进展

| 文件 | 行数 | 问题 |
|------|------|------|
| 原计分板聚合文件 | 已拆分 | 公共容器、记录持久化、台球页面和升级页面均已按领域独立 |
| `SportsSetupDialogView.swift` | 1,907 | 含多个内嵌类型，每个运动设置可独立 |

**进展**：计分板聚合文件已按领域拆分；`SportsSetupDialogView` 仍建议按设置类型拆分。

---

#### 3.11 Resources 目录 MP3 文件全部扁平堆放

37 个 MP3 音效文件直接放在 `Resources/` 下，没有子目录分类。

**建议**：至少按功能分 `Sounds/board_timer/`、`Sounds/scoreboard/`、`Sounds/tools/`，或按语言分 `Sounds/en/` / `Sounds/zh/`。

---

#### 3.12 Football 模块命名不一致

`FootballController.swift` 在其他类比中是 `BoxingScoreboardController` / `BilliardsScoreboardController`，Football 丢掉了 "Scoreboard" 前缀。

**建议**：如果 P1-3.4 执行了，这些文件都会删除。否则应重命名为 `FootballScoreboardController.swift`。

---

### P3 —— 观察项（不需要立即改）

#### 3.13 Watch App 的 `WATCH_SCOREBOARD_MENU_AND_LAYOUT.md` 和 `FINAL_REVIEW_CHECKLIST.md`

这两个 Markdown 放在 Watch App 源码目录里，应该移到 `docs/` 下。

#### 3.14 `dice.html` 放在 `Resources/` 根目录

骰子的 Web 渲染页面放在 Resources 根层级，应放进 `Resources/Web/` 或 `Resources/Html/`。

#### 3.15 主工程和 Watch 有同概念但独立实现的文件

| 主工程 | Watch | 概念 |
|--------|-------|------|
| `FlipCoinTypes.swift` | `WatchFlipCoinTypes.swift` | 抛硬币类型 |
| `SoundManager.swift` | `WatchSoundManager.swift` | 音效 |
| `PreferencesManager.swift` | `WatchPreferences.swift` | 偏好 |
| `ScoreboardRecordManager.swift` | `WatchRecordManager.swift` | 记录管理 |

这不一定是问题——Watch 需要独立实现因为 target 不同。但 `GameType` 枚举在两端是独立定义的（`Types.swift` vs `WatchGameType.swift`），**可能产生不一致**。建议至少把 `GameType` 放入 `JifenCore` 的某个模块中共享。

---

## 四、与 Android/鸿蒙的架构对照

| 维度 | Android | 鸿蒙 | iOS |
|------|---------|------|-----|
| 核心逻辑层 | `shared-core` (55 .kt) | 内嵌模块 | `JifenCore` (28 .swift) |
| 模块划分 | 4 modules | 内嵌分页 | `Core` + `Features` 两层 |
| Score Engine | S1-S4 RuleFamily | 对应逻辑 | `ScoreCore/s1-s4/` |
| 设备联动 | Bluetooth/BLE | 分布式 | `LinkCore` (WCSession) |
| UI 复用方式 | Compose composable | ArkUI @Component | SwiftUI View |

**iOS 的弱项**（相比 Android）：
- `JifenCore` 中 `ScoreCore` 还没覆盖所有运动类型的 reducer（如足球/排球/斗地主/升级），部分直接写在 App Target 里。
- Android 已经用 KernelRegistry + RuntimeRegistry 双注册表模式，iOS 的 `ScoreboardKernelRegistry` 还比较简单。
- Android `shared-core` 有 55 个 .kt，iOS 只有 28 个 .swift——说明还有逻辑可以从 App Target 下沉到 Package。

---

## 五、优先级执行建议

| 优先级 | 条目 | 预估工作量 | 风险 |
|--------|------|-----------|------|
| **P1** | 3.4 消除 4 个 Controller 薄包装 | 30 min | 低 |
| **P1** | 3.5 泛化 5 个 Rally 包装视图 | 1-2 h | 中（需测试所有运动） |
| **P1** | 3.1 Core/ 裸放文件归位 | 10 min | 低 |
| **P1** | 3.2 Home/components/ 改名 | 5 min | 低 |
| **P1** | 3.7 saveGameRecordInRealTime 提取 | 1 h | 中 |
| **P1** | 3.8 applyDefaultNamesIfNeeded 去重 | 10 min | 低 |
| **P2** | 3.3 Legal 模块归并 | 10 min | 低 |
| **P2** | 3.9 小文件合并 (5 个) | 30 min | 低 |
| **P2** | 3.10 巨型文件拆分 | 2-3 h | 中 |
| **P2** | 3.11 Resources MP3 分类 | 20 min | 低（注意 plist 引用路径） |
| **P3** | 3.6 SessionStore 去重 | 4-6 h | 高（影响所有计分记录） |
| **P3** | 3.15 GameType 下沉到 Package | 1-2 h | 中 |

---

## 六、不改的东西

以下保持现状，不需要动：

- **`Scoreboard/Shared/` 共享层** — 作为计分板内的 mini-framework，架构合理
- **`Features/Shared/GameCatalog.swift`** — 位置正确，跨模块的游戏目录定义
- **`Core/Managers/` 下的 9 个 Manager** — 各司其职，无需合并
- **`Assets.xcassets` 图标结构** — Xcode 标准做法
- **Watch App 独立目录结构** — 独立 target，架构清晰
- **`Schemas/` 和 `Activity/` 作为独立 Feature** — 职责单一，保持

---

## 七、总结

**一句话**：架构骨架很好，主要问题是 Scoreboard 模块内部有几组高度相似的薄包装文件可以泛化消除，以及个别文件放置位置偏离了约定。预计全部 P1 项可在半天内完成。
