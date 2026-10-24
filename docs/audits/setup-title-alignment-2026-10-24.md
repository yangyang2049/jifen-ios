# 多端 Setup 小标题对齐与字体梳理

日期：2026-10-24。范围：当前中文界面 29 个计分目录项目，并补充 4 个棋类计时 Setup。

状态：已按用户后续授权完成 iOS、Android 国内版、Android Google 版和鸿蒙的标题对齐，以及后续字号、颜色、字重统一，详见文末两轮实施记录。下方原审计表保留修复前的状态。

审计以工作区源码和中文资源为准；10 月 21 日已有 Setup 截图仅辅助观察，未重新进行全量界面运行验证。

## 建议

计分 Setup 的独立小标题统一居中；开关行、步进器行、名称输入和列表选项按控件结构保留左对齐。当前大多数项目已经符合，主要需要调整掼蛋的两处独立小标题。

现有共享 `settingsLabelStyle()` 已明确采用 14pt、次要文字色、全宽居中。建议顺着这套规范收拢，而不是重新设计所有 Setup。

| 文字角色 | 建议对齐 | 原因 |
|---|---|---|
| 弹窗顶部的项目大标题 | 居中，保持 | 当前 29 个计分项目已经如此 |
| 选项或数字按钮上方的独立小标题 | 居中 | 与现有局数、每局分数、目标分等分组一致 |
| 发球方、开球方、首局开球方、首发选手 | 两侧选择图标之间居中，保持 | 表示左右双方共享的选择，不属于左侧字段标签 |
| 三 A、显示时间、每球得分、比赛抬头等开关标签 | 左标签、右开关，保持 | 同一行的文字和控件需要清楚关联 |
| 大金、小金等数值调节行 | 左标签、右加减控件，保持 | 便于逐行扫描和比较 |
| 姓名输入、板式网球规则列表 | 左对齐，保持 | 输入文字和列表选项不属于独立分组标题 |
| 自动换边、显示时间、语音播报等功能卡 | 卡内居中，保持 | 是功能卡标签；当前没有可见的“比赛功能”分组标题 |
| 投篮训练的说明段落 | 左对齐，保持 | 是说明文字，不是小标题 |
| 棋类计时 sheet 的表单分组标题 | 左对齐，保持 | 输入表单内部保持一致即可，适合独立于计分卡片采用自己的对齐规则 |

## 29 个计分项目全表

下表“→”表示自上而下的顺序；每个项目顶部的大标题均已居中，不在每行重复。

“姓名区”包含选手姓名或队伍名称。姓名区目前没有独立的“姓名”“队伍”小标题，无需为了统一补加。发球方等标题位于姓名区下方、左右选择图标之间；其余独立小标题位于对应选项、数字按钮或输入组上方。

