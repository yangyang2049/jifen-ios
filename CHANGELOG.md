# Changelog

## [Unreleased]

### Fixed
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
