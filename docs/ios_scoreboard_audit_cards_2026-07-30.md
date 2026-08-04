# iOS 计分板全量审查报告：掼蛋 / 升级 / 斗地主 / UNO

> 审查日期：2026-07-30
> 覆盖范围：掼蛋 (guandan) · 升级 (shengji) · 斗地主 (doudizhu) · UNO (uno)

---

## 1. 架构总览

| 维度 | 掼蛋 | 升级 | 斗地主 | UNO |
|------|:---:|:---:|:---:|:---:|
| **架构代** | Scaffold+直驱 | Scaffold+直驱 | 完全自定义 | 共享 MultiScore |
| **UI 容器** | `TwoSideScoreboardScaffold` | `TwoSideScoreboardScaffold` | 自定义 3 列视图 | `MultiScoreboardView` |
| **Store / Session** | ❌ 无（直接 State） | ❌ 无（直接 State） | ❌ 无（直接 State） | ❌ 无（直接 State） |
| **Reducer** | `GuandanSessionReducer` | `ShengjiTierReducer` | ❌ 无（手动加减分） | ❌ 无（手动加减分） |
| **ScoreCore 族** | S4/掼蛋 | S4/升级 | ❌ 不经过 ScoreCore | ❌ 不经过 ScoreCore |
| **Setup 对话框** | `MultiScoreSetupDialogView` | `MultiScoreSetupDialogView` | `MultiScoreSetupDialogView` | `MultiScoreSetupDialogView` |
| **参与人数** | 2 队（红/蓝） | 2 队（左/右） | 固定 3 人 | 2-10 人 |
| **记录 ID 格式** | `"guandan_\(timestamp)"` | `"shengji_\(timestamp)"` | `"doudizhu_\(timestamp)"` | `"uno_\(timestamp)"` |
| **手表联动** | ❌ | ❌ | ❌ | ❌ |
| **语音播报** | ❌ | ❌ | ❌ | ❌ |

---

## 2. Setup 流程逐项对比

四种棋牌全部使用 **`MultiScoreSetupDialogView`**（共用对话框，按 `layoutMode` 分支）：

| Setup 项 | 掼蛋 | 升级 | 斗地主 | UNO |
|----------|------|------|--------|-----|
| **layoutMode** | `.twoTeam` | `.twoTeam` | `.doudizhu` | `.uno` |
| **名称输入** | 2 队名（红/蓝） | 2 队名（左/右） | 3 人名（刘备/关羽/张飞） | 2-10 人名（玩家1~N） |
| **人数选择** | 固定 2 队 | 固定 2 队 | 固定 3 人 | ✅ 2-10 人 Segmented |
| **目标分数** | ❌ | ❌ | ❌ | ✅ 默认 500 |
| **特有设置** | ✅ 过A条件(不能末游/双上) + 三A开关 + 三A回退等级(2-K) | ❌ 无 | ❌ 无 | ❌ 无 |
| **自定义加减分** | ❌ | ❌ | ❌ | ✅ 开关（仅 multiScore 模式） |

### 掼蛋特有设置详情

| 设置项 | 可选值 | 默认 |
|--------|--------|------|
| 过 A 条件 | 不能末游(+2/3级) / 双上(+3级) | 不能末游 |
| 三 A | 开关 | 关 |
| 三 A 不过回退到 | 2 / 3 / 4 / 5 / 6 / 7 / 8 / 9 / 10 / J / Q / K | 2 |

---

## 3. 页面布局逐项对比

### 3.1 掼蛋

| 维度 | 描述 |
|------|------|
| **布局模式** | `TwoSideScoreboardScaffold`：左右 2 列 + 中间发球三角 + 底部操作栏 |
| **显示内容** | 队名(上) → 等级(中，如 "2"/"A"/"A2") → 无 detail |
| **发球指示** | ✅ `CenterLineServeIndicator`：上轮胜方三角指示 |
| **底部操作** | `panelAccessory`：左右各有 [+1] [+2] [+3] 按钮 |
| **等级系统** | 2→3→4→5→6→7→8→9→10→J→Q→K→A（三A模式：A1/A2/A3） |
| **回合机制** | 点击按钮→`beginRoundResult(winner:)`→`applyRoundSettlement(step:)` |
| **交互** | 点击 +N 级 / 编辑模式 +/- 调级 / 左滑撤销 / 长按菜单 |
| **级牌回绕** | A→+1 弹出确认框："级牌回到 2？" |
| **编辑模式** | 铅笔→编辑队名+直接输入等级（支持 A1/A2/A3） |
| **换边** | ❌ 无 |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ |

### 3.2 升级

