# 三端文案对应性与 iOS 47 语言翻译复核（2026-10-21）

2026-10-21 修复状态：本文保留初次审计快照。二次复核纠正了源文改动数量、no-ad 可达性及芬兰语误报，并完成确认缺陷的修复。当前结果、逐项处理和验证边界见 [复核修复记录](group-copy-remediation-2026-10-21.md)。

范围：iOS / Android / HarmonyOS 三端全部界面文案；小组文案为重点。口径为当前**未提交工作区**。
方法：只读静态比对资源与调用点，未修改任何生产代码或资源。翻译由人工逐项核对结构、语义与语言归属，未调用第三方翻译服务，也未做独立母语审校。

## 0. 结论摘要

| 维度 | 结论 |
| --- | --- |
| 小组文案「一一对应」 | **不成立**。三端小组键名 650 / 867 / 826，三端同名键仅 270 个；按中文文案归并后三端共有 235 条，占三端并集 963 条的 **24%** |
| 有契约的部分 | **基本一一对应**。`jifen-hos/docs/groups/shared-copy-contract.json` 的 198 条语义键在英文侧 **195/198 完全一致**（余 3 条为 iOS 单方改写），中文侧 194/198 一致（余 4 条仅占位符语法差异） |
| 无契约的部分 | 三端各自新增约 150–200 条仅本方使用的键，属**平台独有或漏对齐**，需要逐条判定 |
| iOS 47 语言 | 键集合 2101×47 全等、格式参数 0 处不一致、复数 30 键×47 目录齐全、脚本误用 0 处；但存在 **1 类真实翻译漏洞 + 1 类术语风险 + 1 类结构性缺口**（见 §5） |
| iOS 小组外语 | 44 个外语目录中 25 个仍与英文完全相同（共 178 条，单语言最多 14 条），均为白名单词，**可接受**；但 54 条英文源文改写后 44 语言的译文**整体未跟进**（1227 行） |
| 语音播报 | 47 目录中 46 有资源（乌尔都语按设计不开放），但 **7 条语义在所有 46 套里都是英文**，其中 5 条在可达路径上 |

## 1. 三端资源清点

| 项 | iOS | Android | HarmonyOS |
| --- | --- | --- | --- |
| 资源总键 | 2101 | 2843 | 2596 |
| `group_*` 键 | 650 | 867 | 826 |
| 语言目录 | 47（`Localizable` + `InfoPlist` + `stringsdict` + `ScoreVoice`） | 3（`values` 英文 / `zh-rCN` / `zh-rTW`） | 7（`base` 英文 / `en_US` / `zh_CN` / `zh_HK` / `zh_Hant` / `zh_TW` / `zh_MO`） |
| 目录内键齐 | 47/47 全等（Android/HOS 各自目录亦全等） | 是（2856 键） | 是（2596 键） |
| 重复键 | 0 | 0 | 0 |

HarmonyOS 的 5 个中文目录中，`zh_MO` 与 `zh_HK` 2596 键完全相同，`zh_Hant` / `zh_TW` 各只有 3 键与 `zh_HK` 不同（`record_note_microphone_denied` 咪高峰/麥克風、`match_title_placeholder` 桌球/司諾克、`group_training_conflict_unavailable` 網絡/網路），实际只有 en / zh-Hans / zh-Hant 三种语言，与 Android 的 3 目录同构；iOS 的 47 语言是唯一真正多语的一端。这 3 处 HK/TW 用词差异本身是对的，但 `group_training_conflict_unavailable` 说明小组文案里仍混着港台两套网络用词。

## 2. 小组文案：一一对应的实际情况

### 2.1 键名层面

三端同名（`group_*` 完全一致的键名）**270** 个；iOS 独有 342、Android 独有 216、HarmonyOS 独有 185。
同名键的中文文案有 15 条不一致，扣除 1 条纯空格差异后为 **14 条实质差异**（§2.3）。

这三端存在三套并行的命名体系：

