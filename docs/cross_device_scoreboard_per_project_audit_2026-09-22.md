# iOS ↔ Android 跨设备记分板逐项目核查（2026-09-22）

> 本文前半部分保留实施前的审计基线；三端实施后的逐项目状态见文末「实施更新」。

## 范围与判定口径

以当前工作区代码为准，逐项沿着「本机记分状态/设置 → iOS 显示快照 → wire 白名单 → iOS/Android 观看端」检查。iOS `CloudSyncGameTypes.supported` 有 **34 项**，Android `GameTypeCloudMapping.CLOUD_SYNC_SUPPORTED` 也有 **34 项**，交集 **33 项**：iOS 独有 `basketball_training`，Android 独有 `mahjong`。旧版协议审计把 iOS 总数写成 33，已与当前代码不符。两端工作树均可能包含未提交修改，本报告不代表已发布版本。

这里的「参数」指观看端需要的比赛设置和实时展示参数。跨设备房间传的是**显示投影**，不是本机 reducer 的完整比赛状态；例如每局目标分、所有操作历史和撤销栈一般不传，观看端也不能用它们独立继续计分。各项默认还共享 `schemaVersion/gameType/orientation/layoutKind/teams/appearance/result/keyPoint/updatedAt`，有需要时带 `players/sportState/clock/rest`；名称、比分、换边、字体、颜色和结束状态属于共有检查项。iOS `LocalScoreboardSyncCoordinator` 将同一快照发布到本机扩展屏和云端，云端仍经过 `DisplayStateWireCodec` 投影；Android 接收时又对 `sportState` 做白名单投影。

**验证方式**：静态逐链路检查；iPhone 17 模拟器运行 `ScoreboardDisplayTests/testAuditWireProtocolEvidence` 和 `testAuditDisplaySurfaceSnapshots`，**2 项通过**。后者以合成状态渲染 34 类 × 2 尺寸 × 2 投影 × 3 倍率，不能替代实际记分操作或两台真机建房互看。没有修改应用代码，也没有运行 Android 构建。

## 跨项目问题

| 编号 | 级别 | 方向与表现 | 代码依据 / 建议 |
|---|---|---|---|
| F1 | P1 | **Android 控制 → iOS 看多局赛果**：Android 不发 `resultScoreLevel`；iOS 结束遮罩无该键时默认显示 `finalScores.score`/当前点分，而 Android 自己会按项目取 `finalScores.sets`。胜者可正确，结束比分却是最后一局点分。影响下文标记 F1 的项目。 | iOS `ScoreboardExternalResultScorePresentation.score`；Android `resolveDisplayGameOverTeams` / `displayGameTypeUsesSets`。iOS 应从 `gameType` 和实际 `sets/games` 推断，不依赖仅 iOS 发送的键。 |
| F2 | P1 | **iOS 控制 → Android 看发球**：iOS Rally 快照只发屏幕侧 `servingSide`，Android 清洗时丢此键，双边箭头只查逻辑队伍 `servingTeam`。影响下文标记 F2 的单打/双边项目。双打球员 `isServer` 独立传送，球员级箭头仍可工作。 | iOS `RallyScoreboardView.makeSyncDisplayState`；Android `projectDisplaySportState` / `buildTwoSideServerIndicator`。发送端补稳定逻辑队伍 `servingTeam`，保留换边字段。 |
| F3 | P1 | **专用布局降级**：iOS 投篮训练 `shot_training_grid` 在 Android 落入普通双边板，iOS 毽球六人 `team_court` 在 Android 也落入普通双边板。前者丢 1/2/3 分命中/未中分区，后者丢场上六人名单。 | iOS 两项目快照及专用显示面板；Android `DisplaySurfaceModels.resolveTemplate` 无对应分支。若产品允许跨平台观看，需在 Android 加模板与字段消费。 |
| F4 | P1 | **软式网球赛果口径不一致**：iOS 本机规则是单盘、按 `games` 结束，却发 `resultScoreLevel="sets"`；Android 把 `soft_tennis` 视为「有 games、无 sets」，结束遮罩回退到 `score`。两端都没有稳定展示最终局数。 | iOS `TennisScoreboardView.tennisSyncSportState`、`TennisRuleSet.softTennis`；Android `displayGameTypeUsesSets/Games` 与结束遮罩。应明确此项目结束比分取 `games`，再双向测试。 |
| F5 | P2 | **掼蛋/升级 Android 控制 → iOS 看结束页**：实时 UI 会从项目键重建等级；结束遮罩却直接取通用数值分。Android 结束页有等级标签特殊处理。字母等级可能显示成 `0`。 | iOS `formatScoreText` 已读 `guandan*Rank/shengji*Rank`，`ScoreboardExternalResultScorePresentation` 未读；Android `displayGameOverCardRankLabel` 已处理。 |
| F6 | P2 | **网球无占先规则没有进入显示投影**：iOS 设置与本机规则有 `usesNoAdScoring`，Android 本机设置也有 `tennisDeuceMode`；两端发送器均未发送该键，尽管两端解码白名单与 UI 格式化器支持。正常无占先局一般不会形成 AD 持续态，所以当前直接 UI 影响有限；配置一致性不完整。 | iOS `tennisSyncSportState`；Android `TennisScoreScreen.cloudSportState`；两端 `tennisDeuceMode` 格式化分支。 |
| F7 | P3 | iOS 足球 `clock` 无 Android 的 `injuryTimeText`，但**当前两端观看 UI 都由 `footballHalfLengthMs/footballInjuryTargetMs` 计算补时文案**，没有证据显示当前画面丢失。九球 `chasePlayerNames/chasePoints`、UNO `unoRoundCount` 也有方向性字段缺口，现有观看 UI 使用 `players`/追分数/目标分，尚未发现对应可见损失。 | 作为协议元数据缺口记录，不能与 F1–F5 同级。 |

