# iOS 胶囊按钮全量检查

日期：2026 年 10 月 19 日。

“投屏与同步 → 跨设备同步”的生成同步码、加入同步按钮已改为胶囊形；同类独立操作一并统一。全项目检查覆盖 98 个含 Button 的 Swift 文件、579 条 Button 源码行，另含 1 处 UIKit Apple 登录按钮。循环和共用模板按源码计数，一行可能声明多个按钮；这些数量不代表运行时按钮总数。

本轮共调整 20 个 Swift 文件、36 处 SwiftUI 按钮声明或模板，包括跨设备同步、首页短码重试、登录与注销、快速开始编辑、会员活动、比赛结束和规则弹窗、比分自定义、样式应用、小组作废结果、随机分组、AA 计算、弹幕启动和积分表添加队伍。

## 统一规则

- 有独立填充或描边的普通文字操作使用胶囊，包括确认、取消、保存、开始、重试等。
- 数值键盘、步进器、选项、规则预设、分段切换、色样、图文预览卡和圆形图标保留符合其用途的形状。
- 系统 List 和 Form 行、工具栏、菜单、警告弹窗及行内辅助链接保留系统布局。原生 bordered 和 borderedProminent 在当前 iOS 26 环境中使用系统胶囊外观。
- 输入框、弹窗、卡片、展示面板的圆角属于容器，不随操作按钮改形。
- Apple 原生登录按钮按用户要求保留原有样式，cornerRadius 为 10pt，不纳入胶囊改造。同屏的账号密码登录入口也作为例外，与 Apple 按钮统一为 10pt 圆角矩形。

跨端口径参考 Android 的 DesignSystem.kt 和 AppControlComponents.kt，以及鸿蒙 10 月 18 日的按钮形状审计与测试；具体位置见文末。

### 2026 年 10 月 20 日登录入口例外

用户根据登录弹层截图确认：保留 Apple 原生按钮的现有圆角矩形，让下方账号密码登录入口与它一致。代码使用 `ASAuthorizationAppleIDButton`，其 `cornerRadius = 10` 是应用通过苹果提供的圆角属性设置的，并非系统默认值。账号密码登录入口由胶囊调整为 10pt 圆角矩形，两按钮继续保持相同的宽度和 50pt 高度。密码表单内的提交按钮继续适用普通操作按钮的胶囊规则。下文 10 月 19 日的验证及表格记录的是当时结果，其中账号密码登录入口的胶囊结论由本次例外覆盖。

验证：Debug 模拟器构建通过（[build.log](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/login-button-alignment-2026-10-20/build.log)）；安装到 iPhone 17 Pro / iOS 26.5 后，通过 CUA 打开“我的 → 登录”，确认两个入口的圆角矩形外观和宽高一致。`AppleAuthProvider.swift` 与 Git HEAD 无差异，保留现有原生按钮实现。

## 验证

- 修改基于开始任务时的工作区逐文件快照对比，按钮尺寸、颜色、文字、禁用及加载逻辑保持原样；仅调整形状。同步页的命中形状也随按钮改为胶囊。
- 最终 Debug 模拟器构建通过，包含最后补改的乒乓球确认按钮；构建日志见 [build-final.log](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/capsule-button-audit-2026-10-19/build-final.log)。
- iPhone 17 Pro 模拟器 iOS 26.5 通过 CUA 实际核对：同步页生成和加入按钮的浅色及深色外观、空短码时禁用外观、生成入口打开登录弹层、账号密码登录入口的胶囊外观、快速开始编辑取消和保存的胶囊外观、AA 重置和计算的胶囊外观。
- Apple 原生登录按钮已恢复为任务开始前的实现，源码与 Git HEAD 一致；恢复后重新构建及模拟器外观核对均通过。
- AA 验证输入 100 元和 2 人，计算后显示每人 50 元。快捷入口编辑使用取消退出。
- 全局复扫剩余圆角形状与 onTapGesture，普通确认、取消、保存等操作未发现遗漏；git diff --check 通过。视觉验证覆盖上述代表页面，其余项目完成源码逐项检查。

## 用户确认后的再次自检

- 复扫当前 98 个按钮文件、579 条 Button 源码行及共享组件和手势入口；剩余非胶囊控件均符合前述保留规则，没有发现需要补改的普通操作按钮。
- 20 个修改文件的 SHA256 与用户已确认版本一致，精确任务补丁与基线差异一致；AppleAuthProvider.swift 与 Git HEAD 完全一致。此次自检没有修改产品源码。
- 当前代码重新执行 Debug 模拟器构建通过，日志见 [build-selfcheck.log](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/capsule-button-audit-2026-10-19/build-selfcheck.log)。
- 最新构建安装到 iPhone 17 Pro 模拟器后，核对生成同步码和加入同步的胶囊外观；空短码时加入按钮禁用，输入 6 位测试码后启用，点击后正常打开登录页。
- 登录页 Apple 按钮保留原有 10pt 圆角矩形，账号密码登录入口和提交按钮继续使用胶囊；未提交账号登录。
- 两次独立源码复核均通过，未发现遗漏或不合适的胶囊转换；git diff --check 通过。

## 跨设备同步和小组的修改

| 文件和位置 | 操作 | 修改 |
| --- | --- | --- |
| jifen/Features/Display/CloudSyncEntryView.swift:165 | 重新生成短码 | 12pt 圆角矩形改胶囊，背景、描边、命中区同形 |
| jifen/Features/Display/CloudSyncEntryView.swift:218 | 生成同步码及未登录状态 | 14pt 圆角矩形改胶囊 |
| jifen/Features/Display/CloudSyncEntryView.swift:296 | 加入同步及未登录状态 | 14pt 圆角矩形改胶囊 |
| jifen/Features/Display/CloudSyncEntryView.swift:399 | 复制短码和结束同步模板 | 12pt 圆角矩形改胶囊 |
| jifen/Features/Display/CloudSyncEntryView.swift:868 | 同步管理弹窗填充操作模板 | 12pt 圆角矩形改胶囊 |
| jifen/Features/Display/CloudSyncEntryView.swift:878 | 同步管理弹窗描边操作模板 | 12pt 圆角矩形改胶囊 |
| jifen/Features/Display/CloudSyncEntryView.swift:896 | 同步管理弹窗复制和结束模板 | 12pt 圆角矩形改胶囊 |
| jifen/Features/Groups/GroupViews.swift:497 | 作废结果 | 描边和命中区改胶囊 |

## 通用页面的修改

| 位置 | 操作 | 修改 |
|---|---|---|
| jifen/Features/Home/Components/HomeHeaderView.swift:223 | 重新生成短码 | RoundedRectangle(10) → Capsule |
| jifen/Features/Home/Components/QuickStartEditView.swift:228 | 取消/保存 | RoundedRectangle(14) → Capsule |
| jifen/Features/Home/Components/QuickStartEditView.swift:241 | 取消/保存 | RoundedRectangle(14) → Capsule |
| jifen/Features/Account/AccountViews.swift:117 | 账号密码登录入口/登录/注销账号 | RoundedRectangle(12) → Capsule |
| jifen/Features/Account/AccountViews.swift:270 | 账号密码登录入口/登录/注销账号 | RoundedRectangle(12) → Capsule |
| jifen/Features/Account/AccountViews.swift:888 | 账号密码登录入口/登录/注销账号 | RoundedRectangle(12) → Capsule |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:192 | 活动立即购买/开始使用/登录绑定/返回 | RoundedRectangle(13) → Capsule |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:323 | 活动立即购买/开始使用/登录绑定/返回 | RoundedRectangle(13) → Capsule |

## 通用页面逐项判断