- iOS 使用 `group_*` 作调用键，再由 `GroupCopyKey.swift`（214 条别名）映射到 `group_copy_*` 规范键，资源里两套键**同时存在、值相同**（208 条旧键仍在发版资源里）。
- Android 使用 `group_copy_*` 规范键（184 处引用）+ `group_prd_*` / `group_audit_*` / `group_v1_*` 历史前缀。
- HarmonyOS 同 Android 规范键，另有 `group_ui_*` / `group_parity_*` / `group_common_*`。

因此「同名键」数量天然偏低；真正的对应关系要看契约。

### 2.2 契约层面（结论最好的部分）

`shared-copy-contract.json` 覆盖 198 条普通小组通用语义，三端都实现了别名映射。实测：

- **英文文案：195/198 完全一致**。差异 3 条：`group_copy_ranking_me_suffix`（Android 存 `\u0020` 转义，值等价）、`group_copy_reload_version`（iOS 为 `Reload`，另两端 `Load latest version`）、`group_copy_lineup_reload_message`（iOS 用 `latest saved schedule`，另两端 `latest version`）。
- **中文文案：194/198 一致**。差异 4 条全部只是占位符写法（`%@` / `%1$s` / `{name}`），语义一致。
- 资源覆盖：198 条在三端资源里**全部存在**，无缺键。
- 调用覆盖：按调用点统计，**170 条三端都在用**，23 条只有两端在用，4 条一端在用，1 条三端都未使用（`group_copy_discard_upload`）。仅一端在用的几条都是真实缺口（见 §2.4）。

### 2.3 同名键的 14 条实质差异（需修）

| 键 | iOS | Android | HOS | 判定 |
| --- | --- | --- | --- | --- |
| `group_save` | 确认 | 保存 | 保存（`group_common_save`） | **iOS 语义错**：iOS 三处按钮（Done / Save / Confirm）都取「确认」，另两端是「保存」 |
| `group_error_name_length` | 小组名称需为 2–24 个字。 | 名称需为 2–24 个字符 | 名称需 2–24 个字 | 措辞不一致，可统一 |
| `group_error_server` | 操作未能完成，请稍后重试。 | 小组服务暂时不可用，请稍后重试 | 服务暂时不可用，请稍后重试 | iOS 丢了「小组服务」主语 |
| `group_error_reason_required` | 请填写原因后继续。 | 请填写原因 | 请填写原因 | 可接受 |
| `group_error_place_locked` | 已有开局或完赛场次，不能修改场馆。 | …场馆不能再修改 | …场馆不能再修改 | 可接受 |
| `group_error_session_completed` | 该场次已完成。 | 本场已完成，无法请假。请刷新排期查看赛果。 | 该场次已完成，不能请假 | **iOS 缺后半句**，用户不知道下一步 |
| `group_error_session_has_result` | 该场已有赛果，请先作废原赛果再补记。 | 本场已录入赛果。更正前请先作废原赛果。 | 该场次已有赛果，请先作废原赛果再补记 | 可接受 |
| `group_activity_status_scheduled` | 待开始 | 待开始 | **待排赛** | **HOS 与另两端冲突**；同项目 HOS 另有 `schedule_time_status_scheduled`=待开始 |
| `group_list_add_title` | 创建或加入小组 | 创建或加入小组 | 要开始哪个？ | HOS 是按钮标题而非分组标题 |
| `group_audit_ui_share_qr` | 分享二维码 | 分享二维码 | 分享二维码图片 | HOS 多余「图片」 |
| `group_audit_ui_share_invitation` | 分享邀请 | 分享邀请 | 分享邀请文字 | HOS 多余「文字」 |
| `group_join_scan_hint` | 扫描小组二维码 | 扫描小组二维码 | 扫小组二维码 | 可接受 |
| `group_invitation_intro_ball` | …约球、计分！ | …约球、计分！ | …约球、**记分**！ | HOS 单条用词与全端「计分」不一致 |
| `group_training_date` | 日期 | 训练日期 | 训练日期 | **iOS 丢失「训练」限定** |
| `group_share_message` | …输入小组号加入： | …输入小组号加入： | …输入小组号加入小组： | HOS 冗余 |
| `group_activity_section_upcoming` | 进行中 · 报名中 | 进行中 · 报名中 | 进行中·报名中 | 纯空格 |

