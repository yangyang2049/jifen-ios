# iOS 计分板全量审查报告：乒/羽/网/匹 单双打

> 审查日期：2026-07-30
> 覆盖范围：乒乓球、羽毛球、网球、匹克球 单双打
> 审查维度：Setup → 页面布局 → 菜单项 → 记录/保存/展示 → 手机/平板差异 → 与鸿蒙/安卓对比

---

## 1. 架构总览

| 维度 | 乒乓球 | 羽毛球 | 匹克球 | 网球 |
|------|--------|--------|--------|------|
| **iOS UI 层** | `PingPongScoreboardView` | `BadmintonScoreboardView` | `PickleballScoreboardView` | `TennisScoreboardView` |
| **共享引擎** | ✅ RallyScoreboardView | ✅ RallyScoreboardView | ✅ RallyScoreboardView | ❌ 独立实现 |
| **Session Store** | `RallySessionStore` | `RallySessionStore` | `RallySessionStore` | `TennisSessionStore` |
| **Reducer** | `RallyMatchReducer` | `RallyMatchReducer` | `RallyMatchReducer` | `TennisMatchReducer` |
| **Setup 对话框** | 共用 `SportsSetupDialogView`（分支：pingpong/badminton/tennis/pickleball） |
| **菜单** | 共用 `MenuDialog`（所有运动菜单项一致，Rally 用 `menuItems` computed var） |
| **记录系统** | 共用 `ScoreboardRecord` v4 schema，`persistSnapshot()` 统一落库 |
| **手机/平板** | `Theme.usesPadLayout` 控制字号/间距；`ScoreboardLayoutMetrics` 视口自适应 |

---

## 2. Setup 流程逐项对比

### 2.1 单双打选择

| 项目 | iOS 实现 | 鸿蒙/安卓对比 |
|------|---------|--------------|
| 乒乓球 | Segmented Picker：单打/双打，默认单打 | ✅ 对齐 |
| 羽毛球 | 同上 | ✅ 对齐 |
| 网球 | 同上 | ✅ 对齐 |
| 匹克球 | 同上 | ✅ 对齐 |

### 2.2 名称输入

| 项目 | 单打 | 双打 |
|------|------|------|
| 乒乓球 | 左/右队名（"红方"/"蓝方" 占位符）+ 常用名称选择器 | 4 人名称（红A/红B/蓝A/蓝B）+ 双打队名自动拼接 |
| 羽毛球 | 同上 | 同上 |
| 网球 | 同上 | 同上 |
| 匹克球 | 同上 | 同上 |

### 2.3 发球方选择

| 项目 | 图标 | 默认 |
|------|------|------|
| 乒乓球 | `ic_pingpong_serve` | 左侧发球 |
| 羽毛球 | `ic_badminton_serve` | 左侧发球 |
| 匹克球 | `ic_pingpong_serve`（共用乒乓球图标） | 左侧发球 |
| 网球 | `ic_tennis_serve` | 左侧发球 |

### 2.4 赛制/局数设置

| 项目 | 默认局数 | 局数预设 | 每局分数预设 | 完成模式 |
|------|---------|---------|-------------|---------|
| 乒乓球 | 5 局 | 1/3/5/7 | 5/7/9/11/15/21（默认 11） | bestOf / playAll |
| 羽毛球 | 3 局 | 1/3/5/7 | 21/15/11（默认 21） | bestOf / playAll |
| 网球 | 3 盘 | 1/3/5/7 | 赛制=常规/抢七(7)/抢十(10)；每盘 4/6 局；40:40 占先/金球 | bestOf / playAll |
| 匹克球 | 3 局 | 1/3/5/7 | 目标分 11/15/21（默认 11）+ 11 分时可选上限 13/15 | bestOf / playAll |

### 2.5 特有设置项

