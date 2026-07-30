# iOS 计分板全量审查报告：四种台球

> 审查日期：2026-07-30
> 覆盖范围：台球 (billiards) · 黑八 (eightBall) · 九球/追分 (nineBall) · 斯诺克 (snooker)

---

## 1. 架构总览

| 维度 | 台球 (billiards) | 黑八 (eightBall) | 九球/追分 (nineBall) | 斯诺克 (snooker) |
|------|:---:|:---:|:---:|:---:|
| **架构代** | 旧模板架构 | 新 Session 架构 | 新 Session 架构 | 新 Session 架构 |
| **UI 容器** | `ScoreboardTemplate` | `SpecializedScoreboardScaffold` | 自定义 player grid | `SpecializedScoreboardScaffold` |
| **Store** | ❌ 无 | `SpecializedBilliardsSessionStore<EightBallReducer>` | `SpecializedBilliardsSessionStore<NineBallChaseReducer>` | `SpecializedBilliardsSessionStore<SnookerReducer>` |
| **Reducer** | `LineScoreReducer` | `EightBallReducer` | `NineBallChaseReducer` | `SnookerReducer` |
| **ScoreCore 族** | S1/Line | S2/专项 | S3/多人 | S2/专项 |
| **Controller** | `BilliardsScoreboardController` | ❌ 无 | ❌ 无 | ❌ 无 |
| **Setup 对话框** | `SportsSetupDialogView` | `SportsSetupDialogView` | **独立** `NineBallSetupDialogView` | `SportsSetupDialogView` |
| **参与人数** | 2 人（左/右） | 2 人（左/右） | 2-4 人（玩家 grid） | 2 人（左/右） |
| **手表联动** | ❌ | ✅ | ✅ | ✅ |
| **语音播报** | ❌ | ❌ | ❌ | ❌ |

---

## 2. Setup 流程逐项对比

### 2.1 台球 (billiards)

| Setup 项 | 说明 |
|----------|------|
| 名称输入 | "红方"/"蓝方" + 常用名称选择器 |
| 发球方选择 | ❌ 无 |
| 局数/分数 | ❌ 无（纯 LineScore：0-9999，无上限） |
| 自动换边 | ❌ 无 |
| 特有设置 | ❌ 无任何高级设置 |
| 对话框分支 | `shouldShowSettings() == false` → 仅名称输入 |

### 2.2 黑八 (eightBall)

| Setup 项 | 说明 |
|----------|------|
| 名称输入 | "红方"/"蓝方" + 常用名称选择器 |
| 发球方选择 | ❌ 无 |
| **局数** | ✅ 预设 1/3/5/7/9/11 + 自定义（1-99），默认 9 局 |
| **让局** | ✅ 可选：无 / 左让右 / 右让左；局数 > 1 时出现；让局数选择 1~(局数-1) |
| 自动换边 | ❌ 无 |
| 特有设置 | 仅局数 + 让局（handicapRacks + handicapBeneficiary） |

> `confirmSetup` 中 `gameType == .eightBall` 直接 fallthrough 到 snooker 设置逻辑，通过 `billiardsConfiguration(for:)` 解析。

### 2.3 九球/追分 (nineBall) — 独立对话框

| Setup 项 | 说明 |
|----------|------|
| **人数** | Segmented Picker：2/3/4 人 |
| **名称输入** | 每人独立输入框（占位符 "玩家 1"~"玩家 4"）+ 常用名称选择器 |
| **事件分值** | 全部可自定义：大金(默认10)、小金(默认7)、黄金九(默认8)、普胜(默认4)、自由球(默认1)、犯规(默认1) |
| 发球方 | ❌ 无 |
| 局数 | ❌ 无（追分制，按事件累计） |

> **独立 Setup**：九球走 `NineBallSetupDialogView`（不经过 `SportsSetupDialogView`），是唯一有独立 Setup 对话框的运动。

### 2.4 斯诺克 (snooker)