### 2.4 只有一端在用的契约条目（真实缺口）

| 契约键 | 有 | 无 | 说明 |
| --- | --- | --- | --- |
| `group_copy_lineup_reload_message` | HOS | iOS、Android | 放弃未保存场次安排的确认文案，两端缺失 |
| `group_copy_discard_upload` | 无 | 三端 | 契约里保留但三端都没接上（iOS 只有别名，无调用点） |
| `group_copy_reject_message` | HOS | 其余 | — |
| `group_copy_removed_members_expand/collapse` | HOS | 其余 | 已移除成员分组的展开/收起 |
| `group_copy_keep_draft` | iOS、Android | HOS | 冲突弹窗「继续编辑本地版本」 |

### 2.5 平台独有文案规模（需逐条判定，不能默认是缺陷）

按中文文案归并（忽略占位符写法）：

| 分布 | 条数 |
| --- | --- |
| 三端都有 | 235 |
| Android + HOS 有，iOS 无 | 177 |
| Android + iOS 有，HOS 无 | 27 |
| HOS + iOS 有，Android 无 | 14 |
| 仅 Android | 193 |
| 仅 HOS | 161 |
| 仅 iOS | 156 |
| **并集** | **963** |

抽样分类结果：

- **属平台合理差异**：投屏（AirPlay vs Miracast vs 无线投屏）、系统设置入口、机型专属文件名、`sync_*` 同步码措辞（iOS/Android「短码」vs HOS「同步码」）、计时单位（见 §6）。
- **属 iOS 功能缺口导致的文案缺口**（不是文案 bug）：`activity_registration_count`（报名 x/y）、`result_detail_title`（赛果详情，iOS 复用 `match_detail`）、`edit_conflict_*`（编辑冲突对比，iOS 只有弹窗没有对比页）、`join_request_*`（申请未通过/重新申请卡片）、`notice_empty`（iOS 用 `no_notices`=暂无通知，另两端是「暂无小组通知」）。
- **属 HOS/Android 独有交互**：`group_v1_*`、`group_ui_*`、`group_parity_*`、`group_members_*`、`group_prd_*` 前缀共 60+ 条，多为页面结构差异。

## 3. iOS 47 语言结构检查（全绿项）

| 检查 | 结果 |
| --- | --- |
| 47 目录键集合与英文 | **全等**，0 缺 0 多 |
| 格式参数（类型 + 位置） | 0 处不一致（`shot_training_share` 等 3 条日文改为显式 positional，属正确写法） |
| 换行数量 | 仅 zh-Hans/zh-Hant 2 条非小组文案不同（`schedule_reminder_help_message`、`scoreboard_official_break_help_message`，中文用换行分条而非 `\n\n`） |
| `Localizable.stringsdict` | 30 个复数键 × 47 目录齐全，复数类别与语言规则一致 |
| `InfoPlist.strings` | 47 目录齐全，4 键全等 |
| 空白/空值 | 0 处空值；除 2 个允许句首空格的键外无异常首尾空格 |
| 南亚脚本误用 | 0 处（bn/pa/or 已无印地语回退，gu 无旁遮普语残留） |
| 跨语言串用 | ar/he/ru/el/uk 无其他脚本泄漏 |
| 中文标点泄漏到外语 | 0 处 |
| 模板占位符残留（`{name}`、`%s`） | 0 处 |
| 英文源值残留 | 44 外语目录共 25 个目录有 178 条与英文相同，全部落在 `shared_terms` 白名单（`Spam`、`Sport`、`Format`、`Beta`、`min`、`Score` 等），无未登记项 |

## 4. iOS 47 语言：发现的问题

### 4.1 结构性（P1）