| 位置 | 操作/类型 | 审计前有效形状 | 判断 |
|---|---|---|---|
| jifen/Core/Components/FloatingBackButton.swift:11 | 悬浮返回（图标） | Circle | 保留：图标控件维持独立热区 |
| jifen/Core/Components/ModalCloseButton.swift:9 | 关闭（图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Core/Components/ModalCloseButton.swift:29 | 计分板弹窗关闭（图标） | Circle | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/CommonDataManagementShared.swift:47 | 分类筛选（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/CommonDataManagementShared.swift:69 | 添加常用数据（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Home/Components/CommonDataManagementShared.swift:96 | 全选/删除（工具条文本） | plain 文本 | 保留：批量编辑工具条中的全选/删除维持工具条布局 |
| jifen/Features/Home/Components/CommonDataManagementShared.swift:112 | 全选/删除（工具条文本） | plain 文本 | 保留：批量编辑工具条中的全选/删除维持工具条布局 |
| jifen/Features/Home/Components/CommonDataSectionView.swift:51 | 常用数据入口（卡片） | RoundedRectangle(20) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/HomeHeaderView.swift:60 | 投屏与同步（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Home/Components/HomeHeaderView.swift:136 | 同步状态详情（状态区） | plain 复合状态块 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/HomeHeaderView.swift:200 | 复制同步码/管理入口（图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/HomeHeaderView.swift:223 | 重新生成短码（操作） | RoundedRectangle(10) | 改为 Capsule：独立重试操作 |
| jifen/Features/Home/Components/HomeHeaderView.swift:238 | 复制同步码/管理入口（图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:213 | 取消/开始（操作） | cornerRadius(.infinity) | 保留：已为胶囊 |
| jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:223 | 取消/开始（操作） | cornerRadius(.infinity) | 保留：已为胶囊 |
| jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:265 | 人数选择（选择） | RoundedRectangle(12) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:394 | 掼蛋回退级别（选择） | RoundedRectangle(10) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:413 | 过 A 条件（选择） | RoundedRectangle(12) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:436 | UNO 目标分（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/NineBallSetupDialogView.swift:107 | 取消/开始（操作） | Capsule（开始按钮由调用端 clipShape） | 保留：已为胶囊 |
| jifen/Features/Home/Components/NineBallSetupDialogView.swift:126 | 取消/开始（操作） | Capsule（开始按钮由调用端 clipShape） | 保留：已为胶囊 |
| jifen/Features/Home/Components/NineBallSetupDialogView.swift:215 | 分值加减（数值图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/ProToolsSectionView.swift:47 | 工具入口（卡片） | Bento/CardButtonStyle | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/ProToolsSectionView.swift:116 | 全部工具（图标） | plain chevron | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/QuickStartEditView.swift:175 | 快速开始槽位选择（选择卡片） | RoundedRectangle(14) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/QuickStartEditView.swift:228 | 取消/保存（操作） | RoundedRectangle(14) | 改为 Capsule：独立底部确认/取消操作 |
| jifen/Features/Home/Components/QuickStartEditView.swift:241 | 取消/保存（操作） | RoundedRectangle(14) | 改为 Capsule：独立底部确认/取消操作 |
| jifen/Features/Home/Components/QuickStartGridView.swift:34 | 编辑快速开始（图标） | 44×44 / cornerRadius(22) | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/QuickStartGridView.swift:53 | 快速开始运动/新建比赛入口（卡片） | Bento / RoundedRectangle(Theme.xxl) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/QuickStartGridView.swift:83 | 快速开始运动/新建比赛入口（卡片） | Bento / RoundedRectangle(Theme.xxl) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/QuickStartGridView.swift:132 | 快速开始运动/新建比赛入口（卡片） | Bento / RoundedRectangle(Theme.xxl) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/RecentRecordsSectionView.swift:217 | 查看全部记录（列表尾行） | plain 全宽文本 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/ShotTrainingSetupDialogView.swift:67 | 投篮训练模式（选择） | RoundedRectangle(10) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/ShotTrainingSetupDialogView.swift:95 | 取消/开始（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Home/Components/ShotTrainingSetupDialogView.swift:104 | 取消/开始（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Home/Components/SportOptionView.swift:9 | 运动项目选择（选择卡片） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupCommonNameViews.swift:37 | 常用名称选择（选择列表行） | 系统 List 行 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/Components/SportsSetupCommonNameViews.swift:97 | 常用名称展开（图标） | plain chevron | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/SportsSetupDialogView.swift:107 | 取消/开始（操作） | Capsule（开始按钮由调用端 clipShape） | 保留：已为胶囊 |
| jifen/Features/Home/Components/SportsSetupDialogView.swift:127 | 取消/开始（操作） | Capsule（开始按钮由调用端 clipShape） | 保留：已为胶囊 |
| jifen/Features/Home/Components/SportsSetupMatchFeatures.swift:97 | 语音选项展开（图标） | plain chevron | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/SportsSetupMatchFeatures.swift:260 | 比赛功能开关卡（选择卡片） | RoundedRectangle(14) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupParticipantSection.swift:223 | 发球/开球/首发方（图标选择） | plain 图标 | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:172 | 足球半场时长加减（数值图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:227 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:255 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:280 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:321 | 匹克球平分规则（选择列表行） | plain 行 + checkmark | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:395 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:410 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:569 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:590 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:634 | 自定义数值编辑（数值图标） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:657 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:705 | 自定义数值编辑（数值图标） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:750 | 完赛模式展开（展开选择） | plain 文本行 | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:771 | 完赛模式多行说明选项（选择卡片） | RoundedRectangle(12) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:804 | 网球格式/局数/抢七/桌足球分数/规则/数值预设（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/SportsSetupSettingsSection.swift:819 | 自定义数值编辑（数值图标） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Home/Components/UnfinishedGameBarView.swift:213 | 放弃未完成比赛（操作） | Capsule（36pt 圆形展开为 72pt 胶囊） | 保留：已为胶囊 |
| jifen/Features/Home/Components/UnfinishedGameBarView.swift:239 | 继续比赛（图标） | Circle | 保留：图标控件维持独立热区 |
| jifen/Features/Home/HomeTab.swift:567 | 知道了（系统） | 原生 alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Home/HomeTab.swift:1131 | 小组通知/更多/球局入口（图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Home/HomeTab.swift:1146 | 小组通知/更多/球局入口（图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Home/HomeTab.swift:1151 | 小组内容入口（卡片） | RoundedRectangle(16) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Home/HomeTab.swift:1287 | 小组通知/更多/球局入口（图标） | plain 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Home/HomeTab.swift:1308 | 预约新球局（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Home/HomeTab.swift:1328 | 预约球局详情（卡片） | RoundedRectangle(20) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Account/AccountViews.swift:117 | 账号密码登录入口/登录/注销账号（操作） | RoundedRectangle(12) | 改为 Capsule：独立登录/账号操作 |
| jifen/Features/Account/AccountViews.swift:142 | 设置 IAP 测试密钥（STAGING）（行内链接） | 原生文本 | 保留：行内链接维持轻量表现 |
| jifen/Features/Account/AccountViews.swift:175 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:176 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:270 | 账号密码登录入口/登录/注销账号（操作） | RoundedRectangle(12) | 改为 Capsule：独立登录/账号操作 |
| jifen/Features/Account/AccountViews.swift:363 | 登录协议勾选（勾选） | plain circle/checkmark 图标 | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Account/AccountViews.swift:408 | 用户协议/隐私政策（行内链接） | plain 文本 | 保留：行内链接维持轻量表现 |
| jifen/Features/Account/AccountViews.swift:547 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:555 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:621 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:624 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:787 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:790 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:888 | 账号密码登录入口/登录/注销账号（操作） | RoundedRectangle(12) | 改为 Capsule：独立登录/账号操作 |
| jifen/Features/Account/AccountViews.swift:1126 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:1135 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AccountViews.swift:1296 | 个人资料/昵称编辑行（列表行） | plain 信息行 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Account/AccountViews.swift:1340 | 个人资料/昵称编辑行（列表行） | plain 信息行 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Account/AccountViews.swift:1429 | 继续/取消/退出/注销确认/头像来源/昵称保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AvatarCropView.swift:155 | 头像裁剪取消/确认（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Account/AvatarCropView.swift:174 | 头像裁剪取消/确认（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Account/QRLoginApprovalView.swift:143 | 扫码错误提示内重试（行内链接） | 原生文本 | 保留：行内链接维持轻量表现 |
| jifen/Features/Account/QRLoginApprovalView.swift:208 | 拒绝/确认网页登录（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Account/QRLoginApprovalView.swift:220 | 拒绝/确认网页登录（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Me/CommonNamesManagementView.swift:136 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:137 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:155 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:156 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:178 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:184 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:190 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:267 | 选择/编辑常用名称（图标） | plain circle/pencil 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Me/CommonNamesManagementView.swift:278 | 常用名称编辑/选择（列表行） | plain 文本 + commonDataListCardStyle | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/CommonNamesManagementView.swift:304 | 选择/编辑常用名称（图标） | plain circle/pencil 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Me/CommonNamesManagementView.swift:383 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonNamesManagementView.swift:432 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:117 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:118 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:132 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:133 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:155 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:161 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:167 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:237 | 选择/编辑常用地点（图标） | plain circle/pencil 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Me/CommonPlacesManagementView.swift:248 | 地点编辑/常用地点选择（列表行） | plain 行/系统 List 行 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/CommonPlacesManagementView.swift:268 | 选择/编辑常用地点（图标） | plain circle/pencil 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Me/CommonPlacesManagementView.swift:337 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:382 | 取消/清空/删除/完成/编辑/添加/保存（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/CommonPlacesManagementView.swift:553 | 地点编辑/常用地点选择（列表行） | plain 行/系统 List 行 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:137 | 清除确认/外观模式（系统） | 原生 Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/SettingsView.swift:140 | 清除确认/外观模式（系统） | 原生 Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/SettingsView.swift:158 | 清除确认/外观模式（系统） | 原生 Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/SettingsView.swift:211 | 登录/网站/反馈/清除/评分/分享/设置入口（列表行） | SettingsNavigationRow | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:234 | 登录/网站/反馈/清除/评分/分享/设置入口（列表行） | SettingsNavigationRow | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:251 | 登录/网站/反馈/清除/评分/分享/设置入口（列表行） | SettingsNavigationRow | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:296 | 清除确认/外观模式（系统） | 原生 Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Me/SettingsView.swift:317 | 登录/网站/反馈/清除/评分/分享/设置入口（列表行） | SettingsNavigationRow | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:330 | 登录/网站/反馈/清除/评分/分享/设置入口（列表行） | SettingsNavigationRow | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:341 | 登录/网站/反馈/清除/评分/分享/设置入口（列表行） | SettingsNavigationRow | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:439 | 登录/网站/反馈/清除/评分/分享/设置入口（列表行） | SettingsNavigationRow | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:649 | 扫码登录/复制 QQ 群（图标） | plain qrcode/copy 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Me/SettingsView.swift:985 | 常见问题展开/收起（展开内容行） | RoundedRectangle(8) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Me/SettingsView.swift:1129 | 扫码登录/复制 QQ 群（图标） | plain qrcode/copy 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Membership/MembershipView.swift:82 | 兑换（系统） | 原生 toolbar | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Membership/MembershipView.swift:483 | 会员月卡/年卡/终身套餐（选择卡片） | RoundedRectangle(20) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Membership/MembershipView.swift:529 | 会员月卡/年卡/终身套餐（选择卡片） | RoundedRectangle(20) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Membership/MembershipView.swift:633 | 登录/恢复购买（行内链接） | 原生文本/underline | 保留：行内链接维持轻量表现 |
| jifen/Features/Membership/MembershipView.swift:643 | 登录/恢复购买（行内链接） | 原生文本/underline | 保留：行内链接维持轻量表现 |
| jifen/Features/Membership/MembershipView.swift:668 | 立即开通（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Membership/MembershipView.swift:752 | 会员协议勾选（勾选） | plain circle/checkmark 图标 | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:67 | 活动页关闭（图标） | plain xmark | 保留：图标控件维持独立热区 |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:155 | 查看会员权益/稍后绑定先使用（行内链接） | plain 文本 | 保留：行内链接维持轻量表现 |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:170 | 活动协议勾选（勾选） | plain circle/checkmark 图标 | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:192 | 活动立即购买/开始使用/登录绑定/返回（操作） | RoundedRectangle(13) | 改为 Capsule：独立购买/返回/完成操作 |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:266 | 查看会员权益/稍后绑定先使用（行内链接） | plain 文本 | 保留：行内链接维持轻量表现 |
| jifen/Features/Membership/NationalDayMembershipSheet.swift:323 | 活动立即购买/开始使用/登录绑定/返回（操作） | RoundedRectangle(13) | 改为 Capsule：独立购买/返回/完成操作 |
| jifen/Features/Feedback/FeedbackViews.swift:297 | 重新加载/发送/提交举报（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Feedback/FeedbackViews.swift:405 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:493 | 加载更多（列表尾行） | plain 全宽文本 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Feedback/FeedbackViews.swift:683 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:686 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:701 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:705 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:737 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:747 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:750 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:858 | 点赞（图标 + 数字） | plain heart/count | 保留：图标控件维持独立热区 |
| jifen/Features/Feedback/FeedbackViews.swift:903 | 图片预览（图片卡片） | RoundedRectangle(8) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Feedback/FeedbackViews.swift:971 | 重新加载/发送/提交举报（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Feedback/FeedbackViews.swift:1144 | 全屏预览关闭（图标） | Circle | 保留：图标控件维持独立热区 |
| jifen/Features/Feedback/FeedbackViews.swift:1221 | 重新加载/发送/提交举报（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Feedback/FeedbackViews.swift:1285 | 举报原因单选（选择列表行） | RoundedRectangle(8) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Feedback/FeedbackViews.swift:1372 | 发布反馈/删除/举报/继续打开/取消（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Feedback/FeedbackViews.swift:1402 | 反馈类型选择（选择卡片） | RoundedRectangle(12) / 80pt 高 | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Feedback/FeedbackViews.swift:1487 | 删除已选图片（图标） | plain xmark.circle.fill | 保留：图标控件维持独立热区 |
| jifen/Features/Activity/RecentActivityPage.swift:34 | 编辑/完成（系统） | 原生 toolbar | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Activity/RecentActivityPage.swift:121 | 删除记录（图标） | plain minus.circle.fill | 保留：图标控件维持独立热区 |
| jifen/Features/Records/RecordNotesCard.swift:56 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:57 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:260 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:261 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:330 | 文字笔记/语音笔记入口（内容入口卡） | RoundedRectangle(16) / 180pt 高 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Records/RecordNotesCard.swift:331 | 文字笔记/语音笔记入口（内容入口卡） | RoundedRectangle(16) / 180pt 高 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Records/RecordNotesCard.swift:409 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:448 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:455 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:532 | 录音控制/语音播放暂停（图标） | Circle | 保留：图标控件维持独立热区 |
| jifen/Features/Records/RecordNotesCard.swift:679 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:680 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:721 | 录音控制/语音播放暂停（图标） | Circle | 保留：图标控件维持独立热区 |
| jifen/Features/Records/RecordNotesCard.swift:743 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordNotesCard.swift:745 | 取消/删除/保存/编辑/重新录制（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:73 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:79 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:86 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:98 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:140 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:141 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:151 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:152 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:181 | 时间/项目筛选（选择列表行） | 系统 Form 行 + checkmark | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Records/RecordsTab.swift:197 | 时间/项目筛选（选择列表行） | 系统 Form 行 + checkmark | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Records/RecordsTab.swift:211 | 时间/项目筛选（选择列表行） | 系统 Form 行 + checkmark | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Records/RecordsTab.swift:239 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:265 | 完成/筛选/编辑/清空/删除/应用/重置（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/RecordsTab.swift:303 | 记录类型分类（选择） | RoundedRectangle(16) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Records/RecordsTab.swift:451 | 批量记录选择（列表行） | plain 记录行 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:73 | 删除/取消/确定/修正分数保存（系统） | 原生 toolbar / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:85 | 删除/取消/确定/修正分数保存（系统） | 原生 toolbar / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:86 | 删除/取消/确定/修正分数保存（系统） | 原生 toolbar / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:89 | 删除/取消/确定/修正分数保存（系统） | 原生 toolbar / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:309 | 笔记/分享（图标） | plain square.and.pencil/share | 保留：图标控件维持独立热区 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:318 | 笔记/分享（图标） | plain square.and.pencil/share | 保留：图标控件维持独立热区 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:327 | 再来一场（操作） | 系统 .borderedProminent（iOS 26 默认胶囊） | 保留：已为胶囊 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:393 | 删除/取消/确定/修正分数保存（系统） | 原生 toolbar / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Records/ScoreboardRecordDetailPage.swift:552 | 全场/分节详情选择（选择） | Capsule | 保留：已为胶囊 |
| jifen/Features/Schedule/BookingDetailPage.swift:63 | 取消预约/删除预约确认（系统） | 原生 alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/BookingDetailPage.swift:64 | 取消预约/删除预约确认（系统） | 原生 alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/BookingDetailPage.swift:72 | 取消预约/删除预约确认（系统） | 原生 alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/BookingDetailPage.swift:73 | 取消预约/删除预约确认（系统） | 原生 alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/BookingDetailPage.swift:140 | 一键开赛/编辑/取消预约/复制预约/删除（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Schedule/BookingDetailPage.swift:201 | 一键开赛/编辑/取消预约/复制预约/删除（操作） | Capsule | 保留：已为胶囊 |
| jifen/Features/Schedule/CreateBookingPage.swift:110 | 保存/确认（系统） | 原生 toolbar / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/CreateBookingPage.swift:153 | 保存/确认（系统） | 原生 toolbar / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/CreateBookingPage.swift:246 | 常用地点/名称选择/移除参与者/时长加减（图标） | plain chevron/plus/minus 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Schedule/CreateBookingPage.swift:267 | 常用地点/名称选择/移除参与者/时长加减（图标） | plain chevron/plus/minus 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Schedule/CreateBookingPage.swift:273 | 常用地点/名称选择/移除参与者/时长加减（图标） | plain chevron/plus/minus 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Schedule/CreateBookingPage.swift:282 | 添加参与者（系统表单行） | 原生 Form 操作行 | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Schedule/CreateBookingPage.swift:438 | 常用地点/名称选择/移除参与者/时长加减（图标） | plain chevron/plus/minus 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Schedule/CreateBookingPage.swift:473 | 常用地点/名称选择/移除参与者/时长加减（图标） | plain chevron/plus/minus 图标 | 保留：图标控件维持独立热区 |
| jifen/Features/Schedule/CreateBookingPage.swift:484 | 提醒时间多选（选择） | RoundedRectangle(10) | 保留：选择控件维持原状，与 Android/HarmonyOS 区分普通操作和选择控件的规则一致 |
| jifen/Features/Schedule/SchedulePage.swift:32 | 预约详情/批量选择（列表行） | bookingRow / RoundedRectangle(12) | 保留：列表/内容卡维持信息布局 |
| jifen/Features/Schedule/SchedulePage.swift:72 | 完成/编辑/批量删除/新建预约/确认删除（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/SchedulePage.swift:86 | 完成/编辑/批量删除/新建预约/确认删除（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/SchedulePage.swift:99 | 完成/编辑/批量删除/新建预约/确认删除（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/SchedulePage.swift:109 | 完成/编辑/批量删除/新建预约/确认删除（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/SchedulePage.swift:176 | 完成/编辑/批量删除/新建预约/确认删除（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Schedule/SchedulePage.swift:177 | 完成/编辑/批量删除/新建预约/确认删除（系统） | 原生 toolbar / Menu / alert | 保留：系统工具栏、菜单或确认弹窗使用原生表现 |
| jifen/Features/Account/AppleAuthProvider.swift:162 | 使用 Apple 登录（原生品牌操作） | cornerRadius 10，高 50pt | 保留原有样式；按用户要求恢复原生登录按钮，不参与胶囊统一 |