补充：四人斗地主 iOS 解析为 `cardThreePlayer`，Android 解析为 `MULTI_GRID`，但当前两端同步观看都落成**单行四列**；这是模板命名/实现差异，非本轮已证实的布局故障。iOS 一局制 Rally 会发 `resultScoreLevel="score"`，Android 会按项目统一显示局数 `sets`；结束页虽都能给出胜负，**一局制结束比分口径不同**，与 F1 属同一问题族。

## 逐项目小报告（iOS 全部 34 项）

下列「通过」表示当前代码的主要可见投影对齐，仍受上述静态验证范围限制。F 编号指向上表；`sets`/`games` 均为逻辑队伍身份，`team0ScreenSide` 决定换边后的视觉位置。

### 01. 足球 `football`
本机展示队名、进球、上下半场、运行计时与补时；iOS 快照传 `teams.score`、`clockStage/clockStageTitle` 及 `clock.footballHalf/footballHalfLengthMs/footballInjuryTargetMs`。两端观看 UI 都能由数值时钟重建比赛时间和补时，双边比分布局一致。**结论：主要 UI 通过；`injuryTimeText` 为 F7 元数据缺口。**

### 02. 五人制足球 `football_5v5`
与足球共用本机模板和计时投影，区别保留在 `gameType`；比分、半场、计时/补时进入同一类双边 UI。**结论：主要 UI 通过；同 F7。**

### 03. 篮球 `basketball`
本机有两队得分、犯规、节次/加时、比赛钟与进攻钟。wire 使用 `basketballCurrentPeriod/basketballIsOT/basketballLeftFouls/basketballRightFouls` 和 6 个篮球时钟锚点；不发通用 `clock`，与 Android 观看面板的 BasketballClockPill 口径一致。**结论：字段和主要 UI 通过。**

### 04. 三人篮球 `three_basketball`
复用篮球快照，`gameType` 区分规则；犯规、节次/加时、比赛钟/进攻钟仍按上述 10 键同步。**结论：字段和主要 UI 通过。**

### 05. 投篮训练 `basketball_training`
本机有固定分值/自由训练，未中/命中总数及 1/2/3 分分项。iOS 发 `shot_training_grid` 与 8 个 `training*` 键，iOS 观看端有对应分区模板；Android 不在云端可控清单，观看端也没有训练模板或字段分支。若 Android 显示端加入该房间，画面只能降级为两侧总数。**结论：iOS 内观看通过；跨到 Android 观看存在 F3。**

### 06. 排球 `volleyball`
本机显示分数、局数、发球侧和换边；iOS 发点分/局分、`team0ScreenSide/servingSide/resultScoreLevel` 及官方休息。Android 能显示分局与比分，但 iOS 控制时缺发球箭头；Android 控制时 iOS 结束分数会按 F1 回退到点分。一局制双方结束口径另有差异。**结论：F1、F2。**

