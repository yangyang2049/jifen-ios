# 九球赛制：iOS 规则版本3

本轮仅实现 iOS，沿用 `demos/nine-ball-rule-presets-2026-10-24/` 已确认的交互；未提交或发布应用。Android、鸿蒙及手表尚未接入版本3，不应把本轮结果视为跨端发布验收。

## 配置与兼容

- 新开局、预约开局、再来一局显式使用 `ruleVersion = 3`。既有版本1、2会话保留原规则及已存分数；缺失版本仍解码为1。ScoreCore 的兼容初始化默认版本2未改变，应用新开局入口明确传3。
- `NineBallChaseConfig` 新增 `ruleFamily`（folk/tournament）、`pointScheme`（14710/1357）、`handoffEnabled`、`thirdFoul`、`breakRule`（winner/alternate）、`totalRacks`；缺失字段使用旧民间配置的兼容默认值。
- 赛事强制两人；民间保持2至4人。1357默认大金7、小金5、普胜3、犯规1、黄金9独立3；14710和赛事均使用10/7/4/1，赛事第三犯默认2。
- `rackFouls` 按逻辑玩家保存本局次数，保持四个存储位置。既有七个统计槽位不变，赛事显示大金、小金、普胜、犯规四项；民间关闭让杆时隐藏该项。
- 版本1仅接收旧 `chaseEvent`；版本2及版本3民间使用 `chaseTransfer`；版本3赛事仅接收 `tournamentEvent`，禁止黄金9、让杆、自由球得分意图。

## 赛事结算

普通得分仅增加得分方积分；犯规给对手加分，不扣犯规方分数。同一人同局分别累计三次犯规，不要求连续。前两犯每次给对手 `foul`，第三犯给 `thirdFoul` 并判负本局；不叠加犯规分或普胜分。换局双方次数清零。

第三犯与其他记分事件复用完整 `chaseTransferred` 事件载荷，包含全员增量、原局号及前后开球人。SessionCore 为一次操作保存一次撤销快照。原生记录使用独立 `nine_ball_tournament_*` 操作名和完整文字摘要。

每局结束后比较积分。总局数打完仍平分时逐局加赛。提前结束使用：

```
单局最大追分 = 2 × foul + max(bigGold, smallGold, normalWin, thirdFoul)
分差 > 剩余局数 × 单局最大追分
```

必须严格大于，等于时仍可追平。仅在一局结束时检查，包含自定义分值；已结束比赛沿用原生操作限制。赛事手动改分拒绝负数；民间允许负数，合计非0仅提醒。

## 原生链路

`SportsSetupResult`、预约开局、会话快照、记录配置、继续比赛和再来一局传递全部赛制配置。新比赛清空积分与本局犯规，首局默认1号开球；继续原比赛保留局号、开球人与本局犯规。iOS 显示数据白名单增加 `chaseRuleFamily/chasePointScheme/chaseBreakRule/chaseHandoffEnabled/chaseTotalRacks/chaseRackFouls`，`chasePoints` 包含第三犯分值，按版本和赛制映射统计顺序及开球标记。

2026-10-25 体验调整：移除主计分板及投屏中每侧底部的“第几局／总局数 · 本局犯规”小字。只改变显示；局数、犯规状态、三犯结算和保存恢复仍保留，第三犯操作继续提示本局判负。此前验收图中的该行属于调整前画面。

规则页连续展示三段，使用 `SectionTitleView` 绿色竖条。反馈复用 `FeedbackListView(initiallyCreate: true, initialCreateTitle: "#九球追分# ")`，遵循 `AppFeatureFlags.feedbackEntryEnabled` 和原登录处理。本轮验收不会发布线上反馈。

名称使用“赛事积分”，依据已确认的2025年10月16日独牙标准规则说明，不宣称最新决金官方版。未增加双打、黑金或自定义方案命名。

## 本轮验证

- JifenCore：275项通过，含新增8项版本3测试。
- 定向应用回归累计223项均通过：首轮220项，预约4项中新增1项，最终恢复与投屏66项中新增1项，繁体原生布局1项。重复运行的测试不累加。
- iOS 最终模拟器构建通过。测试结果包保存在 `/tmp/nine-ball-v3-native-tests.xcresult`、`/tmp/nine-ball-v3-booking-tests.xcresult`、`/tmp/nine-ball-v3-final-regression.xcresult`、`/tmp/nine-ball-v3-layout.xcresult`；摘要已导出到下方验收目录。
- 原生界面已验证英文摘要换行、两类人数差异、数字键盘输入、键盘出现时底部按钮可用、修改后才显示恢复、恢复后隐藏；赛事三犯积分依次为1、2、4，第三犯进入第2局、开球人移动、犯规清零。
- 原生截图及后续人工检查记录保存在 `verification/nine-ball-rule-presets-ios-2026-10-24/`。
- iPhone SE 实际检查了小屏、数字键盘及深色模式。0局和空分值均禁用开始；恢复后重新启用、隐藏恢复入口。恢复操作使用输入修订号拦截旧输入框异步回写，自定义局数的启用状态与文字独立保存。
- 补充恢复用例覆盖完整会话编码、解码、继续后第三犯结算与整笔撤销，以及放弃比赛时记录配置和犯规状态的保留。投屏字段白名单、线缆数据往返及原生显示布局回归通过，未连接实体电视或实际AirPlay接收端。
- 繁体中文原生渲染矩阵覆盖375pt四人长姓名、赛事自定义局数、320pt深色设置、375pt与768pt三段完整规则页。原生渲染图与实际模拟器截屏在验收目录中分别标注。
- 简体、繁体、英文新增文案已提供；其他语言的新增长说明和控件文案暂用英文，现有已翻译键不变。全部支持语言的键集和格式参数校验通过。

编译过程中，工作区已有个人记录同步模块的6个响应 DTO 触发 Swift 隔离一致性错误。本轮仅为这些值类型补充 `nonisolated` 标注，没有改动该模块同步逻辑；修改前副本位于 `/tmp/nine-ball-ios-v3-baseline/`。
