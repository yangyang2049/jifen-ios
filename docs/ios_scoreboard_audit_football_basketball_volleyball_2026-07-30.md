# iOS 计分板全量审查报告：足球 / 篮球 / 三种排球

> 审查日期：2026-07-30
> 覆盖范围：足球、篮球、室内排球、沙滩排球、气排球
> 审查维度：Setup → 页面布局 → 菜单项 → 记录/保存/展示 → 手机/平板差异

---

## 1. 架构对比总览

| 维度 | 足球 | 篮球 (含 3x3) | 室内排球 | 沙滩排球 | 气排球 |
|------|------|------------|---------|---------|--------|
| **架构代** | 旧模板架构 | 新 ScoreCore 架构 | 新 Rally 架构 | 新 Rally 架构 | 新 Rally 架构 |
| **UI 容器** | `ScoreboardTemplate` | 自定义 3 列布局 | `RallyScoreboardView` | `RallyScoreboardView` | `RallyScoreboardView` |
| **Store** | 无 SessionStore | `BasketballSessionStore` | `RallySessionStore` | `RallySessionStore` | `RallySessionStore` |
| **Reducer** | `LineScoreReducer` | `BasketballMatchReducer` | `RallyMatchReducer` | `RallyMatchReducer` | `RallyMatchReducer` |
| **ScoreCore 族** | s1/Line | s2/Basketball | s1/Rally | s1/Rally | s1/Rally |
| **视图文件** | `FootballScoreboardView` | `BasketballScoreboardView` | `VolleyballScoreboardView` | `VolleyballScoreboardView` | `VolleyballScoreboardView` |
| **Controller** | `FootballScoreboardController` | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **ViewModel** | `FootballViewModel` | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **手表联动** | ❌ 不支持 | ✅ 支持 | ✅ 支持 | ✅ 支持 | ✅ 支持 |
| **语音播报** | ❌ 不支持 | ❌ 不支持 | ❌ 硬编码 false | ❌ 硬编码 false | ❌ 硬编码 false |
| **Setup 对话框** | ❌ 跳过（直接名称输入） | ✅ SportsSetupDialogView | ✅ SportsSetupDialogView | ✅ SportsSetupDialogView | ✅ SportsSetupDialogView |

---

## 2. Setup 流程逐项对比

### 2.1 足球

| Setup 项 | iOS 现状 |
|----------|---------|
| 名称输入 | `SportsSetupDialogView`：左/右队名，占位符 "主队"/"客队" + 常用名称选择器 |
| 单/双打选择 | ❌ 不适用（团队运动） |
| 发球方选择 | ❌ 不适用 |
| 局数设置 | ❌ 无（足球=单场制） |
| 分数设置 | ❌ 无（Goal=+1） |
| 自动换边 | ❌ 无 |
| 语音播报 | ❌ 无 |
| 特有设置 | ❌ 无 |

> **注意**：足球的 Setup 路径为 `SportsSetupDialogView`，进入 `isConfirmedTeamSetupGame()` 分支（仅名称输入 + 开始按钮）

### 2.2 篮球

| Setup 项 | 5v5 | 3x3 |
|----------|-----|-----|
| 名称输入 | ✅ "主队"/"客队" + 常用名称 | ✅ 同左 |
| 单/双打选择 | ❌ 不适用 | ❌ 不适用 |
| 发球方选择 | ❌ 无 | ❌ 无 |
| 规则选择 | ✅ FIBA / NBA 切换 | ✅ FIBA / NBA 切换 |
| 局数/节数 | ❌ 内置（FIBA 4节、NBA 4节） | ❌ 内置（3x3 单节10分钟或21分） |
| 自动换边 | ❌ 无 | ❌ 无 |
| 语音播报 | ❌ 无 | ❌ 无 |
| 特有设置 | **FIBA vs NBA**：暂停数/时长不同 | **仅规则** |
| setup 对话框 | `shouldShowSettings() = true` | `shouldShowSettings() = true`（同为 basketball 规则分支） |

> ⚠️ **潜在 Bug**：`confirmSetup` 中 `gameType == .basketball` 固定设 `basketballMode = "five_v_five"`，而 `.threeBasketball` 不会进入此分支 → `basketballMode` 保留 `nil` → `BasketballSessionStore` 初始化时 `basketballMode == "three_x_three" ? .threeXThree : .fiveVFive` → **3x3 从 setup 进入也变成 5v5**。可能 3x3 仅支持快速开始（无 setup），需确认。