### 07. 沙滩排球 `beach_volleyball`
使用同一 Rally 快照和双边 UI；分数、局数、休息倒计时有投影，发球与结束遮罩继承排球问题。**结论：F1、F2。**

### 08. 气排球 `air_volleyball`
使用同一 Rally 快照；分数、局数和官方休息可见，发球箭头与结束比分存在相同方向差异。**结论：F1、F2。**

### 09. 乒乓球 `pingpong`
本机有分数/局数/发球，以及双方暂停、黄牌、红牌计数。iOS 发 `tableTennisTeam0/1*` 六键与 Rally 共有字段，Android UI 能消费纪律状态；iOS 控制时 Android 双边发球箭头丢失，Android 控制时 iOS 结束遮罩点分/局分错位。**结论：纪律字段通过；F1、F2。**

### 10. 乒乓球双打 `pingpong_doubles`
本机四个姓名、上下站位、当前发球员、分数/局数、纪律状态。iOS 发 `doubles_court`、四个 `players.isServer`、六个纪律键；Android 双打模板能按球员发球字段画站位，因此 F2 的双边箭头缺口不等同于双打球员标记丢失。**结论：实时主要 UI 通过；结束遮罩 F1。**

### 11. 网球 `tennis`
本机展示 0/15/30/40/AD、局数、盘数、发球、抢七/换边。wire 以点数序号、`teams.games/sets`、`tennisIsTieBreak/tennisTiebreakOnly/tennisIsDeuce/tennisAdvantage` 和 `servingTeam` 表示；两端可重建实时 UI。无占先规则字段缺失；Android 控制时 iOS 结束遮罩未按盘数显示。**结论：实时主要 UI 通过；F1、F6。**

### 12. 网球双打 `tennis_doubles`
承接网球点/局/盘字段，另发 `doubles_court`、四名球员及 `isServer`；两端能绘制双打站位、比分和发球员。**结论：实时主要 UI 通过；F1、F6。**

### 13. 软式网球 `soft_tennis`
本机按软网规则显示普通局数字/AD、抢七、累计局数与发球，发送 `softTennisMatchGames`、`teams.games` 和网球族通用字段。Android 明确按 games 而非 sets 建队，但两端结束遮罩均未采用最终局数；iOS 还误发 `resultScoreLevel="sets"`。**结论：实时得分格式基本对齐；赛果 F4。**

### 14. 板式网球 `padel`
本机双打站位、点/局/盘及金分/占先规则；iOS 发四名球员、`padelDeuceMode/starPointReturnedAdvantages`、发球/抢七字段。Android 和 iOS 有对应双打面板与金分格式化。**结论：实时主要 UI 通过；Android 控制到 iOS 的结束遮罩 F1。**

### 15. 毽球 `shuttlecock`
普通模式本机为 Rally 分数/局数/发球；六人团体模式另显示双方各三名队员。iOS 团体模式发 `team_court`、`competitionFormat="team"`、`teamCourtPlayers`，iOS 观看端有六人面板；Android 白名单虽保留队员键，却无 `team_court` 模板，观看时丢名单。普通模式还有发球/赛果方向差异。**结论：六人模式 F3；普通模式 F1、F2。**

### 16. 羽毛球 `badminton`
本机点分、局分、发球与换边经 Rally 快照传输；双边观看端可显示比分和局数。iOS 只发 `servingSide`，Android 双边箭头不出现；Android 控制到 iOS 的结束遮罩取点分。**结论：F1、F2。**

### 17. 羽毛球双打 `badminton_doubles`
本机四名队员/站位及发球员；wire 为 `doubles_court` + `players.isServer` + 分数/局数。Android 有双打布局并保留球员发球标记。**结论：实时主要 UI 通过；结束遮罩 F1。**

### 18. 壁球 `squash`
本机点分、局分、发球与比赛格式；Rally 快照能同步比分和换边，Android 双边发球箭头仍需 `servingTeam`。**结论：F1、F2。**

### 19. 拳击 `boxing`
本机左右累计分和当前/总回合；iOS 发 `boxingCurrentRound/boxingMaxRounds`，Android 对应比分/回合 UI 可读取。**结论：主要字段与 UI 通过。**