| Setup 项 | 说明 |
|----------|------|
| 名称输入 | "红方"/"蓝方" + 常用名称选择器 |
| **发球方/开球方** | ✅ 首局开球方选择（左/右） |
| **局数** | ✅ 预设 1/3/5/7/9/11/15/17/19/25/33/35 + 自定义（1-99），默认 1 局 |
| 自动换边 | ❌ 无 |
| 特有设置 | 首局开球方 + 超多局数预设（11-35） |

---

## 3. 页面布局逐项对比

### 3.1 台球 (billiards)

| 维度 | 描述 |
|------|------|
| **布局模式** | `ScoreboardTemplate`：左右 50/50 分屏 |
| **颜色方案** | 主题色（通过 appearance 切换） |
| **显示内容** | 上方队名 → 中间大分 → 无局分/无 detail |
| **计分按钮** | `getScoringOptions() = []` → **无快捷按钮**，仅单击半区 +1 |
| **交互** | 单击 +1 / 下滑 -1 / 左滑撤销 / 长按菜单 / 双击查分 |
| **编辑模式** | 铅笔 → 编辑队名 + 分数 +/- |
| **发球指示** | ❌ 无 |
| **换边** | ✅ sidesSwapped |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ 字体/主题调整 |

### 3.2 黑八 (eightBall)

| 维度 | 描述 |
|------|------|
| **布局模式** | `SpecializedScoreboardScaffold`：左右 50/50 + 顶部 pill（目标局数）+ 中间让局显示 |
| **颜色方案** | 主题色 |
| **显示内容** | 队名 → 大分(局数) → 顶栏目标局数 → 中栏让局提示(如有) |
| **计分交互** | 点击左侧 +1 局 / 点击右侧 +1 局（`addRack`） |
| **交互** | 单击加局 / 左滑撤销 / 长按菜单 |
| **编辑模式** | 铅笔 → 编辑队名 + 局数 +/-（`onEditAdjust`） |
| **换边** | ✅ `exchangeSides` |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ |
| **让局显示** | 状态栏中心显示 "让局 N"（如 `state.handicapRacks > 0`） |

### 3.3 九球/追分 (nineBall) — 独立布局

| 维度 | 描述 |
|------|------|
| **布局模式** | 自定义 player grid：`ScoreboardPlayerGridLayout.nineBallRows()` |
| **网格规则** | 2人=并排2列 / 3人=3列 / 4人=(2×2) 或宽屏并排4列 |
| **每列内容** | 玩家名(上) → 得分(中) → 排名(下) |
| **颜色方案** | 主题色 |
| **计分交互** | 点击玩家列 → 弹出追分事件面板（大金/小金/黄金九/普胜/自由球/犯规） |
| **追分面板** | 底部 sheet → 6 种事件按钮 + 确认/取消 |
| **编辑模式** | 独立 `showEditPanel` sheet → 玩家名 + 分数直接编辑 |
| **换边** | ❌ 不适用（多人 grid） |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ |
| **排名标识** | ✅ 底部显示 "第 N 名" |

### 3.4 斯诺克 (snooker)

| 维度 | 描述 |
|------|------|
| **布局模式** | `SpecializedScoreboardScaffold`：左右 50/50 + 顶部 pill(当前局/总局) + 底部彩球条 + 中间发球三角 |
| **显示内容** | 队名(上) → 主分(中) + break(下) → 局数 pill → 7 颗彩球按钮 |
| **颜色方案** | 主题色 |
| **底部彩球条** | 红(1) 黄(2) 绿(3) 棕(4) 蓝(5) 粉(6) 黑(7)，每颗可点击加分 |
| **发球指示** | ✅ `CenterLineServeIndicator` 三角指示当前开球方 |
| **计分交互** | 点击彩球 +对应分（红1/黄2/绿3/棕4/蓝5/粉6/黑7） |
| **犯规面板** | 覆层 `snookerFoulOverlay`：选择犯规值(1-7) + 轮换开关 |
| **结算面板** | sheet `snookerSettleSheet`：选择本局胜者 → 记录局分 |
| **记录面板** | sheet `snookerRecordSheet`：查看历史局记录 |
| **换边** | ❌ 不适用（frame 制，开球方在 Setup 确定） |
| **编辑模式** | 铅笔 → 编辑队名 + +/- 调整分数 |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ |
| **特有菜单** | 结算本局 (settleFrame) + 记录 (frameRecord) |

