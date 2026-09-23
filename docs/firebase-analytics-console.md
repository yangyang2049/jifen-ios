# Firebase Analytics 后台配置

本文件记录 iOS 新埋点口径上线时需要在 Firebase / GA4 后台完成的配置。代码侧不会上传玩家姓名、账号、联系方式、反馈或备注正文、预约地点、业务记录 ID、投屏码、原始错误文本或通知载荷。

## 自定义定义

在 Google Analytics 的“管理 → 数据显示 → 自定义定义”中创建以下事件级自定义维度：

- `entry_point`
- `game_type`
- `record_type`
- `layout_mode`
- `session_state`
- `source_surface`
- `action_name`
- `result`
- `outcome`
- `end_reason`
- `error_category`
- `setting_name`
- `setting_value`
- `flow`

创建以下事件级自定义指标，单位按说明选择：

- `duration_ms`：标准单位
- `player_count`：标准单位
- `participant_count`：标准单位
- `team_count`：标准单位

`screen_name`、`screen_class`、`content_type`、`item_id`、`method`、购买金额和币种使用 Firebase 预定义字段，不重复登记为自定义定义。

## 关键事件

将下列事件标记为关键事件：

- `match_finish`
- Firebase 标准 `in_app_purchase`（StoreKit 2 由 `Analytics.logTransaction` 生成）

`login`、`share` 先保留为普通漏斗事件。

## DebugView 验收

发布前用 DebugView 完成以下检查：

1. 首页和五个 Tab、详情页返回、计分页、计时器、工具、登录和会员页每次真实出现只产生一个正确的 `screen_view`。
2. 不出现 `app_shell` 或 `UIHostingController` 页面。
3. 核心漏斗完整：`select_content` → `score_setup_confirm` → `scoreboard_open` → `match_start` → `match_finish` → `record_save`。
4. 取消系统分享不产生 `share`；登录失败不产生 `login`。
5. StoreKit 2 购买成功由 `Analytics.logTransaction` 产生标准 `in_app_purchase`；主动购买路径只额外记录 `purchase_flow` 的开始、等待、取消或失败，恢复路径和交易监听器不重复记录收入事件。
6. 预约通知点击产生 `booking_reminder_open`，不存在自定义 `notification_open`。

## 发布前隐私复核

- App Store Connect 隐私披露包含 Analytics、购买记录、设备标识和产品交互用途。
- 隐私政策与实际采集字段一致。
- DebugView 中抽查所有事件参数，确认没有用户输入正文、业务 ID、投屏码或原始错误信息。