| 项目 | 独立小标题（自上而下） | 位置与显示条件 | 当前对齐 | 行标签或其他文字 | 建议 |
|---|---|---|---|---|---|
| 羽毛球 | 发球方 → 局数·经典/打满 → 每局分数 | 姓名区下方；局数和分数按钮各自上方 | 均居中 | 底部自动换边、语音播报为功能卡 | 保持 |
| 网球 | 发球方 → 盘数·经典/打满 | 发球方在姓名区下；盘数仅在标准赛制显示，位于赛制选项之后、四局制/六局制之前 | 均居中 | 标准赛制/抢七赛/抢十赛、四局制/六局制、抢七/抢十、占先/无占先均为选项；无需补加标题 | 保持 |
| 乒乓球 | 发球方 → 局数·经典/打满 → 每局分数 | 姓名区下方及对应数字按钮上方 | 均居中 | 单打底部有自动换边、显示时间、语音播报；双打无显示时间卡；播报发球方为弹出开关标签 | 保持 |
| 匹克球 | 发球方 → 局数·经典/打满 → 目标分 → 最高分上限 | 上限标题仅在目标分为 11 时显示 | 均居中 | 每球得分为左标签、右开关 | 标题保持居中；开关行保持左对齐 |
| 毽球 | 发球方 → 每局分数 | 赛制和姓名区下方；每局分数在数字按钮上方 | 均居中 | 单打/双打/混双/团队赛是顶部选项；姓名输入随赛制变化 | 保持 |
| 壁球 | 发球方 → 局数·经典/打满 | 姓名区下方；局数按钮上方 | 均居中 | 底部功能卡不是独立标题 | 保持 |
| 软式网球 | 发球方 → 全场局数 | 姓名区下方；7/9 局选项上方 | 均居中 | 实际中文为“全场局数”，源码 fallback 为“整场局数” | 保持 |
| 板式网球 | 发球方 → 平分规则 | 双打姓名区下方；规则列表上方 | 标题居中 | 占先/黄金分/星星分列表文字在左、勾选在右 | 标题和列表均保持现状 |
| 足球 | 无 | 只有双方队名，无独立规则标题 | — | 姓名字段靠左，双方之间有 vs | 不改，不补标题 |
| 5×5 足球 | 半场时长 | 姓名区下方、减号/时间值/加号上方；文字与帮助按钮成组 | 标题和帮助按钮整体居中 | 实际中文为“半场时长”，源码 fallback 为“每半场时长” | 保持 |
| 篮球 | 规则 | 队名下方、FIBA/NBA 选项上方 | 居中 | 选项下规则摘要也居中 | 保持 |
| 三人篮球 | 无 | 只有双方队名，无独立规则标题 | — | 姓名字段靠左 | 不改，不补标题 |
| 投篮训练 | 无 | 模式选项下方有说明段落 | — | 1 分/2 分/3 分/自由在按钮内居中；说明段落靠左 | 不改，说明段落保留左对齐 |
| 排球 | 发球方 | 队名下方、左右发球图标中间 | 居中 | 下方自动换边、显示时间、语音播报为功能卡，无“比赛功能”标题 | 保持 |
| 沙滩排球 | 发球方 | 队名下方、左右发球图标中间 | 居中 | 下方为功能卡 | 保持 |
| 气排球 | 发球方 | 队名下方、左右发球图标中间 | 居中 | 下方为功能卡 | 保持 |
| 射箭 | 首发选手 | 姓名区下方、左右选手图标中间 | 居中 | 无其他独立规则标题 | 保持 |
| 拳击 | 回合数 | 姓名区下方、回合数字按钮上方 | 居中 | 本 Setup 没有单回合时长/休息时长小标题 | 保持 |
| 台球 | 无 | 只有双方姓名，无独立规则标题 | — | 姓名字段靠左 | 不改，不补标题 |
| 斯诺克 | 首局开球方 → 局数 | 姓名区下方；局数在数字按钮上方 | 均居中 | 比赛抬头是左标签、右开关；开启后追加输入框 | 标题保持居中；比赛抬头行不改 |
| 黑八追局 | 局数 → 让局 | 姓名区下方；让局仅在局数大于 1 时显示 | 均居中 | 无/左让右/右让左是选项；选择让局后追加数字选项，没有额外标题 | 保持 |
| 九球追分 | 事件分值 | 人数和姓名列表之后、六个事件调节行上方 | 居中，12pt | 大金/小金/黄金九/普胜/自由球/犯规均为左标签、右加减控件 | 对齐不改；字号可统一为 14pt |
| 斗地主 | 无 | 人数选项 → 玩家名称列表 | — | 3/4 人为分段选项；姓名输入靠左 | 不改，不补标题 |
| 掼蛋 | 过 A 条件 → 三 A 不过回退到 | 前者在队名下、条件选项上方；后者仅开启三 A 后显示，位于等级网格上方 | **两处均左对齐，12pt** | 三 A、显示时间是左标签、右开关 | **两个独立小标题改居中**；开关行保持；字号可统一为 14pt |
| 升级 | 无 | 双方队名之后是显示时间开关 | — | 显示时间为左标签、右开关，没有掼蛋的规则标题 | 不改 |
| UNO | 目标分 | 人数和姓名列表之后、目标分按钮上方 | 居中，12pt | 玩家名称靠左；分值按钮和自定义分数输入居中 | 对齐不改；字号可统一为 14pt |
| 桌上足球 | 开球方 → 局数·经典/打满 → 每局分数 → 决胜局最高分上限 | 姓名区下方；上限标题仅开启决胜局净胜 2 分后显示 | 均居中 | 决胜局净胜 2 分为左标签、右开关；顶部 1V1/2V2 为选项 | 标题保持居中；开关行不改 |
| 简单计分 | 无 | 双方队名 → 自定义加减分 → 显示时间 | — | 两项均为左标签、右开关，自定义加减分另带帮助按钮 | 不改 |
| 多人计分 | 无 | 人数选项 → 姓名列表 → 自定义加减分 | — | 人数按钮文字居中；姓名靠左；自定义加减分为左标签、右开关 | 不改 |

