# iOS 计分项目 Android 3.0 / 3.1 对齐审计

## 固定基线与范围

- Android 3.0：`5af5de7ea81971c1e7958d5f052bb927d0c13983`
- Android 3.1：`ffc68f8fcca51042ef4afc4e3040730f56daebca`
- 开工时已刷新 `origin/3.0`、`origin/3.1`，上述提交与远端一致。
- 2026-08-30 第二轮自检时，Android `origin/3.1` 已继续推进到 `87c8c9ebb8e4f9a36146ce02b3650402ae94554a`（冻结点之后另有 4 个提交、71 个变更文件）。按照已确认的实施假设，本轮仍以 `ffc68f8f` 为唯一 3.1 验收点，不把后续 Tennis reducer、布局、投屏和跨设备变更静默并入；后续增量需单独开一轮审计。
- `3.0...3.1` 计分相关范围共 66 个变更文件；3.1 行为覆盖 3.0，iOS 不提供版本模式切换。
- 最终目录为 28 个入口、33 个精确 `ScoreCore.GameType`。本轮只覆盖 iPhone/iPad 的本地计分闭环；账户、支付、云同步、跨设备联动、投屏、独立计时 Tab、小工具和 Watch 功能不在范围内。

## 双版本逐项目矩阵

状态说明：“完成”表示最终类型路由、规则内核、设置、比赛内交互、版本化快照或专项覆盖已落入当前工作树；自动化列给出主要回归入口。矩阵按 3.0 底座逐项核对，再用 3.1 差异覆盖，未把“3.1 未修改”误当成“不需要验收”。

