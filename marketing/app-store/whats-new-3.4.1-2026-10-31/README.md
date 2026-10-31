# iOS 3.4.1（84）更新说明源稿

日期：2026-10-31（Asia/Shanghai）。状态：**四条源稿已获用户确认，全部 50 个语言地区已通过现有 API 写入并回读一致**。3.4.1 草稿 ID `045507ac-dc8a-4208-9250-0bfc95e62c65`，最新状态 **`WAITING_FOR_REVIEW`（等待审核）**，构建 **84**。按用户要求，先修复并验证 Duo 首行比分异常，重新打包并通过 Apple 服务端校验后上传；2026-10-31 13:13（Asia/Shanghai）通过 API 提交审核并回读确认。尚未审核通过或发布。

[draft.json](draft.json) 沿用已有的 App Store 源稿结构，每条以「• 」开头，中英文顺序对应。按用户要求精简为四条：五人制篮球、多人计分、匹克球、小屏幕优化。中英文源保持确认稿不变；其他英语地区沿用英文，其余地区使用对应译文。全程使用项目现有 App Store Connect API，未使用 Computer Use。

## 发布基线

2026-10-31 本轮只读检查已确认：App Store Connect 中 iOS **3.4（82）为 `READY_FOR_SALE`**，Apple 公开查询亦返回 3.4，公开发布时间为 **2026-10-26 11:22:32（Asia/Shanghai）**。本轮随后通过 API 创建 3.4.1 草稿并更新全部 50 个地区。

本稿以已发布的 3.4 为基线，仅写本轮增量；微信登录、我的记录、记录云同步、九球新规则、语音播报及扫码等已在 [3.4 说明](../whats-new-3.4-2026-10-25/draft.json) 出现的内容不再重复。该目录 README 中 10-25 尚未提审的状态属于历史快照。

只读原始证据：[asc-preflight-readonly.json](/Users/yangyang/Library/Developer/jifen-ios-test-artifacts/runs/20261031T022812187319Z-ios-341-preflight-20261031/asc-preflight-readonly.json)。该证据属于外部测试批次，会按保留策略到期；上述精简结论保留在本目录。

## 简体中文

```text
• 五人制篮球支持赛前自定义时长。
• 多人计分支持最多 50 人。
• 匹克球支持自定义 1～99 分的目标分。
• 优化小屏幕下的设置和计分显示。
```

## English

```text
• Set custom durations before starting a 5-on-5 basketball game.
• Multi-Score now supports up to 50 players.
• Pickleball now supports custom target scores from 1 to 99.
• Improved setup and score displays on smaller screens.
```

## 提审状态

[submission-status.json](submission-status.json) 保存最终摘要。Review Submission ID 为 `1c0d67e5-2d71-4fc2-8a1a-3f78455d22f6`，build ID 为 `38e6703c-10b2-4e85-9b0a-f6cb850d5409`。发布方式沿用 `AFTER_APPROVAL`。

Apple 提审前校验要求补充新分级字段 `socialMedia`；旧版和草稿均为空。按 Apple 官方定义，该项指通过社交动态或类似发现方式向许多用户传播/放大用户内容；本工具没有这种社交内容流，因此仅为当前草稿填 `false`，其他分级项和已发布版本未变。正式包、校验、上传及提审的完整证据存于 `/Users/yangyang/Library/Developer/jifen-ios-release-artifacts/2026-10-31-3.4.1-84-duo-fixed/`。

## API 写入与核对

- [translations.json](translations.json)：45 个非 en-US / zh-Hans 地区的四条译文；其余三个英语地区沿用英文。
- [metadata.json](metadata.json)：全部 50 个地区上传稿。每个地区四条，最长 322 个 UTF-16 单位。
- [upload_whats_new.py](upload_whats_new.py)：复用仓库外现有凭据，创建版本并仅修改 `whatsNew`；没有构建上传、提审或发布调用。
- [verification.json](verification.json)：2026-10-31 12:29（Asia/Shanghai）回读，50/50 精确匹配，其他文本字段无变化，已发布 3.4 资料不变，沿用 `AFTER_APPROVAL` 发布方式。
- [validation.json](validation.json) 分别记录写入前源稿哈希 `metadataBeforeUploadSha256` 与写入后当前文件哈希 `metadataCurrentSha256`；后者包含上传状态、版本 ID 和回读时间。
- [上传计划](upload-plan.json)、[回执](upload-report.json)、[回读](after-upload.json)与带时间戳的快照保留核查依据。
- 翻译经 Codex 逐条核对语义及术语，不声称独立母语人工复核。

## 取舍与依据

| 条目 | 已核对的来源与边界 |
| --- | --- |
| 篮球自定义计时 | `SportsSetupSettingsSection.swift`、`SportsSetupDraft.swift`、`BasketballMatch.swift`。五人制篮球仅在开赛前设置每节与加时时长，进入计分板后锁定，不能从设置或编辑中修改；文案不扩大到三人篮球。历史文档中的赛中修改流程不再作为功能或验证依据。 |
| 多人计分最多 50 人 | `MultiScoreSetupControls.swift`、`MultiScorePaging.swift`、`MultiScoreboardView.swift`。人数范围是 3～50，精简文案只保留人数上限；与小组成员容量无关。 |
| 匹克球目标分 | `RallyMatch.swift`、`SportsSetupDraft.swift`，范围明确为 1～99。 |
| 小屏幕显示与修复 | [SE 2 回归记录](../../../docs/verification/se2-regression-2026-10-30/README.md)、[多人样式验证记录](../../../docs/verification/multi-score-style-2026-10-31/README.md)，涵盖姓名区滚动、固定底部操作区及分页比分净空。 |

未单列以下内容：

- 按用户要求缩短为四条，不展开多人分页、批量姓名、找人、纯色样式和篮球预约沿用配置。

- 实体投屏尚未验收，本稿不把多人投屏分页作为宣传重点，也不承诺电视或 AirPlay 实测通过。
- Watch 拆除及 Apple 支持工单、归档签名、内部重构、测试接线、临时测试产物管理、英文临时回填，均不作为面向用户的新增功能。
- 小组人数限制、网络 30 秒总超时、乒乓球自定义背景等不在本次实现范围。
- 3.3 已公布的小组试用与静音模式声音播放不重复写入。

综合变更依据：[3.4.1 移植与收尾记录](../../../docs/2026-10-30-ios-3.4.1-android-parity.md) 及当前工作区差异。本稿只表述功能，不将历史回归记录写成当前正式发布包已验收。