## 非 Button 内容入口补充

- Home 的 BentoCard、近期记录、常用数据、预约、小组入口，以及 Me 的 SettingsNavigationRow、Account 资料行、Feedback 图片缩略图和记录列表 NavigationLink：维持内容卡/列表结构。
- Feedback 的 PhotosPicker 添加图片区为 72×72 方形缩略图网格；维持 RoundedRectangle(8)，与同排图片一致。
- 原生 Picker、Menu 标签、表单选择项、勾选图标和展开内容行保持选择/导航语义；无额外普通独立文本操作需要改形。
- Activity/TimerRecordDetailPage 等文件出现的 cornerRadius 是展示卡片，未误判为按钮。


## 计分和工具页面的修改

行号为当前文件行号（本轮改动未增减行）。一处模板可能渲染多个按钮。

| 位置 | 标签/作用 | 之前 | 决定及原因 |
|---|---|---|---|
| jifen/Features/Scoreboard/Sports/Rally/TableTennisCardsDialog.swift:104 | 确认 / 确认判负 | RoundedRectangle 12 | 改 Capsule；选手选择后的提交操作 |
| jifen/Features/Scoreboard/Shared/GameOverDialog.swift:266 | 再来一场 | RoundedRectangle 12 | 改 Capsule；结束弹层主操作 |
| jifen/Features/Scoreboard/Shared/GameOverDialog.swift:506 | 查看记录 / 分享 / 关闭（共用模板） | RoundedRectangle 12 | 改 Capsule；结束弹层次操作 |
| jifen/Features/Scoreboard/MultiScore/MultiScoreboardView.swift:822 | 取消编辑玩家 | RoundedRectangle 12 | 改 Capsule，命中区同形 |
| jifen/Features/Scoreboard/MultiScore/MultiScoreboardView.swift:835 | 确定编辑玩家 | RoundedRectangle 12 | 改 Capsule，命中区同形 |
| jifen/Features/Scoreboard/Shared/ScoreCustomAdjustPanel.swift:142 | 应用自定义分值 | RoundedRectangle 14 | 改 Capsule；输入后的提交操作 |
| jifen/Features/Scoreboard/Shared/ScoreboardAppearance.swift:1720 | 取消字体设置 | RoundedRectangle 24；高度手机48/平板56 | 改 Capsule；平板原先未完全圆头 |
| jifen/Features/Scoreboard/Shared/ScoreboardAppearance.swift:1731 | 应用字体设置 | RoundedRectangle 24；高度手机48/平板56 | 改 Capsule；平板原先未完全圆头 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift:1301 | 取消文字色传播 | RoundedRectangle 12 | 改 Capsule；确认弹层操作 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift:1316 | 确认文字色传播 | RoundedRectangle 12 | 改 Capsule；确认弹层操作 |
| jifen/Features/Scoreboard/Sports/Archery/ArcheryScoreboardView.swift:428 | 距离相同，继续加赛 | RoundedRectangle 10 | 改 Capsule；继续比赛操作 |
| jifen/Features/Scoreboard/Sports/Basketball/BasketballScoreboardView.swift:1426 | 节次开始/结束/进入加时（共用模板） | RoundedRectangle 8 | 改 Capsule；独立比赛流程操作 |
| jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift:652 | 犯规 | RoundedRectangle 10 | 改 Capsule；打开罚分操作 |
| jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift:667 | 交杆 | RoundedRectangle 10 | 改 Capsule；独立流程操作 |
| jifen/Features/Scoreboard/Sports/Boxing/BoxingScoreboardView.swift:445 | 回合确认/取消（共用模板） | cornerRadius 22，minHeight44 | 改 Capsule；让实际高度增长时仍保持圆头 |
| jifen/Features/Tools/AACalculatorView.swift:254 | 重置 | RoundedRectangle 12 | 改 Capsule；底部常规操作 |
| jifen/Features/Tools/AACalculatorView.swift:266 | 计算 | RoundedRectangle 12 | 改 Capsule；底部主操作 |
| jifen/Features/Tools/FullscreenBarrageView.swift:393 | 开始滚动展示 / 开始静态展示（共用模板） | RoundedRectangle 12 | 改 Capsule；启动展示操作，不是模式选项 |
| jifen/Features/Tools/PointsTable/PointsTableView.swift:401 | 添加队伍 | RoundedRectangle 12 | 改 Capsule；内容区常规操作 |
| jifen/Features/Tools/RandomTeamView.swift:204 | 重选人数 / 模拟 / 再来一次（共用模板） | RoundedRectangle 11 | 改 Capsule；分组流程操作 |

