# G3 完整逐条深审 · 2026-09-30

范围：cs 捷克语、sk 斯洛伐克语、sl 斯洛文尼亚语、hr 克罗地亚语。仅修改各自 catalog，尚未 promote；由根代理统一处理包内资源、截图入口和视觉验证。

每套所有 Localizable、InfoPlist、Plural 行均逐条读取 EN 源文与候选值并决定保留或修订。按源身份对齐四套、每批100行；斯洛文尼亚语独有28条 two 单独出包逐条读审。不是扫描通过后整套批准。决策均经 apply-review；自有目录保存16批源文/候选快照、分批决策、sl two 独立决策、FAQ最终源变更证据、逐行差异和身份覆盖统计。

| 语言 | 完整覆盖/总行 | 改写最终值 | 当前 reviewed | 新鲜 hash | blockers |
|---|---:|---:|---:|---:|---:|
| cs | 1555/1555 | 538 | 1555 | 1555 | 0 |
| sk | 1555/1555 | 545 | 1555 | 1555 | 0 |
| sl | 1555/1555 | 510 | 1555 | 1555 | 0 |
| hr | 1527/1527 | 481 | 1527 | 1527 | 0 |

## 语义决策

- 体育 match 全部改为 zápas / zápas / tekma / utakmica；home、预约、恢复、记录、投屏各族不再保留“匹配”义。棋类 Go 四套均保留 Go，player 不用播放器名词；away 使用客队。
- 篮球投篮 miss 是未命中，made 是命中，free 是自由选分，非女士、制造或免费。分享句明确“命中数/尝试数”，帮助文案所引按钮与最终标签一致。
- 常规/网球局采用 Set / Set / Niz / Set；网球子局 gemy / gemy / igre / gemovi。record_recap_set_format 和 scoreboard_set_end_format 与每局分数同步；网球抢七六键重新读当前源文，统一 tiebreak to7/to10。
- 台球 frame/rack 使用借词 frame（cs/sk）或 igra / partija（sl/hr），不译成图片框/支架；pot 是落袋；break score 是连续得分而非休息。Dealer 为发牌者，非商贩。
- no-ad 表示无占先；draw 为平局；period/round、足球上下半场/伤停补时/加时与工作加班语义分开。
- setup_suffix 保留冒号连接；会员直接拼接的3个片段保留必要空格，前缀采用冒号避免标题格变化。所有新行经原有边界空白门禁。
- FAQ5 最终重审：分享端登录生成6位码，显示端登录输入分享端码；AirPlay、系统控制中心与屏幕镜像步骤替代旧Miracast，未承诺app自行搜电视。FAQ10明确仅常用名称和地点云同步，比赛/计时记录与未完赛留本机，没有云备份/换机恢复。FAQ11与NSCameraUsageDescription明确可信登录二维码和头像拍照，移除旧“仅QR/全部本地”承诺。
- 复数 one/few/many/other 与同名Localizable对拉：cs/sk区分1、2–4、分数、5以上；sl另审two双数（tekmi、igralca、niza、igri等）；hr one/few/other。天数字段用相应介词格；“人数上限”按up-to格处理。
- 帅/将为象棋棋子符号，中文公司法定名称为源文的有意保留项；没有盲目清除。source-equality 警告均逐项复核，剩余项是游戏名/单位/字母/体育缩写/可接受借词；hr长preset警告已缩短。

## 验证与交接

四套 validate --require-reviewed 全部 blockers=0。覆盖集严格等于当前source身份集；每条当前status=reviewed、source_hash新鲜；占位符签名、换行数、NFC、首尾空白、断句粘连、双空格、受保护词均通过原门禁。无第三方翻译调用。

证据目录：g3（已于2026-10-04清理），统计：summary.json（已于2026-10-04清理）。原稿备份 *-before.jsonl 可回滚。尚未做任何晋级或设备截图，视觉通过不由文本校验代证。

总负责人收尾：本组已统一晋级并纳入 47 套包内资源，44 套审核目录的新鲜 hash/严格门禁均通过，目录与资源逐字节一致。本组报告上文记录分组交接时点；返修后的统一备份比较口径、构建、回归和视觉结果以[主报告](localization-deep-review-2026-09-30.md)为准。
