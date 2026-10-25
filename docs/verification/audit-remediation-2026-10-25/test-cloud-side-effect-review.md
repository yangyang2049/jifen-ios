# 测试期间云同步影响面的本地只读核对（2026-10-25）

采集时间：2026-10-25T11:32:08+08:00。设备：iPhone 17 Pro / iOS 26.5 模拟器。

仅读取模拟器 Application Support 中 `participant-identity/identity.json`、`cloud.json`、仓库测试源码及既有测试日志；未读取 Keychain 或 token，未请求远程接口，未修改或删除任何缓存/云端记录。下面账户仅使用本地 ID 的 SHA-256 前 12 位指纹。

后续用户确认：模拟器此前登录的是**专用测试账号**。这一用途确认来自用户直接回复；下文保留原始只读核对证据。测试数据继续保留，没有执行云端清理，30 条 UUID 记录的逐条来源也没有因此被重新认定。

## 可确认的范围

活动账户指纹 `aceb4705a756` 在全量测试源码中没有相同 ID 字面量；原始本地元数据无法识别其用途，现已由用户确认是专用测试账号。其云同步缓存有 59 条记录，全部带服务端 ID 和正 revision；29 条可明确归为 UI fixture，另外 30 条 UUID 记录缺少 fixture 标记，不能据此认定可删除。

29 条 fixture 同时满足 `ui-fixture-` 固定记录键及 `fixture_score` / `fixture_section` 操作标记；生成出处为 `jifen/Features/Records/UITestRecordFixtures.swift:108-125`。它们的本地 ledger owner 全部匹配该活动账户。服务端 revision 为 28 条 3、1 条 2，均非删除状态。

| 活动账户状态 | 明确 UI fixture | 来源未确定 | 合计 |
|---|---:|---:|---:|
| 服务端记录缓存 | 29 | 30 | 59 |
| 待处理 outbox | 29（upsert） | 24（delete） | 53 |
| 冲突 | 29 | 0 | 29 |
| 被隔离的失败 | 0 | 24（RECORD_NOT_FOUND） | 24 |

这 24 个删除目前为失败隔离状态，不能把它们记为已成功删除。没有执行任何补偿删除。

另一个非活动账户指纹 `a9e18465f1d5` 在 `WechatBindingTests` / `APIClientSessionIsolationTests` 有固定测试字面量引用；其服务端记录缓存为 0，outbox 为 52 条 upsert（29 条 UI fixture、23 条来源未确定）。字面量匹配本身也不能证明某个远程账户的实际用途。

## 时间区分

全部日期均为 2026-10-25：

| 明确 UI fixture 的服务端字段 | UTC 范围 | Asia/Shanghai 范围 |
|---|---|---|
| updatedAt | 2026-10-25T03:14:04+00:00 → 2026-10-25T03:14:05+00:00 | 2026-10-25T11:14:04+08:00 → 2026-10-25T11:14:05+08:00 |
| playedAt | 2026-10-25T02:23:07+00:00 → 2026-10-25T02:51:07+00:00 | 2026-10-25T10:23:07+08:00 → 2026-10-25T10:51:07+08:00 |

29 条 fixture 的服务端更新时间在 **11:14:04–11:14:05**，早于最终全量单测日志中的 **11:23** push。这些 fixture 在该轮最终单测开始前已经存在，不能都算作这一轮新上传。

30 条未分类 UUID 记录的服务端 updatedAt 为 **2026-10-25T11:23:28+08:00 → 2026-10-25T11:23:31+08:00**（UTC：2026-10-25T03:23:28+00:00 → 2026-10-25T03:23:31+00:00），与最终测试 push 窗口一致；其 revision 分布为 7 条 1、4 条 3、19 条 5。这是测试窗口发生真实记录更新的强证据，但缺少运行前快照及逐条服务端审计，不能单靠缓存确认这些记录的来源或给出安全删除名单。

`ios-unit-final.log:2733-2751` 记录了 self-identity 200、pull 200 及两次 push 200，响应大小明显不同于单元测试固定 mock。`ScoreboardDisplayTests.fixture()` 本身只构造展示状态、不持久化记录；网络事件在其快照循环让出主线程时出现，不能仅按日志所属 test case 把记录归为该 suite 生成。

身份侧存在 41,414 个 recordLibraries 键（41,375 UUID、29 UI fixture、10 其他），与此前 View init 循环生成临时 UUID 的故障一致；这并不等于云端也存在 41,414 条记录。

## 明确的 29 个 UI fixture 记录键

下表时间为 Asia/Shanghai。每条 UTC 时间、owner 匹配布尔值、操作标记数量及队列状态见 [聚合 JSON](test-cloud-side-effect-metadata.json)。不包含人名、账户 ID 全文或未分类 UUID。

| recordKey | 服务端 revision | playedAt | updatedAt |
|---|---:|---|---|
| `ui-fixture-air_volleyball` | 3 | 10:36:07 | 11:14:04 |
| `ui-fixture-archery_dual` | 3 | 10:35:07 | 11:14:04 |
| `ui-fixture-badminton` | 3 | 10:51:07 | 11:14:04 |
| `ui-fixture-basketball` | 3 | 10:41:07 | 11:14:04 |
| `ui-fixture-basketball_training` | 3 | 10:39:07 | 11:14:04 |
| `ui-fixture-beach_volleyball` | 3 | 10:37:07 | 11:14:04 |
| `ui-fixture-billiards` | 3 | 10:33:07 | 11:14:04 |
| `ui-fixture-boxing` | 3 | 10:34:07 | 11:14:04 |
| `ui-fixture-doudizhu` | 3 | 10:29:07 | 11:14:05 |
| `ui-fixture-eight_ball` | 3 | 10:31:07 | 11:14:05 |
| `ui-fixture-foosball` | 3 | 10:25:07 | 11:14:05 |
| `ui-fixture-football` | 3 | 10:43:07 | 11:14:04 |
| `ui-fixture-football_5v5` | 3 | 10:42:07 | 11:14:04 |
| `ui-fixture-guandan` | 3 | 10:28:07 | 11:14:05 |
| `ui-fixture-multi_scoreboard` | 3 | 10:23:07 | 11:14:05 |
| `ui-fixture-nine_ball` | 3 | 10:30:07 | 11:14:05 |
| `ui-fixture-padel` | 3 | 10:44:07 | 11:14:04 |
| `ui-fixture-pickleball` | 3 | 10:48:07 | 11:14:04 |
| `ui-fixture-pingpong` | 3 | 10:49:07 | 11:14:04 |
| `ui-fixture-shengji` | 3 | 10:27:07 | 11:14:05 |
| `ui-fixture-shuttlecock` | 3 | 10:47:07 | 11:14:04 |
| `ui-fixture-simple_score` | 3 | 10:24:07 | 11:14:05 |
| `ui-fixture-snooker` | 3 | 10:32:07 | 11:14:04 |
| `ui-fixture-soft_tennis` | 3 | 10:45:07 | 11:14:04 |
| `ui-fixture-squash` | 3 | 10:46:07 | 11:14:04 |
| `ui-fixture-tennis` | 3 | 10:50:07 | 11:14:04 |
| `ui-fixture-three_basketball` | 3 | 10:40:07 | 11:14:04 |
| `ui-fixture-uno` | 2 | 10:26:07 | 11:14:05 |
| `ui-fixture-volleyball` | 3 | 10:38:07 | 11:14:04 |