## 明确保留的非胶囊候选

| 位置 | 标签/类型与现状 | 决定及原因 |
|---|---|---|
| jifen/Features/Scoreboard/Cards/Doudizhu/DoudizhuScoreboardView.swift:919,961 | 胜者、底分/番数选项，RoundedRectangle12 | 保留；选择控件，不是确认操作；确认按钮814已是胶囊 |
| jifen/Features/Scoreboard/MultiScore/MultiScoreboardView.swift:763 | +/-，56×44 RoundedRectangle12 | 保留；数值步进器 |
| jifen/Features/Scoreboard/MultiScore/MultiScoreboardView.swift:906 | UNO 胜者选项，RoundedRectangle12 | 保留；选手选择网格 |
| jifen/Features/Scoreboard/MultiScore/MultiScoreboardView.swift:1033,1049 | UNO 张数 +/-，同组背景 RoundedRectangle10 | 保留；带数值的组合步进器 |
| jifen/Features/Scoreboard/Shared/ScoreCustomAdjustPanel.swift:90,104 | 数值/省略号键盘，RoundedRectangle16 | 保留；统一数字键盘与自定义入口 |
| jifen/Features/Scoreboard/Shared/ScoreCustomAdjustPanel.swift:190 | 加分/减分选项，RoundedRectangle16 | 保留；正负方向选择；应用按钮142已修改 |
| jifen/Features/Scoreboard/Shared/ScoreboardAppearance.swift:1783 | 字体预览图文卡片，RoundedRectangle14 | 保留；含123示例与字体名的预览选项 |
| jifen/Features/Scoreboard/Shared/ScreenshotSaveCoordinator.swift:485 | 预览卡右下角分享，行内无底文字 | 保留；预览卡页脚辅助链接；取消/主操作534,550已是胶囊 |
| jifen/Features/Scoreboard/Shared/ScoreboardAppearance.swift:1821 | 恢复默认，行内无底文字 | 保留；字号区域辅助文字操作，不添加新底形/尺寸 |
| jifen/Features/Scoreboard/Shared/ScoreboardAppearance.swift:2154 | 显示控制按钮，透明88×88 | 保留；沉浸界面隐形唤出命中区 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift:466,497 | 颜色/文字样式图文工具栏项，无独立背景 | 保留；工具面板入口条目 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift:1040 | 左/中/右/左右同色，RoundedRectangle10 | 保留；组合分段选择器 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift:1070 | 背景色预览卡，RoundedRectangle12 | 保留；带色样和十六进制的卡片选项 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift:1126,1169 | 字体和主题预览卡，RoundedRectangle14 | 保留；视觉预览与选择语义 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift:864 | 自定义颜色面板返回，无底箭头 | 保留；面板导航图标 |
| jifen/Features/Scoreboard/Shared/MenuDialog.swift:461 | 语音选项展开，无底箭头 | 保留；附属于卡片的 disclosure 图标 |
| jifen/Features/Scoreboard/Shared/MenuDialog.swift:564 | 菜单图文卡片，RoundedRectangle8/10/12 | 保留；图文工具卡片布局 |
| jifen/Features/Scoreboard/Shared/ScoreboardTemplate.swift:58,1315 | 名称输入框旁常用名称箭头，无底 | 保留；输入框内附属入口 |
| jifen/Features/Scoreboard/Shared/ScoreboardTemplate.swift:1257 | 篮球 +1/+2/+3 数值键，RoundedRectangle8 | 保留；比分操作键盘，与数字功能对应 |
| jifen/Features/Scoreboard/Sports/Archery/ArcheryScoreboardView.swift:401,414 | 双方近心胜者选项，RoundedRectangle10 | 保留；选手选择，继续加赛动作已改 |
| jifen/Features/Scoreboard/Sports/Basketball/BasketballScoreboardView.swift:1227 | 节次下拉选项入口，RoundedRectangle12 | 保留；节次当前值选择器 |
| jifen/Features/Scoreboard/Sports/Basketball/BasketballScoreboardView.swift:1366,1388 | Q1-Q4/OT，RoundedRectangle8 | 保留；节次选择网格 |
| jifen/Features/Scoreboard/Sports/Billiards/NineBallChaseScoreboardView.swift:702 | 九球事件/分值名条卡，RoundedRectangle12 | 保留；多字段计分操作卡 |
| jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift:803 | 犯规换手/犯规方继续，RoundedRectangle12 | 保留；犯规策略二选一 |
| jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift:820 | 4/5/6/7 罚分名条卡，RoundedRectangle14 | 保留；数字计分选项 |
| jifen/Features/Scoreboard/Sports/Football/FootballScoreboardView.swift:589 | 撤销最近一次补时，行内无底文字 | 保留；补时列表内辅助撤销链接 |
| jifen/Features/Scoreboard/Sports/Rally/RallyScoreboardView.swift:315 | 双方普通/医疗暂停图文卡，RoundedRectangle12 | 保留；选手与暂停类型选择卡 |
| jifen/Features/Scoreboard/Sports/Rally/RallyScoreboardView.swift:2337,2356 | 羽球选手/处罚类型，RoundedRectangle12 | 保留；选择状态与处罚色标 |
| jifen/Features/Scoreboard/Sports/Rally/TableTennisCardsDialog.swift:138 | 选手与牌状态预览卡，RoundedRectangle10 | 保留；卡片预览选择；确认104已修改 |
| jifen/Features/Tools/AACalculatorView.swift:79,100 | ¥金额预设，RoundedRectangle8 | 保留；数值预设网格 |
| jifen/Features/Tools/AACalculatorView.swift:128,157 | 人数 +/-，60×60 RoundedRectangle12 | 保留；数值步进器 |
| jifen/Features/Tools/FullscreenBarrageView.swift:281,288 | 运行中滚动/静态，RoundedRectangle8 共用样式 | 保留；互斥模式选择，不是启动操作 |
| jifen/Features/Tools/FullscreenBarrageView.swift:303 | 收起编辑器，无底上箭头 | 保留；面板收起图标 |
| jifen/Features/Tools/PointsTable/PointsTableView.swift:31 | 积分表列表行，矩形命中区 | 保留；系统列表导航条目 |
| jifen/Features/Tools/RandomTeamView.swift:105 | 参与人数，RoundedRectangle12/14 | 保留；人数选择网格 |
| jifen/Features/Tools/TenSecondChallengeView.swift:104 | 开始/停止，200×60 cornerRadius30 | 保留；固定尺寸下已是完整胶囊，无视觉问题 |
| jifen/Features/Tools/WhistleToolView.swift:80,120 | 短哨/长哨，正方形图文大卡 RoundedRectangle16 | 保留；大面积快速触发控制 |
| jifen/Features/Tools/ToolsTab.swift:105 | 工具入口卡，Theme.cornerRadius | 保留；主目录图文卡片 |
| jifen/Features/Scoreboard/ScoreboardTab.swift:241 | 项目入口卡，Theme.cornerRadius | 保留；主目录图文卡片 |
| jifen/Features/Timer/TimerTab.swift:145 | 计时工具入口卡，Theme.cornerRadius | 保留；主目录图文卡片 |
| jifen/Features/Timer/TimeoutCountdownView.swift:305 | 秒数/运动时长预设，RoundedRectangle12 | 保留；含主副标题的时间选择网格 |
| jifen/Features/Tools/DateTimeToolView.swift:76 | 返回/旋转，无底图标，矩形命中区 | 保留；透明悬浮导航图标 |
| 多处（完整库存见下） | Circle 图标按钮、球/环值圆键、色样；原生 alert/menu/toolbar 按钮 | 保留；功能型形状或系统控件 |