| 项目 | 特有设置 | 备注 |
|------|---------|------|
| 乒乓球 | 自动换边 ✅、语音播报 ✅ | — |
| 羽毛球 | 自动换边 ✅、语音播报 ✅ | — |
| 网球 | 自动换边 ✅、语音播报 ✅ + **赛制（常规/抢七/抢十）** + **每盘局数（4/6）** + **盘内抢分（7/10）** + **40:40 规则（占先/金球）** | 网球独有 |
| 匹克球 | 自动换边 ✅、语音播报 ✅ + **目标分（11/15/21）** + **最高分上限（无/13/15）** + **每球得分开关** | 匹克球独有 |

---

## 3. 页面布局逐项对比

### 3.1 乒乓球

| 维度 | 单打 | 双打 |
|------|------|------|
| **布局模式** | 左右半分屏 + 中间发球三角指示器 | 左右半分屏 + 每侧上下两排名字 + 叠层分数 |
| **显示内容** | 上方队名 → 中间大分 → 下方局分 | 上排球员名 → 中间叠层大分+局分 → 下排球员名 |
| **发球指示** | `CenterLineServeIndicator` 居中三角 | 根据发球 slot 上下定位三角 + 匹克球发球序号胶囊 |
| **计分交互** | 点击 = +1 分；左滑 = 撤销；下滑 = -1 分 | 同上 + 双打闪烁动画 |
| **编辑模式** | 铅笔按钮 → 编辑队名 + 大分/局分 +/- | 铅笔按钮 → 编辑 4 人姓名 + 大分/局分 +/- |
| **自动换边** | 支持 sidesSwapped 翻转 | 支持 + 场地方位轮换 |
| **乒乓球特殊** | — | 每局开始需确认首发顺序（`pingPongDoublesOpeningOverlay`） |

### 3.2 羽毛球

| 维度 | 单打 | 双打 |
|------|------|------|
| **布局模式** | 同乒乓球单打 | 同乒乓球双打（共用 `RallyScoreboardView`） |
| **特殊差异** | 羽毛球默认 21 分制，`servingModel = .scorerServes` | 双打轮换 `BadmintonDoublesRotationState`（含 courtOrderSwapped） |
| **发球轮换** | 得分方发球 | 羽毛球双打发球规则：连续得分不换位，失分后换发 |

### 3.3 匹克球

| 维度 | 单打 | 双打 |
|------|------|------|
| **布局模式** | 同乒乓球单打 | 同乒乓球双打 |
| **发球指示** | 居中三角 | 三角 + 发球序号胶囊（#1 / #2） |
| **特殊差异** | `useRallyScoring` 可选（每球得分制） | `PickleballDoublesRotationState`：发球 #1/#2、每局 0-0-2 开局、搭档交换站位 |
| **得分规则** | winByTwo、scoreCap；默认传统发球得分 | 同上 |

### 3.4 网球

| 维度 | 单打 | 双打 |
|------|------|------|
| **布局模式** | **独立实现**：左右半分屏，队名 → 小分(15/30/40) → 局分+盘分列 | **独立实现**：左右半分屏，上下两排名字 → 叠层小分+局分+盘分 |
| **显示内容** | 队名(上) → 小分(中) → 局分+盘分(右列) | 球员名(上/下) → 叠层小分 → 局分+盘分 |
| **分数格��** | 15/30/40/AD 文字显示（`scoreDisplay`） | 同上 |
| **发球指示** | `CenterLineServeIndicator` | 根据 `tennisDoublesServerIsLeftScreen` + `tennisDoublesServerIsTopRow` 定位 |
| **抢七标识** | 橙色 "抢七"/"抢十" 胶囊标签 | 同上 |
| **计分交互** | 点击 = +1 分；双击 = -1 分（需开启）；左滑 = 撤销 | 同上 |
| **编辑模式** | 编辑队名 + 小分/局分/盘分（三级） | 编辑 4 人姓名 + 小分/局分/盘分 |

---

## 4. 菜单项对比

所有 4 个项目（单双打）共用 `ScoreboardMenuItemBuilder.defaultItems`，菜单项完全一致：