### 20. 射箭对抗 `archery_dual`
本机左右成绩、局分、当前射手；iOS 发 `archeryCurrentShooter` 逻辑队伍，Android 的专用箭头分支读取它。**结论：实时 UI 通过；Android 控制到 iOS 的多局结束遮罩 F1。**

### 21. 台球 `billiards`
本机双边姓名/比分与换边，使用通用 `teams.score`/外观/结果，无专用 `sportState`。Android 也使用普通双边模板。**结论：主要字段与 UI 通过。**

### 22. 中式八球 `eight_ball`
本机局数、目标局数、让局数及受让方；iOS 发 `eightBallTargetRacks/eightBallHandicapRacks/eightBallHandicapBeneficiary` 和换边身份，Android 有同名字段及目标/让局副行。**结论：主要字段与 UI 通过。**

### 23. 九球追分 `nine_ball`
本机支持 2–4 人、每人积分及追分明细；iOS 发 `players`、`chasePlayerCount/chasePlayerCounts/chaseLeftCounts/chaseRightCounts`，>2 人用 `multi_grid`。Android 可画分格及追分带；Android 额外发 `chasePlayerNames/chasePoints`，iOS 未发，但现有观看 UI 从 `players` 和 counts 获取显示值。**结论：当前可见 UI 基本通过；F7 元数据差异。**

### 24. 斯诺克 `snooker`
本机比分、局分/当前局、单杆分、总局数、当前击球方及可选比赛抬头；iOS 发 `snookerLeftBreak/snookerRightBreak/snookerMaxFrames/currentSet/servingTeam/matchTitle`。两端实时栏位有对应消费。**结论：实时 UI 通过；Android 控制到 iOS 的多局结束遮罩 F1。**

### 25. 匹克球 `pickleball`
本机点分、局分、发球与换边由 Rally 发送。Android 实时比分可读，但双边发球箭头只认 `servingTeam`。**结论：F1、F2。**

### 26. 匹克球双打 `pickleball_doubles`
本机四人站位和发球轮转；iOS 发 `doubles_court`、`players.isServer`、分/局与休息状态。双方双打模板可显示球员；Android 白名单还允许搭档换位键，iOS 当前源没有发它，现有四人姓名/位置由 `players` 提供。**结论：实时主要 UI 通过；结束遮罩 F1。**

### 27. 桌上足球 `foosball`
本机分/局、发球和换边由 Rally 发送，Android 双边模板有发球箭头。iOS→Android 缺 `servingTeam`；Android→iOS 结束页回退点分。**结论：F1、F2。**

### 28. 桌上足球双打 `foosball_doubles`
本机四人姓名/上下站位、分/局与发球员；wire 带 `doubles_court` 及四个 `players.isServer`，Android 双打模板有球员级发球表现。**结论：实时主要 UI 通过；结束遮罩 F1。**

### 29. 简易计分 `simple_score`
本机双边姓名与任意增减分、可选通用比赛时间；wire 传队伍分数，启用时传通用 `clock`。Android 普通双边 UI 与基础计时信息可消费。**结论：主要字段与 UI 通过。**

### 30. 斗地主 `doudizhu`
本机 3/4 人各自积分、姓名、结算与赢家；iOS 发 `board_card`、逐人 `players/teams` 和 `multiGridColumns`。三人两端都为卡片排列；四人 iOS 模板名仍是 `cardThreePlayer`，Android 是 `MULTI_GRID`，实际同步观看均单行四列；赢家由 player ID 标记。**结论：当前可见布局通过；模板命名有差异。**

### 31. 掼蛋 `guandan`
本机红蓝队等级、A 失败数、三 A 模式、庄家和比赛时间；iOS 发六个 `guandan*` 键、双队 `board_card`，两端实时等级/庄家显示能消费。Android→iOS 结束遮罩可能显示数值 `0` 而非等级。**结论：实时 UI 通过；结束页 F5。**

### 32. 升级 `shengji`
本机红蓝等级、庄家和比赛时间；iOS 发 `shengjiRedRank/shengjiBlueRank/shengjiBankerTeam` 与 `board_card`。实时 UI 两端会从等级键重建；Android→iOS 结束遮罩没有等级特判。**结论：实时 UI 通过；结束页 F5。**

### 33. UNO `uno`
本机多人姓名/累计分、目标分和轮次操作；iOS 发 `multi_grid`、`players`、`unoTargetScore`，两端观看 UI 可显示网格和目标分。Android 还发 `unoRoundCount`，iOS 当前快照未发；观看端未发现轮数徽标依赖。**结论：主要 UI 通过；F7 元数据差异。**

