# iOS 3.4 清单二次复核与修复

日期：2026-10-25。基线：`9ff0e922`，另有工作区未提交修改。

本轮重新读取首轮改过的 19 个清单条目，以及第 1、3 节的实现和现有回归。没有调用 subagent；本报告是新一轮源码复核与自动验证，不代表双人真机验收。

## 复核结论与处理

路径以仓库根目录为起点，行号对应本轮最终工作区。

| 清单 | 结论与处理 | 源码依据 |
| --- | --- | --- |
| 1.7 | 确认 v3 民间关闭让杆时 UI 过滤、reducer 拒绝；保留 v2 会话的兼容行为。 | `Packages/JifenCore/Sources/ScoreCore/s2/SpecializedScoreboards.swift:255`；`NineBallChaseTransfers.swift:56` |
| 1.14 | 确认新开局为 v3、沿用已有分值，不重置用户原配置；旧版标签只看规则版本。 | `jifen/Features/Scoreboard/Sports/Billiards/NineBallChaseScoreboardView.swift:1626`；`jifen/Features/Records/ScoreboardRecord.swift:509` |
| 1.16 | 确认赛事 4 项、民间 6／5 项；补清“关闭让杆后第 5 格为犯规”。换边不改变开球人的逻辑索引。 | `jifen/Features/Display/ScoreboardExternalDisplayView.swift:1192`、`:1240`、`:3436`；`NineBallChaseScoreboardView.swift:8` |
| 1.19 | 确认赛事拒绝负数且原子不改状态；民间 v2／v3 总分不为 0 仅提示后保存。 | `NineBallChaseScoreboardView.swift:1306`；`SpecializedScoreboards.swift:431` |
| 1.20 | **修复实际缺口**：旧保护只验证规则版本、局号、开球人，让杆不改变这些值，同一确认回调可能排入两次。为每次弹窗分配独立 ID，确认时同步消费当前弹窗，再交给队列；旧弹窗回调不能消费新弹窗。保留独立犯规／让杆连续记录的现有行为。 | `NineBallChaseScoreboardView.swift:37`、`:62`、`:1109`；`jifenTests/ScoreboardCatalogTests.swift:1060`、`:1121` |
| 2.8 | 确认普通名称只改显示名，“我”才携带身份；最终筛掉名称不匹配的选择。无需改变身份规则。 | `jifen/Features/Home/Components/SportsSetupCommonNameViews.swift:52`；`SportsSetupParticipantSection.swift:60`；`jifen/Features/Identity/ParticipantSetupIdentity.swift:6` |
| 2.9 | 进一步纠正：个人页除了没有搜索框，也没有记录类型选择器，只筛时间与项目；根页才有三种筛选及搜索。 | `jifen/Features/Records/RecordsTab.swift:84`、`:335`、`:413` |
| 2.11 | 确认队名制与训练结果不参与本人身份筛选；毽球 team 格式同样排除。 | `jifen/Features/Scoreboard/Shared/Types.swift:472`；`jifen/Features/Identity/PersonalRecordAdapter.swift:85` |
| 3.1 | 确认同步入口条件为冲突、lastError、受阻记录任一；有记录冲突时优先显示冲突标签。 | `jifen/Features/Records/RecordsTab.swift:119` |
| 3.3 | 确认“使用云端版本”仍在；保留本机内容时换新 recordKey，不复活墓碑。原生文件作为离线备份保留，不等于继续在列表展示。补清 3.2／3.3 要先制造同版本离线修改，否则顺序同步或无本机修改时不会产生冲突。 | `jifen/Features/Identity/ParticipantIdentityViews.swift:245`；`PersonalRecordsCloudSync.swift:284` |
| 3.9 | 进一步纠正：阈值针对编码后的 mutation 加 16 字节；批量 413 先缩批，单条 413 才隔离，拒绝码不总是 RECORD_TOO_LARGE。确认受阻条目计入待同步总数，没有独立受阻计数行。 | `PersonalRecordsCloudSync.swift:245`、`:711`、`:743`、`:783`、`:819`；`ParticipantIdentityViews.swift:235` |
| 5.2 | 确认只转换 5 个名字字段；进一步明确混合姓名只转汉字，英文／数字片段保留。 | `jifen/Core/Managers/NameTransliteration.swift:39`、`:84` |
| 5.6 | **纠正错误预期**：显式播报语言偏好在英文界面仍优先。改为“先选中文，再切英文界面”验证，避免同为英文而无法区分偏好与默认。 | `jifen/Core/Managers/SportsVoiceSupport.swift:16`、`:27`；`jifen/Features/Home/Components/SportsSetupMatchFeatures.swift:82`；`jifen/Features/Scoreboard/Shared/MenuDialog.swift:263` |
| 6.2 | 确认多码优先选择业务码；没有业务码时回退第一个码交给业务层；无二维码才报未识别。 | `jifen/Features/Scan/QRScanSheet.swift:125` |
| 6.5 | 确认失败后暂停、屏蔽原码且要手动重试；补清 expiresAt／apiBaseUrl 来自 JSON，伪域名网页 URL 是无效码，HTTP 错误不能直接套用本地校验文案。 | `jifen/Features/Account/QRLoginApprovalView.swift:12`、`:44`、`:262`、`:299` |
| 7.4 | 确认 group: 云端赛果不可编辑，筛选／搜索变化会重算选择集，删除前再次校验。 | `jifen/Features/Records/RecordsTab.swift:174`、`:804`、`:832`、`:1141` |
| 8.3 | 记忆索引无该决策，但 10-24 交付文档和现有测试均明确全局一次。本轮用户明确选择“保留全局只弹一次”，因此保留代码、补齐条件与历史依据。 | [10-24 规则](../wechat-login-prompt-2026-10-24/README.md)；`jifen/Features/Account/WechatBindingUpgradePrompt.swift:3`；`jifenTests/WechatBindingTests.swift:401` |
| 9.3 | 确认终局白名单为改名、管理员修正、重开、结束；原清单漏写重开，修正后的规则成立。 | `Packages/JifenCore/Sources/ScoreCore/s4/GuandanScoreboard.swift:198` |
| 9.9 | 确认显式箭头方向优先；进一步补准确高度公式的 80–480pt 限制，不把“空间减 44pt”当作唯一约束。 | `jifen/Core/Components/CustomDialogs.swift:126` |
| 1.13（额外） | 补清终局边界：全场结束禁止撤销；三犯后仍在比赛中才能做一次撤销。 | `NineBallChaseScoreboardView.swift:17`、`:1460` |

