# iOS 业务埋点口径

## 范围与原则

- iOS 使用友盟作为传输层，业务代码统一经过 `AppAnalytics`。
- 事件名以 Android `AnalyticsTracking.kt` 为主规范，页面别名参考鸿蒙 `analyticsSchema.ts`。
- Watch App 不接入埋点；手机发起联动及 Watch 回传结果均由 iPhone 上报。
- 不上传姓名、队名、地点、备注、URL、设备名、记录/预约/会话 ID、分享目标或错误原文。
- 不采集每次加减分；首次有效操作才发送 `match_start`。
- AA 计算器不上传金额。

## 跨端差异

| 语义 | iOS 标准值 | Android | 鸿蒙旧值 |
|---|---|---|---|
| 预约列表 | `schedule_list` | `schedule_list` | `schedule_page` |
| 记录详情 | `sports_record_detail` | `sports_record_detail` | `scoreboard_record_detail_page` |
| 多人记录详情 | `multiscore_record_detail` | `multiscore_record_detail` | `multi_group_record_detail_page` |
| Watch 设置 | `watch_link_page` | `watch_link_page` | `watch_sync_page` |
| 我的 Tab | `me_tab` | `me_tab` | `me_tab` |

iOS 不发送 Android 的 `score_adjust`、`amount`、`score_delta`、`score_after`。本轮新增跨端标准事件为 `share_result`、`watch_link_start`、`watch_link_result`、`notification_open`。

## 参数约束

- 事件名及参数名最多 40 字符，参数值最多 100 字符，单事件最多 25 个参数。
- 参数只能来自 `AnalyticsParameter` 白名单；非法名称、空值及友盟保留字段会被丢弃。
- `result`: `success`, `failed`, `cancelled`, `timeout`, `not_reachable`, `rejected`, `requested`。
- `outcome`: 工具产生的业务结果；抛硬币仅使用 `heads`、`tails`。
- `winner`: `side_a`, `side_b`, `draw`, `unknown`。
- `end_reason`: `rule_completed`, `manual_finish`, `abandoned`, `watch_reported`。
- `source_surface`: `phone`, `watch`。

## 核心事件链路

### 页面与入口

`screen_view` 由页面修饰器保证单个页面实例只发送一次；主 Tab 首次显示和用户切换发送 `tab_view`；主动进入二级页发送 `open_page`；业务弹窗显示发送 `open_dialog`。

### 比赛

标准漏斗：

`score_item_select` → `score_setup_confirm` → `start_game` → `match_start` → `match_finish` → `save_record` → `record_view` → `share_start` → `share_result`

- 恢复草稿只发 `resume_game`，不重复发原始开局事件。
- `ScoreboardRecordManager` 根据记录状态跃迁集中发送首次操作、首次完赛和保存结果，避免页面重绘或重复回调导致重复完赛。
- Watch 回传记录使用 `source_surface=watch` 与 `end_reason=watch_reported`。
- 计分板内“再来一场”原地重置当前页面，发送 `scoreboard_menu_action(action_name=play_again, result=requested)`；它不会创建新的页面启动上下文，因此不重复发送 `start_game`。从记录详情发起的重赛属于新的导航启动，仍发送 `start_game(entry_point=record_replay)`。

### 计时器与工具

- 计时器统一使用 `timer_item_select`, `timer_setup_option_select`, `timer_start`, `timer_pause`, `timer_resume`, `timer_switch_player`, `timer_finish`, `timer_exit`。
- 工具统一使用 `tool_item_select`, `tool_action`, `tool_setting_change`, `tool_result`, `tool_reset`。
- 十秒挑战发送 `elapsed_ms` 与 `delta_ms`；骰子只发送骰子数量；抛硬币使用 `result=success` 与 `outcome=heads|tails`；随机分组只发送参与人数和组数。

### 分享、评论、预约与 Watch

- 系统分享面板成功打开后发送 `share_start`，关闭回调只发送一次 `share_result`。
- StoreKit 只能发送 `rate_app(result=requested)`，不能解释为评分完成。
- 预约通知点击发送 `notification_open(entry_point=booking_notification)`；通知送达不发送事件。
- 每次 iPhone 联动尝试发送一个 `watch_link_start`，最终只发送一个 `watch_link_result`。

## 友盟报表建议

- 开局转化：`score_item_select` → `score_setup_confirm` → `start_game`
- 有效开局率：`match_start / start_game`
- 完赛率：`match_finish / match_start`
- 再来一场率：`scoreboard_menu_action[action_name=play_again] / match_finish`
- 分享成功率：`share_result[result=success] / share_start`
- Watch 联动成功率：`watch_link_result[result=success] / watch_link_start`
- 预约召回：`submit_form[content_type=booking_create]` → `notification_open` → `start_game[entry_point=booking_notification]`
- D1/D3/D7 留存直接使用友盟内置留存能力。
