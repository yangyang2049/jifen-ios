# iOS 计分板全量审查报告：简单计分 / 多人计分 / 射箭 / 拳击

> 审查日期：2026-07-30
> 覆盖范围：简单计分 (simpleScore) · 多人计分 (multiScoreboard) · 射箭 (archery) · 拳击 (boxing)

---

## 1. 架构总览

| 维度 | 简单计分 | 多人计分 | 射箭 | 拳击 |
|------|:---:|:---:|:---:|:---:|
| **架构代** | 旧模板 | 共享 MultiScore | 旧模板 | 旧模板 |
| **UI 容器** | `ScoreboardTemplate` | `MultiScoreboardView` | `ScoreboardTemplate` | `ScoreboardTemplate` |
| **ViewModel** | `LineScoreViewModel` | ❌ 无（直接 State） | `ArcheryViewModel` | `BoxingViewModel` |
| **Controller** | `SimpleScoreboardController` | ❌ 无 | `ArcheryScoreboardController` | `BoxingScoreboardController` |
| **Reducer** | `LineScoreReducer` (.freeCounter) | ❌ 无 | `ArcheryMatchReducer` (ScoreCore S2) | ❌ 无（手动） |
| **Setup 对话框** | `MultiScoreSetupDialogView` | `MultiScoreSetupDialogView` | `SportsSetupDialogView` | `SportsSetupDialogView` |
| **参与人数** | 2 队 | 3-9 人 | 2 人（选手） | 2 人（拳手） |
| **手表联动** | ❌ | ❌ | ✅ | ❌ |
| **语音播报** | ❌ | ❌ | ❌ | ❌ |

---

## 2. Setup 流程逐项对比

### 2.1 简单计分

| Setup 项 | 说明 |
|----------|------|
| 对话框 | `MultiScoreSetupDialogView`，layoutMode = `.twoTeam` |
| 名称输入 | 2 队名（红方/蓝方） |
| 自定义加减分 | ✅ 开关（`simpleScoreCustomAdjustEnabled` preference） |

> 与掼蛋/升级共用 `.twoTeam` 模式，无特有设置。

### 2.2 多人计分

| Setup 项 | 说明 |
|----------|------|
| 对话框 | `MultiScoreSetupDialogView`，layoutMode = `.multiScore` |
| 人数 | 3-9 人（Segmented Picker） |
| 名称输入 | 每人独立输入框（"玩家 1"~"玩家 N"）+ 常用名称选择器 |
| 自定义加减分 | ✅ 开关（`multiScoreboardCustomAdjustEnabled`） |

### 2.3 射箭

| Setup 项 | 说明 |
|----------|------|
| 对话框 | `SportsSetupDialogView` |
| 名称输入 | 双人（"红方"/"蓝方" + 常用名称选择器），`isConfirmedPlayerSetupGame()` |
| **首发选手** | ✅ 左/右选择（`ic_pingpong_serve` 图标，标记为 "首发选手"） |
| 局数/分数 | ❌ 内置规则（先到 6 分胜，5:5 一箭决胜） |
| 自动换边 | ❌ |
| 特有设置 | ❌ 无（仅首发选择） |

### 2.4 拳击

| Setup 项 | 说明 |
|----------|------|
| 对话框 | `SportsSetupDialogView` |
| 名称输入 | 双人（"红方"/"蓝方" + 常用名称选择器），`isConfirmedPlayerSetupGame()` |
| 发球方 | ❌ 无 |
| **回合数** | ✅ 预设 3/8/10/12 + 自定义（1-99），默认 3 回合 |
| 自动换边 | ❌ |
| 特有设置 | 仅回合数 |

---

## 3. 页面布局逐项对比

### 3.1 简单计分

