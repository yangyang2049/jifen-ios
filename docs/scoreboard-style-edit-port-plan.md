# 计分板样式编辑移植计划（安卓 StyleEditOverlay → iOS）

> 对应需求 5：样式 1:1 抄安卓；计分设置里移除主题、字体。
> 参考实现：`jifen-android/app/src/main/java/com/douhua/jifen/screen/score/style/`（7 文件）+ `shared-model/.../ScoreboardStyleV2.kt`

## 一、两端现状对比

| 维度 | 安卓 V2 | iOS 现状 | 差距 |
|------|---------|----------|------|
| 数据模型 | `ScoreboardStyleProfileV2`：panels（slotKey+bgColor）+ elements（elementKey→每槽 textColors）+ fontSizeMultipliers map + serverIndicatorColor | `ScoreboardStyleProfileV2`（ScoreboardAppearance.swift L135-287）：**扁平** team0/1/center bg+textHex、autoContrast、themeCode | 缺逐元素 key、多人 player 槽位、字号 map 结构、发球指示器色 |
| 编辑形态 | 全屏编辑会话：TopControls + 浮动调色板 + 模态面板 + 点元素弹出面板 | 右侧侧滑面板（ScoreboardDisplaySettingsView L562-975） | 形态完全不同，需重写 UI |
| 会话控制 | Controller：draft/active/revision/save（只写本项目 profile，绝不写全局 theme/font） | TypographySession 已有 preview→apply/cancel；样式无 draft 会话 | 需统一 Controller |
| 能力注册表 | 26 个 gameType 白名单，elementKeys/slotKeys 按项目裁剪 | styleID 注册表（L367-373），无能力维度 | 需建 capabilities |
| 颜色数学 | WCAG 对比度、auto 黑白、色轮 HSV、最近 6 色 | autoTextHex（WCAG）已有 | 补 HSV/色轮/readable(3.0)/recent |
| 持久化 | DataStore 按 gameType + revision + 云房间 snapshot | PreferencesManager 按 styleID + scoreboardRevision（L349-355） | 结构接近，字段需升级 |
| 文字传播 | TextColorPropagationPrompt：确认后应用到同侧全部元素 | 无 | 新增 |
| 入口 | 白名单菜单项=「样式编辑」，非白名单=「显示设置」（仅字号） | 菜单「显示设置」→ 侧滑面板 | 按能力分叉 |

## 二、分阶段实施

### 阶段 1：模型升级（数据层，先行合入）
1. `ScoreboardStyleProfileV2` 增加（全部 `decodeIfPresent` + 默认值，旧 JSON 兼容）：
   - `panels: [StylePanel]`（slotKey: side_left/side_center/side_right + player_0...8）
   - `elements: [StyleElement]`（key: matchTitle/teamName/playerName/mainScore/setScore/gameScore/setGameScore → 每槽 TextColor(colorMode, color)）
   - `fontSizeMultipliers: [String: Float]`
   - `serverIndicatorColor`
   - 旧扁平字段（team0Hex 等）保留读取：首次访问时映射为 slot 结构；保存只写新结构 + 镜像旧字段（对齐安卓"绝不写全局 theme/font"）
2. 新建 `ScoreboardStyleEditCapabilities` 注册表（对齐安卓 26 项白名单：篮球/九球/UNO/多人/棋类排除）；`elementPanelTitle` 按项目裁剪（斯诺克"单杆得分"）
3. 归一化函数 `normalizeScoreboardStyleProfileV2`（清洗非法 key/色值/版本）
4. 颜色数学补齐：`hsvToHex/colorToHsv/colorWheelPointToHex/mixHex/styleIsReadableTextColor(3.0)/commitRecentColor(限6)`
5. 测试：模型迁移（旧→新映射）、归一化、对比度、能力注册表快照

### 阶段 2：编辑会话 Controller
1. `ScoreboardStyleEditorController`：`active/draft/revision/isEditing/isSaving`；`effective = draft ?? active`；`updateFromPreferences` 编辑中不覆盖；save 事务写本 styleID profile + revision++ + 推送渲染
2. 对接 `TypographySession`（字号 preview/apply 既有机制并入 draft）
3. BackHandler 逐级退出：自定义取色页 → 面板 → 取消会话

