# 全能计分器 iOS TODO（iOS 专属执行细节）

> 最后核对：2026-08-30
>
> **本文只保留 iOS 端的实现细节与验收。** 跨端功能范围与优先级以主表 `jifen-hos/TODO.md` 为唯一来源；冲突时以主表为准并回改本文。
>
> 各端分片：安卓 `jifen-android/TODO.md` ｜ 网站 `jifenqi-website/TODO.md` ｜ 小程序 `jifen-wechat/REVIEW_TODO.md` ｜ 后端 `jifenqi-backend/TODO.md`
>
> 维护规则：完成即删除并压成一行写入文末「归档」，注明证据（`文件:行`、测试名、接口实测日期）。**历史报告（`BUGS_AND_OPTIMIZATION_REPORT.md`、`QA_FEATURE_VALIDATION_REPORT.md`）中的条目必须先复核代码再登记，其原始结论不作为依据。**

## 待办

### P0

- [ ] **账号体系对齐**〔主表 P0〕：登录、注销与登录态需与鸿蒙/安卓同一套协议。**扫码登录 iOS 当前完全没有**——2026-08-30 全仓复核，手机端无 `scanLogin` / 二维码解析实现，仅 `jifenWatch Watch App/Views/WatchSupportQRCodeView.swift` 是手表端展示用二维码，与网页扫码登录无关。需补：「我的」页扫码入口、相机权限与 Data Safety 声明、`/scan` 与 `/confirm approve|deny` 状态流。
- [ ] **比赛记录多端云同步（iOS 侧）**〔主表 P0〕：与鸿蒙/安卓共用字段名与覆盖规则；服务端当前只有 `commonDataSync.ts`（常用名称/地点），记录同步 API 尚未存在，须等后端先行。

### P1

- [ ] **会员兑换码与赠卡**〔主表 P1〕：2026-08-30 复核，iOS 全仓对 `兑换` / `redeem` / `promoCode` / `giftCard` **零命中**，即兑换码输入、卡号卡密解析与权益展示全部未实现；VIP 已有 IAP 与恢复购买。后端 `adminPromoCodes.ts`、`adminGiftCards.ts`、`vip.ts` 已具备服务端基础。
- [ ] **篮球日志区分比赛时间与真实时间（iOS 侧）**〔主表 P0〕：动作落库需同时保存节次、小节内比赛时间与真实时间，字段命名与安卓/鸿蒙一致。
- [ ] **比赛记录结果纠错（iOS 侧）**〔主表 P1〕：名称与笔记已具备，剩余改最终比分/积分与重算；与记录云同步同批定 revision 语义。
- [ ] **反馈与合规**：反馈闭环、隐私与账号删除流程对齐鸿蒙；上架材料须与 `DEPLOYMENT_PRE_CHECK` 级别的实机验证一致。
- [ ] **补一轮 iOS 跨端一致性对照审计**：**当前最大的结构性缺口**。`jifen-android/docs/2026-08-28-cross-platform-diff/` 只覆盖安卓 vs 鸿蒙两端，iOS 未纳入任何一致性基线。建议按同一方法（计分板容器 / 规则与设置 / 记录列表 / 记录详情与分享四线）做一次 iOS 对照，产出同格式差异表并入主表。
- [ ] **崩溃风险清理**：`record.endTime`、`playerCount`、`timerSubscription`、`displayTimer` 等强解包改 `guard` / `if let`（报告列为 P1，动手前逐条复核是否仍成立）。
- [ ] **本地化硬编码**：`BoxingScoreboardView`、`ScoreboardRecordDetailPage` 相关中文硬编码提取为本地化 key（2026-08-30 确认这些符号仍在 `jifen/Features/Scoreboard/Shared/ScoreboardLaunchView.swift` 等文件中被引用）。

### P2

- [ ] Sheet 统一加 `presentationDragIndicator`（`QuickStartEditView`、`SettingsView` 内部分 sheet）。
- [ ] `ScoreboardRecordsViewModel.refreshRecords` 移到后台线程，避免主线程卡顿。
- [ ] 记录 / 预约 / 活动列表补 loading 与空状态（`ProgressView` 或骨架）。
- [ ] Theme 逐步替换裸 `padding` / `color` 值；`CHANGELOG.md` 拆条与补全空 bullet。
- [ ] Watch 端「返回」与「退出」文案统一，并与 iOS 隐私策略一致。

## 归档（不再跟踪，仅留痕）

| 事项 | 证据 |
|---|---|
| 原报告两项「P0 Bug」已不成立 | `FlipCoinView.swift:229-232` 已在 `onDisappear` 中 `flipTimer?.invalidate()` 并置 nil；`NewGameDialogView.swift` 内已无 `asyncAfter`（`HomeTab.swift:258,696` 的 `asyncAfter` 属另一处已确认逻辑）。**`BUGS_AND_OPTIMIZATION_REPORT.md` 的优先级表不得直接引用** |
| 四项新增运动（毽球、壁球、软式网球、板式网球）iOS 已迁移 | 2026-08-09 跨端实现与分端审查完成，iOS 修复 5 项；协议字段与三端一致；按 3.0 决策不进手表入口 |
| 后端 `gameType` 白名单已覆盖 iOS | 线上 `GET /api/client-config/scoreboard`（`x-client-platform: ios`）实返 controller 33 项，含四项新运动（2026-08-30） |
| 排球与沙排每局首发规则 | `jifen-ios/docs/p0_volleyball_opening_service_rules_todo.md` 自标「已确认，按产品决定暂缓实现」，决胜局需重新掷币的差异已知但不做；不构成待办 |
| 报告类历史文档 | `BUGS_AND_OPTIMIZATION_REPORT.md` 转为历史证据，其 P0 两项本轮已复核为不成立（见上），P1/P2 项仍需在动手前逐条验证代码；`QA_FEATURE_VALIDATION_REPORT.md`（预约极端参数崩溃、提醒触发精度、批量常用名称英文名拆分）**本轮未复核**，登记为待办前先验证是否仍成立 |