| 维度 | 描述 |
|------|------|
| **布局** | `ScoreboardTemplate` 左右 2 列 |
| **计分** | 点击 +1（`getScoringOptions() = [1]`）|
| **自定义加减分** | ✅ 展开 `ScoreCustomAdjustPanel`：显示当前分数，可选 +1/+2/+5...+N 或任意数字 |
| **规则** | `.freeCounter`：无上限（-9999~9999 钳制） |
| **交互** | 单击 +1 / 下滑 -1 / 左滑撤销 / 长按菜单 / 双击查分 |
| **编辑** | 铅笔 → 编辑队名 + 分数 +/- |
| **换边** | ✅ |
| **沉浸** | ✅ |

### 3.2 多人计分

| 维度 | 描述 |
|------|------|
| **布局** | `MultiScoreboardView`：`ScoreboardPlayerGridLayout.multiRows()` |
| **网格自适应** | 2人=2行 / 3人=3行 / 4人=2×2 / 5-10人=自适应 |
| **颜色** | 12 色 HOS 对齐色板 |
| **计分** | 单击 +1 / 双击 -1 / 自定义加减分（需开启） |
| **自定义加减分** | ✅ 面板 `customAdjustIndex` |
| **交互** | 单击 +1 / 双击 -1 / 左滑撤销 / 长按菜单 |
| **编辑** | 点击玩家名 → 独立编辑框 |
| **横竖屏** | ✅ 设置中切换（multi_scoreboard_use_landscape_layout） |
| **排名** | 自动最高分高亮 |

### 3.3 射箭

| 维度 | 描述 |
|------|------|
| **布局** | `ScoreboardTemplate` + `ArcheryMiddleLayer`（中线叠加层） |
| **中间层** | 箭靶分数选择网格：3行×4列 |
| **分数网格** | [10,9,8,7] / [6,5,4,3] / [2,1,0,M(Miss)] |
| **局间结算** | ✅ `showSetEndOverlay`：每轮 3 箭后自动弹窗，展示本局分数 + 可选 "最接近中心"(shoot-off) |
| **计分方式** | 点击分数格 → 加到当前选手 → 满 3 箭自动结算 |
| **规则** | 每局 2 分(胜)/1 分(平)/0 分(负)；先到 6 分胜；5:5 一箭决胜；shoot-off 时 1 箭/人 |
| **发球指示** | ❌ 无（通过 `tapToAddEnabled: false` 禁用默认点击计分） |
| **Watch 联动** | ✅ 支持（`PhoneWatchLinkService`） |
| **编辑** | 铅笔→编辑名称 + 总分/局分 |
| **换边** | ✅ |
| **沉浸** | ✅ |

### 3.4 拳击

| 维度 | 描述 |
|------|------|
| **布局** | `ScoreboardTemplate` 左右 2 列 |
| **回合弹窗** | ✅ 核心交互：每回合结束弹出 `roundLeftPoints:roundRightPoints` 对话框（默认 10:10） |
| **分数规则** | 标准 10 分制（胜者 10，败者 ≤9），回合胜者+1 总回合胜数 |
| **回合管理** | `BoxingViewModel` 跟踪 `roundsWon`，达到半数以上自动结束 |
| **计分交互** | ❌ 不能直接点击计分（`tapToAddEnabled` 无），仅通过回合弹窗 |
| **编辑** | 铅笔→编辑名称 + 总分数 |
| **换边** | ✅ |
| **沉浸** | ✅ |
| **显示设置** | ✅ `ScoreboardTypographySession` |

---

## 4. 菜单项对比

### 4.1 简单计分

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 换边 | match | ✅ |
| 结算 | match | ✅ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 自定义加减分 | 面板交互 | — |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |

### 4.2 多人计分

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 自定义加减分 | match | ❌ (切换开关) |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |

### 4.3 射箭

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 换边 | match | ✅ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |
| 手表同步 | sync | 动态 |

### 4.4 拳击

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 换边 | match | ✅ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |

---

## 5. 记录/保存/展示

