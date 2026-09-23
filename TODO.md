# 全能计分器 iOS TODO（iOS 专属执行细节）

> 最后核对：2026-08-31
>
> **本文只保留 iOS 端的实现细节与验收。** 跨端功能范围与优先级以主表 `jifen-hos/TODO.md` 为唯一来源；冲突时以主表为准并回改本文。
>
> 各端分片：安卓 `jifen-android/TODO.md` ｜ 网站 `jifenqi-website/TODO.md` ｜ 小程序 `jifen-wechat/REVIEW_TODO.md` ｜ 后端 `jifenqi-backend/TODO.md`
>
> 维护规则：完成即删除并压成一行写入文末「归档」，注明证据（`文件:行`、测试名、接口实测日期）。**历史报告（`BUGS_AND_OPTIMIZATION_REPORT.md`、`QA_FEATURE_VALIDATION_REPORT.md`）中的条目必须先复核代码再登记，其原始结论不作为依据。**

## 待办

### P0

- [ ] **账号体系对齐**〔主表 P0〕：登录、注销与登录态需与鸿蒙/安卓同一套协议。扫码登录：实现（`QRLoginApprovalView.swift`）与「我的」页入口（`AccountViews.swift` AccountProfileView toolbar，对齐安卓 Me 页顶栏 action，仅登录后显示）均已就绪；**剩余：真机扫码 → /scan → confirm approve|deny → 网页登录成功 的链路实测**。
- [ ] **比赛记录多端云同步**〔主表 P0，跨端均未实现〕：iOS/安卓/鸿蒙三端均尚未实现、非 iOS 独有缺口；届时字段名与覆盖规则须与鸿蒙/安卓共用，且对齐 BUG-1 已统一的扁平 extraData 键规范；服务端当前只有 `commonDataSync.ts`（常用名称/地点），记录同步 API 尚未存在，须等后端先行。该 API 一旦落地，跨越的正是 P1 架构级 🔴「blob↔flattened 跨端续打」（安卓记录无 `stateSnapshot` → iOS 续打/胜者失真），须同批处理。

### P1

- [ ] **会员兑换码与赠卡**〔主表 P1〕：✅ 2026-09-23 已按新决策接入 Apple StoreKit 系统优惠码兑换页，会员页右上角提供“兑换”入口；不恢复自建兑换码/礼品卡输入框。兑换交易继续走 Apple JWS 验单，登录态直接上传服务端绑定账号，未登录时先保留本机权益并在登录后补验。剩余仅为 App Store Connect 配置优惠码及 Sandbox 真机端到端验收。
- [ ] **比赛记录结果纠错（iOS 侧）**〔主表 P1〕：✅ 2026-08-31 已实现两队制纠错：`ScoreboardRecordCorrection.applied`（改最终比分/局分、按 局分>当局分 层级重算胜者、平局清空胜者、首次纠错留痕 `correction`、stateSnapshot/detailedActions 不动）；详情页比分卡「纠错」入口 + sheet（`ScoreboardRecordDetailPage.swift:264-276,345-430`）；测试 `testLegacyRecordDecodesWithoutCorrectionAndCorrectionRoundTrips`、`testScoreCorrectionRewritesWinnerPreservesOriginalValuesAndReplayFields` 通过。多人（participants）记录纠错与 revision 语义仍待记录云同步同批定。
- [ ] **反馈与合规**：2026-08-31 差异核验完成：反馈闭环（API 全套+列表/创建视图）与账号删除（`/api/account-deletion/request` + 输入「注销账号」确认）两端已对齐；已知文案级差异：鸿蒙删除页含会员警告（`AccountDeletionPage.ets:94-124`）、iOS 为确认 sheet 无此文案。剩余：隐私与 Data Safety 文案覆盖相机权限（扫码登录）；上架材料须与 `DEPLOYMENT_PRE_CHECK` 级别的实机验证一致。
- [ ] **补一轮 iOS 跨端一致性对照审计**：**当前最大的结构性缺口**。`jifen-android/docs/2026-08-28-cross-platform-diff/` 只覆盖安卓 vs 鸿蒙两端，iOS 未纳入任何一致性基线。建议按同一方法（计分板容器 / 规则与设置 / 记录列表 / 记录详情与分享四线）做一次 iOS 对照，产出同格式差异表并入主表。
- [ ] **跨端续打 / 胜者失真（blob↔flattened，架构级 🔴）**〔与掼蛋同类，不在 BUG-1 范围，当前无需求·留作 TODO 未来做〕：iOS 续打读取已存记录的 `stateSnapshot` blob（`ReducerScoreboardRecordPersistence.loadResume` `jifen/Features/Scoreboard/Shared/ReducerScoreboardRecordPersistence.swift:182-198`，解码完整引擎 State+undo+intentTimeline+detailedActions）；安卓记录仅摊平 extraData、无 blob → `loadResume` 返回 nil，`isReliableForResume` 闸门（`ScoreboardRecordPresentation.swift:244` = `status==.finished || stateSnapshot!=nil`）对安卓 finished 记录仍放行 → 详情页点「继续比赛」→ `record_unavailable`「无法继续比赛」。`resolvedWinnerIdentity`：guandan 已在 BUG-1 补 `guandanFinalWinner` extraData 回退（✅）；**shengji 仍仅读 blob 无回退（`ScoreboardRecord.swift:479-487`）**，安卓记录胜者走 legacy/比分回退、不可靠。**当前无跨端续打需求**（记录云同步 API 三端均未实现，用户无「iOS 读安卓记录」路径），无需立即复验/立项；留作 TODO，待未来有跨端记录恢复需求时再处理，届时与记录云同步 API 同批处理。**该场景仅在云同步（P0，iOS 未实现）落地后才会真实触达用户，当前为潜伏问题。**