---

## 4. 菜单项对比

### 4.1 台球 (billiards)

通过 `ScoreboardTemplate` 默认菜单：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 换边 | match | ✅ |
| 结算 | match | ✅ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |

### 4.2 黑八 (eightBall)

通过 `SpecializedScoreboardScaffold`：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 换边 | match | ✅ |
| 重置 | match | ✅ |
| **结束比赛** | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |
| 手表同步项 | sync | 动态 |

### 4.3 九球 (nineBall)

自定义菜单（不经过 Scaffold）：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| **结算** | match | ✅ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |
| 手表同步项 | sync | 动态 |

### 4.4 斯诺克 (snooker)

标准菜单 + 2 个额外项：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 重置 | match | ✅ |
| **结算本局** (settleFrame) | match | ✅ (绿色) |
| **记录** (frameRecord) | match | ❌ (直接打开 sheet) |
| 结束比赛 | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |
| 手表同步项 | sync | 动态 |

> ⚠️ 斯诺克**无换边菜单项**（`onExchange: nil`）。换边逻辑由每局开球方决定。

---

## 5. 记录/保存/展示对比

### 5.1 台球 (billiards) — 旧架构

| 维度 | 说明 |
|------|------|
| **保存方式** | `BilliardsScoreboardView.saveGameRecordInRealTime()` 自定义实现 |
| **Draft 结构** | `LineScoreSessionArchive`（state + undoHistory + intentTimeline） |
| **记录格式** | ScoreboardRecord（混合 v4 字段 + 旧字段） |
| **记录 ID** | `"billiards_\(timestamp)"` 字符串拼接 |
| **Session 持久化** | ❌ 无（自编码 JSON 到 `stateSnapshot`） |
| **Draft 恢复** | ⚠️ 部分：从 `stateSnapshot` 解 `LineScoreSessionArchive` 恢复 |

### 5.2 黑八 / 斯诺克 / 九球 — 新架构

| 维度 | 说明 |
|------|------|
| **保存方式** | `SpecializedBilliardsSessionStore.persistSnapshot()` → `SessionArchiveRepository` |
| **Draft 结构** | `ScoreSessionResumeBundle<State, Event, Intent>` |
| **记录格式** | ScoreboardRecord v4（sessionId UUID） |
| **记录 ID** | UUID |
| **Session 持久化** | ✅ `SessionArchiveRepository.saveResumeBundle()` |
| **Draft 恢复** | ✅ 从 SessionArchive 或旧 Draft 兼容恢复 |

---

## 6. 从架构代视角总结

```
                     Setup 入口
                         |
        ┌────────────────┼──────────────────┐
        │                │                  │
   旧模板架构        新 Session 架构      新 Session 架构
  (billiards)    (黑八·斯诺克)        (九球·追分)
        │                │                  │
  ScoreboardTemplate  Specialized-      自定义 Player Grid
  + LineScoreVM     ScoreboardScaffold   + 追分事件面板
  + Controller      + BilliardsStore     + BilliardsStore
        │                │                  │
  LineScoreReducer   EightBallReducer    NineBallChaseReducer
  (S1 Line)          SnookerReducer      (S3 多人)
                     (S2 专项)
```

### 关键问题

| # | 问题 | 涉及运动 | 严重度 |
|---|------|---------|--------|
| 1 | **台球用旧模板架构**，与其他三种不统一（无 Session、无 watch 联动、String ID） | billiards | P1 |
| 2 | **九球有独立 Setup 对话框**，架构上与 SportsSetupDialogView 分支不一致 | nineBall | P2 |
| 3 | 四种台球**均无语音播报** | all | P3 |
| 4 | 斯诺克**无换边功能**（合理，frame 制不换边，但菜单项缺失可能引起困惑） | snooker | P3 |
| 5 | 黑八 / 斯诺克 Setup 走同一 `SportsSetupDialogView`，通过 `billiardsConfiguration(for:)` 多态解析 | eightBall/snooker | 架构合理 |
| 6 | 九球 2-4 人 grid 布局**与其他运动完全不同**，是唯一的多玩家网格计分板 | nineBall | 架构合理 |