## 计分工具和计时按钮文件清单

以下逐文件列出全部 184 处直接 Button 声明，覆盖包括已是胶囊与系统按钮的保留项。

| 文件 | Button 声明行号 | 数量 | 审核结论 |
|---|---|---:|---|
| jifen/Features/Scoreboard/Cards/Doudizhu/DoudizhuScoreboardView.swift | 479, 508, 523, 541, 678, 814, 838, 919, 961 | 9 | 圆形返回/编辑/菜单/加分/关闭与步进器；胜者/番数选择方卡；确认已胶囊。 |
| jifen/Features/Scoreboard/Cards/Guandan/GuandanScoreboardView.swift | 632, 635 | 2 | 系统退出确认；scoreboardCardActionButton 共用胶囊数值辅助键。 |
| jifen/Features/Scoreboard/Cards/Shengji/ShengjiScoreboardView.swift | 129 | 1 | 系统确认；scoreboardCardActionButton 共用胶囊辅助键。 |
| jifen/Features/Scoreboard/MultiScore/MultiScoreboardView.swift | 387, 402, 763, 822, 835, 906, 953, 980, 994, 1033, 1049 | 11 | 圆形工具按钮；编辑取消/确认已改；步进器/UNO胜者选项保留；UNO提交/取消原已胶囊；完成为系统键盘工具栏。 |
| jifen/Features/Scoreboard/ScoreboardTab.swift | 241 | 1 | 项目图文入口卡，保留。 |
| jifen/Features/Scoreboard/Shared/GameOverDialog.swift | 266, 506 | 2 | 再来一场与次操作模板已改胶囊。 |
| jifen/Features/Scoreboard/Shared/MenuDialog.swift | 461, 564 | 2 | 菜单图文卡片与附属展开箭头，保留。 |
| jifen/Features/Scoreboard/Shared/ScoreCustomAdjustPanel.swift | 90, 104, 142, 190 | 4 | 数字键盘、加减方向保留；应用已改胶囊。 |
| jifen/Features/Scoreboard/Shared/ScoreboardAppearance.swift | 1720, 1731, 1783, 1821, 1863, 2012, 2027, 2154 | 8 | 取消/应用已改；字体预览卡、行内恢复默认、圆形步进器保留；休息撤销/继续原已胶囊；隐形唤出区保留。 |
| jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift | 276, 294, 335, 427, 466, 497, 836, 864, 1040, 1070, 1126, 1169, 1301, 1316, 1385, 1595, 1618 | 17 | 传播取消/确认已改；其余圆形关闭/确认、图文样式工具项、分段选项、色样/预览卡、无底返回保留；说明关闭原已胶囊。 |
| jifen/Features/Scoreboard/Shared/ScoreboardTemplate.swift | 58, 399, 445, 476, 1257, 1315, 1458 | 7 | 输入附属箭头、圆形导航/编辑/步进器与篮球分值键保留。 |
| jifen/Features/Scoreboard/Shared/ScoreboardUsageHint.swift | 383 | 1 | 说明确认原已胶囊。 |
| jifen/Features/Scoreboard/Shared/ScreenshotSaveCoordinator.swift | 485, 534, 550 | 3 | 预览卡右下角分享为行内无底链接，保留；取消/主操作原已胶囊；预览图、弹层圆角是容器。 |
| jifen/Features/Scoreboard/Shared/TwoSideScoreboardScaffold.swift | 495, 716, 772 | 3 | 圆形工具/步进器与共用胶囊卡牌辅助操作，保留。 |
| jifen/Features/Scoreboard/Sports/Archery/ArcheryScoreboardView.swift | 304, 401, 414, 428 | 4 | 圆形环值键与双方近心选项保留；继续加赛已改。 |
| jifen/Features/Scoreboard/Sports/Basketball/BasketballScoreboardView.swift | 346, 841, 854, 867, 1037, 1227, 1294, 1337, 1366, 1388, 1426 | 11 | 圆形工具/步进器、原有胶囊时间操作保留；节次选择矩形保留；节次流程动作已改。 |
| jifen/Features/Scoreboard/Sports/Basketball/ShotTrainingScoreboardView.swift | 452 | 1 | 共用圆形返回/菜单工具按钮保留。 |
| jifen/Features/Scoreboard/Sports/Billiards/EightBallScoreboardView.swift | 161 | 1 | 系统确认保留；主要控制复用共用模板。 |
| jifen/Features/Scoreboard/Sports/Billiards/NineBallChaseScoreboardView.swift | 229, 260, 274, 604, 620, 702 | 6 | 圆形导航与数值步进器保留；九球名条计分卡保留。 |
| jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift | 214, 298, 616, 652, 667, 803, 820, 880 | 8 | 圆形工具/球值、犯规策略/罚分名条卡与系统结算保留；犯规/交杆已改。 |
| jifen/Features/Scoreboard/Sports/Boxing/BoxingScoreboardView.swift | 249, 429, 445 | 3 | 圆形加回合/分值键保留；回合确认/取消动作模板已改。 |
| jifen/Features/Scoreboard/Sports/Football/FootballScoreboardView.swift | 381, 575, 589 | 3 | 阶段继续原已胶囊；原生补时数值键与行内撤销保留。 |
| jifen/Features/Scoreboard/Sports/Rally/RallyScoreboardView.swift | 315, 819, 822, 832, 835, 1569, 1758, 2298, 2310, 2337, 2356 | 11 | 暂停选手卡、系统确认、圆形工具/步进器、处罚选项卡保留；处罚确认/取消原已胶囊。 |
| jifen/Features/Scoreboard/Sports/Rally/TableTennisCardsDialog.swift | 104, 138 | 2 | 确认已改胶囊；选手牌状态预览卡保留。 |
| jifen/Features/Scoreboard/Sports/Tennis/TennisScoreboardView.swift | 233, 334, 346, 919 | 4 | 圆形编辑/返回/菜单/数值步进器保留。 |
| jifen/Features/Scoreboard/UsageHintAnimation/ScoreboardUsageHintAnimatedDialog.swift | 71, 150, 178 | 3 | 知道了/开始及左右翻页原已胶囊，保留。 |
| jifen/Features/Tools/AACalculatorView.swift | 79, 100, 128, 157, 254, 266 | 6 | 金额预设和人数步进器保留；重置/计算已改。 |
| jifen/Features/Tools/DateTimeToolView.swift | 76 | 1 | 无底返回/旋转图标保留。 |
| jifen/Features/Tools/DiceToolView.swift | 98, 122, 126 | 3 | 骰子数量入口已胶囊；数量与取消为系统对话框选项。 |
| jifen/Features/Tools/FullscreenBarrageView.swift | 281, 288, 303, 377, 393, 410 | 6 | 启动展示已改；模式选择、圆色样、圆形悬浮工具及收起箭头保留。 |
| jifen/Features/Tools/PointsTable/PointsTableView.swift | 31, 66, 194, 201, 206, 225, 226, 368, 401 | 9 | 添加队伍已改；列表行、系统工具栏/菜单/警告、圆形删除保留。 |
| jifen/Features/Tools/RandomTeamView.swift | 105, 124, 128, 204 | 4 | 人数与系统组数选择保留；重选/模拟/再来一次动作模板已改。 |
| jifen/Features/Tools/StopwatchView.swift | 172 | 1 | 开始/暂停/计次/重置圆形计时控制保留。 |
| jifen/Features/Tools/TenSecondChallengeView.swift | 104 | 1 | 固定200×60、圆角30，视觉已完整胶囊。 |
| jifen/Features/Tools/ToolsTab.swift | 105 | 1 | 工具图文入口卡保留。 |
| jifen/Features/Tools/WhistleToolView.swift | 80, 120 | 2 | 正方形哨音图文大触发卡保留。 |
| jifen/Features/Timer/CubeTimerView.swift | 130, 214 | 2 | 提示确认原已胶囊；返回/截图/重置圆形图标保留。 |
| jifen/Features/Timer/DualPlayerTimerView.swift | 164, 165, 176, 177, 270, 298, 322, 415, 492, 525, 538 | 11 | 系统确认、点击切换胶囊、圆形先手/思考状态与计时工具、重赛/退出胶囊保留。 |
| jifen/Features/Timer/DualTimerSetupView.swift | 89 | 1 | 开始为系统工具栏操作，关闭为共用ModalCloseButton，保留。 |
| jifen/Features/Timer/TimeoutCountdownView.swift | 196, 264, 305, 336, 359, 375, 460 | 7 | 圆形工具/播放/重置/步进器、胶囊运动/模式、圆角时长预设保留。 |
| jifen/Features/Timer/TimerTab.swift | 145 | 1 | 计时工具图文入口卡保留。 |