## 验证

- 改动前 iOS 全量单测：891 项，890 通过、1 项 APNs 实网探针按配置跳过、0 失败。日志 `/tmp/jifen-qa-recheck-baseline-20261025.log`，结果包 `/tmp/jifen-qa-recheck-baseline-20261025.xcresult`。
- JifenCore：277 项 Swift Testing 与 8 项 XCTest 全通过。日志 `/tmp/jifen-qa-recheck-core-20261025.log`。
- 改动后 iOS 全量单测：892 项，891 通过、1 项 APNs 实网探针按配置跳过、0 失败。日志 `/tmp/jifen-qa-recheck-final-20261025.log`，结果包 `/tmp/jifen-qa-recheck-final-20261025.xcresult`。
- 模拟器冒烟：iPhone SE 3 与 iPad Pro 13 各 4 项，合计 8 次通过、0 失败。实际项为个人页筛选与 Tab 隐藏、九球横屏弹窗、长帮助气泡、首页扫码与取消返回。
- 首次 UI 结果包只发现个人页用例（两台设备各 1 次）；没有把未发现的 3 项记为通过。随后 `clean test` 重新编译并实际执行另外 3 项，两台设备均各通过 3 次。结果包 `/tmp/jifen-qa-recheck-ui-20261025.xcresult` 与 `/tmp/jifen-qa-recheck-ui-clean-20261025.xcresult`，同名 `.log` 为日志。
- 清理构建通过、0 编译错误；按来源与类别检查了既有 Swift 并发隔离、系统 API 弃用、测试捕获和未使用值等告警，变更的两个 Swift 文件无编译告警。增量基线有部分测试告警被缓存省略，未用告警总数声称零新增。结果计数来自 xcresult，摘要见 [summary.json](summary.json)。

自动回归覆盖既有的九球赛制、禁用让杆、三犯、提前结束、旧记录、显示统计、身份隔离、云端删除冲突、超大记录隔离、拒绝后重试、扫码解析、名字转写和微信提醒持久化。本轮新增用例验证让杆确认只入队一次，统计、撤销、持久化时间线均只一笔，且旧回调不能消费重新打开的确认框。

真机电视／AirPlay、多端真实账号、真实相机扫描、数字键盘与折叠设备没有在本轮执行，仍按手动清单验收。未执行生产账号操作、提审或发布。