**A. 54 条英文源文改写后，44 语言的译文未跟进（1227 行）**

英文 `Localizable.strings` 相对 HEAD 改了 54 条小组文案，其中 28 条是**语义变化**而非缩写/大小写。44 个外语目录的对应行**逐字节未变**，且审核目录被重新盖成 `reviewed` + 新源哈希，导致现有门禁无法发现。

语义漂移最明显的一组：

| 键 | 旧英文 | 新英文 | 外语现状（以 de/fr/ja 为例） |
| --- | --- | --- | --- |
| `group_archive_hint` | Archiving keeps all history and pauses group changes. You can restore it later. | Archive this group? Its content will be read-only. | 「归档会保留全部历史并暂停小组改动，之后可恢复」——**语义已变仍保留旧译文** |
| `group_open` | Anyone with the number can join | Join directly | 仍为「知道号码的人都能加入」 |
| `group_manual_result` | Add a past match | Add match result | 仍为「添加过去的比赛」 |
| `group_results` | Matches | Records | 仍为「比赛」（与 `group_matches` 区分消失） |
| `group_leader` | Leader | Owner | 仍为「组长/Leader」 |
| `group_void_result` | Void result | Void | 可接受 |
| `group_batch_names_hint` | One name per line, 1–24 characters per name. | One name per line | 仍带长度限制，与校验放宽后矛盾 |

**B. 规范键 `group_copy_activity_multi_match_hint` / `_single_match_hint` 在 44 个外语目录仍是旧短句**

英文 / 简体 / 繁体 / Android / HOS 都是完整的新句（含「单打选 2 人、双打选 4 人」），44 个外语目录只有旧的一句「报名选手可被安排到多场比赛」。实测 **44/44 全部缺少 2/4 人规则**，日文/韩文尤其短（长度仅为英文 15%/16%）。同键的 `group_multi_match_hint`（iOS 旧键）存在同样问题。

这不是「翻译腔」问题，是**规则说明缺失**：外语用户看不到排阵人数的硬性要求。

### 4.2 翻译质量（P2）

**C. `group_save` = 「确认」，与三处调用点语义不匹配**

`group_save` 英文为 `Confirm`，中文「确认」，ja「確認」，de「Bestätigen」。但 iOS 三个调用点分别传 fallback `Done`（规则弹窗关闭）、`Save`（赛果修正提交）、`Confirm`（权限操作），另两端同一位置用「保存」。用户在「修正赛果」页看到「确认」而不是「保存」，会误解为二次确认。

**D. zh-Hant 混用大陆用词（51 个键、53 处）**

`保存`13 / `設置`15 / `登錄`8 / `加載`3 / `支持`4 / `搜索`2 / `緩存`1 / `信息`1 / `文件`1 / `界面`1 / `自定義`4。
对照：Android `zh-rTW` 同类词 0 处（`儲存`66、`設定`27、`登入`71、`載入`15、`搜尋`9），HOS `zh_TW` 也有 17 处 `保存`。iOS 是三者中最不一致的，典型如 `loading`=「加載中」而 Android 是「載入中…」、`open_settings`=「去設置」、`group_cached`=「當前顯示緩存資料」。

**E. 语音播报：7 条语义在 46 套语言里全部是英文**

| 键 | 可达性 | 影响 |
| --- | --- | --- |
| `squash.game.to` | 壁球 setEnd（en/fr/es/pt） | 法语、西语、葡语壁球局末播英文 |
| `squash.match.to` | 壁球 matchEnd | 同上 |
| `squash.leads` | 壁球 setEnd | 同上 |
| `squash.game.unit` / `squash.games.unit` | 同上（`game` / `games`） | 同上 |
| `squash.games.all` | 同上 | 同上 |
| `padel.advantage.number` | 仅英文板网球可达 | 不影响外语 |

另外 3 条**可达且未翻译**的独立项：