| 精确项目 | Android 3.0 行为 | 3.1 变化 | 最终 iOS 行为 | iOS 当前状态 | 源码证据 | 自动化测试 |
|---|---|---|---|---|---|---|
| `pingpong` | 目标分/局数、发球轮换、决胜换边 | 暂停、医疗暂停、黄/红牌、官方休息、语音清理 | 单打规则及 3.1 管理动作 | 完成 | Android `S1DualSideScoreRouteScreen.kt`; iOS `RallyMatch.swift`, `RallyScoreboardView.swift` | `pingPong*`, `officialBreak*` |
| `pingpong_doubles` | 单打底座 + 四人接发顺序 | 同上并保持双打轮转 | 精确双打类型、四人身份与管理动作 | 完成 | Android S1 双打实现；iOS `DoublesRotation.swift`, `RallyMatch.swift` | `pingPongDoubles*` |
| `badminton` | 11/15/21、封顶、净胜、换边 | 局点/赛点语音、60/120 秒官方休息 | 3.1 最终规则与休息 | 完成 | Android `OfficialBreak.kt`; iOS `RallyScoreboardView.swift` | `badminton*`, `officialBreak*` |
| `badminton_doubles` | 单打底座 + 双打站位/发球员 | 同上 | 精确双打身份和 3.1 休息/语音 | 完成 | Android S1；iOS `RallyMatch.swift` | `badmintonDoubles*` |
| `shuttlecock` | 独立目标分、净胜、发球/换边 | 60 秒局间休息、项目语音 | 不以标题复用其他运动 | 完成 | Android `shuttlecockGameBreak`; iOS `.shuttlecock()` | `newRallyProfiles*` |
| `squash` | 11 分、净胜、发球/换边 | 90 秒局间休息、项目语音 | 独立壁球内核与休息 | 完成 | Android `squashGameBreak`; iOS `.squash()` | `newRallyProfiles*` |
| `tennis` | 标准赛、抢七/抢十、占先、发球换边 | 90 秒换边/120 秒盘间休息 | 3.1 最终标准网球行为 | 完成 | Android `TennisScoreScreen.kt`; iOS `TennisMatch.swift` | `tennis*`, `officialBreak*` |
| `tennis_doubles` | 单打底座 + 四人发接轮转 | 休息及播报清理 | 精确双打类型与轮转 | 完成 | Android Tennis；iOS `TennisMatch.swift` | `tennisDoubles*` |
| `soft_tennis` | 7/9 局与决胜换边 | 60 秒换边休息、项目语音 | 7/9 局、决胜分换边与休息 | 完成 | Android `softTennisChangeoverBreak`; iOS `.softTennis()` | `softTennis*` |
| `padel` | advantage/golden/star point | 90 秒换边、120 秒盘间休息、项目语音 | 三种平分模式与 3.1 休息 | 完成 | Android `padel*Break`; iOS `.padel()` | `padelGoldenAndStarPoint*` |
| `pickleball` | 发球得分/每球得分、目标分、换边 | 修正目标分/封顶、第二发球播报、官方休息 | 只保留 3.1 修正规则 | 完成 | Android Pickleball + `OfficialBreak.kt`; iOS `RallyMatch.swift` | `pickleball*` |
| `pickleball_doubles` | 单打底座 + 双发球序号 | 同上 | 精确双打类型与发球序号 | 完成 | Android Pickleball；iOS `RallyMatch.swift` | `pickleballDoubles*` |
| `volleyball` | 普通局/决胜局、自动换边、比赛时间 | 通用菜单/布局回归 | 室内排球独立规则 | 完成 | Android Volleyball；iOS `RallyMatch.swift` | `indoorVolleyball*` |
| `beach_volleyball` | 沙排局分与每 7 分换边 | 通用交互回归 | 沙排专属换边间隔 | 完成 | Android Volleyball；iOS `RallyMatch.swift` | `beachVolleyball*` |
| `air_volleyball` | 气排球普通/决胜局分值 | 通用交互回归 | 气排球独立规则 | 完成 | Android Volleyball；iOS `RallyMatch.swift` | `volleyballVariants*` |
| `football` | 非负比分、撤销、换边、记录/续局 | 自动 45 分钟半场、补时、两段 15 分钟加时 | 自动正计时；补时 `+MM:SS`；平局可加时或结束 | 完成 | Android `FootballMatchClockSession.kt`; iOS `OfflineScoreboardTypes.swift`, `FootballScoreboardView.swift` | `football31*`, `footballStoppage*` |
| `football_5v5` | 3.0 无此类型 | 新增；默认 20 分钟、1–90 分钟、仅上下半场、手动暂停 | 独立类型，无补时/加时入口 | 完成 | Android 3.1 Football；iOS Football session/view | `football31*`, `fiveByFivePeriod*` |
| `basketball` | FIBA/NBA、节时、24/14 秒、暂停/犯规/加时 | 比赛钟、进攻钟同步和暂停恢复修正 | 3.1 最终时钟状态机 | 完成 | Android Basketball；iOS `BasketballMatch.swift` | `basketball*`, `automaticBasketballClock*` |
| `three_basketball` | 3×3、12 秒、21 分、加时 | 共享时钟修正 | 3.1 三人篮球行为 | 完成 | Android Basketball；iOS `BasketballMatch.swift` | `threeByThree*` |
| `billiards` | 普通台球自由计分 | 通用菜单/改分保护 | 非负自由计分、撤销/记录 | 完成 | Android S2；iOS `LineScore.swift`, `BilliardsScoreboardView.swift` | `lineScoreReducer*` |
| `eight_ball` | 抢局、让局、开球方、续局 | 通用结束提示回归 | 黑八独立状态和记录 | 完成 | Android EightBall；iOS `SpecializedScoreboards.swift` | `eightBall*` |
| `nine_ball` | 2–4 人、事件分、犯规、排名/重置 | 通用改分保护 | 追分多人事件内核 | 完成 | Android NineBall；iOS `SpecializedScoreboards.swift` | `nineBall*` |
| `snooker` | 红彩/清台、犯规档、失误/交杆；最后黑球后非平局自动结算，多局赛等待确认下一局 | 通用菜单回归 | 自动局结算、平局延分黑、下一局确认与完整阶段 | 完成 | Android `SnookerViewModel.kt`; iOS `SnookerScoreboard.swift`, `SnookerScoreboardView.swift` | `snookerClearanceAutoSettles*`, `snooker*` |
| `archery_dual` | 3 箭/M 箭、局分、加赛、最近中心 | 通用结束提示回归 | 精确射箭类型、加赛状态及可撤销姓名编辑 | 完成 | Android Archery；iOS `ArcheryMatch.swift`, `ArcherySessionStore.swift`, `ArcheryScoreboardView.swift` | Archery reducer/resume/name-edit suites |
| `boxing` | 回合预设/自定义、逐回合录分/编辑 | 通用布局回归 | 回合状态、最终结束、记录及可撤销姓名编辑 | 完成 | Android Boxing；iOS `BoxingMatch.swift`, `BoxingViewModel.swift`, `BoxingScoreboardView.swift` | `boxing*`, Boxing resume/name-edit suites |
| `guandan` | 2–A、过 A、三 A、编辑/记录 | 通用菜单回归 | 等级与三 A 尝试完整保存 | 完成 | Android Guandan；iOS `GuandanScoreboard.swift`, `GuandanScoreboardView.swift` | `guandan*` |
| `shengji` | 等级、庄家转移、编辑/记录 | 通用菜单回归 | 等级/庄家状态完整保存 | 完成 | Android Shengji；iOS `SpecializedScoreboards.swift`, `ShengjiScoreboardView.swift` | `shengji*` |
| `doudizhu` | 三人结算、地主/农民分配、撤销 | 通用菜单回归 | 轮次动作与三人结算 | 完成 | Android Doudizhu；iOS `DoudizhuScore.swift`, `DoudizhuScoreboardView.swift` | `doudizhu*` |
| `uno` | 2–10 人、逐轮结算、排名 | 最终预设 300/500/700/1000，范围 1–99999 | 使用 3.1 目标分策略 | 完成 | Android UNO setup；iOS `UnoTargetScorePolicy` | `testUnoTargetScorePolicy*`, `unoRoundScore*` |
| `foosball` | 5/7/8、局数、决胜净胜/封顶、进球后发球 | 通用菜单回归 | 单打精确类型与发球规则 | 完成 | Android Foosball；iOS `RallyMatch.swift` 的 `.foosball()` profile | `foosball*` |
| `foosball_doubles` | 单打底座 + 四人姓名 | 双打布局回归 | 精确双打类型、四人身份 | 完成 | Android Foosball；iOS `RallyMatch.swift`, `DoublesRotation.swift` | `foosballDoubles*` |
| `simple_score` | 可负分、自定义步长 | 通用改分保护 | 旧 `simpleScore` 可解码，写出规范标识 | 完成 | iOS `ScoreCore.GameType` compatibility decode | `canonicalGameTypeDecoder*` |
| `multi_scoreboard` | 3–9 人、增删改名、排名、赢家、撤销 | 通用菜单回归 | 多人状态、赢家与动作流水 | 完成 | Android Multi；iOS `MultiParticipantReducer.swift`, `MultiScoreboardView.swift` | `multiParticipant*`, `testMultiScore*` |