---

## 7. 逐项对照总表

| 检查项 | 台球 | 黑八 | 九球/追分 | 斯诺克 |
|--------|:---:|:---:|:---:|:---:|
| **Setup: 名称输入** | ✅ 红/蓝方 | ✅ 红/蓝方 | ✅ 2-4人独立名 | ✅ 红/蓝方 |
| **Setup: 参与人数** | 固定 2 人 | 固定 2 人 | ✅ 2/3/4 人可选 | 固定 2 人 |
| **Setup: 局数/盘数** | ❌ | ✅ 1/3/5/7/9/11+自定义 | ❌ (追分制) | ✅ 1/3/5/7...35+自定义 |
| **Setup: 发球/开球方** | ❌ | ❌ | ❌ | ✅ 左/右选择 |
| **Setup: 让局** | ❌ | ✅ 左让右/右让左 | ❌ | ❌ |
| **Setup: 事件分值** | ❌ | ❌ | ✅ 大金/小金/黄金九/普胜/自由球/犯规 | ❌ |
| **Setup: 对话框** | SportsSetupDialog | SportsSetupDialog | **独立** NineBallSetupDialog | SportsSetupDialog |
| **布局: 基本模式** | 2列模板 | 2列+顶pill | 多人grid | 2列+顶pill+底球条 |
| **布局: 颜色方案** | 主题色 | 主题色 | 主题色 | 主题色 |
| **布局: 底部操作栏** | ❌ | ❌ | ❌ | ✅ 7 颗彩球按钮 |
| **布局: 发球指示** | ❌ | ❌ | ❌ | ✅ 居中三角 |
| **布局: 顶栏信息** | ❌ | ✅ 目标局数+让局 | ❌ | ✅ 当前局/总局 |
| **计分方式** | 单击+1 | 单击加局 | 单击弹出事件面板 | 点击彩球加分 |
| **交互: 下滑-1** | ✅ | ❌ | ❌ | ❌ |
| **交互: 左滑撤销** | ✅ | ✅ | ✅ | ✅ |
| **交互: 长按菜单** | ✅ | ✅ | ✅ | ✅ |
| **犯规系统** | ❌ | ❌ | ❌ | ✅ 犯规覆层+分值选择 |
| **局结算** | ❌ | ❌ | ❌ | ✅ 结算本局 sheet |
| **历史记录面板** | ❌ | ❌ | ❌ | ✅ frameRecord sheet |
| **编辑: 名称** | ✅ | ✅ | ✅ | ✅ |
| **编辑: 分数** | ✅ +/- | ✅ +/- | ✅ 直接编辑 | ✅ +/- |
| **换边** | ✅ | ✅ | ❌ | ❌ |
| **沉浸模式** | ✅ | ✅ | ✅ | ✅ |
| **显示设置** | ✅ | ✅ | ✅ | ✅ |
| **截图** | ✅ | ✅ | ✅ | ✅ |
| **哨声** | ✅ | ✅ | ✅ | ✅ |
| **手表联动** | ❌ | ✅ | ✅ | ✅ |
| **语音播报** | ❌ | ❌ | ❌ | ❌ |
| **记录保存** | ⚠️ 混合格式 | ✅ v4 | ✅ v4 | ✅ v4 |
| **Draft 恢复** | ⚠️ 部分 | ✅ Session | ✅ Session | ✅ Session |
| **比赛结束弹窗** | ✅ | ✅ | ✅ | ✅ |
| **再来一场** | ✅ | ✅ | ✅ | ✅ |
| **分享** | ✅ | ✅ | ✅ | ✅ |