### 2.3 三种排球

| Setup 项 | 室内排球 | 沙滩排球 | 气排球 |
|----------|---------|---------|--------|
| 名称输入 | ✅ "红方"/"蓝方" + 常用名称 | ✅ 同左 | ✅ 同左 |
| 单/双打选择 | ❌ 不适用 | ❌ 不适用 | ❌ 不适用 |
| 发球方选择 | ✅ `ic_volleyball_serve` 图标 | ✅ 同左 | ✅ 同左 |
| 局数设置 | ❌ 无（硬编码：室内5局、沙排/气排3局） | ❌ 同左 | ❌ 同左 |
| 分数设置 | ❌ 无（内置规则） | ❌ 同左 | ❌ 同左 |
| 自动换边 | ✅ 开关 | ✅ 开关 | ✅ 开关 |
| 语音播报 | ❌ 无 | ❌ 无 | ❌ 无 |
| 特有设置 | ❌ 无 | ❌ 无 | ❌ 无 |

> 排球 Setup 在 `confirmSetup` 中仅设置 `autoChangeSides` + `servingSide`，不传递 `maxSets`/`pointsPerSet`/`voiceAnnouncement`。局数由 `VolleyballScoreboardView` 内部硬编码。

---

## 3. 页面布局逐项对比

### 3.1 足球

| 维度 | 描述 |
|------|------|
| **布局模式** | `ScoreboardTemplate`：左右 50/50 分屏（横屏）/ 上下 50/50（竖屏？实际强制横屏） |
| **颜色方案** | 左红(C62828)、右蓝(007AFF) |
| **显示内容** | 上方队名 → 中间大分 → 下方无局分（单场） |
| **计分按钮** | 仅 [1]（每次 +1 球） |
| **交互** | 点击 +1 / 下滑 -1 / 左滑撤销 / 长按菜单 |
| **得分面板** | `TeamSection` → 显示 1/2/3 等可选加分 |
| **编辑模式** | 铅笔按钮 → 编辑队名 + 大分 +/- |
| **发球指示** | ❌ 无 |
| **换边** | 支持 sidesSwapped |
| **沉浸模式** | ✅ 支持 |

### 3.2 篮球

| 维度 | 5v5 | 3x3 |
|------|-----|-----|
| **布局模式** | **3 列布局**：左面板 / 中面板(时钟+节次) / 右面板 | 同左 |
| **颜色方案** | 左红(C62828)、右蓝(007AFF) | 同左 |
| **左/右面板** | `BasketballTeamPanel`：队名 + 大分 + 犯规 + 暂停 + 罚球 bonus 标识 | 同左 |
| **中面板** | `BasketballCenterPanel`：比赛时钟 + 24/14/12秒进攻时钟 + 节次选择 + 加时 | 同左 |
| **犯规显示** | FIBA 5犯/NBA 6犯，bonus(第5犯)/doubleBonus(第10犯) 标识 | 3x3 规则 |
| **暂停显示** | FIBA 上半场2次+下半场3次/NBA 全场7次+加时1次 | 3x3 1次暂停 |
| **计分按钮** | [+1] [+2] [+3] 三分球分级 | [+1] [+2] 无三分 |
| **比赛时钟** | FIBA 10分钟×4节 / NBA 12分钟×4节，暂停/节间控制 | 10分钟单节或先到21分 |
| **进攻时钟** | 24秒(FIBA) / 24秒(NBA) / 12秒(3x3) | 12秒 |
| **交互** | 点击加分 / 左滑撤销 / 长按菜单 | 同左 |
| **编辑模式** | 铅笔 → `BasketballEditTeamPanel`（队名+分数编辑） | 同左 |
| **换边** | ✅ 支持 sidesSwapped | ✅ |
| **节次控制** | 前进下一节/加时赛按钮 | 同左 |
| **沉浸模式** | ✅ 支持 |

### 3.3 三种排球

