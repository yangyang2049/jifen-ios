# iOS 3.4 — What’s New（2026-10-25，API 上传与回读完成）

状态：**中英文已获用户确认，全部 50 个语言地区已通过 API 写入并逐项回读一致**。已创建 iOS `3.4` 商店草稿，版本 ID `2c76bf82-22a6-4fc8-b176-299bd2424a50`，状态 `PREPARE_FOR_SUBMISSION`。本次仅更新 What’s New，未上传／选择构建、未提交审核、未发布。

用户已澄清口述的“Watch app”指手机版 iOS 3.4 的 **What’s New**，不涉及 Apple Watch 手表版。本轮全程使用 API，没有使用 Computer Use。

## 当前基线与评审稿

2026-10-25 已通过 Apple 公开查询接口只读核对：中国区当前公开版是 **3.3**，`currentVersionReleaseDate=2026-10-22T18:27:01Z`。其公开更新说明与 [3.3 中英文确认稿](../whats-new-3.3-2026-10-22/draft.json) 的简体中文一致。此前仅依据仓库上传记录推测 3.3 尚未发布的判断已过时。

来源：[Apple Lookup](https://itunes.apple.com/lookup?id=6759768784&country=cn)；随后 App Store Connect API 再次确认 3.3 为 `READY_FOR_SALE`，创建 3.4 前后台没有同版本草稿。新草稿沿用 3.3 的 `AFTER_APPROVAL` 发布方式，未更改发布策略。

| 文件 | 当前用途 | 条目 |
| --- | --- | --- |
| [draft.json](draft.json) | **用户已确认的中英文源**；包含用户修正的 basketball shooting practice | 简体中文 7 条、英文 6 条 |
| [translations.json](translations.json) | 其余 45 个非英语地区译文；三个英语地区直接沿用确认稿 | 繁体中文 7 条，其余 6 条 |
| [metadata.json](metadata.json) | 全部 50 个语言地区的最终上传稿 | 简繁中文各 7 条，其余各 6 条 |
| [trimmed-if-3.3-live.json](trimmed-if-3.3-live.json) | 较早的长稿，仅作历史参考；已被本轮评审稿替代，不用于翻译或上传 | 不采用 |

按本轮用户要求：**仅简繁中文包含微信登录与账号绑定，英文及其他语言均不包含微信内容**；其余内容对应。不重复上一版的小组首发与静音模式音频说明。简繁中文使用中文源，其他语言使用英文源。

## 文案

| locale | 条目 | UTF-16 长度 |
| --- | --- | --- |
| zh-Hans | 7 | 258 |
| zh-Hant | 7 | 266 |
| en-US | 6 | 627 |

50 个地区均通过长度、分点、数字方案、语言覆盖及微信范围检查，最长 890 个 UTF-16 单位，低于 4000 上限。英语四地区使用相同确认稿，原稿无需拼写变体；西语、法语、葡语按地区处理，繁体中文采用当地用词。翻译由 agent 按含义和术语逐条审校，未声称另有独立母语人工复核。

## 上传与核验

- 中英文确认源文案未改动；篮球投篮训练的含义在各语言中保留。
- 创建 3.4 后，Apple 已继承全部 50 个地区的版本资料；本轮 50 次更新均仅 PATCH `whatsNew`。
- 回读结果：50/50 与最终稿一致，其他版本本地化文本字段无变化，已发布 3.3 的全部本地化资源回读与上传前相同。
- 核验时间：2026-10-25 20:15（Asia/Shanghai）；版本仍为 `PREPARE_FOR_SUBMISSION`。
- 证据：[本地校验](validation.json)、[线上原版本备份](live-before.json)、[上传计划](upload-plan.json)、[上传回执](upload-report.json)、[最终回读](after-upload.json)、[字段保护核验](verification.json)。带时间戳的 `before-create-*.json` 和 `before-upload-*.json` 另保留创建／上传前快照。
- API 程序：[upload_whats_new.py](upload_whats_new.py)。私钥只从仓库外读取，JWT 仅在内存中；程序不调用构建上传、提审或发布接口。

## 逐条依据（都能在本仓库复核）

| 条目 | 代码与证据 |
| --- | --- |
| 小组加入流程 | 仅写扫码加入体验改进；小组（试用）的首发内容已在 3.3 公开说明中出现，不重复 |
| 我的记录 / 本人身份 | `jifen/Features/Identity/`、`Packages/JifenCore/Sources/ScoreCore/ParticipantIdentity.swift`；[实施记录](../../../docs/implementation/participant-identity-2026-10-24.md) |
| 记录云端同步与冲突 | `PersonalRecordsCloudSync.swift`、`RecordsTab.swift`（正常同步隐藏入口；冲突与失败保留处理入口）、删除文案 `records_delete_synced_message` |
| 微信登录与账号绑定 | `WechatAuthProvider.swift`、`WechatBindingView.swift`；[账号关联记录](../../../docs/account-linking-implementation-2026-10-24.md)。**仅简繁中文界面**，因此仅简繁更新说明包含此条 |
| 九球赛事积分 / 14710 / 1357 | `NineBallChaseTransfers.swift`、`NineBallTournament.swift`、`NineBallSetupDialogView.swift`、`NineBallRulesView.swift`；[规则说明](../../../docs/nine-ball-rule-presets-ios-2026-10-24.md) |
| 语音语言切换与英文拼音 | `SportsVoiceSupport.swift`、`NameTransliteration.swift`、`LocalizedVoiceAnnouncement.swift`；[官方结果播报](../../../docs/verification/official-result-voice-2026-10-24/README.md) |
| 统一扫码 + 相册 | `jifen/Features/Scan/QRScanSheet.swift`，小组加组与网页扫码登录共用，入口在首页顶栏右上 |
| 布局 / 掼蛋 / 投篮手势 / 修复 | `GuandanScoreboardView.swift`、`ShotTrainingScoreboardView.swift`、`Theme.swift` 等 |

## 不要写进说明的内容

- 不承诺“九球投屏已在电视实测”“多端登录联调已完成”“账号合并任意组合都能自动完成”——均属未验收项，见 [手动测试清单](../../../docs/qa/ios-3.4-manual-test-2026-10-25.md) 第 10 节。
- 不写技术名词（API、JSON、canonical、Keychain、ruleVersion 等），商店说明面向用户。
- 小组仍标「试用/Beta」，与 3.3 定位一致。

## 写法约定（沿用 3.3 已确认稿）

- 每条以「• 」开头、一行内读完、动词开头；末条保留“修复若干已知问题”兜底。
- 中英文共同条目的顺序一致；中文额外包含微信条目，英文及后续非中文译文不包含。
- 中文不出现品牌前缀；App 名称与截图不随本任务改动。
