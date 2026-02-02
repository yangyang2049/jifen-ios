# Changelog

## [Unreleased]

### Fixed
- 计分板（乒乓球/网球/排球）：在 addScore 中加分之前增加「局/盘/抢七已结束则不再加分」的防护，避免快速连点导致分数超出胜局条件（如乒乓球 12:2）。羽毛球此前已在加分前做局胜判断并 return，逻辑正确未改。
- Watch App: 修复所有界面显示字符串 key（如 tab_score、game_badminton、game_tennis）而非本地化文案的问题。为 Watch 应用添加独立 Resources（en.lproj / zh-Hans.lproj）下的 Localizable.strings，使 NSLocalizedString 从 Watch 自身 bundle 正确加载中英文文案。
- Watch App 抛硬币：修复动画结束时硬币不正对用户的问题。原因是旋转圈数包含小数导致最终角度不是 0°/180°；改用整数圈数（4-6圈随机），确保硬币落地时正面朝上（0°）或反面朝上（180°）。
- Watch App 抛硬币：重新设计硬币外观，与鸿蒙版本风格一致。
- Watch App 随机数字：为起始 👆 emoji 添加脉冲动画，提示用户点击。
- Watch App：将「记录」从计分页移出，改为独立 Tab，顺序为：工具 → 计分 → 记录 → 设置。
- Watch App 十秒挑战：未计时时显示 👆 并添加与随机数字相同的脉冲动画，提示点击开始。
- Watch App 计分 Tab：将网球排在乒乓球之前，顺序为羽毛球 → 网球 → 乒乓球。
- Watch App 记录：列表行显示相对时间戳（如 5分钟前、2小时前、3天前），与鸿蒙 SportsSetupDialog 一致；记录详情「比赛记录」中每条动作为相对比赛开始时间显示 MM:SS 或 HH:MM:SS，与鸿蒙 WatchRecordDetail 一致；盘结束/比赛结束动作用强调色。使用径向渐变模拟金属光泽，添加边缘高光描边增强立体感，文字添加微妙阴影呈现浮雕效果。尺寸比例调整为 120/110/104（与鸿蒙 144/132/124 比例一致）。
- Watch App 抛硬币：引入与主应用/鸿蒙一致的 flip_coin.mp3 音效；将 flip_coin.mp3 放入 Watch App Resources，抛硬币时使用 mp3 播放。
- Watch App 首页 Tabs：计分、工具、记录、设置四个 Tab 的页面标题使用内联样式（.navigationBarTitleDisplayMode(.inline)）。

### 三端一致（iOS 主应用 / Watch / 鸿蒙）
- **休息弹窗 + 撤销**：iOS 主应用局间/局中/盘间休息弹窗（RestCountdownOverlay）增加可选「撤销」按钮；羽毛球/乒乓球/网球计分页在显示休息时传入 onUndo，与 Watch、鸿蒙一致。鸿蒙 Watch 局中休息已在 ViewModel 中调用 showUndoButton。
- **日期同年不显示年份**：iOS 主应用 ScoreboardRecordSummary.date、ScoreboardRecordDetailPage.formatDate 改为同年 MM-dd、跨年 yyyy-MM-dd；鸿蒙多人计分记录详情页（MultiGroupRecordDetailPage）日期改用 formatDateWithConditionalYear。Watch 记录详情此前已改。

### Added
- iOS 主应用：新增「记录」Tab（与 Watch 一致）。Tab 顺序为首页 → 计分 → 记录 → 工具；记录 Tab 展示计分记录列表（按日期分组）、空状态与加载态，点击进入记录详情。首页「最近记录」保留最近 3 条，底部「查看全部记录」改为跳转到记录 Tab（onViewAllTapped），不再进入活动页。

### Fixed / Improved
- 计分板：羽毛球、网球导航标题改为 NSLocalizedString（game_badminton / game_tennis），与其余运动一致。
- 计分板：篮球、足球、排球增加比赛结束浮层（GameFinishedOverlay），ViewModel 增加 getWinnerName()，与乒/羽/网一致。
- 计分板：排球局数已通过 TeamData.sets 与 TeamSection 展示，无需改动。
- 计分板：菜单（MenuDialog）标题与项（操作、哨子、截图、交换边、重置、撤销）、休息弹窗撤销按钮、比赛结束浮层「X 获胜」改为本地化文案（operations / menu_whistle / menu_screenshot / menu_swap_sides / menu_reset / menu_undo / game_winner_format）。
- 主应用抛硬币（FlipCoinView）：对齐 Watch 实现——整数圈数（4–6 圈）保证落地 0°/180° 无跳变；硬币外观改为径向渐变（外/中/内 180/165/156）、边缘描边、正反面文字阴影；动画用 ease-out cubic、perspective 0.6、scale 0.25；结束时使用精确 targetAngle 不做二次 snap。
- 快速开始设置：按钮文案由「完成并保存」改为「保存」（中英文 Localizable.strings）。
- 记录详情分享：从鸿蒙 jifen MultiGroupRecordDetailPage 移植分享功能。比赛详情页菜单增加「分享」项；将记录摘要（项目、比分、日期时间等）渲染为图片，通过系统分享面板（UIActivityViewController）分享；新增 RecordDetailShareCardView、ShareActivityView 及 share_match_record 本地化。
- 发布前清理：新增 RELEASE_CHECKLIST.md（除 App Icon、Launch Screen 外的发布检查项）。QuickStartConfigManager.saveConfig 中 fatalError 改为 do/try/throw；所有调试用 print() 包在 #if DEBUG；SportsSetupDialogView 中 CommonNameSelectorDialog 占位按钮移除 print。
- Watch 显示名：与主应用一致。新增 Watch App Resources 下 en.lproj/InfoPlist.strings、zh-Hans.lproj/InfoPlist.strings，CFBundleDisplayName 分别为「iScore」「全能计分器」；移除 project.pbxproj 中 Watch target 的 INFOPLIST_KEY_CFBundleDisplayName = jifenWatch。