| 菜单项 | 分组 | 图标 | 二次确认 |
|--------|------|------|---------|
| 撤销 | match | arrow.uturn.backward | ❌ 直接执行 |
| 换边 | match | arrow.left.arrow.right | ✅ 绿色确认 |
| 重置 | match | arrow.counterclockwise | ✅ 绿色确认 |
| 结束比赛 | match | flag.checkered | ✅ 绿色确认 |
| 哨声 | tools | bell.fill | ❌ 直接执行 |
| 显示设置 | tools | "Aa" 文字 | — |
| 截图 | tools | camera.fill | — |
| 使用说明 | tools | "?" 文字 | — |
| 语音播报开关 | sync | speaker.wave.2/slash | ❌ 直接切换 |
| 手表同步项 | sync | 动态 | 根据链接状态 |

**网球额外差异**：网球 `TennisScoreboardView` 中语音播报在 sync 组（而非 rally 代码中），使用 `store.voiceAnnouncementEnabled`。

---

## 5. 记录/保存/展示对比

### 5.1 保存时机

| 场景 | 触发方式 |
|------|---------|
| 比赛中 | `scheduleDraftPersist` → 0.35s 防抖 → `persistSnapshot()` (draft 状态) |
| 比赛结束 | `state.finished == true` → 立即 `persistSnapshot()` (finished 状态) |
| 离开页面 | `onDisappear` → `persistSnapshot()` |
| 开始新比赛 | 旧比赛 `persistSnapshot` → 新比赛 `persistSnapshot` |
| 手表跟随模式 | `!isFollower` 时才写记录（防止重复） |

### 5.2 记录结构

```
ScoreboardRecord (v4)
├── sessionId: UUID
├── status: .draft / .finished
├── gameType: scoreCoreGameType
├── stateSnapshot: Data (完整状态序列化)
├── projectConfiguration: [Key: AnyCodable]
│   └── scoreCoreGameType, voiceAnnouncement
├── extraData: [String: AnyCodable]
├── participants: [SessionParticipant]
└── metadata: ScoreSessionMetadata
```

### 5.3 记录展示

- **记录列表**：`ScoreboardRecordsViewModel` 按日期分组（全部/计分/计时子Tab）
- **记录详情**：`ScoreboardRecordDetailPage`（fullScreenCover）
- **比赛结束弹窗**：`GameOverDialog` → "查看记录" / "再来一场" / "分享" / "退出"

### 5.4 各项目记录差异

| 项目 | 保存的比分 | 特殊性 |
|------|-----------|--------|
| 乒乓球/羽毛球/匹克球 | leftPoints, rightPoints, leftSets, rightSets | Rally 格式 |
| 网球 | leftPoints, rightPoints, leftGames, rightGames, leftSets, rightSets | 三级分数结构 |

---

## 6. 手机 vs 平板对比

所有计分板使用相同的自适配机制，**不区分 Phone/Pad 硬编码布局**：

| 维度 | 机制 | 手机效果 | 平板效果 |
|------|------|---------|---------|
| **字体大小** | `ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight:)` 视口自适应 | 约 144-200pt | 约 200-480pt |
| **间距** | `nameToMainSpacing` / `mainToSetSpacing` 视口自适应 | 约 24/8pt | 约 48/16pt |
| **编辑模式** | `Theme.usesPadLayout` 分支 | 紧凑布局 | 宽松布局(更大间距) |
| **菜单宽度** | `Theme.dialogWidth(role: .scoreboardMenu)` | 约 300-360pt | 约 560pt |
| **菜单卡片** | `isCompact` 判断（containerShortSide < 400） | compact 尺寸 | 标准尺寸 |
| **网球内列** | `usesPadLayout` 控制局分/盘分列尺寸 | setBoxSize 约 54pt | setBoxSize 约 72pt |
| **方向** | 均 `.lockOrientation(.landscape)` 强制横屏 | 横屏 | 横屏 |

### ⚠️ 已知风险

- **iPad 分屏**：5 处计分板用 `UIScreen.main.bounds`（Boxing/Archery/Simple/Doudizhu/MenuDialog），分屏模式下尺寸不准确
- **比赛详情页**：无 maxWidth 限制，iPad 全屏显示过宽

---

## 7. 与鸿蒙/安卓端对比（基于代码标注和文档推断）

### 7.1 架构对比