| 维度 | 室内排球 | 沙滩排球 | 气排球 |
|------|---------|---------|--------|
| **布局模式** | Rally 左右分屏 + 发球三角指示器 | 同左 | 同左 |
| **显示内容** | 上方队名 → 中间大分 → 下方局分 | 同左 | 同左 |
| **发球指示** | ✅ `CenterLineServeIndicator` 居中三角 | ✅ | ✅ |
| **计分交互** | 点击 +1 / 下滑 -1 / 左滑撤销 / 长按菜单 | 同左 | 同左 |
| **编辑模式** | 铅笔 → 编辑队名 + 大分/局分 +/- | 同左 | 同左 |
| **自动换边** | ✅ sidesSwapped | ✅ 沙排特有 7/14 分换边 | ✅ |
| **默认局数** | 5 局 | 3 局 | 3 局 |
| **每局分数** | 25 分（决胜局 15 分） | 21 分（决胜局 15 分） | 21 分（决胜局 15 分） |
| **得分模式** | Rally 得分（scorerServes） | Rally 得分 | Rally 得分 |
| **决胜局换边** | 8 分换边 | 7 分换边 / 5 分换边（决胜局） | 8 分换边 |
| **沉浸模式** | ✅ | ✅ | ✅ |

---

## 4. 菜单项对比

### 4.1 足球

通过 `ScoreboardTemplate` 的 `buildDefaultMenuItems`：

| 菜单项 | 分组 | 图标 | 二次确认 |
|--------|------|------|---------|
| 撤销 | match | arrow.uturn.backward | ❌ 直接执行 |
| 换边 | match | arrow.left.arrow.right | ✅ 绿色确认 |
| 结算 | match | checkmark.seal | ✅ 绿色确认 |
| 重置 | match | arrow.counterclockwise | ✅ 绿色确认 |
| 结束比赛 | match | flag.checkered | ✅ 绿色确认 |
| 哨声 | tools | bell.fill | ❌ 直接执行 |
| 显示设置 | tools | "Aa" | — |
| 截图 | tools | camera.fill | — |
| 使用说明 | tools | "?" | — |

> 足球特有 `showSettleMatch: true`（结算项在非篮球/非拳击运动中显示）

### 4.2 篮球

通过 `ScoreboardMenuItemBuilder.defaultItems` + 手表联动额外项：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ 直接执行 |
| 换边 | match | ✅ 绿色确认 |
| 重置 | match | ✅ 绿色确认 |
| 结束比赛 | match | ✅ 绿色确认 |
| 哨声 | tools | ❌ 直接执行 |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |
| 手表同步/重同步/切换/结束链接 | sync | 根据链接状态动态 |
| 语音播报开关 | sync | ❌ 直接切换 |

> 语音播报开关仅在手表中控/非跟随模式下显示，篮球本身无语音播报（`VoidVoiceAnnouncementMapper`）。

### 4.3 三种排球

通过 `RallyScoreboardView` 的默认菜单项（与乒乓球/羽毛球/匹克球相同）：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ 直接执行 |
| 换边 | match | ✅ 绿色确认 |
| 重置 | match | ✅ 绿色确认 |
| 结束比赛 | match | ✅ 绿色确认 |
| 哨声 | tools | ❌ 直接执行 |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |
| 语音播报开关 | sync | ❌ 直接切换 |
| 手表同步项 | sync | 动态 |

> ⚠️ 排球有语音播报菜单开关，但 `VolleyballScoreboardView` 初始化 Rally 时**未传 `voiceAnnouncementEnabled` 参数**，默认 false，且即使开关打开也不会传递到 setup。

---

## 5. 记录/保存/展示对比

### 5.1 足球（旧架构）

| 维度 | 描述 |
|------|------|
| **保存方式** | `FootballViewModel.saveGameRecordInRealTime()` → `BaseScoreboardController.saveScoreboardRecord()` |
| **保存时机** | `onDisappear` / `viewModel.gameFinished == true` / GameOverDialog 各按钮 |
| **记录 ID** | `"football_\(timestamp)"` 字符串拼接（非 UUID） |
| **记录结构** | 旧 ScoreboardRecord 格式（id + gameType + startTime + endTime + duration + team1Name/Score + team2Name/Score + team1SetScore/team2SetScore + actions + winner） |
| **状态管理** | draft / finished |
| **无 Session** | ❌ 不支持 SessionArchiveRepository 持久化 |
| **无 Draft 恢复** | ❌ `restoreDraftIfNeeded` 仅从已保存记录恢复，不通过 Session |
| **无详细动作** | ❌ `gameActions` 是纯字符串列表 |

### 5.2 篮球（新架构）