### 阶段 3：编辑器 UI（工作量主体，1:1 安卓）
复用现有 overlay 先例（`scoreboardDisplaySettingsOverlay` modifier / MenuDialog 的 ZStack 嵌入模式）：
1. `TopControls`：左退出 Close、右保存 Check
2. `PaletteEntry` 右下浮动工具条：收起为双色圆按钮，展开横滚（背景/发球/主题/字体/重置/收起），按 capabilities 条件显示、canReset 置灰
3. `ModalPanel`：全局面板居中、元素面板按 side 靠左/右；高度 ELEMENT 0.92 / FONT 0.62 / 其余 0.84；PanelHeader 绿色确认=关面板
4. 子面板：BackgroundPanel（目标分段 左/右/both/中 + 总览卡 + 20 预设色）、ThemePanel（6 主题 3 列）、FontPanel（4 字体带预览）、ElementPanel（字号 Slider + 自动对比 Switch + ColorPickerPanel：当前色卡/常用色/最近 6 色/自定义彩虹入口 + 对比度不足红字警示）、ServerIndicatorPanel
5. `CircularColorPickerPage`：HSV 色轮、拖动实时 onPreview/松手 onCommit、`colorToHsv` 反算标记位
6. 渲染元素编辑态高亮：`styleElementSelectable`（白框 + 可点开面板）
7. `TextColorPropagationPrompt`：关元素面板时若文字色有改动，5 秒提示"同步到同侧元素"，确认调 `applyTextColorToSameSide`
8. 首次进入使用引导（UserDefaults key `scoreboard_style_edit_usage_hint_v1_shown`）

### 阶段 4：入口切换 + 计分设置瘦身（需求 5 收口）
1. MenuDialog"显示设置"项按 capabilities 分叉：白名单 → `useStyleEditLabel`（"样式编辑"）打开新 overlay；非白名单保持现有侧滑面板（只留字号档位，对齐安卓 ScoreboardFontSizePanel 行为）
2. 白名单项目的侧滑面板中**移除主题、字体、字号、样式颜色分区**（样式编辑全走新 overlay）；保留显示时间 toggle 等
3. iOS 现有侧滑面板中安卓没有的项（最近颜色、自动高对比 toggle）随样式颜色分区一并迁入 ElementPanel/ColorPickerPanel

### 阶段 5：渲染接入 + 收尾
1. ScoreboardTemplate/Rally 等读新 profile：panelColor/textColorOr 走槽位化取色（含 matchTitle 跨左右槽联动、换边 slot 重映射——iOS `logicalIsLeft` 已有对应机制）
2. 发球指示器色应用（Rally/Tennis）
3. 云房间 snapshot 对齐（`DisplayStyleSnapshotV2` 等价物 + 展示端回退链 V2 槽位→participantId→旧色→主题默认）——若云同步模块本期不动可延后
4. 门禁：全项目编译 + 既有测试 + 新增模型测试

## 三、关键决策点（开工前确认）
1. **多人/棋类/篮球/九球/UNO 是否维持现状**（安卓同样排除）→ 建议维持
2. **斗地主独立编辑层**（安卓 DoudizhuScoreScreen 独立 StyleEditorLayer）→ iOS doudizhu 结构不同，建议第一期并入统一 overlay，三槽位用 capabilities 表达
3. **云房间样式同步**是否随本期做（依赖云同步链路联调状态）→ 建议延后，本地样式先落地
4. **旧扁平字段的读取兼容期**：建议永久保留读取、写入双写，待下个大版本再删

## 四、风险
- iOS `ScoreboardStyleProfileV2` 被多处直接读扁平字段（ScoreboardTemplate/Rally/Doudizhu…），阶段 5 需逐点切换，回归面大 → 用取色函数统一收敛访问
- 色轮手势（awaitEachGesture 预览/提交）在 SwiftUI 需 DragGesture + 状态机复刻，注意与 ScrollView 冲突
- 字号档位范围差异：iOS 0.8–1.5（iPhone）/0.7–1.5（iPad）与安卓 multiplier map 需对齐刻度（0.05 步长一致）