| 维度 | iOS | 鸿蒙/安卓 |
|------|-----|----------|
| 计分引擎 | JifenCore/ScoreCore（RallyMatchReducer + TennisMatchReducer） | Android Score Engine（同样架构模板） |
| 双打轮换 | DoublesRotation.swift（3 种模式） | 对应 Android DoublesRotation |
| Session 层 | ScoreSession 封装状态+事件 | 相同的 Session Runtime |
| 手表联动 | PhoneWatchLinkService (WatchConnectivity) | 鸿蒙分布式 / Android Wear |
| 语音播报 | RallyVoiceAnnouncementMapper | 对应语音系统 |

### 7.2 已知差异点

| 差异项 | iOS 现状 | 鸿蒙/安卓 |
|--------|---------|----------|
| **手表联动协议版本** | v1 | 鸿蒙实际 v3（文档过期为 v2） |
| **心跳/断连检测** | ❌ 缺失 | ✅ 有 |
| **CONTROL_INTERRUPTED** | ❌ 缺失 | ✅ 有 |
| **手动同步入口** | ❌ 缺失 | ✅ 有 |
| **NACK 立即补发** | ❌ 缺失 | ✅ 有 |
| **foosball 项目数** | iOS 多了 1 个（鸿蒙 2.7 缺 foosball） | 鸿蒙 2.9 才有 |
| **匹克球发球指示器** | 三角 + 序号胶囊 | 对齐 |
| **网球占先/金球** | 支持 advantage/no_ad | 对齐 |
| **布局方向** | iOS 强制横屏 | 鸿蒙支持横竖屏切换 |

### 7.3 各项目逐项对比

| 检查项 | 乒乓球单打 | 乒乓球双打 | 羽毛球单打 | 羽毛球双打 | 网球单打 | 网球双打 | 匹克球单打 | 匹克球双打 |
|--------|-----------|-----------|-----------|-----------|---------|---------|-----------|-----------|
| **Setup: 单双打选择** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Setup: 名称输入** | ✅ 红/蓝方 | ✅ 4人红/蓝A/B | ✅ 红/蓝方 | ✅ 4人红/蓝A/B | ✅ 红/蓝方 | ✅ 4人红/蓝A/B | ✅ 红/蓝方 | ✅ 4人红/蓝A/B |
| **Setup: 发球方选择** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Setup: 局数** | ✅ 5局默认 | ✅ 5局默认 | ✅ 3局默认 | ✅ 3局默认 | ✅ 3盘默认 | ✅ 3盘默认 | ✅ 3局默认 | ✅ 3局默认 |
| **Setup: 分数** | ✅ 11分默认 | ✅ 11分默认 | ✅ 21分默认 | ✅ 21分默认 | ✅ 抢七默认 | ✅ 抢七默认 | ✅ 11分默认 | ✅ 11分默认 |
| **Setup: 自动换边** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Setup: 语音播报** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Setup: 特有项** | — | — | — | — | ✅ 赛制/局数/抢分/金球 | ✅ 赛制/局数/抢分/金球 | ✅ 目标分/上限/每球得分 | ✅ 目标分/上限/每球得分 |
| **布局: 左右分屏** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **布局: 队名显示** | ✅ 居中 | ✅ 4人分上下 | ✅ 居中 | ✅ 4人分上下 | ✅ 居中 | ✅ 4人分上下 | ✅ 居中 | ✅ 4人分上下 |
| **布局: 分数显示** | ✅ 大分+局分 | ✅ 叠层大分+局分 | ✅ 大分+局分 | ✅ 叠层大分+局分 | ✅ 小分+局分+盘分 | ✅ 叠层小分+局分+盘分 | ✅ 大分+局分 | ✅ 叠层大分+局分 |
| **布局: 发球指示** | ✅ 三角 | ✅ 三角+slot定位 | ✅ 三角 | ✅ 三角+slot定位 | ✅ 三角 | ✅ 三角+slot定位 | ✅ 三角 | ✅ 三角+序号胶囊 |
| **布局: 关键分标识** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **交互: 点击+1分** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **交互: 左滑撤销** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **交互: 下滑-1分** | ✅ | ✅ | ✅ | ✅ | ❌ (双击-1) | ❌ (双击-1) | ✅ | ✅ |
| **交互: 双击-1分** | ❌ | ❌ | ❌ | ❌ | ✅ (需开启) | ✅ (需开启) | ❌ | ❌ |
| **交互: 长按菜单** | ✅ 0.55s | ✅ 0.55s | ✅ 0.55s | ✅ 0.55s | ✅ 0.55s | ✅ 0.55s | ✅ 0.55s | ✅ 0.55s |
| **编辑: 名称编辑** | ✅ | ✅ 4人独立 | ✅ | ✅ 4人独立 | ✅ | ✅ 4人独立 | ✅ | ✅ 4人独立 |
| **编辑: 分数编辑** | ✅ +/- | ✅ +/- | ✅ +/- | ✅ +/- | ✅ +/- 三级 | ✅ +/- 三级 | ✅ +/- | ✅ +/- |
| **编辑: 局分编辑** | ✅ +/- | ✅ +/- | ✅ +/- | ✅ +/- | ✅ +/- 局分+盘分 | ✅ +/- 局分+盘分 | ✅ +/- | ✅ +/- |
| **双打: 发球轮换** | — | ✅ 乒乓规则 | — | ✅ 羽毛规则 | — | ✅ 网球规则 | — | ✅ 匹克规则 |
| **双打: 闪烁动画** | — | ✅ 得分方闪烁 | — | ✅ 得分方闪烁 | — | ❌ | — | ✅ 得分方闪烁 |
| **特殊: 局间确认** | — | ✅ 确认首发 | — | ❌ | — | ❌ | — | ❌ |
| **特殊: 抢七标识** | — | — | — | — | ✅ | ✅ | — | — |
| **沉浸模式** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **显示设置** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **截图** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **哨声** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **手表联动** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **记录保存** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Draft 恢复** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **比赛结束弹窗** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **再来一场** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **分享** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 8. 发现的问题 & 差异汇总