| 维度 | 描述 |
|------|------|
| **保存方式** | `BasketballSessionStore.persistSnapshot()` → `SessionArchiveRepository.saveResumeBundle()` + `persistRecord()` |
| **保存时机** | `state.finished → persistSnapshot()` / `scheduleDraftPersist` 0.35s 防抖 / `onDisappear → persistSnapshot()` |
| **记录 ID** | `sessionId.uuidString` (UUID) |
| **记录结构** | ScoreboardRecord v4（含 sessionId + stateSnapshot + projectConfiguration + extraData + detailedActions） |
| **Session 持久化** | ✅ 支持 ScoreSession 完整序列化 |
| **Draft 恢复** | ✅ 支持通过 `sessionId` 恢复完整状态 |
| **详细动作** | ✅ `detailedActions: [DetailedScoreAction]` 可追溯 |

### 5.3 三种排球（新架构）

| 维度 | 描述 |
|------|------|
| **保存方式** | `RallySessionStore.persistSnapshot()` → 同篮球 |
| **保存时机** | 同篮球 |
| **记录 ID** | UUID |
| **记录结构** | ScoreboardRecord v4 |
| **Session 持久化** | ✅ |
| **Draft 恢复** | ✅ |
| **详细动作** | ✅ |

---

## 6. 手机 vs 平板对比

| 维度 | 足球 | 篮球 | 三种排球 |
|------|------|------|---------|
| **字体适配** | `ScoreboardTemplate` → `ScoreboardTypographyResolver` 视口自适应 | 自定义适配（`mainScoreFontSize` 等视口算法） | `ScoreboardLayoutMetrics` 视口自适应 |
| **布局方向** | 强制横屏 | 强制横屏 | 强制横屏 |
| **3 列中宽** | ❌ 2 列 | 160/180/200pt 按屏幕宽 | ❌ 2 列 |
| **编辑模式** | 无特殊平板分支 | 无特殊分支 | 无特殊分支 |
| **沉浸模式** | ✅ | ✅ | ✅ |
| **显示设置** | ✅ | ✅ | ✅ |

> ⚠️ **足球共用旧模板**：足球使用 `ScoreboardTemplate`，该模板支持横竖屏自适应（`isLandscape` 判断），但 `FootballScoreboardView` 强制 `.lockOrientation(.landscape)`。

---

## 7. 从 Rally 视角看差异（排球 vs 乒/羽/匹）

三种排球虽然是 Rally 家族，但与乒/羽/匹存在明显功能落差：

| 差异项 | 乒/羽/匹 | 三种排球 | 差距 |
|--------|---------|---------|------|
| 语音播报 | ✅ Setup 可选 + 菜单切换 | ❌ 硬编码 false | 功能缺失 |
| 局数选择 | ✅ Setup 自定义（1/3/5/7 + 自定义） | ❌ 硬编码（室内5、沙排/气排3） | 灵活性不足 |
| 每局分数 | ✅ Setup 自定义（多个预设 + 自定义） | ❌ 硬编码（内置 rules） | 灵活性不足 |
| 完成模式 | ✅ bestOf / playAll | ❌ 硬编码 | 灵活性不足 |
| 单双打 | ✅ 支持 | ❌ 不适用 | — |
| 特有规则 | ✅ 双打发球轮换 | ❌ 排球场地方位逻辑 | — |
| Watch 联动 | ✅ | ✅ | 一致 |
| 菜单项 | ✅ 完整 | ✅ 完整 | 一致 |
| 记录机制 | ✅ ScoreboardRecord v4 | ✅ 同 | 一致 |

---

## 8. 从 ScoreCore 架构视角看层次差异

```
                    共享入口 (SportsSetupDialog / ScoreboardLaunchView)
                              |
            ┌─────────────────┼───────────────────┐
            │                 │                   │
      旧模板架构          新 Session 架构       新 Session 架构
      (Football)         (Basketball)        (Rally 家族)
            │                 │                   │
   ScoreboardTemplate  自定义 3 列布局     RallyScoreboardView
   + LineScoreViewModel  + BasketballSessionStore  + RallySessionStore
   + BaseScoreboardController  + BasketballMatchReducer  + RallyMatchReducer
            │                 │                   │
   LineScoreReducer     BasketballMatchEngine   RallyMatchEngine
   (S1 Line 族)         (S2 专项族)            (S1 Rally 族)
            │                 │                   │
  旧 Record 格式        ScoreboardRecord v4    ScoreboardRecord v4
  (字符串 ID)           (UUID Session)        (UUID Session)
```

### 关键技术债