补充条件：支持语音的项目在语音不可用时会隐藏语音播报卡。如果只剩一个功能，布局会退化为左标签、右开关的横条，这种条件布局无需改成居中。

## 棋类计时 Setup 补充

这四项属于计时 Tab 的系统 sheet，不属于上面的 29 个计分项目。顶部项目名称居中；正文是输入表单。

| 项目 | 独立小标题 | 位置与显示条件 | 当前对齐 | 建议 |
|---|---|---|---|---|
| 围棋 | 主时间 → 读秒 | 模式选择下方；读秒仅在读秒模式显示 | 均左对齐 | 保持表单分组左对齐 |
| 象棋 | 主时间 → 加秒 | 模式选择下方；加秒仅在加秒模式显示 | 均左对齐 | 保持 |
| 国际象棋 | 主时间 → 加秒或延迟 | 模式选择下方；根据计时模式显示，倒计时模式无附加标题 | 均左对齐 | 保持 |
| 国际跳棋 | 主时间 → 加秒 | 模式选择下方；加秒仅在加秒模式显示 | 均左对齐 | 保持 |

四者下方“语音播报”“震动反馈”都是左标签、右开关，建议保持。秒表、魔方计时和暂停倒计时没有同类的入场 Setup；暂停倒计时的编辑时间弹层是工具内编辑，不混入本次开局 Setup 标题统一。

## 建议改动清单

1. 优先：掼蛋“过 A 条件”“三 A 不过回退到”改居中。仅修对齐共两处。
2. 可选：把掼蛋上述两处、UNO“目标分”、九球追分“事件分值”统一复用 14pt 小标题样式，共四处；这是字号/样式统一，不是另外两处对齐错误。
3. 如果调整共享标题样式，可补充多行文字居中，避免长翻译换行后内部行仍靠左；保留现有开关、输入和数值行布局。
4. 其他计分项目和四个棋类计时 Setup 保持；无需为没有独立小标题的姓名区、选项组补标题。

## 源码依据

- 当前完整目录共 29 项：[GameCatalog.swift:95](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Shared/GameCatalog.swift:95)。入口使用目录，不能用 `HomeTab` 中未使用的不完整旧集合推断全量范围。
- 四类 Setup 路由：[HomeTab.swift:981](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/HomeTab.swift:981)。21 项通用 SportsSetup、6 项休闲、九球追分、投篮训练。
- 通用小标题规范：[SportsSetupCommonNameViews.swift:70](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/SportsSetupCommonNameViews.swift:70)。
- 通用项目大标题与内容顺序：[SportsSetupDialogView.swift:35](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/SportsSetupDialogView.swift:35)。
- 姓名结构、单双打及赛制：[SportsSetupParticipantSection.swift:25](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/SportsSetupParticipantSection.swift:25)；发球方等标题：[同文件:198](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/SportsSetupParticipantSection.swift:198)。
- 通用设置分支：[SportsSetupSettingsSection.swift:114](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/SportsSetupSettingsSection.swift:114)；篮球/拳击 220/238，网球 254，软式网球 340，板式网球 351，每局分数 377，匹克球 392，桌上足球 420，黑八追局 471，斯诺克 505，局数模式标题 751。
- 功能卡范围及“无分组抬头”：[SportsSetupMatchFeatures.swift:45](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/SportsSetupMatchFeatures.swift:45)。
- 休闲项目布局顺序：[MultiScoreSetupDialogView.swift:186](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:186)；掼蛋两处标题：[同文件:368](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:368)；UNO 标题：[同文件:434](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:434)。
- 掼蛋、升级、简单计分显示时间开关的精确范围：[ScoreboardLaunchView.swift:15](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Scoreboard/Shared/ScoreboardLaunchView.swift:15)。
- 九球追分标题及行标签：[NineBallSetupDialogView.swift:42](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/NineBallSetupDialogView.swift:42)、[同文件:157](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/NineBallSetupDialogView.swift:157)。
- 投篮训练模式及说明：[ShotTrainingSetupDialogView.swift:63](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/ShotTrainingSetupDialogView.swift:63)。
- 棋类计时 Setup 分组：[DualTimerSetupView.swift:112](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Timer/DualTimerSetupView.swift:112)；模式范围：[BoardTimerConfig.swift:74](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Timer/BoardTimerConfig.swift:74)。
- 中文实际名称与文案：[Localizable.strings:735](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Resources/zh-Hans.lproj/Localizable.strings:735)；半场时长、全场局数：[同文件:823](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Resources/zh-Hans.lproj/Localizable.strings:823)。

