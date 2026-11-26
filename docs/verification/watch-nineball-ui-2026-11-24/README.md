# 手表端九球（追分）3–4 人交互与开球人切换 · UI 走查

- 日期：2026-11-24（Asia/Shanghai）
- 入口：[`index.html`](index.html)（自包含：截图在 [`shots/`](shots/)，每张图标注「第几页 · 哪个页面 · 哪种状态」）
- 设备：Apple Watch Series 12 (46mm) 模拟器，watchOS 27.2，Xcode 27.2（Debug）

## 这次跑的是什么

新增手表 UI 测试 target `jifenWatch Watch AppUITests`（`WatchNineBallUITests`，共享 scheme `jifenWatchUITests`），用 XCUITest 在手表模拟器上真实点击/长按：

1. `testThreePlayerBreakerAndPayerFlows`：3 人局主流程——开球人徽标、事件面板「开球」徽章、普通胜/小金/让杆的一步式二级选人（付分人 / 继续击球人）、长按菜单切换开球人、大金 1 步直出、完赛确认与完赛遮罩。
2. `testFourPlayerQuadrantFlows`：4 人 2×2 棋盘下的同一套规则。
3. `testTwoPlayerSmallGoldUnavailableForBreaker`：2 人单人付分时开球人「小金」置灰、非开球人小金不弹二级选人。

三个用例全部通过（27 条断言），共 34 张截图。

复跑：

```bash
xcodebuild test -project jifen.xcodeproj -scheme jifenWatchUITests \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)' \
  -resultBundlePath /tmp/watch-nineball.xcresult
xcrun xcresulttool export attachments --path /tmp/watch-nineball.xcresult --output-path /tmp/watch-nineball-att
python3 scripts/generate_watch_nineball_ui_report.py /tmp/watch-nineball-att docs/verification/watch-nineball-ui-2026-11-24 verification
```

## 结论

功能行为与声明一致：开球徽标跟随 `breakerPlayer`、3–4 人支付/接杆 1 步选人且推荐人正确（上家 / 开球 / 下家）、大金仅开球人可点、2 人开球人小金置灰、二级面板计分后自动关闭。

界面问题见 [`index.html`](index.html) 的「发现的问题」一节（2 条 P2 + 3 条 P3 + 1 条观察），要点：

1. 「选择人数」弹层「4 人」按钮超出卡片底部，点下缘会关掉弹层。
2. 九球 3/4 人设置页首屏第 3（4）个选手名称行被底部「开始」按钮盖住。
3. 4 人棋盘的球杆徽标只有约 8×8pt，比 2 人的 10×10pt 难辨认。
4. 事件面板标题「开球」胶囊与姓名仅隔 4pt，视觉粘连。
5. 普通胜/小金结算后开球人自动轮转，界面无提示。
6. 2 人开球人「小金」置灰无文字解释（与手机端一致，属预期）。

## 工程侧改动

- 新增 target `jifenWatch Watch AppUITests`（watchOS UI-test bundle，宿主为 `jifenWatch Watch App`，源码目录 [`jifenWatch Watch AppUITests`](../../../jifenWatch%20Watch%20AppUITests/)）与共享 scheme [`jifenWatchUITests`](../../../jifen.xcodeproj/xcshareddata/xcschemes/jifenWatchUITests.xcscheme)。
- 同时补了共享 scheme [`jifenWatch Watch App`](../../../jifen.xcodeproj/xcshareddata/xcschemes/)：该 scheme 之前是 xcodebuild 为 target 自动生成的，一旦项目里出现多个共享 scheme 就会消失，`xcodebuild test -scheme 'jifenWatch Watch App'` 会直接报「does not contain a scheme」。补成共享 scheme 后手表单测仍是 **110 / 110 通过**。
- 报告生成器：[`scripts/generate_watch_nineball_ui_report.py`](../../../scripts/generate_watch_nineball_ui_report.py)。

## 原始证据

测试批次：`~/Library/Developer/jifen-ios-test-artifacts/runs/20261124T083548388287Z-watch-nineball-ui-final/`（xcresult + 运行日志），受 14 天保留策略管理，过期自动清理。本目录只保留报告与选出的 34 张截图。