## 收尾复核

- 全量复扫剩余 154 处 RoundedRectangle / cornerRadius / UnevenRoundedRectangle 语法：对应上述保留选项、数字键、步进器、卡片、输入框、弹层、预览图片、计时显示或装饰容器；未发现遗漏的有底普通操作按钮。
- 另核对无底文字操作：字体面板恢复默认、补时列表撤销、截图预览卡页脚分享按行内辅助链接保留。它们不属于已有有底按钮的半圆头缺失。
- 验证相对逐文件基线的 diff，14 文件仅有 22 行形状替换；本轮不产生行号变化。编译交由根代理在最后一次 TableTennis 修改后重跑。

## 投屏小组和共用组件逐项判断

All file paths below are relative to `/Users/yangyang/Desktop/jifenqi/jifen-ios/`. The complete full-path and line inventory follows this decision table.

| File | Decisions and labels |
| --- | --- |
| [jifen/Features/Display/CastConnectionView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/CastConnectionView.swift) | `77`: preserve plain **无线投屏使用说明** expansion row; card container is 16 pt rounded rectangle, not a standalone action. |
| [jifen/Features/Display/CloudSyncEntryView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/CloudSyncEntryView.swift) | Fixed action helpers/calls `165,218,296,399,868,878,896` as above. Preserve native confirmation-dialog **结束同步 / 取消** `75,79,722,726`; plain explanation/role-card expansion rows `484,604`; circular sharing icon `668` and circular dialog close icon `768`. Remaining 8/10/12/16 pt rounded rectangles are input/device-row/card/dialog containers (`343,473,557,647,845`). |
| [jifen/Features/Display/RemoteDisplayView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/RemoteDisplayView.swift) | `167,229`: **退出显示端** already capsule (160 × 48); `258`: floating back chevron is deliberately circular 48 × 48. Status banner and logo shapes are non-action decoration. |
| [jifen/Features/Display/ScoreboardExternalDisplayView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/ScoreboardExternalDisplayView.swift) | `1667`: **退出** already native `.bordered`; surrounding overlay uses a card radius, not button radius. No change. |
| [jifen/Features/Groups/GroupActivityViews.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupActivityViews.swift) | `41,331`: saved-location icon controls preserve icon presentation. Other 20 lines are native Form/List, toolbar or system-dialog actions: reload/save/edit/register/arrange/finish/retry/cancel, start/resume/manual result/release match, add/save/remove matches. Their layout has no custom non-capsule action background/outline. |
| [jifen/Features/Groups/GroupDetailView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupDetailView.swift) | `77,242`: already capsule-backed actions (**直接排赛 / 取消解散**). `83,403,504,603,606,720,737,741`: native bordered/prominent actions (**发布活动 / overview actions / 确认结果 / 拒绝或同意 / empty-state action / 保留编辑或使用最新版本**) preserve native capsules. `128,130,184,190`: native confirmation or toolbar/menu actions. `165`: tab selection deliberately uses a rounded-rectangle segment inside the shared 12 pt segmented track. `520,556`: format menu/ranking choices preserve selection roles. `278,280,290,297,490,491,493,539,620`: inline copy/invite/sync/correct/discard/load/add links. `281,304`: QR-image controls; `633,662`: chevron icons. `325,351,362`: whole-card navigation/disclosure controls preserve card shape. |
| [jifen/Features/Groups/GroupForms.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupForms.swift) | `59,70,72`: **比赛规则 / 重试 / 提交结果或开始计分** are native form actions; preserve presentation. |
| [jifen/Features/Groups/GroupManagementView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupManagementView.swift) | `75,85,89,90,94,102,112,167`: native form/toolbar/dialog **移除成员 / 加载最新 / 保留编辑 / 确认 / 保存 / 导入** actions. `162`: multi-select member row with selection indicator; preserve choice role. |
| [jifen/Features/Groups/GroupPreviewReportView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupPreviewReportView.swift) | `19`: **提交举报** native form action; preserve. |
| [jifen/Features/Groups/GroupPushViews.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupPushViews.swift) | `20,23`: **开启系统通知 / 重试** native List action rows. `63`: inline retry in destination error state; no custom shape to replace. |
| [jifen/Features/Groups/GroupQRViews.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupQRViews.swift) | `48`: native borderless QR-scanner affordance. `52,63,67,76,81,85`: native Form **预览 / 撤回 / 打开小组 / 加入 / 举报** actions. `97`: keyboard toolbar **完成**. `249`: native share-page **复制小组号** action. |
| [jifen/Features/Groups/GroupRegistrationEditor.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRegistrationEditor.swift) | `95,96,117`: native form and confirmation-toolbar **加载最新 / 确认 / 保存**. `102,104`: native discard/keep-edit dialog actions. |
| [jifen/Features/Groups/GroupResultScoreControls.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupResultScoreControls.swift) | `28,50,53`: inline form clear/add-score actions; `44`: minus-circle deletion icon. `62`: manual/set-detail disclosure row. `75`: numeric score preset choice; `120`: rule choice, both native bordered selection controls. `102`: keyboard **完成**. The 12 pt rounded rectangle at `127` belongs to the choice-group container. |
| [jifen/Features/Groups/GroupScheduleEditor.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupScheduleEditor.swift) | All 9 source lines are native form/toolbar actions: shift/remove/add session, reload, preview and publish/save. No custom non-capsule action style. |
| [jifen/Features/Groups/GroupSupportViews.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupSupportViews.swift) | `15,18`: clear/select member List choices. `59`: native temporary-member add affordance. `95,98,116`: restore rules/done/add game-score native form/toolbar actions. `113`: minus-circle icon. `133,145,273,275,341,381,391,400`: retry/load/open/sign-in/rules/save native or inline actions. `158`: toolbar mark-all-read icon. `205`: already circular individual mark-read icon. |
| [jifen/Features/Groups/GroupTrainingNoticesView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupTrainingNoticesView.swift) | `36`: inline **已读** action inside notice card; `79`: native cancellation-form action. Preserve hierarchy. |
| [jifen/Features/Groups/GroupTrainingViews.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupTrainingViews.swift) | `38`: **新增训练** already native bordered plus capsule background. `54,55`: native menu actions. `99,116,117,119`: native bordered/prominent **已读 / 开始计分 / 补记 / 请假**. `266,287`: native form **请假 / 提交举报**. |
| [jifen/Features/Groups/GroupViews.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupViews.swift) | `158`: native prominent **创建小组**; `162`: bordered **加入小组** with existing capsule background. `491`: native prominent **确认结果**; `497`: **作废结果** fixed custom capsule outline. `22,29,30,32,308,508,565,568`: native form/list/inline retry/refresh/withdraw/join/create/reload/load actions. `70`: beta-notice expansion row. `88`: circular notification icon. |
| [jifen/Features/Shared/InAppWebLink.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Shared/InAppWebLink.swift) | `212`: web-load **重试**, native bordered prominent; preserve native capsule. |
| [jifen/Core/Components/CustomDialogs.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Core/Components/CustomDialogs.swift) | `33`: help question-mark icon; preserve icon role. `172`: reusable confirm/cancel action already uses `Capsule().fill(...)`, height 48; preserve. 16 pt radius at `157` is the dialog card. |