## 2026-10-24 第一轮实施：标题对齐

用户授权修复 iOS 两处，并检查、修复安卓和鸿蒙同类问题。本轮仅修改标题对齐；保留原有字号、字体、颜色、间距、开关结构及状态逻辑，未执行上文可选的 14pt 字号统一。

| 端 | 已修复的当前可见标题 | 数量 | 文件 |
|---|---|---|---|
| iOS | 掼蛋“过 A 条件”“三 A 不过回退到” | 2 | [MultiScoreSetupDialogView.swift:370](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:370) |
| Android 国内版 | UNO“目标分”、掼蛋上述两个标题 | 3 | [CardGameSetupDialog.kt:431](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/score/setup/CardGameSetupDialog.kt:431) |
| Android Google 版 | 同国内版，独立仓库分别修正 | 3 | [CardGameSetupDialog.kt:431](/Users/yangyang/Desktop/jifenqi/jifen-android-google/app/src/main/java/com/douhua/jifen/screen/score/setup/CardGameSetupDialog.kt:431) |
| 鸿蒙 | UNO“目标分”、掼蛋“过 A 条件”和三把不过 A 的退回等级标题 | 3 | [CasualGameSetupDialog.ets:769](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/components/CasualGameSetupDialog.ets:769) |

另将鸿蒙网球备用“盘数”标题样式由 Start 改为 Center：[TennisSettingsSection.ets:98](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/components/sportsSetup/sections/TennisSettingsSection.ets:98)。当前唯一调用传 `showSetOptions: false`，这处不计入当前可见问题数量。

跨端检查覆盖各一级运动、休闲/棋牌、九球、投篮训练 Setup，并检查 Android/HarmonyOS 的麻将 Setup。其余独立小标题已由显式居中或父容器居中；Android/HarmonyOS 九球的“事件分值/追分设置 + 右侧编辑箭头”属于编辑入口行，保留现状。麻将二级规则编辑页维持其内部一致的左对齐表单布局。

验证：iOS 修改文件通过 `xcrun swiftc -frontend -parse`；四个仓库本次涉及的代码文件均通过 `git diff --check`。Android 两仓与操作前备份比较均只有上述三处标题变化，最终相关文件完全一致，Google 仓既有改动完整保留。此次只采用现有布局属性，按照小型样式改动的验证策略跳过全量构建；未执行新的截图回归、安装或发布。

## 2026-10-24 第二轮实施：字号、颜色和字重

用户要求检查各端 Setup 的字号例外，尤其小标题的字号、颜色及字重，发现问题直接修复。本轮沿用前述计分 Setup 与棋类计时 Setup 范围，Android/HarmonyOS 同时检查麻将开局及其编辑表单。

### 统一规则

- 独立小标题：14pt/sp/fp、常规字重、各端现有主题的次要文字色。计分弹窗继续居中，棋类输入表单继续左对齐。
- iOS 计分 Setup 底部操作：16pt；取消常规字重、开始 Medium，与通用运动/休闲 Setup 一致。
- 功能卡、紧凑模式选项、输入字段、编号、数值、说明及错误提示继续按各自的文字角色使用样式。棋类系统导航栏保留平台原生标题样式。
- 直接复用现有 `settingsLabelStyle()`、`AppTextStyles.fieldLabel`、`SetupStyle.sectionTitleFontSize` 与主题色；不修改全局 Token 值，也不调整业务行为。

