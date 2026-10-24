# 微信登录与绑定提醒 · 2026-10-24

## 本次规则

- 微信登录入口只跟随简体／繁体中文，不以安装检测控制显隐。点击后先检查是否安装；缺失时直接提示“未安装微信，请安装微信后重试”。
- 已安装但未勾选协议：只提示用户阅读并手动勾选，等待再次点击登录；不会代为同意或自动跳转。已同意时一次点击发起授权。
- iOS 和鸿蒙的微信授权等待上限均为 30 秒，适用于登录和绑定。无需判断微信内部是否已经登录。
- 绑定建议改为 Bottom Sheet：顶部品牌图标，标题两行居中，说明居中，下方“立即绑定／稍后再说”。iOS 文案保持已确认版本；鸿蒙的跨平台说明对应 iOS、安卓、网页端。
- iOS：服务端确认当前 Apple 会话、简体／繁体中文、尚未绑定且允许绑定时，自动提示。
- 鸿蒙：服务端确认当前华为原生会话、简体／繁体中文、尚未绑定且允许绑定时，首页自动提示；未解决的华为账号冲突优先保留原处理入口。
- 两端共用语义键 `wechat.binding.prompt.presented`，各自应用本地持久化。真实展示后全局只自动提示一次，不按版本、账号或登录次数重置；关闭、下滑、选择绑定均算已经展示。两端的本地展示记录不跨设备云同步。
- 状态请求失败、未登录、服务端尚未开放、其他弹层或页面阻挡时，不消耗展示次数。
- 本次没有更改服务端灰度开关，真实绑定仍遵守服务端能力和现有账号关联确认流程。

## 验证

- iOS 定向单元测试 56/56 通过，包含提示持久化、中文判断、服务端能力、回调路由及账号绑定契约。
- iOS 界面测试：简繁标题与对齐、稍后关闭、未安装时入口及即时提示、协议不自动同意；3/3 通过。
- 原生 Sheet 调整为 400pt 后，简繁展示与关闭定向复测通过。截图见本目录 `prompt-zh-Hans.png` 和 `prompt-zh-Hant.png`。
- 另补“立即绑定”从预览关闭后进入正常登录 Sheet 的界面回归，1/1 通过，结果见 `/tmp/jifen-wechat-prompt-route-20261024-test.log`。
- 鸿蒙 `test_wechat_binding_prompt.mjs` 17 项断言、`test_wechat_login_entry.mjs`、`test_wechat_login_language.mjs` 16 项语言用例通过；7 份 locale 提示资源校验及相关 diff 检查通过。
- 鸿蒙 default / entry@default / debug 的 `assembleHap --no-daemon` 最新构建成功。中途被其他在途语音文件的类型错误阻挡过，未修改该语音文件；源文件随后更新后的重新构建成功。
- iOS Debug 真机构建成功，3.4（78）保留数据安装到已连接的 iPhone SE。

日志：`/tmp/jifen-wechat-prompt-20261024-test.log`、`/tmp/jifen-wechat-prompt-final-20261024-test.log`、`/tmp/jifen-wechat-prompt-final-20261024-device-build.log`、`/tmp/jifen-hos-wechat-prompt-20261024-build-current.log`。

## 真机强制预览

仅 Debug 支持启动参数 `-PreviewWechatBindingPrompt`。已用该参数启动真机 App，预览与正式 Sheet 共用视图；不伪造登录、不修改令牌，也不写入正式“一次”记录。退出应用后从桌面正常打开不会携带该启动参数。真实微信授权和跨应用登录过程留给用户在手机上验收。

## 真机按钮样式调整

- 根据 iPhone SE 实际画面反馈，两按钮间距从 8 调到 16，“稍后再说”改为与主按钮同为 50 高的圆角背景按钮，文字使用主文字色；iOS 沿用 `Theme.dialogControlBackground`，鸿蒙沿用 `app_cancel_button_background`，未更改全局 Token。
- iOS Debug 真机构建成功，保留数据重新安装并使用强制预览启动；通过 `devicectl device capture screenshot` 获取且人工查看真机截图 [prompt-buttons-iphone-se.png](prompt-buttons-iphone-se.png)。当前两个按钮完整显示，背景和间距清楚。
- 鸿蒙同步同一间距、按钮高度和次要按钮背景，只做相关差异与 Token 检查；本轮为孤立样式修改，按仓库验证规则跳过重新构建。
- 构建日志：`/tmp/jifen-wechat-prompt-buttons-20261024-build.log`；安装日志：`/tmp/jifen-wechat-prompt-buttons-20261024-install.log`。