| 维度 | 描述 |
|------|------|
| **布局模��** | `TwoSideScoreboardScaffold`：左右 2 列 + 中间庄家三角 + 底部操作栏 |
| **显示内容** | 队名 → 当前等级（2/3/.../J/Q/K/A） |
| **庄家指示** | ✅ `CenterLineServeIndicator`：`state.dealer` 指向庄家侧 |
| **底部操作** | `panelAccessory`：**庄未定** → [抢庄]；**庄已定** → 胜方 [上台] / [+1] [+2] [+3] |
| **等级系统** | 2/3/4/5/6/7/8/9/10/J/Q/K/A（13级） |
| **回合机制** | `resolveRound(winner:delta:)`，上台/升级一体化 |
| **编辑模式** | 铅笔→编辑队名+等级 +/- |
| **换边** | ❌ 无 |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ |
| **LocalSync** | ✅ `LocalScoreboardSyncCoordinator` 注册（无 Watch 联动） |

### 3.3 斗地主

| 维度 | 描述 |
|------|------|
| **布局模式** | 完全自定义：3 列 grid（刘备/关羽/张飞），3 人固定 |
| **颜色方案** | 主题色（`appearance.theme.palette`） |
| **显示内容** | 玩家名(上) → 得分(中) → 排名/无 detail |
| **计分面板** | ✅ **独立计分面板**：底分(1/2/3) × 倍数(1/2/4/8/16/32) = 实际加减分 + 胜方选择(checkbox) |
| **交互** | 点击玩家 → 弹出计分面板 / 左滑撤销 / 长按菜单 |
| **编辑模式** | 铅笔→单独编辑姓名+分数 textfield |
| **换边** | ❌ 不适用（3 人） |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ 字体/主题 |
| **特有交互** | 双击玩家 = -1 分（直接扣减） |

### 3.4 UNO

| 维度 | 描述 |
|------|------|
| **布局模式** | `MultiScoreboardView`：多人网格，`ScoreboardPlayerGridLayout.multiRows()` |
| **颜色方案** | 12 色 HOS 对齐色板（红/蓝/绿/橙/紫/粉/青/桔/靛/柠/天蓝/玫红） |
| **网格自适应** | 2人=2行 / 3人=3行 / 4人=2×2 / 5-10人=自适应行列 |
| **显示内容** | 玩家名 → 得分 → 目标分进度 |
| **目标分** | 默认 500，达到目标分时高亮胜者 |
| **UNO 回合面板** | ✅ **专属面板**：选胜者 + **+20(Wild)**、**+40(Wild Draw 4)** 按钮 + 数字牌总分手动输入 |
| **交互** | 单击 +1 / 双击 -1 / 左滑撤销 / 长按菜单 / 自定义加减分开关 |
| **编辑模式** | 点击玩家名 → 单独编辑 |
| **横竖屏** | ✅ 设置中切换横屏/竖屏布局（uno_use_landscape_layout） |
| **沉浸模式** | ✅ |
| **显示设置** | ✅ |

---

## 4. 菜单项对比

### 4.1 掼蛋 / 升级

通过 `TwoSideScoreboardScaffold` 默认菜单：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |

> 掼蛋/升级无换边菜单项（`onExchange: nil`）

### 4.2 斗地主

自定义菜单（通过 buildDefaultMenuItems）：

| 菜单项 | 分组 | 二次确认 |
|--------|------|---------|
| 撤销 | match | ❌ |
| 重置 | match | ✅ |
| 结束比赛 | match | ✅ |
| 哨声 | tools | ❌ |
| 显示设置 | tools | — |
| 截图 | tools | — |
| 使用说明 | tools | — |

### 4.3 UNO

通过 `MultiScoreboardView` 菜单：

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

---

## 5. 记录/保存/展示对比

四种棋牌**全部使用自编码的旧格式**（String ID + JSON stateSnapshot），不经过 SessionArchiveRepository：

### 共性

| 维度 | 四种棋牌 |
|------|---------|
| **记录 ID** | `"游戏名_\(timestamp)"` 字符串拼接 |
| **保存方式** | 各 View 内 `saveRecord()` 自定义函数 |
| **Draft 数据** | `stateSnapshot = JSONEncoder.encode(state)` |
| **Draft 恢复** | 从 `ScoreboardRecordManager` 取 draft → 解 JSON 恢复 |
| **Session 持久化** | ❌ 全部无 |
| **详细动作** | ⚠️ 部分有（actionLog 字符串数组） |

### 各项目差异

| 项目 | JSON 格式 | extraData | 特有字段 |
|------|----------|-----------|---------|
| 掼蛋 | `GuandanMatchState` | schemaVersion:3, guandanTripleA, passACondition, fallbackRank | 等级数据用 rankDisplayScore 转数值 |
| 升级 | `ShengjiTierState` | — | 等级 int index 存储 |
| 斗地主 | `DoudizhuDraftSnapshot` (names+scores+finished) | playerNames | 3 人分数 + 姓名数组 |
| UNO | 自定义 saveMultiScoreRecord | playerNames, targetScore, gameType:uno | 多人分数数组 |