| 端 | 发现的例外 | 已完成修正 |
|---|---|---|
| iOS | 掼蛋两个标题、UNO“目标分”、九球“事件分值”仍为 12pt | 四处改用共享小标题样式，统一 14pt、Regular、次要色；共享样式明确常规字重并支持换行居中 |
| iOS | 九球取消/开始及投篮训练取消未显式设定完整字号；投篮训练开始为 Semibold | 四个操作统一为 16pt，取消 Regular、开始 Medium |
| Android 国内版 | UNO、掼蛋的三个标题使用 Medium、主文字色 | 三处改用与运动项目相同的 `fieldLabel`，14sp、Normal、次要色 |
| Android 国内版 | “半场时长”缺少显式标题颜色和完整文字样式 | 使用 `fieldLabel` 与次要色，标题/帮助按钮布局不变 |
| Android 国内版 | 棋类“主时间”为 16sp | 改用 14sp 的 `fieldLabel`，保持左对齐 |
| Android Google 版 | 同上述 Android 五处例外 | 分别在本仓同步修正，保留该仓已有其他改动 |
| 鸿蒙 | UNO、掼蛋三个独立标题为 Medium、主文字色 | 改为 Regular、主题次要色，字号继续使用现有 14fp Token |
| 鸿蒙 | 棋类主时间、读秒、加秒/延迟标题使用计分板专用次要色 | 三处实现分支统一为 Setup 现用的主题次要色，覆盖四类文字；保持 14fp 和左对齐 |

### 代码位置

- iOS 共享样式：[SportsSetupCommonNameViews.swift:71](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/SportsSetupCommonNameViews.swift:71)。掼蛋/UNO：[MultiScoreSetupDialogView.swift:368](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:368)；九球：[NineBallSetupDialogView.swift:63](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/NineBallSetupDialogView.swift:63)；投篮训练操作：[ShotTrainingSetupDialogView.swift:94](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/ShotTrainingSetupDialogView.swift:94)。
- Android 国内版：[CardGameSetupDialog.kt:431](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/score/setup/CardGameSetupDialog.kt:431)、[SportsSetupScreen.kt:1514](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/score/SportsSetupScreen.kt:1514)、[TimerSettingsSheet.kt:134](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/timer/TimerSettingsSheet.kt:134)。
- Android Google 版：[CardGameSetupDialog.kt:431](/Users/yangyang/Desktop/jifenqi/jifen-android-google/app/src/main/java/com/douhua/jifen/screen/score/setup/CardGameSetupDialog.kt:431)、[SportsSetupScreen.kt:1520](/Users/yangyang/Desktop/jifenqi/jifen-android-google/app/src/main/java/com/douhua/jifen/screen/score/SportsSetupScreen.kt:1520)、[TimerSettingsSheet.kt:134](/Users/yangyang/Desktop/jifenqi/jifen-android-google/app/src/main/java/com/douhua/jifen/screen/timer/TimerSettingsSheet.kt:134)。
- 鸿蒙：[CasualGameSetupDialog.ets:764](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/components/CasualGameSetupDialog.ets:764)、[BoardTimerSettingsView.ets:281](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/components/BoardTimerSettingsView.ets:281)。

### 验证与边界

本轮修改前对 12 个目标源码文件保存快照；逐行检查相对此快照的新增差异，确认只有文字样式、相关导入与注释变化，没有覆盖此前修改或改动状态逻辑。

- iOS 四个修改文件一起通过 `xcrun swiftc -frontend -parse`。
- 四个仓库共 12 个修改源码文件均通过目标范围 `git diff --check`。
- Android 两版 `CardGameSetupDialog`、`TimerSettingsSheet` 文件一致；`SportsSetupScreen` 保留两仓原有差异，本轮新增的字体修正一致。
- 未改全局主题/字号 Token、开关和输入行的对齐、禁用态配色或数值规则。
- 此次为现有 API 下的局部文字样式修正，按仓库验证策略未运行全量构建；未重新执行模拟器/设备截图回归、安装或发布。