| 项目 | 架构 | 记录 ID | 格式 |
|------|------|---------|------|
| 简单计分 | 旧模板 | `"simple_score_\(timestamp)"` | `BaseScoreboardController.saveScoreboardRecord()` |
| 多人计分 | 共享 MultiScore | `"multi_scoreboard_\(timestamp)"` | 自定义 `saveMultiScoreRecord()` |
| 射箭 | 旧模板 | `"archery_\(timestamp)"` | 旧 ScoreboardRecord（含 archeryState 序列化） |
| 拳击 | 旧模板 | `"boxing_\(timestamp)"` | `BoxingViewModel.saveGameRecordInRealTime()` |

全部无 Session 持久化。

---

## 6. 特殊功能亮点

### 射箭 — 最复杂的旧模板项目

射箭虽然是旧模板架构，但通过 `ArcheryMiddleLayer` 叠加层实现了独特的交互：
- 3×4 箭靶分数网格替代默认点击+1
- 每轮 3 箭自动结算 + shoot-off 逻辑
- 局间 overlay 动画
- 支持 Watch 联动（是少数有联动的旧模板项目）

### 拳击 — 回合制弹窗

拳击的核心交互不在计分板面板上，而在于 **回合结束弹窗**：
- 不能手动计分，完全靠回合制驱动
- 每回合弹窗预设 10:10，手动调整后确认
- 自动追踪回合胜数、判断比赛结束

---

## 7. 逐项对照总表

| 检查项 | 简单计分 | 多人计分 | 射箭 | 拳击 |
|--------|:---:|:---:|:---:|:---:|
| **Setup: 对话框** | MultiScoreSetup | MultiScoreSetup | SportsSetupDialog | SportsSetupDialog |
| **Setup: 名称输入** | ✅ 2队名 | ✅ 3-9人名 | ✅ 2人名 | ✅ 2人名 |
| **Setup: 人数选择** | 固定2队 | ✅ 3-9人 | 固定2人 | 固定2人 |
| **Setup: 发球/首发** | ❌ | ❌ | ✅ 首发选手 | ❌ |
| **Setup: 回合/局数** | ❌ | ❌ | ❌ 内置 | ✅ 3/8/10/12+自定义 |
| **布局: 容器** | ScoreboardTemplate | MultiScoreboardView | ScoreboardTemplate | ScoreboardTemplate |
| **布局: 列数** | 2列 | 3-9人网格 | 2列+中置分数层 | 2列 |
| **计分方式** | 单击+1/自定义面板 | 单击+1/双击-1/自定义 | 3×4 分数网格 | 回合弹窗 |
| **回合/局机制** | ❌ | ❌ | ✅ 3箭/局+shootoff | ✅ 10分制回合弹窗 |
| **自定义加减分** | ✅ 可开关 | ✅ 可开关 | ❌ | ❌ |
| **局间结算** | ❌ | ❌ | ✅ 自动弹窗 | ✅ 手动弹窗 |
| **编辑: 名称** | ✅ | ✅ 逐个编辑 | ✅ | ✅ |
| **编辑: 分数** | ✅ +/- | ✅ 逐个编辑 | ✅ +/- | ✅ +/- |
| **换边** | ✅ | ❌ | ✅ | ✅ |
| **横竖屏** | ❌ | ✅ 可切换 | ❌ | ❌ |
| **沉浸模式** | ✅ | ✅ | ✅ | ✅ |
| **显示设置** | ✅ | ✅ | ✅ | ✅ |
| **截图** | ✅ | ✅ | ✅ | ✅ |
| **哨声** | ✅ | ✅ | ✅ | ✅ |
| **手表联动** | ❌ | ❌ | ✅ | ❌ |
| **语音播报** | ❌ | ❌ | ❌ | ❌ |
| **ScoreCore Reducer** | ✅ S1 Line | ❌ | ✅ S2 Archery | ❌ |
| **比赛结束弹窗** | ✅ | ✅ | ✅ | ✅ |
| **再来一场** | ✅ | ✅ | ✅ | ✅ |
| **分享** | ✅ | ✅ | ✅ | ✅ |