## 补充检查范围

- [jifen/Features/CommonData/CommonDataCloudSyncManager.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/CommonData/CommonDataCloudSyncManager.swift) is data synchronization logic only.
- [jifen/ContentView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/ContentView.swift) is the root forwarding view.
- [jifen/Features/MainTabView.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/MainTabView.swift) uses native `TabView` items; no custom Button declaration.
- [jifen/Core/Theme/Theme.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Core/Theme/Theme.swift) provides semantic values/colors and no button style implementation that imposes a rounded rectangle on actions.
- Other files in the reviewed scope without a matching Button source line are models, fixtures, policy/helper logic or non-button display views.

## 投屏小组和共用组件按钮文件清单

| Full local file path | Matching source lines | Count |
| --- | --- | ---: |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupActivityViews.swift` | 41, 56, 75, 156, 161, 163, 174, 186, 188, 196, 216, 219, 240, 243, 245, 246, 248, 249, 331, 350, 358, 377 | 22 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupDetailView.swift` | 77, 83, 128, 130, 165, 184, 190, 242, 278, 280, 281, 290, 297, 304, 325, 351, 362, 403, 490, 491, 493, 504, 520, 539, 556, 603, 606, 620, 633, 662, 720, 737, 741 | 33 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupForms.swift` | 59, 70, 72 | 3 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupManagementView.swift` | 75, 85, 89, 90, 94, 102, 112, 162, 167 | 9 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupPreviewReportView.swift` | 19 | 1 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupPushViews.swift` | 20, 23, 63 | 3 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupQRViews.swift` | 48, 52, 63, 67, 76, 81, 85, 97, 249 | 9 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRegistrationEditor.swift` | 95, 96, 102, 104, 117 | 5 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupResultScoreControls.swift` | 28, 44, 50, 53, 62, 75, 102, 120 | 8 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupScheduleEditor.swift` | 112, 113, 116, 125, 154, 160, 170, 182, 183 | 9 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupSupportViews.swift` | 15, 18, 59, 95, 98, 113, 116, 133, 145, 158, 205, 273, 275, 341, 381, 391, 400 | 17 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupTrainingNoticesView.swift` | 36, 79 | 2 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupTrainingViews.swift` | 38, 54, 55, 99, 116, 117, 119, 266, 287 | 9 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupViews.swift` | 22, 29, 30, 32, 70, 88, 158, 162, 308, 491, 497, 508, 565, 568 | 14 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/CastConnectionView.swift` | 77 | 1 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/CloudSyncEntryView.swift` | 75, 79, 165, 218, 296, 399, 484, 604, 668, 722, 726, 768, 868, 878, 896 | 15 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/RemoteDisplayView.swift` | 167, 229, 258 | 3 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/ScoreboardExternalDisplayView.swift` | 1667 | 1 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Shared/InAppWebLink.swift` | 212 | 1 |
| `/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Core/Components/CustomDialogs.swift` | 33, 172 | 2 |


## 应用根视图补充

`jifen/jifenApp.swift:477,485` 的确定按钮均属于系统 alert，保留原生外观。ContentView 和 MainTabView 没有自定义 Button 声明；TabView 保留系统标签栏。全项目另行检查 onTapGesture、NavigationLink、PhotosPicker 和复用控件入口，展示卡片、缩略图、开关、遮罩和计分大触区按用途保留。

## 安卓和鸿蒙参考

- `/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/ui/theme/DesignSystem.kt:79-98`: ordinary text action buttons use `AppButton.shape = RoundedCornerShape(AppRadius.pill)`. Numeric, choice, and icon controls retain their own shape. Ordinary, compact, prominent, and inline action sizes are 48/40/56/44 dp.
- `/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/ui/theme/DesignSystem.kt:109-116`: `AppChoice.shape = RoundedCornerShape(AppRadius.md)` keeps form choices separate from actions (12 dp rounded rectangle).
- `/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/ui/components/AppControlComponents.kt:41-49`: `AppActionButton` defaults its shape to `AppButton.shape`.
- `/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/cloudsync/ui/RemoteSyncEntryPanel.kt:370-392,435-461`: generation/join entry actions use `AppActionButton`, inheriting the shared pill shape. `/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/cloudsync/ui/RemoteSyncSharedUi.kt:582-615` uses the shared action/outline shape for force-sync, copy-code and end-sharing controls.
- `/Users/yangyang/Desktop/jifenqi/jifen-hos/scripts/audit_button_shapes.mjs:5-9`: actions explicitly use `ButtonType.Capsule` with no direct `borderRadius` or `border.radius` override; choice/chip uses `BorderRadius.option` (12 vp).
- `/Users/yangyang/Desktop/jifenqi/jifen-hos/scripts/audit_button_shapes.mjs:24-27`: cards/dialogs retain their container radii; do not mechanically convert containers or choices into action buttons.
- `/Users/yangyang/Desktop/jifenqi/jifen-hos/scripts/audit_button_shapes.mjs:52-98`: deliberate exceptions include scoring controls, calendar/date choices, color dots, crop circles, joined watch-start halves, watch pairing circles, large whistle tool stages, presets and form options.
- `/Users/yangyang/Desktop/jifenqi/jifen-hos/scripts/test_button_shapes.mjs:77-108`: broad scoring/date-picker exceptions must not hide ordinary confirm/cancel/save actions; icons, circles, joined halves and choice controls remain specialized.
- `/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/display/RemoteSyncEntryPanel.ets:820-920`: main action, outline main action, outline destructive action, and join-display builders all explicitly use Capsule. Same sync feature as the requested iOS change.
- Git context: HarmonyOS commit `ebba02b0` dated 2026-10-18 contains the button shape audit/apply/test scripts and broad action-button cleanup; `9a744e4e` dated 2026-10-18 continues UI/theme work. Android currently has substantial uncommitted changes and its shared pill policy is already in HEAD; current uncommitted sync diff concerns dialog title bars, not button shape.

