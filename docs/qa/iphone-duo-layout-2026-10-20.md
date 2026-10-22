# iPhone Duo 首轮布局预适配

日期：2026-10-20。范围：外屏 compact、展开内屏 regular 的首页、目录与开赛弹窗，及实时切换检查。

## 独立工作区

- 分支：`codex/iphone-duo-layout`
- 工作目录：`/Users/yangyang/.codex/worktrees/iphone-duo-layout/jifen-ios`
- 起点：原 `3.3` 的 `66c2cc55`。
- `bea27952` 是适配前源码的隔离快照，包含原工作区已有修改；本轮布局提交从该快照之后计算。
- 原工作区仍在 `3.3`；本任务的源码修改位于独立工作区。

## 官方适配依据

Apple [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) 明确以外屏 compact width、内屏 regular width 两种基础布局覆盖不同姿态。结合当前可用空间、布局边距和 safe area 调整内容，不按设备方向为每种姿态单独设计。

[官方适配步骤](https://developer.apple.com/iphone-duo/prepare/) 要求避免用 `UIDevice.current.orientation`、`interfaceOrientation` 决定布局，并避免用设备 idiom 代替当前窗口空间。

本轮布局读取 SwiftUI `horizontalSizeClass` 与 `GeometryReader`。没有新增自动旋转策略；`jifenApp.swift`、`MainTabView.swift` 与本轮快照一致。现有运动和工具的方向锁定沿用原逻辑。

## 环境

- Xcode 27.1，27A9275；iOS Simulator SDK 27.1。
- 已通过 Xcode 官方命令安装 iOS 27.1、24A94425、arm64 运行时，下载约 7.85 GB。
- 开始时磁盘约剩 19 GiB；安装和截图后复查仍有约 76 GiB，可继续使用模拟器。
- 本任务没有清理原有模拟器或其他项目数据。
- 原生 Duo 模拟器：`Jifen iPhone Duo layout 20261020`，设备 ID `57F91B1F-92B7-4948-90FE-936BBE191802`。
- 普通 iPhone 对照：本任务创建的 iPhone 17 Pro / iOS 26.5。

## 代码范围

| 文件 | 修改 |
| --- | --- |
| `Theme.swift` | 按当前 size class 提供边距；按内容宽度计算 2/3/4 列；开赛弹窗支持显式宽窗参数。 |
| `HomeTab.swift` | regular 且可用宽度足够时进入双栏；开赛及工具呈现使用当前窗口布局上下文。 |
| `ScoreboardTab.swift`、`TimerTab.swift`、`ToolsTab.swift` | 当前窗口决定列数、边距和最大内容宽度，运行中可更新。 |
| `CenteredSetupDialogContainer.swift` | regular 开赛弹窗目标宽 480pt，compact 为 340pt，并按可用空间夹紧。 |
| `RallyScoreboardView.swift` | 双打比分添加不可见的自动化标识，验证切换后比分保留。 |
| `FullAppScreenshotUITests.swift` | 外屏/内屏截图、实时切换检查；用标签唯一标识避免同名筛选控件误命中。 |
| `scripts/capture_duo_layout.py` | 从模拟器明确指定内外屏采集实际像素，并保存截图元数据。 |

未改全局 `Theme.usesPadLayout`、比赛逻辑或样式配置。横竖屏仍共用同一份样式。

## 截图与复查

[14 张截图总览](../../artifacts/iphone-duo-layout-20261020/overview.jpg)。完整 PNG 位于同级 `folded/` 和 `unfolded/`。

- 外屏实测截图 1398 × 2034 像素，内屏截图 2853 × 2007 像素。
- 展开首页可排成双栏；计分、计时及工具目录按可用宽度扩为四列。
- 开赛弹窗在两种屏幕均保留取消、开始操作。
- 系统 TabView 自动适配侧边标签栏；页面内容由系统安全区及当前布局约束避让。
- 当前 Xcode 的 XCTest 截图接口在内屏返回黑图，改用 `simctl io --display=… screenshot`；没有用黑图作为视觉验收依据。
- JSON 中的 `width` / `height` 是 XCTest 的 app.frame 坐标；`pixels` 为实际截图像素。两者的轴顺序可能不同，不以此推断产品方向或姿态。

## 验证记录

- 适配前基线、首轮布局，以及撤回方向策略后的 `build-for-testing` 均通过。
- 最终普通 iPhone 单元回归：`ScoreboardCatalogTests` 与 `LocalScoreboardDisplayStateTests` 128 项通过、0 失败、0 跳过。结果：`build/duo/final-compact-regular-unit.xcresult`。
- 原生 Duo 外屏和内屏的七页截图流程均通过；已修正同名控件误命中，并增加秒表入口断言确认采到真正的计时页。
- 实时开赛草稿：展开、合拢后双打模式、四个球员输入框及开始按钮保留。
- 实时比分：展开、合拢后均保留 3:0，菜单在过渡完成后可点击，整项测试通过。结果：`build/duo/host-live-1792481414.xcresult`。
- 实时切换截图位于 `artifacts/iphone-duo-layout-20261020/live/`，共六张。菜单检查等待布局过渡完成后进行，避免在中间帧直接断言。

最终两组截图结果：`build/duo/host-folded-1792482003.xcresult`、`build/duo/host-unfolded-1792481907.xcresult`。构建日志：`build/duo/tab-identifier-build.log`。

截图使用当时工作区：`HomeTab.swift` 的小组区顺序、`HomeModels.swift` 的快速开始卡片策略及 `MainFlowUITests.swift` 的相应断言存在并行编辑，已原样保留，未计入本轮 Duo 改动。

## 复现

先构建到 `build/duo/DerivedData`，在 Device Hub 选择本任务 Duo 设备并切换 Closed / Open，再分别运行：

```sh
python3 scripts/capture_duo_layout.py 57F91B1F-92B7-4948-90FE-936BBE191802 folded
python3 scripts/capture_duo_layout.py 57F91B1F-92B7-4948-90FE-936BBE191802 unfolded
python3 scripts/capture_duo_layout.py 57F91B1F-92B7-4948-90FE-936BBE191802 live --live
```

实时测试在日志出现 `DUO_RESIZE_READY` 时依次展开、合拢、展开、合拢。

## 覆盖边界

本轮是根页面和通用开赛弹窗的模拟器预适配；尚未全量审核所有运动、账号会员、小组及工具二级页，也未验证半展开折痕区域、Split View 和真机。本报告不代表全项目 Duo 适配或发版回归已完成。
