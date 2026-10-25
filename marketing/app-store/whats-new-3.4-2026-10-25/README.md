# iOS 3.4 — What’s New 草稿（2026-10-25）

状态：**仅供评审的草稿，未上传 App Store Connect**，未提交审核、未发布。版本 `3.4 (78)`。

## 先确认基线：3.3 到底发布了没有

本仓库最后一次 3.3 商店记录（[whats-new-3.3-2026-10-22](../whats-new-3.3-2026-10-22/README.md)）是 `PREPARE_FOR_SUBMISSION`，明确写着未提交审核、未发布，此后没有新的线上版本证据。`3.3` 标签本身已包含「小组（试用）」和中文界面微信登录。

所以两份稿子，二选一，不要混发：

| 文件 | 适用前提 | 条目 |
| --- | --- | --- |
| [draft.json](draft.json) | **线上仍是 3.2.3、3.3 未发布**（当前证据更支持这一种） | 7 条，含小组（试用）与微信登录 |
| [trimmed-if-3.3-live.json](trimmed-if-3.3-live.json) | 3.3 已经上线 | 6 条，去掉 3.3 已发的小组与微信登录 |

上传前先在 App Store Connect 只读确认线上版本号，再选口径。两种口径的其余条目相同。

## 文案

| locale | 条目 | UTF-16 长度 |
| --- | --- | --- |
| zh-Hans | 7（trimmed 6） | 416（351） |
| zh-Hant | 7（trimmed 6） | 412（355） |
| en-US | 7（trimmed 6） | 1206（1033） |

上限 4000，均通过。繁体用词按台港习惯：記錄、雲端、介面、最佳化、摜蛋、乒乓球、相簿、辨識。其余 47 个商店地区**尚未翻译**，补译走既有流程（[scripts/app_store_localization.py](../../../scripts/app_store_localization.py)，编辑源在 `marketing/app-store/localization-2026-10-02/locales/<ASC-locale>.json`），翻完再上传，避免只有 3 个地区更新。

## 逐条依据（都能在本仓库复核）

| 条目 | 代码与证据 |
| --- | --- |
| 小组（试用） | 3.3 标签已含；见 [3.3 稿](../whats-new-3.3-2026-10-22/draft.json) |
| 我的记录 / 本人身份 | `jifen/Features/Identity/`、`Packages/JifenCore/Sources/ScoreCore/ParticipantIdentity.swift`；[实施记录](../../../docs/implementation/participant-identity-2026-10-24.md) |
| 记录云端同步与冲突 | `PersonalRecordsCloudSync.swift`、`RecordsTab.swift`（正常同步隐藏入口；冲突与失败保留处理入口）、删除文案 `records_delete_synced_message` |
| 微信登录与账号绑定 | `WechatAuthProvider.swift`、`WechatBindingView.swift`；[账号关联记录](../../../docs/account-linking-implementation-2026-10-24.md)。**仅简繁中文界面**，文案里已注明 |
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
- 简繁英三份条目顺序一致，便于逐条对照审校。
- 中文不出现品牌前缀；App 名称与截图不随本任务改动。