### 8.1 交互差异（iOS 内部）

| # | 问题 | 涉及运动 | 严重度 |
|---|------|---------|--------|
| 1 | **Rally 类用下滑-1分，网球用双击-1分**，交互方式不统一 | 网球 vs 其他 | P2 |
| 2 | **网球双打缺少闪烁动画**（`flashSlots`/`runDoublesFlash` 在 Tennis 中未实现） | 网球双打 | P2 |
| 3 | **匹克球发球图标共用乒乓球图标**（`ic_pingpong_serve`） | 匹克球 | P3 |

### 8.2 与鸿蒙/安卓差异

| # | 问题 | 影响范围 | 严重度 |
|---|------|---------|--------|
| 1 | 手表联动协议 v1 vs v3，缺心跳/断连/CONTROL_INTERRUPTED/NACK | 所有联动场景 | P1 |
| 2 | iOS 强制横屏，鸿蒙支持横竖屏切换 | 所有运动 | P2 |
| 3 | iOS 多 1 个 foosball 项目（鸿蒙 2.7 没有） | 项目数量 | P3 |

### 8.3 iPad/平板问题

| # | 问题 | 文件 | 严重度 |
|---|------|------|--------|
| 1 | `UIScreen.main.bounds` 分屏不准确 | Boxing/Archery/Simple/Doudizhu/MenuDialog | P1 |
| 2 | 比赛详情页无 maxWidth | RecordDetailPage | P2 |

---

## 9. 结论

**整体评价**：iOS 乒乓球、羽毛球、匹克球 3 种 Rally 类运动通过共享 `RallyScoreboardView` 实现了高度一致的布局和交互。网球因计分模型特殊采用独立实现，功能完整。Setup 流程 4 项运动共用同一对话框。菜单、记录系统跨运动一致。

**核心问题**：
1. 手表联动协议落后于鸿蒙（v1 vs v3）
2. 网球与 Rally 类的减分交互不一致（双击 vs 下滑）
3. iPad 分屏场景下部分布局使用硬编码屏幕尺寸

**推荐优先修复**：P1 → 手表联动协议升级 + iPad 分屏 `UIScreen.main.bounds` 替换
