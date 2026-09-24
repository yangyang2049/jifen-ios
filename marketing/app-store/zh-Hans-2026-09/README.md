# 全能计分器 · 简体中文 App Store 截图测试

本目录有两套 iPhone 截图方案，每套 5 张。`A-score-first` 以比赛中清楚可见的大比分开场；`B-start-first` 以快速开赛开场。两套都使用真实 App 界面，文案放在截图外侧。`preview.html` 和 `overview.png` 可用于并排审稿。

## 输出

- `A-score-first/01.png` 至 `05.png`：比赛现场优先。
- `B-start-first/01.png` 至 `05.png`：快速开赛优先。
- 每张均为 1320 × 2868、无透明通道的 PNG，对应 Apple 接受的 6.9 英寸 iPhone 竖屏尺寸。
- `render.mjs` 生成可编辑 HTML 和 PNG。修改文案或样式后，在本目录运行 `node render.mjs`。

## 图源与准确性

| 源文件 | 来源 | 使用位置 |
| --- | --- | --- |
| `sources/home.png` | 2026-09-23 本地 Debug 构建，iPhone 17 Pro Max 模拟器，简体中文 | A2、B1 |
| `sources/record_detail.png` | 同一构建的测试比赛记录，比分与趋势由 App 实际渲染 | A5、B5 |
| `sources/pingpong_live.png` | 同一构建的真实显示端渲染快照 | A1、B2 |
| `sources/sports.png` | 同一构建的计分目录 UI 测试截图 | B3 |
| `sources/badminton_setup.png` | 同一构建的羽毛球赛前设置 UI 测试截图 | A3 |
| `sources/basketball.png`、`sources/go_timer.png` | 同一构建的篮球计分与围棋计时 UI 测试截图 | A4、B4 |

所有画面都来自 2026-09-23 的本地当前构建。记录页和显示端为 Debug 测试数据，比分与界面由 App 实际渲染，不是真实用户比赛。旧截图中曾有的篮球 24 秒计时已不在当前 iOS 项目列表，本方案不展示该功能。正式上传前仍需核对待审核 App 版本与本地构建一致。

项目列表、羽毛球设置、篮球计分和围棋计时可通过 `FullAppScreenshotUITests/testCaptureAppStoreSourceScreenshots` 再次抓取；测试生成的附件在 `.xcresult` 中。首张的比分画面使用 `-DisplaySnapshotFixture pingpong_live`，记录页使用 `-UITestRecordFixtures -UITestRecordDetail pingpong`。

## App Store Connect 测试方案

1. 保留当前产品页作为对照组。将 A、B 分别建立为两个“产品页优化”测试方案，仅替换简体中文的 iPhone 截图，其他元素先保持一致。
2. 比较“先看到清晰比分”和“先看到快速开赛”哪个更能促成首次下载。重点查看产品页转化率、相对提升和置信度；流量有限时可先只测 A，以免样本被两套方案分散。
3. 新截图作为测试元数据提交 App Review。审核通过后再开始测试；至少等 Apple 标记达到 90% 置信度的结果，再决定是否应用胜出的方案。未改动的 iPad 截图可沿用原始产品页。

Apple 建议前 1–3 张图就呈现 App 的主要价值；竖屏截图也可能出现在搜索结果。产品页优化可同时测试最多三个方案，并支持按语言本地化。参考：[产品页截图建议](https://developer.apple.com/app-store/product-page/)、[截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)、[产品页优化](https://developer.apple.com/app-store/product-page-optimization/)、[测试方案设置](https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/configure-test-treatments)。类别文案参考了 [Keep](https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580) 和 [咕咚](https://apps.apple.com/cn/app/%E5%92%95%E5%92%9A-%E8%B7%91%E6%AD%A5%E9%AA%91%E8%A1%8C%E5%81%A5%E8%B5%B0%E8%AE%AD%E7%BB%83%E9%A9%AC%E6%8B%89%E6%9D%BE%E8%B5%9B%E4%BA%8B%E6%B4%BB%E5%8A%A8/id453480684) 的运动场景表达，没有使用其他应用的图像素材。