### 34. 多人计分 `multi_scoreboard`
本机多人姓名/独立分数、横竖屏网格和完成状态；iOS 发 `multi_grid`、`players/teams`、`orientation`，两端由人数/方向构造网格。**结论：主要字段与 UI 通过。**

## Android 独有项目边界

Android 云端清单另有 **麻将 `mahjong`**；iOS 无该 `gameType` 的控制入口与专用观看模板。当前 iOS 解码可保留未知键并尝试普通投影，但不能据此宣称麻将跨端 UI 对齐。该项不计入上述 iOS 34 项通过率。

## 建议回归顺序

1. 结束页：Android→iOS 的多局项目与掼蛋/升级等级；iOS↔Android 的软式网球、一局制 Rally。分别在 **进行中、刚结束、换边后结束、手动结束** 查看双方比分和胜者。
2. 发球：iOS 控制、Android 看单打/双边 Rally；在加分、换发和换边后确认箭头。
3. 专用模板：iOS 投篮训练固定/自由两模式、毽球六人团体到 Android 观看。
4. 字段补齐后再检查网球无占先、九球追分配置、UNO 轮次；这些不应挡住前 3 项高优先级修复。

## 主要代码索引

- iOS 清单、发布与线协议：`jifen/Core/CloudSync/CloudSyncAPI.swift:138`；`jifen/Core/Link/LocalScoreboardSyncCoordinator.swift:222`；`jifen/Core/CloudSync/DisplayStateWireCodec.swift:426`；`jifen/Core/Display/ScoreboardDisplayState+Compact.swift:90`。
- iOS 源记分板：`jifen/Features/Scoreboard/Sports/Rally/RallyScoreboardView.swift:2092`；`jifen/Features/Scoreboard/Sports/Tennis/TennisScoreboardView.swift:1589`；`jifen/Features/Scoreboard/Sports/Basketball/BasketballScoreboardView.swift:603`；`jifen/Features/Scoreboard/Sports/Basketball/ShotTrainingScoreboardView.swift:751`；`jifen/Features/Scoreboard/Shared/ScoreboardTemplate.swift:900`。
- iOS 观看端：`jifen/Features/Display/ScoreboardExternalDisplayView.swift:13`（模板）、`:82`（结束分）、`:640`（表面选择）、`:1599`（结束遮罩）、`:2695`（多人网格）。
- Android 清单、清洗与观看端：`../jifen-android/app/src/main/java/com/douhua/jifen/cloudsync/GameTypeCloudMapping.kt:9`；`../jifen-android/app/src/main/java/com/douhua/jifen/display/model/DisplayState.kt:276`；`../jifen-android/app/src/main/java/com/douhua/jifen/display/ui/DisplaySurfaceModels.kt:554`（模板）、`:1769`（发球）；`../jifen-android/app/src/main/java/com/douhua/jifen/display/ui/DisplayScoreboardView.kt:537`（结束页）；`../jifen-android/app/src/main/java/com/douhua/jifen/display/model/DisplayPresentation.kt:206`（局分项目）。

## 实施更新：逐项目状态

以下「已补」表示代码和协议测试覆盖了审计缺口；仍需三台真机互测，不能视为线上验收。鸿蒙端本轮还增加投篮训练 `shot_training_grid`、六人毽球 `team_court` 和结束比分层级兼容。原审计的「结论」仍是修改前的记录。