## 第二轮 Score Engine → 数据控制层 → 计分板纵向自检

本轮没有只看 reducer 单测，而是沿每次用户操作的完整事务边界核对：计分板产生 typed intent，数据控制层在串行队列内取得权威 `before` 状态，Score Engine 返回 `after/events`，控制层原子更新撤销帧、记录投影和恢复快照，最后 SwiftUI 只渲染已接受状态。重点项目结果如下。

| 项目 | Score Engine | 数据控制层 | 计分板投影 | 撤销 / 恢复 / 正式记录结论 |
|---|---|---|---|---|
| 乒乓球（单/双） | `RallyMatchReducer` + `DoublesRotation`；发球、接发、决胜换边、牌和暂停均为 typed state/event | `RallySessionStore` 串行化 intent，并在队列内部返回同一事务的 `before/after/events` | `RallyScoreboardView`、单/双入口仅消费 store 状态；快速连点不再读取过期前态 | 终结分产生的多条 action 作为一组撤销；旧双打接发槽位迁移覆盖 current/replay/undo；暂停/医疗暂停来源写入快照并全程静音，普通官方休息不受影响 |
| 羽毛球（单/双） | 同一 reducer 的 badminton profile；11/15/21、21/30 封顶、发球与双打站位独立验证 | 同一 store 负责输入冻结、动作组 checkpoint、参与者同步 | 入口适配层不复制规则；局点/赛点、换边和休息来自 engine events | 连续计分、局末、撤销、后台恢复和 completed-set 语音历史保持一致 |
| 网球（单/双） | `TennisMatchReducer`；局/盘、占先、抢七/抢十、双打发接轮转 | `TennisSessionStore` 使用队列内事务回调和完整记录 checkpoint | `TennisScoreboardView` 不自行推算下一比分；编辑/换边/语音均以 accepted transition 为准 | 一个终结分同时产生 point/game/set 时整体撤销；四人身份、盘历史、官方休息和恢复快照保持一致 |
| 匹克球（单/双） | `RallyMatchReducer` 的明确 `.pickleball` profile；传统发球得分与每球得分、单双发球序号 | `RallySessionStore` 按精确 GameType 迁移旧 snapshot；单打 next set 回开局发球方，双打从开局方交替 | 设置、预约开局、Watch 启动适配和手机计分板使用同一 3.1 规则投影 | 修复旧快照缺 profile、预约/启动入口 next-set 规则不一致；撤销同时恢复比分、发球员/第二发球和记录 |
| 掼蛋 | `GuandanSessionReducer` 拒绝错误 phase/no-op，并限制合法升级步长 | 当前为主线程内的 view-local typed reducer 控制层；状态、undo snapshot、详细回合动作原子更新 | `GuandanScoreboardView` 显示 2–A、A 阶段、三 A 尝试及实际升级结果 | 旧 `notStarted` 恢复后仍可首轮计分；撤销不会留下空帧；记录保存真实等级差、过 A/失败/回退结果 |
| 斗地主 | `DoudizhuScoreReducer` 统一三人结算与手工改单 | view-local 控制层保存分数快照和 action/detailed-action checkpoint | `DoudizhuScoreboardView` 显示三人带符号分数、地主/农民和多人赢家 | 结束态禁止菜单及全局滑动撤销，避免正式记录与屏幕状态分叉；旧记录兼容，新记录保留三人角色和每轮结算 |
| 斯诺克 | `SnookerReducer` 负责红彩阶段、清台、犯规、局结算和下一局确认 | `BilliardsSessionStore` 统一串行派发、derived intent、即时撤销预留、记录上下文和 typed resume bundle；nil/rejected intent 不预约虚假撤销 | `SnookerScoreboardView` 的绝对改分在队列内基于权威状态计算；终局记录只在 bundle 最终化后写入 | 修复快速改分丢一次、结算读取旧状态、send 后立即 undo 失败、正式快照落后一拍、终局撤销再结算被旧 commit 去重等竞态；终局异步清理改为按 resume generation 精确 compare-and-delete，不会删除撤销后新写入的 live session |
| 九球追分 | `NineBallChaseReducer` 负责 2–4 人、事件分值、犯规和排名 | 同一 `BilliardsSessionStore` 原子维护 state、undo、动作流水和恢复数据 | `NineBallChaseScoreboardView` 从 accepted events 投影多参与者动作，终局后禁用滑动/菜单撤销 | 设置范围 1–99；完成后的 UI/记录生命周期不再分叉；正式记录包含最终 state + action context，而不是前一拍 bundle |