- `tennis.deciding.point` = `Deciding point, receiver's choice`：zh-Hans、zh-Hant、ko 走 `reviewedNativeTennisPoint` 的 no-ad 分支时直接播英文。
- `squash.game.ball` / `squash.match.ball`：pt-BR / pt-PT 仍为 `Game ball` / `Match ball`（法、西已译）。
- `pingpong.score.all`：ko 仍为 `%1$@ all`。

`softtennis.number.0…6`（zero…six）在除日语外全部是英文，但软网分支只对 en/ja 开启，属不可达，**不计为缺陷**。

### 4.3 其他（P3）

- **F. `group_view_schedule` 键不存在**：`GroupActivityViews.swift:360` 在非管理员分支调用 `groupText("view_schedule", "View matches")`，47 个目录均无此键（资源里只有 `group_preview_schedule`=检查排期，语义不同）。当前回落英文 `View matches`，**外语用户会看到英文**。HOS 对应 `group_activity_lineup_view`=查看场次。
- **G. 训练/请假通知类型标签缺失**：`GroupNotification.label`（`GroupExtendedModels.swift:345`）按 `notice_ + kind` 取键，但 `training_published` / `training_changed` / `training_cancelled` / `leave_changed` 四类在 iOS 资源里都没有键，落到 `fallbackLabel` 的英文与兜底 `Notification`。Android/HOS 分别用 `group_audit_training_change_*` 映射。后端 `notices.ts` 的 `GroupNoticeKind` 只覆盖 12 类，训练类走推送通道，因此该路径影响的是推送落地页，不是站内列表。
- **H. `group_error_*` 映射：iOS 105 个码 / 53 个目标键，服务端 84 个业务码覆盖 79 个**。缺的 5 个全部是推送安装类（`INSTALLATION_FORBIDDEN`、`INVALID_INSTALLATION_KEY`、`PUSH_APP_UNCONFIGURED`、`PUSH_MESSAGE_UNAVAILABLE`、`STALE_PUSH_BINDING`），Android/HOS 同样未映射，属三端一致的已知边界。
- **I. 工具链红灯**：`group_copy_20261017.py --check` 因阿拉伯语 2 条 `overrides`（`group_confirm_authority_message`、`group_abandon_game_message`）不是 NFC 而失败；`group_audit_copy_20261020.py --check` 因同一键「catalog differs」而失败；`test_group_localization.py` 7 项中 1 项失败（443 条 group catalog blocker）、`test_localize.py` 26 项中 5 项失败。发版资源本身是 NFC 正确的（已逐值验证），是**校验脚本与数据文件不同步**，不是线上文案错误；但不修则门禁一直红。

## 5. 非小组文案的对应性（抽查）

取中文三端同名（555 个键）对比：**375 条完全一致（67.6%）**，180 条不同，其中 37 条是三方三样。主要集中区：

| 区段 | 典型差异 |
| --- | --- |
| `cast_*`（投屏，9 条） | iOS AirPlay 专有措辞、步骤顺序与另两端不同（平台合理，但标题「投屏怎么用」vs「如何使用投屏」可统一） |
| `countdown_compact_*` | **iOS zh-Hans/zh-Hant 为 `%d h %d min` / `%d min %d s`，另两端为「%d小时%d分」「%d分%d秒」** —— 中文界面出现英文单位，真实缺陷 |
| `scoreboard_usage_hint_*`（9 条） | iOS 与另两端操作描述完全不同（滑动手势、撤销入口） |
| `sync_*`（23 条） | 「短码」vs「同步码」；`sync_code_expired`/`_exhausted` HOS 用「加入码」 |
| `common_*`（19 条） | 「选手」vs「球员」、「添加」vs「添加名称」、「无搜索结果」vs「没有找到匹配的名称」 |
| `schedule_*`（11 条） | 「球局」vs「预约」 |
| `feedback_*`（8 条） | 引导文案整段不同 |

这些多为**同一功能三套写法**，不是翻译错误，但属于「大部分需要一一对应」范围内的偏离，建议纳入下一轮统一。