| 项目 | 实施后状态 |
|---|---|
| 足球、五人制足球 | 补时文本字段已补；比分和计时路径沿用原实现。 |
| 篮球、三人篮球 | 原有 10 个节次/犯规/时钟字段与观看 UI 保留。 |
| 投篮训练 | Android、鸿蒙补固定/自由模式的六格快照、发送端、专用观看布局和结束标记；后端按 Android 320、鸿蒙 313 放行，旧包仍禁用。 |
| 排球、沙滩排球、气排球 | iOS 发逻辑 `servingTeam`；iOS、Android、鸿蒙结束页按 `resultScoreLevel`，旧帧按项目回退。 |
| 乒乓球、乒乓球双打 | 上述发球和终局口径已补；纪律六键与双打球员标记保留。 |
| 网球、网球双打 | iOS、Android 发 `tennisDeuceMode`；三端结束页按分/盘层级。 |
| 软式网球 | 三端结束比分优先取最终 `games`；三端发送 `resultScoreLevel=games`。 |
| 板式网球 | 三端结束页按盘数回退，原金分与双打站位字段保留。 |
| 毽球 | Android、鸿蒙补 `team_court` 六人观看和发球指示；Android 团体模式发送六人名单；普通模式的发球、终局口径已补。 |
| 羽毛球、羽毛球双打、壁球 | iOS 发逻辑发球队；三端结束页按分/局层级。 |
| 拳击 | 回合与累计分字段沿用原实现。 |
| 射箭对抗 | 当前射手字段沿用；三端多局结束比分按层级兼容。 |
| 台球、中式八球 | 原双边比分与黑八目标/让局字段保留。 |
| 九球追分 | iOS 补 `chasePlayerNames/chasePoints`，线协议增加整数对象编解码。 |
| 斯诺克 | 原单杆/总局/抬头字段保留；三端多局结束比分按层级兼容。 |
| 匹克球、匹克球双打 | iOS 发逻辑发球队；三端结束页按分/局层级。 |
| 桌上足球、桌上足球双打 | iOS 发逻辑发球队；三端结束页按分/局层级。 |
| 简易计分 | 原双边分数与通用计时字段保留。 |
| 斗地主 | 四人逐人分数、赢家、配色保持原本机改动；iOS 新增四人协议往返测试，Android 四人观看模板测试通过。 |
| 掼蛋、升级 | iOS 结束页优先显示牌面等级；鸿蒙、Android 同步保持等级文案。 |
| UNO | iOS 补 `unoRoundCount`，目标分和网格沿用原实现。 |
| 多人计分 | 原多人网格与方向字段保留。 |

自动验证（2026-09-23 二次回归）：iOS `ScoreboardDisplayTests` 46 项通过，主应用单测 471 项通过；Android `DisplayStateContractTest`/结束页/版式/四人斗地主定向测试通过，鸿蒙 `assembleApp` 成功，后端能力清单 3 项及 TypeScript 类型检查通过。iOS 曾因网球协议分值、V2 样式丢失而出现 9 项失败，现已修复并重跑；网球同步快照也已恢复完整 `sportState`，并保留屏幕侧发球字段。鸿蒙新增 Hypium 协议用例已写入测试源；本地 hvigor 任务清单没有独立单元测试任务，因此尚无该用例执行结果。鸿蒙还有并行的手表足球改动，本次构建结果对应当前工作区时点。Android 与鸿蒙观看布局仍需真机截图核对，三端跨设备建房/重连/逐次出手测试仍待实机完成。

### 今晚实机验收清单

| 控制端 → 观看端 | 必查状态 |
|---|---|
| iOS → Android／鸿蒙、Android → iOS／鸿蒙、鸿蒙 → iOS／Android | 投篮训练固定 1／2／3 分与自由模式：每次命中/未中、六格累计、撤销、重置、结束、手动结束、断线重连后快照一致。 |
| 同上六个方向 | 四人斗地主：四人姓名/积分/配色、逐轮加减、撤销、赢家、手动结束、重连后四列布局一致。 |
| 任意两端 | 换边后逻辑发球箭头与赢家不反转；一局制显示点分，多局显示局/盘分；软式网球显示局数；掼蛋/升级显示等级。 |
| 华为 Pura X 或同类折叠屏 | 本轮投篮训练与斗地主入口、设置、控制页、观看页、结束页在内外屏和开合切换后不裁切；后台恢复与断线重连保留模式、六格计数、四人积分和结束态。 |

当前可见设备清单没有可用的 Pura X，以上实机项尚未勾选。通过后再提交三端审核。后端能力更新可先部署；20:30 的本机提醒事项已设好。

### 2026-09-22 自检补正

- 鸿蒙六人毽球控制端补发 `teamCourtPlayers`，并在六人团体模式发送 `team_court`；姓名按逻辑 `team_0/team_1` 固定，换边后仍保持正确队伍。鸿蒙四个双打项目的自定义快照现显式发送 `resultScoreLevel`。
- Android 投篮训练观看端现在构造完整双边字号模型；自由模式补未中/命中标签，观看文案使用已有本地化资源。
- 补正后的 Android 定向测试与鸿蒙 `assembleApp` 均通过。仍没有三端实体设备互测或 Pura X 折叠屏验收结果。