---

## 6. 架构代归类

四种棋牌全部不经过 `ScoreSession` / `SessionArchiveRepository`，属于**直接 State 驱动**的模式，但内部又有梯度：

```
              Setup: MultiScoreSetupDialogView (共用)
                           |
        ┌──────────────────┼──────────────────┐
        │                  │                  │
  Scaffold+Reducer    完全自定义         共享 MultiScore
  (掼蛋·升级)         (斗地主)            (UNO)
        │                  │                  │
  SpecializedScoreboard   自定义 3 列      MultiScoreboardView
  Scaffold                 + 计分面板       + UNO 回合面板
        │                  │                  │
  GuandanSessionReducer    无 Reducer        无 Reducer
  ShengjiTierReducer       纯手动加减         纯手动加减
  (S4 棋牌族)             (无 ScoreCore)     (无 ScoreCore)
```

### 架构梯度

| 梯度 | 项目 | 特征 |
|------|------|------|
| **高** (有 Reducer) | 掼蛋、升级 | 有 ScoreCore Reducer，规则严谨（等级系统、庄家/过A逻辑） |
| **中** (有 Scaffold) | — | — |
| **低** (纯手动) | 斗地主 | 自定义 UI，底分×倍数计算，无 Reducer |
| **低** (纯手动) | UNO | 共享 MultiScoreboardView，+特殊牌面板 |

---

## 7. 逐项对照总表

| 检查项 | 掼蛋 | 升级 | 斗地主 | UNO |
|--------|:---:|:---:|:---:|:---:|
| **Setup: 对话框** | MultiScoreSetup | MultiScoreSetup | MultiScoreSetup | MultiScoreSetup |
| **Setup: 名称输入** | ✅ 2队名 | ✅ 2队名 | ✅ 3人名(刘关张) | ✅ 2-10人名 |
| **Setup: 人数选择** | 固定2队 | 固定2队 | 固定3人 | ✅ 2-10人 |
| **Setup: 目标分** | ❌ | ❌ | ❌ | ✅ 默认500 |
| **Setup: 特有设置** | ✅ 过A/三A/回退 | ❌ | ❌ | ❌ |
| **布局: 容器** | Scaffold | Scaffold | 自定义3列 | MultiScoreboardView |
| **布局: 列数** | 2列 | 2列 | 3列 | 2-10人网格 |
| **布局: 发球/庄家指示** | ✅ 上轮胜方 | ✅ dealer三角 | ❌ | ❌ |
| **布局: 底部操作** | ✅ [+1][+2][+3] | ✅ [抢庄/上台][+1][+2][+3] | ❌ (点击弹出面板) | ❌ (点击计分) |
| **计分方式** | 点击+N级 | 点击+N级 | 底分×倍数面板 | 单击+1/UNO面板 |
| **计分面板/回合** | ❌ (默认框架) | ❌ (默认框架) | ✅ 底分+倍数+胜方 | ✅ UNO回合面板 |
| **特殊规则** | 等级2→A, 三A | 庄家, 抢庄/上台 | 底分×倍数, 全选胜方 | +20/+40/+50 |
| **交互: 双击-1** | ❌ | ❌ | ✅ 直接扣减 | ✅ 直接扣减 |
| **交互: 左滑撤销** | ✅ | ✅ | ✅ | ✅ |
| **交互: 长按菜单** | ✅ | ✅ | ✅ | ✅ |
| **编辑: 名称** | ✅ | ✅ | ✅ 独立编辑 | ✅ 独立编辑 |
| **编辑: 分数** | ✅ +/- 等级 | ✅ +/- 等级 | ✅ textfield | ✅ textfield |
| **换边** | ❌ | ❌ | ❌ | ❌ |
| **沉浸模式** | ✅ | ✅ | ✅ | ✅ |
| **显示设置** | ✅ | ✅ | ✅ | ✅ |
| **截图** | ✅ | ✅ | ✅ | ✅ |
| **哨声** | ✅ | ✅ | ✅ | ✅ |
| **横竖屏切换** | ❌ | ❌ | ❌ | ✅ 设置项 |
| **手表联动** | ❌ | ❌ | ❌ | ❌ |
| **语音播报** | ❌ | ❌ | ❌ | ❌ |
| **ScoreCore Reducer** | ✅ S4 | ✅ S4 | ❌ | ❌ |
| **记录保存** | 自编码 JSON | 自编码 JSON | 自编码 JSON | 自编码 JSON |
| **Session 持久化** | ❌ | ❌ | ❌ | ❌ |
| **Draft 恢复** | ✅ | ✅ | ✅ | ✅ |
| **比赛结束弹窗** | ✅ | ✅ | ✅ | ✅ |
| **再来一场** | ✅ | ✅ | ✅ | ✅ |
| **分享** | ✅ | ✅ | ✅ | ✅ |