共享接口另有一层独立验收：`ScoreboardKernelRegistry` 对 33 个类型都有精确 descriptor，`ScoreboardSessionFactory` 对 `GameType.allCases` 做到 33/33 真实构造，并拒绝错误 family、错误 profile 和错误参与人数。生产 SwiftUI 当前仍由各项目 store/controller 直接构造 session；工厂是公共组合与测试边界，不虚构为所有页面都已统一经过同一个 factory。

## 3.1 覆盖与回归映射

| 3.1 覆盖 | 被替代的 3.0 行为 | iOS 回归入口 |
|---|---|---|
| 11 人制足球自动钟、补时、加时 | 足球只有比分、无比赛钟 | `football31*`, `footballStoppage*` |
| 5×5 足球 | 3.0 无此入口/类型 | 28 入口与 33 类型覆盖测试、`fiveByFivePeriod*` |
| 5×5 设置提示、1–90 分钟与手动暂停 | 3.0 无对应设置 | `testNewSportDefaultsAndExplicitSetupProjectionMatchAndroid31`, Football UI tests |
| 乒乓管理动作：60 秒暂停、600 秒医疗、黄牌不限次、红牌最多两次、撤销与记录标题 | 无暂停/医疗/牌 | `pingPongAdministrative*`, `testTableTennisAdministrativeRecordTitlesMatchAndroid31` |
| 8 项官方休息且末 3 秒计入总时长，冻结输入、跳过、撤销、快照恢复 | 无统一开关/恢复状态 | `officialBreak*` |
| 官方休息 2.5 秒开场播报及 30/10/5/3/2/1 秒阈值提示 | 3.0 无统一播报时序 | `officialBreak31WarningCuesOnlyEmitNearCrossedThresholds` |
| 项目化语音、匹克球第二发球，以及改分/换边/撤销时清理过期队列 | 部分项目共用或缺失 | Rally/Tennis/Pickleball voice suites |
| 篮球单调时钟、比赛钟/进攻钟同步、犯规停表、暂停显式恢复与加时 | 3.0 旧同步/暂停语义 | `automaticBasketballClock*`, `basketball31*` |
| 匹克球目标分/封顶及局数预设联动修正 | 3.0 已废弃限制 | Pickleball factory/scoring tests, `testPickleballPresetSetSelectionUpdatesTargetLikeAndroid31` |
| 网球/板网失去占先回到规范 40:40，star point 计数修正 | 3.0 旧展示/计数路径 | `tennisAndPadelReturnLostAdvantageToCanonicalDeuceLikeAndroid31` |
| 通用菜单排序与可用态：撤销优先、编辑/换边居中、结算靠后、结束最后 | 3.0 旧菜单次序 | `ScoreboardMenuConfirmStateTests` |
| UNO 目标分范围 | 旧预设与四位输入 | `testUnoTargetScorePolicyKeepsPresetsAndCustomValues` |