| # | 问题 | 严重度 |
|---|------|--------|
| 1 | 足球使用旧模板架构，与篮球/排球/Rally 不统一（无 Session、无 draft 恢复、无 watch 联动） | P1 |
| 2 | 三种排球 Setup 不支持局数/分数自定义（硬编码），语音播报硬编码 false | P2 |
| 3 | 篮球 3x3 从 Setup 进入时 basketballMode 可能被错误设为 5v5 | P2 |
| 4 | 足球和篮球无语音播报（可考虑后续支持） | P3 |

---

## 9. 逐项对照总表

| 检查项 | 足球 | 篮球 5v5 | 篮球 3x3 | 室内排球 | 沙滩排球 | 气排球 |
|--------|------|----------|----------|---------|---------|--------|
| **Setup: 名称输入** | ✅ 主/客队 | ✅ 主/客队 | ✅ 主/客队 | ✅ 红/蓝方 | ✅ 红/蓝方 | ✅ 红/蓝方 |
| **Setup: 发球方选择** | ❌ | ❌ | ❌ | ✅ 排球图标 | ✅ 排球图标 | ✅ 排球图标 |
| **Setup: 局数** | ❌ | ❌ 内置 | ❌ 内置 | ❌ 硬编码 5 | ❌ 硬编码 3 | ❌ 硬编码 3 |
| **Setup: 分数** | ❌ | ❌ 内置 | ❌ 内置 | ❌ 硬编码 25 | ❌ 硬编码 21 | ❌ 硬编码 21 |
| **Setup: 规则选择** | ❌ | ✅ FIBA/NBA | ✅ FIBA/NBA | ❌ | ❌ | ❌ |
| **Setup: 自动换边** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Setup: 语音播报** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **布局: 基本模式** | 2列 | 3列(左+中+右) | 3列 | 2列 Rally | 2列 Rally | 2列 Rally |
| **布局: 队名显示** | ✅ 居中 | ✅ 面板顶部 | ✅ 面板顶部 | ✅ 居中 | ✅ 居中 | ✅ 居中 |
| **布局: 分数显示** | ✅ 大分 | ✅ 大分+犯规+暂停 | ✅ 大分+犯规+暂停 | ✅ 大分+局分 | ✅ 大分+局分 | ✅ 大分+局分 |
| **布局: 中心面板** | ❌ | ✅ 时钟+节次 | ✅ 时钟+节次 | ❌ | ❌ | ❌ |
| **布局: 发球指示** | ❌ | ❌ | ❌ | ✅ 三角 | ✅ 三角 | ✅ 三角 |
| **计时器** | ❌ | ✅ 比赛+进攻 | ✅ 比赛+进攻(12s) | ❌ | ❌ | ❌ |
| **犯规系统** | ❌ | ✅ team fouls | ✅ team fouls | ❌ | ❌ | ❌ |
| **暂停系统** | ❌ | ✅ FIBA/NBA | ✅ 1次 | ❌ | ❌ | ❌ |
| **节次/局间** | ❌ | ✅ 4节+加时 | ✅ 单节+21分 | ❌(Rally 局间) | ❌(Rally 局间) | ❌(Rally 局间) |
| **计分按钮** | [1] | [+1][+2][+3] | [+1][+2] | 点击+1 | 点击+1 | 点击+1 |
| **交互: 下滑-1分** | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **交互: 左滑撤销** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **交互: 长按菜单** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **编辑: 名称** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **编辑: 分数** | ✅ +/- | ✅ +/- 编辑面板 | ✅ +/- 编辑面板 | ✅ +/- | ✅ +/- | ✅ +/- |
| **编辑: 局分** | ❌ | ❌ | ❌ | ✅ +/- | ✅ +/- | ✅ +/- |
| **换边** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **沉浸模式** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **显示设置** | ✅ 字体调整 | ✅ 字体调整 | ✅ 字体调整 | ✅ 字体调整 | ✅ 字体调整 | ✅ 字体调整 |
| **截图** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **哨声** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **手表联动** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **语音播报** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **记录保存** | ✅ 旧格式 | ✅ v4 | ✅ v4 | ✅ v4 | ✅ v4 | ✅ v4 |
| **Draft 恢复** | ❌ 部分 | ✅ Session | ✅ Session | ✅ Session | ✅ Session | ✅ Session |
| **详细动作** | ❌ 字符串 | ✅ DetailedAction | ✅ DetailedAction | ✅ DetailedAction | ✅ DetailedAction | ✅ DetailedAction |
| **比赛结束弹窗** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **再来一场** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **分享** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
