# iOS 九球赛制验收（2026-10-25）

实现说明：[规则版本3](../../nine-ball-rule-presets-ios-2026-10-24.md)。本轮未提交或发布应用，已有工作区修改保留。

JifenCore 全量275项通过；iOS相关回归累计223个不同测试通过，重复运行不叠加。`verification.json` 记录各次结果包、人工流程和验证边界；各 `*-summary.json` 为Xcode直接导出的结果摘要。

## 实际模拟器截屏

以下由 Device Hub 原生截图功能保存，没有裁剪或合成。

- [iPad 简体设置](ipad-setup-zh.png)
- [iPhone 英文设置](iphone-setup-en.png)
- [第三犯后进入第2局：0比4、犯规清零](iphone-three-foul-en.png)
- [iPhone SE 数字键盘与固定底部操作](iphone-se-keyboard-zh.png)
- [iPhone SE 深色设置](iphone-se-setup-dark-zh.png)

## 生产 SwiftUI 视图渲染

以下由 iPad 模拟器内的原生布局测试渲染，采用繁体中文；规则页使用加长画布方便连续检查三段文案、绿色竖条与反馈入口。

- [四人长姓名](native-setup-folk-four-zh-Hant.png)
- [赛事自定义局数](native-setup-tournament-zh-Hant.png)
- [320pt 深色设置](native-setup-folk-dark-zh-Hant.png)
- [375pt 完整规则](native-rules-375-zh-Hant.png)
- [768pt 完整规则](native-rules-768-zh-Hant.png)

反馈复用原有开关与登录逻辑，标题传入 `#九球追分# `。人工验证了游客登录入口，没有提交线上反馈。未测试实体电视/AirPlay连接；投屏数据和原生显示回归已通过。新增简体、繁体、英文文案已提供，其余语言的新键暂用英文。
