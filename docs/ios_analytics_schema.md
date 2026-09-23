# iOS Firebase Analytics 业务口径

## 范围与原则

- iOS 业务事件统一经过 `AppAnalytics`，生产 sink 为 Firebase Analytics。
- 屏幕使用 Firebase SwiftUI 原生 `analyticsScreen(name:class:extraParameters:)`；适配层只提供类型安全的屏幕名和分组，不自行发送 `screen_view`。
- `FirebaseAutomaticScreenReportingEnabled` 保持关闭，避免业务页面与 `UIHostingController` 自动页面重复。
- Android 友盟事件只用于核对业务触发点，不要求两端事件名完全一致。
- 不上传姓名、队名、账号、手机号或邮箱、地点或备注正文、反馈正文、URL、业务记录或预约 ID、投屏码、通知载荷或错误原文。
- 不采集每次加减分；每局首次有效计分只发送一次 `match_start`。
- AA 计算器不上传金额。

## 参数约束

- 事件名及参数名最多 40 字符，参数值最多 100 字符，单事件最多 25 个参数。
- 参数只能来自 `AnalyticsParameter` 白名单；非法名称、空值、Firebase 保留事件名、保留前缀和敏感字段会被拒绝。
- `result`: `success`, `failed`, `cancelled`, `timeout`, `not_reachable`, `rejected`, `requested`, `pending`, `started`。
- `outcome`: 工具或投屏动作产生的非生命周期结果。
- `winner`: `side_a`, `side_b`, `draw`, `unknown`。
- `end_reason`: `rule_completed`, `manual_finish`, `abandoned`, `watch_reported`。
- `source_surface`: `phone`, `watch`。
- `session_state`: `new`, `resumed`。

## 屏幕

Firebase 原生 modifier 在页面真实出现时发送 `screen_view`。不再发送 `app_shell`、`tab_view`、`open_page` 或 `open_dialog`，也不以本地 `didTrack` 状态阻止返回页面后的新一次浏览。

稳定的 `screen_class` 分组为：`tab`、`scoreboard`、`timer`、`tool`、`record_detail`、`schedule`、`account`、`settings`、`display`。

## 核心事件链路

### 比赛

标准漏斗：

`select_content` → `score_setup_confirm` → `scoreboard_open` → `match_start` → `match_finish` → `record_save`

- `select_content` 使用 `content_type`、`item_id` 和可选 `entry_point`。
- 新开与恢复均发送 `scoreboard_open`，通过 `session_state=new|resumed` 区分。
- `ScoreboardRecordManager` 根据记录状态跃迁集中发送首次计分、首次完赛和保存结果，避免 SwiftUI 重绘导致重复。
- Watch 回传记录使用 `source_surface=watch` 与 `end_reason=watch_reported`。
- 撤销、重置、菜单操作和再来一场统一为 `scoreboard_action`，使用 `action_name` 区分。

### 计时器与工具

- 计时器使用 `timer_start`、`timer_finish` 和 `timer_action`；暂停、继续、切换玩家、退出和配置确认由 `action_name` 区分。
- 工具统一使用 `tool_action`，`item_id` 标识工具，`action_name` 标识操作。
- 十秒挑战只发送时长与误差；骰子只发送骰子数量；抛硬币使用 `outcome=heads|tails`；随机分组只发送参与人数和组数。

### 记录、预约、常用数据和反馈

- 记录筛选、编辑、删除、查看与备注动作统一为 `record_action`。
- 预约使用 `booking_action`，常用名称、地点和快捷项目使用 `common_data_action`，反馈使用 `feedback_action`。
- 预约通知点击发送 `booking_reminder_open`；不使用 Firebase 移动端保留名称 `notification_open`。

### 分享、登录和购买

- 系统分享只在完成回调成功时发送推荐事件 `share`；用户取消不发送，真实错误发送内部事件 `share_failed`，只含允许列表内的 `error_category`。
- 登录成功发送推荐事件 `login(method=apple|password|qr)`；失败或取消只发送 `auth_result`。
- 主动购买使用 `purchase_flow` 记录开始、等待、取消和失败；StoreKit 2 验证成功后通过 Firebase `Analytics.logTransaction` 生成标准 `in_app_purchase`，不另建自定义收入事件。
- 恢复购买使用 `purchase_flow(flow=restore)` 记录开始及最终结果。
- `Transaction.updates` 监听器和恢复购买路径不重复调用 `Analytics.logTransaction`，避免同一交易被重复计收。

## 报表口径

- 开局转化：`select_content` → `score_setup_confirm` → `scoreboard_open`
- 有效开局率：`match_start / scoreboard_open`
- 完赛率：`match_finish / match_start`
- 保存成功率：`record_save[result=success] / match_finish`
- 再来一场率：`scoreboard_action[action_name=play_again] / match_finish`
- 预约召回：`booking_action[action_name=create]` → `booking_reminder_open` → `select_content[entry_point=booking_notification]`
- D1/D3/D7 留存使用 Firebase 内置留存能力。

Firebase/GA4 后台的自定义定义、关键事件与 DebugView 验收清单见 `docs/firebase-analytics-console.md`。