### P2

- [ ] Theme 逐步替换裸 `padding` / `color` 值；`CHANGELOG.md` 拆条与补全空 bullet。

## 归档（不再跟踪，仅留痕）

| 事项 | 证据 |
|---|---|
| 篮球日志区分比赛时间与真实时间已完成 | 2026-08-31：`DetailedScoreAction` 新增可选 `gameTimeSeconds`（与安卓/鸿蒙状态字段同名，旧记录兼容）；篮球落库 10 处动作传入 `state.gameTimeSeconds`（`BasketballSessionStore.swift:352-377`）；JifenCore 252 测试全过 |
| 记录/预约/活动列表 loading 与空状态已补齐 | 2026-08-31：活动页补 loading（`RecentActivityPage.swift:16-20,45-51`）；记录列表（`RecordsTab.swift:310-315,679-689`）、预约（`SchedulePage.swift:18-21`）原有 |
| 扫码登录入口已接入「我的」页 | 2026-08-31：`AccountViews.swift` AccountProfileView toolbar 加 `qrcode.viewfinder` 按钮 push `QRLoginApprovalView`，对齐安卓 Me 页顶栏 action（`QrLoginTopBarAction.kt`）仅登录后显示 |
| 崩溃风险清理（`record.endTime`/`playerCount`/`timerSubscription`/`displayTimer` 强解包）已不成立 | 2026-08-31 全仓 grep 强解包零命中，历史上已修复 |
| 本地化硬编码（BoxingScoreboardView / ScoreboardRecordDetailPage）已不成立 | 2026-08-31 复核：`BoxingScoreboardView.swift:333-349` 中文均在 NSLocalizedString value 内；`ScoreboardRecordDetailPage.swift:48-57` 同 |
| Sheet 统一加 presentationDragIndicator 已完成 | `QuickStartEditView.swift:166-168`、`SettingsView.swift:90-94` 均已 `.presentationDragIndicator(.visible)`（2026-08-31） |
| ScoreboardRecordsViewModel.refreshRecords 后台线程已完成 | `ScoreboardRecordsViewModel.swift:78-110`：加载在 `DispatchQueue.global(qos:.userInitiated)`，主线程仅收 UI 更新（2026-08-31） |
| Watch 端「返回/退出」文案统一已完成 | Watch 端无「返回」字样，统一「退出」（`watch_exit`/`exit`，`WatchScoreboardComponents.swift:489`、`WatchBasketballTrainingView.swift:385`、`zh-Hans.lproj/Localizable.strings:87-88`）；2026-08-31 |
| 原报告两项「P0 Bug」已不成立 | `FlipCoinView.swift:229-232` 已在 `onDisappear` 中 `flipTimer?.invalidate()` 并置 nil；`NewGameDialogView.swift` 内已无 `asyncAfter`（`HomeTab.swift:258,696` 的 `asyncAfter` 属另一处已确认逻辑）。**`BUGS_AND_OPTIMIZATION_REPORT.md` 的优先级表不得直接引用** |
| 四项新增运动（毽球、壁球、软式网球、板式网球）iOS 已迁移 | 2026-08-09 跨端实现与分端审查完成，iOS 修复 5 项；协议字段与三端一致；按 3.0 决策不进手表入口 |
| 后端 `gameType` 白名单已覆盖 iOS | 线上 `GET /api/client-config/scoreboard`（`x-client-platform: ios`）实返 controller 33 项，含四项新运动（2026-08-30） |
| 排球与沙排每局首发规则 | `jifen-ios/docs/p0_volleyball_opening_service_rules_todo.md` 自标「已确认，按产品决定暂缓实现」，决胜局需重新掷币的差异已知但不做；不构成待办 |
| 报告类历史文档 | `BUGS_AND_OPTIMIZATION_REPORT.md` 转为历史证据，其 P0 两项本轮已复核为不成立（见上），P1/P2 项仍需在动手前逐条验证代码；`QA_FEATURE_VALIDATION_REPORT.md`（预约极端参数崩溃、提醒触发精度、批量常用名称英文名拆分）**本轮未复核**，登记为待办前先验证是否仍成立 |
