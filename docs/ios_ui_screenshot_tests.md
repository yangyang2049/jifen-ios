# iOS UI 截图测试

截图型 UI 测试参考 Android 的全项目矩阵和 HarmonyOS 的 `AllScoreboardsUiTest`：
每个可发起的计分项目都必须打开设置页、成功进入真实计分板，并分别保留 iPhone 和 iPad 截图。

## 覆盖范围

- 23 个计分项目：乒乓球、羽毛球、网球、匹克球、足球、篮球、三人篮球、排球、沙滩排球、气排球、射箭、拳击、台球、黑八、追分、斯诺克、斗地主、掼蛋、升级、UNO、桌上足球、简单计分、多人计分
- 9 个计时项目：围棋、象棋、国际象棋、国际跳棋、魔方、秒表、倒计时、篮球 24 秒、篮球 12 秒
- 10 个工具以及首页、记录、计分、计时、我的、常用数据、设置、预约球局等页面
- 每种设备至少 89 张截图

## 运行

```bash
./scripts/run_ui_screenshot_tests.sh
```

可通过环境变量替换模拟器：

```bash
IPHONE_DESTINATION='platform=iOS Simulator,name=iPhone Air,OS=26.5' \
IPAD_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' \
./scripts/run_ui_screenshot_tests.sh
```

脚本会从两份 `.xcresult` 中导出测试附件，结果统一写入
`UITestScreenshots-All/`。文件使用 `iPhone_` 或 `iPad_` 前缀，横屏计分板
与计时器会在附件生成时归一化为可直接审查的横向 PNG。
