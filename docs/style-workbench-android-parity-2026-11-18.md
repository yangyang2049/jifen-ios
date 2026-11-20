# iOS 样式工作台对齐 Android 最新版（2026-11-18）

本轮把 iOS 的样式编辑面板补齐到 Android 最新版（Android 侧为 `b5c1133e` + 未提交的「限免」角标）。

## 起点

iOS 的最后一次样式面板改动是 `c4e9ef2e`（2026-11-13），与鸿蒙改造前停在同一基线：骨架、tab、分栏、倍率字号、名称字体、自动色、保存前对比度复查都已具备，但缺下面 7 项。

## 本轮补齐

| # | 项 | 改动 |
| --- | --- | --- |
| 1 | 主题卡「限免」角标 | 新增 `jifen/Features/Scoreboard/Shared/ThemeFreeBadge.swift`：36pt 斜切三角、促销橙 `#FF6B35`、45° 文字按内切圆自动缩字号、读屏「限时免费」；挂在背景图片主题格右上角并由卡片圆角裁切 |
| 2 | 自由编辑的选元素提示 | 画布下方新增「点击文字或发球图标进行编辑」（仅自由编辑且非全屏预览） |
| 3 | 色板度量与选中勾 | 色点 34（不再 38/32）、间距 9（不再 8/5）、标题 13 + `#D7DCE5`；选中色点内加勾，勾色按 `isReadableTextColor` 取黑/白 |
| 4 | 背景页结构 | 分段按钮 + 左右概览卡 + 「左右同色」整段删除，改为左/中/右 chips + 一块色板（与 Android 一致），连带删掉两个无引用私有视图 |
| 5 | 主题格尺寸 | 缩略图 40×22.5、名称 11pt；当前主题卡 48×27、名称 14pt；当前卡改为 `#253A30` 底 + 绿色 65% 描边 |
| 6 | 照片页 | 新增来源（默认图片/自定义图片）、非 16:9 的居中裁切提示（`backdrop.image.size`，9% 容差）、滑块两端百分比标签 |
| 7 | 实时红字对比度警告 | 删除，只在保存前复查（与 Android 一致） |

文案口径同步：`scoreboard_style_font_size` → 文字大小（双方）、`style_workbench_server_visible` → 显示发球指示、`style_server_indicator` → 发球指示；「当前主题 / 可选主题 / 样式」分组标题改为 13pt Medium + `#D7DCE5`。

新增 6 条文案写入 47 个已承载样式文案的语言文件（en、zh-Hans、zh-Hant 为真翻译，其余先用英文兜底）。

## 仍未对齐（刻意保留）

1. 元素 chips 文案沿用 iOS 的逐元素说法（队伍名称／主比分／盘分／局分／盘局分），Android 用更短的「名称／大分／局分／盘分／小分」——iOS 的 chips 只在窄屏横滑，长文案仍可读。
2. 照片页色板标题沿用 `style_background_color`（背景颜色），Android 为「背景色」；该键同时被计分板背景设置页使用，未改。
3. 照片页没有单独的读取进度条（Android 有线性进度），iOS 的 PhotosPicker 走系统相册选择，短暂无反馈。

## 验证

- `xcodebuild -project jifen.xcodeproj -scheme jifen -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**。
- 已把构建产物安装到已启动的模拟器「Tactical Release iPhone SE」并成功启动（`simctl launch` PID 71847），启动截图存在 `qa-screenshots/ios-style-workbench-2026-11-18/01-launch.png`。
- **未做**：样式面板逐项视觉核对、横竖屏截图、UI 自动化。截图与 UI 测试需要人工或真机确认。