## 本地生命周期与兼容性

- 33 个精确项目类型贯通目录、设置结果、比赛工厂、记录、续局和“再来一场”；旧 iOS 类型标识继续兼容解码，规范写出最终标识。
- 比分层级、撤销流水、发球/接发/换边、射箭先手、项目比赛时间、乒乓管理动作、官方休息、篮球计时和足球阶段均进入本地快照。
- 3.0 足球旧记录没有比赛钟字段时按“第一阶段、暂停、保留原比分”迁移；运行中的足球/篮球时钟用墙钟或单调锚点补齐后台经过时间。
- 官方休息旧记录缺字段时恢复为当前无休息；旧比赛记录仍能展示，新增乒乓牌/暂停动作显示精确语义，不再退化成通用犯规文字。
- Resume envelope 增加向后兼容的 generation 标识；终局异步清理只删除它捕获的原始快照，撤销终局或重新开局产生的新快照不会被过期任务误删。48 小时归档仍保留 action log、详细动作和动作计数。
- 射箭与拳击的姓名编辑已进入 reducer/store 真源、revision、checkpoint 和 resume；`编辑 → JSON 恢复 → 撤销` 后姓名与比赛状态同步回退。
- 服务端、账户、支付、云同步、投屏和跨设备协议没有新增或修改。

## 验收命令

```sh
swift test --package-path Packages/JifenCore
xcodebuild -workspace jifen.xcworkspace -scheme jifen -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:jifenTests test
xcodebuild -workspace jifen.xcworkspace -scheme jifen -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:jifenUITests test
xcodebuild -workspace jifen.xcworkspace -scheme jifen -configuration Debug -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' CODE_SIGNING_ALLOWED=NO -only-testing:jifenUITests test
xcodebuild -workspace jifen.xcworkspace -scheme jifen -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace jifen.xcworkspace -scheme jifen -configuration Debug -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' CODE_SIGNING_ALLOWED=NO build
```

工程构建不应传全局 `-sdk iphonesimulator`，否则 Xcode 会把嵌入 Watch target 错误强制到 iOS SDK；手机 target 和 Watch target 保持各自平台 SDK。

## 最终验证记录

- 2026-08-30 第二轮纵向自检最终复验：`swift test --package-path Packages/JifenCore` 的 Swift Testing 252 个测试 / 9 个套件，加上 XCTest 2 个测试，全部通过。
- iPhone 17 Pro 完整 `jifenTests`：402 个测试，0 失败；这是本轮全部竞态、姓名真源和 resume-generation 修复合入后的结果。
- iPhone 17 Pro 重点闭环 `jifenUITests`：7 个测试，0 失败。覆盖乒乓球、羽毛球、网球、匹克球的单/双打设置与计分板，掼蛋、斗地主、斯诺克、九球追分，以及 28 个公开入口的记录详情；同时覆盖计分、撤销、编辑、菜单、退出和关键横屏布局。
- iPhone 17 Pro 完整 `jifenUITests`：41 个测试，0 失败；3 个按运行环境设计跳过。覆盖 28 个公开入口、代表性项目设置/横屏计分/撤销/编辑/退出、记录详情与“再来一场”、中英文和主流程。
- iPad Air 11-inch (M4) 完整 `jifenUITests` 已执行 41 个用例，其中 1 个按设备条件跳过；38 个原始用例直接通过。完整运行暴露的 3 个 UI 测试夹具问题（iPad 主导航定位、首页长列表截图导航、全控件穷举的失效元素/外链命中）已修正，并分别定向复验通过：法律同意流程 1/1、全量截图 1/1（截图数达到断言下限）、全控件穷举 1/1（1835.179 秒、31,096 个活动步骤）。这些修正只提高测试稳定性，不改变产品行为。
- iPhone 17 Pro Debug：构建成功，0 编译错误。
- iPad Air 11-inch (M4) Debug：构建成功，0 编译错误。
- 两次构建均让手机 target 使用 iOS Simulator SDK、嵌入 Watch target 使用 watchOS Simulator SDK，未再出现全局 SDK 污染导致的 `WatchKit` 阻塞。
- 独立回归复核针对四个高风险链路（斯诺克终局清理、台球 nil/rejected derived intent、射箭姓名真源、拳击姓名 revision）逐一复现并确认修复，未发现剩余确定性 P1/P2。
