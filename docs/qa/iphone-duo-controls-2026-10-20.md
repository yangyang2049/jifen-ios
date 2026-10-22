# iPhone Duo 内屏计分按钮与旧版样式侧栏补测

## 最终范围

仅展开内屏调整普通计分的编辑/完成按钮：与右下角菜单同一列，间隔 12pt。菜单在编辑时隐藏，完成按钮仍保留同一位置。外屏及普通 iPhone、iPad 保持原有顶部位置。新版样式编辑的确认勾保持原实现。旧版右侧样式面板只在内屏让内容遵守安全区，背景继续铺至边缘。

按钮覆盖七个共享或专用实现：ScoreboardTemplate、TwoSideScoreboardScaffold、Rally、Tennis、Basketball（含三人篮球）、Doudizhu、NineBallChase。UNO、多人计分没有同类普通编辑按钮，本轮检查其旧版样式面板。追分底部统计区为双层按钮额外预留 60pt，避免按钮移下后压住统计。

## 判断与布局

使用 iOS 27.1 的环境信息 `horizontalSizeClass == .regular && toolbarVerticalEdge != nil`，并明确排除现有 iPad idiom。它依据平台的宽布局及侧边系统栏能力适配，没有添加机型名称字符串、方向判断或宽高比例阈值，也没有改变现有旋转策略。折叠/展开后环境变化会重新计算，不缓存屏幕类型。iOS 27.1 以前保留原分支。

`toolbarVerticalEdge` 表示平台侧栏能力/首选侧边，不是硬件型号标识。这里是当前 SDK 下对用户指定适用范围的组合判断；将来平台能力变化应重新验证。Apple 的 [iPhone Duo 设计文档](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) 要求布局考虑保留区域、侧栏不对称及安全区。应用没有依照设备朝向决定编辑按钮位置。

本轮未分离或重置样式配置；篮球和三人篮球保留现有横屏策略。所有按钮留在原页面层级，网球仅在内屏打开菜单/结束弹窗时隐藏会覆盖弹窗的编辑浮层。

## 可复核证据

补测原始目录：`build/duo/controls-followup-20261020/`。交付副本：`/Users/yangyang/.codex/visualizations/2026/10/20/01a157c6-0a09-7783-82b6-306a2d7aca85/iphone-duo-review/controls-followup/`。

三个章节分别覆盖乒乓球/足球/黑八/网球，篮球/三人篮球/追分，以及斗地主/UNO/多人计分。每章分别录制内屏和外屏。检查普通编辑可进入/完成、按钮与菜单水平对齐、内屏在菜单上方、外屏仍位于上方、完成位置稳定；并检查新版样式确认入口，旧版面板取消及应用未变更的设置。内屏追分另外断言统计区位于编辑按钮上方。

MP4 是真实模拟器连续录屏，PNG 是对应时间点的原始画面；同名 JSON 保存界面层级。点击截图可跳到视频时间，支持内外屏筛选及倍速。每段 session.json 保留实际二进制指纹与日志；最终第二章在额外统计避让和明确排除 iPad 后重录，第一/三章保留行为相同的上一构建采集。失败/中间尝试归档在原始目录 attempts，不计入交付统计。

首轮主索引的 64 段/1,004 张是本修复之前的全应用巡检基线，不能当成本轮修复后的全部录像。新补测单独索引，避免混淆。本次仅重新遍历上述受影响的页面及弹窗，没有重新录制全应用。

## 验证结果

- 最终 Simulator build-for-testing 通过，日志 `build/duo/duo-controls-final-build.log`。
- Duo 内外屏共 6/6 段通过，102 张检查点（每种屏幕 51 张），17.10 分钟原始录像。内屏追分通过统计区避让断言。文件校验为 0 问题。
- 普通 iPhone 17 Pro Max、iPad Pro 13 M5 / iOS 26.5 各通过一次代表流程：乒乓球、足球、篮球，覆盖共享/专用布局及新旧样式面板。各保存 16 张 XCTest 截图到 ordinary-phone、ordinary-ipad。日志 `controls-ordinary-phone.log`、`controls-ordinary-ipad-final.log`。iOS 27.1 本机运行时仅支持 Duo，普通设备回归使用已安装的 26.5。
- Python 脚本编译及 git diff --check 通过。

本轮没有重跑前一轮的 131 项单元测试，也不把以前的通过数算作本轮结果。本次验证针对模拟器 UI，未声称全字号、所有动态字体、所有多人数量或所有窗口尺寸覆盖。

## 后续用户确认：追分明细贴底

用户随后明确要求追分底部明细不为浮动按钮区域留白，内外屏统一处理。已取消原有88pt以及内屏额外60pt预留，只保留4pt贴底间距，并删除“统计必须在编辑按钮上方”的旧断言。上文录像保留的是这次确认之前的画面；按用户要求不再重录。按钮本身仍沿用已确认的内屏菜单上方/外屏顶部位置。

本次贴底调整的Simulator build-for-testing通过，日志为build/duo/duo-nineball-bottom-build.log；未启动新的录屏或UI巡检。