## 6. 判定为合理例外、不建议强行对齐的项

1. 投屏实现路径：iOS `AirPlay`、Android `Miracast`、HOS 无线投屏；文案必须按平台写。
2. 系统设置入口名称：iOS「设置」、Android「系统设置」、HOS「设置」。
3. 商店评分邀请：Android 专属渠道文案（`rate_invite_group_*` 13 条 `@string/` 别名，仅在 `rate_invite_grouping.xml` 中）。
4. 语言覆盖：Android 3 目录、HOS 实际 3 语言是当前产品决策，不按 iOS 47 语言要求补齐。
5. 乌尔都语无 `ScoreVoice.strings`：`SportsVoiceLanguage` 支持列表中共 46 项，按设计排除 ur。
6. 计时单位 `min`/`h`/`s` 在 de/nl/sv/da/nb/fr/it/es/pt/ca 等语言中与英文相同：这些缩写是当地通行写法。
7. `zh-Hans == zh-Hant` 的 284 条、小组内 62 条：字形本身相同（如「刷新」「通知」），不是漏转。

## 7. 建议修复顺序

| 优先级 | 事项 | 归属 |
| --- | --- | --- |
| P1 | 54 条英文源改动重译 44 语言（1227 行），并让 `group_copy_*` 脚本恢复 `--check` 绿 | iOS 多语言 |
| P1 | `group_copy_activity_multi_match_hint` / `_single_match_hint` + `group_multi_match_hint` 补齐 2/4 人规则，44 语言 | iOS 多语言 |
| P1 | 新增 `group_view_schedule`（47 语言）或改用 `group_activity_lineup` 别名 | iOS 代码 |
| P1 | `group_save` 拆成 `save` / `done` / `confirm`，或按调用点改用 `save` | iOS 代码 + 资源 |
| P2 | `group_error_session_completed` 补后半句；`group_training_date` 恢复「训练」限定 | iOS 资源 |
| P2 | HOS `group_activity_status_scheduled` 改「待开始」，与 `schedule_time_status_scheduled` 一致 | HOS |
| P2 | zh-Hant 51 个键的大陆用词按 Android `zh-rTW` 口径统一 | iOS 多语言 |
| P2 | 语音：壁球 setEnd/matchEnd 三端模板与 `tennis.deciding.point` 补齐 zh/ko/pt；修 `group_copy_20261017.json` 2 条 NFC | iOS 语音 + 工具链 |
| P2 | `countdown_compact_*` 中文恢复「小时/分/秒」 | iOS 非小组 |
| P3 | 补 `notice_training_*` / `notice_leave_changed` 四类标签 | iOS 资源 |
| P3 | 三端统一 `选手/球员`、`球局/预约`、`短码/同步码` 等术语表 | 三端 |

## 8. 验证方式与边界

- 资源解析：`Localizable.strings` 用正则逐行解析（47 目录 × 2101 键），Android 用 `ElementTree` 解析 `values*`（含 `item type="string"` 别名），HOS 用 `json` 解析 `string.json`。
- 对比口径：占位符先归一化为 `{}`（支持 `%@` / `%1$s` / `%1$d` / `{name}`），再去重空白、NFC 归一。
- 调用点统计：`groupText("…")` / `NSLocalizedString("group_…")` 静态字面量 + 已枚举的 21 个动态键（`filter_*` 2、`notice_*` 12、`report_*` 7）。
- 已运行门禁：`sync_group_copy.py --check` 通过（198 键、0 文件需更新）；`test_voice_localization.py` 9/9 通过；`test_group_localization.py` 6/7、`test_localize.py` 21/26。
- 未做：47 语言逐页截图、VoiceOver/AVSpeech 实听、Android/HarmonyOS 真机视觉验收、独立母语审校。

## 9. 可维护产物

- `docs/groups/group-copy-mapping-2026-10-21.csv`：198 条契约键 × (中文文案, iOS 键, Android 键, HOS 键, 三端是否在用)，供后续逐条判定「一一对应」范围。
