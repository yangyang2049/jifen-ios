# 本地化翻译复查 · 2026-09-26

修复状态：下列 14 组问题已修复，审核目录与正式资源已同步。本文保留初次检查的原文和证据供追溯，当前验证结果见“修复记录”。

## 初次检查范围和验证

- 检查当前工作区昨天新增的日语、韩语、德语、法语（法国、加拿大）、西班牙语（西班牙、墨西哥）、葡萄牙语（巴西、葡萄牙）、俄语、阿拉伯语，共 11 套资源。多数新增资源尚未提交，本报告对应当前工作区，而非仅对应 HEAD。
- 全量结构检查：16,447 条目录记录；缺键、重复键、源文案哈希过期、占位符、换行、复数类别及审核状态均通过。逐项核对正式 `.strings` / `.stringsdict` 与目录最终值，一致。
- `plutil -lint`：33 个资源文件全部通过。
- `python3 -m unittest discover -s scripts/localization -p 'test_localize.py'`：12 项测试通过。
- 语义重点复查：计分/计时、赛制、牌类、记录修正、预约、数量单复数、会员协议组合及系统权限说明；以中文含义、英文源文案和实际调用代码交叉核对。语义复查不等于全部 16,447 条均完成母语级逐句验收。
- 核对昨天的截图报告，并查看阿拉伯语会员页旧截图；本轮未重跑模拟器 UI 矩阵、未执行完整 Xcode 构建。
- 结构校验明细：JSON（已于2026-10-04清理）。

## 初次检查确认的问题（现已修复）

以下按问题类型合并为 14 组；同一组可能涉及多个语言及键。P2 为应修复的语义/可读性问题，P3 为术语或表达质量问题。

### 1. P2：会员协议文字直接粘连，涉及除日语外的本次重点语言

位置：各语言 `Localizable.strings` 的 `vip_agreement_plain_prefix`（1406 行）、`vip_agreement_link_separator`（1407 行）及 `vip_agreement_link_middle_separator`（1415 行）。

[`MembershipView.swift:689`](../jifen/Features/Membership/MembershipView.swift#L689) 将前缀、连接词和链接直接相加，没有补空格。例如当前法语最终拼接为：

`J’ai lu et j’accepte lesContrat d'utilisationetConditions d’abonnement`

俄语为 `...принимаюПользовательское соглашениеиСоглашение...`；阿拉伯语为 `...علىاتفاقية المستخدمواتفاقية العضوية`。后者已在昨天的会员页截图中看到单词粘连。

建议：按语言保留必要空格，或用完整句子的可点击范围组装文本；并检查已登录/未登录、订阅/终身四种链接组合。法语 `les`、西语 `el`、葡语 `o` 也不应固定后直接接所有不同性数的协议名称，可改为冒号引出链接列表。

根因之一：[`localize.py:1140`](../scripts/localization/localize.py#L1140) 一律禁止首尾空白，但这些片段的空白承担语法作用。修复文案时需一起调整校验，不能简单再次 trim。

### 2. P2：葡萄牙语（葡萄牙）“赛点”变成“碰面地点”

[`pt-PT/Localizable.strings:1159`](../jifen/Resources/pt-PT.lproj/Localizable.strings#L1159)：`key_point_match = Ponto de encontro`。

`Ponto de encontro` 表示集合/碰面地点，不是体育赛点。建议采用 `Match point`（巴西葡语版本已使用），并与局点、盘点统一术语风格。

### 3. P2：日语把“局分／盘分”字段误解为“设置得分”动作

[`ja/Localizable.strings:1497`](../jifen/Resources/ja.lproj/Localizable.strings#L1497)：`record_correction_set_score = 得点を設定`。

实际用于 [`ScoreboardRecordDetailPage.swift:364`](../jifen/Features/Records/ScoreboardRecordDetailPage.swift#L364) 的局分/盘分输入分区标题。英文 `Set Score` 中的 Set 是名词。建议 `ゲーム数／セット数`，并按该表单实际表示的赢局/赢盘数确定最终名称。

### 4. P2：韩语把第二张红牌误译为第二次罚出场

[`ko/Localizable.strings:1181`](../jifen/Resources/ko.lproj/Localizable.strings#L1181)：`second_red_penalty = 두 번째 퇴장 · 상대 +2`。

`퇴장` 是退场/罚出场。此处是乒乓球罚分提示，原文为“第二张红牌，对手 +2”，不是退场提示。建议 `두 번째 레드 카드 · 상대 +2점`。实际调用：`RallyScoreboardView.swift:1951`。

### 5. P2：俄语积分表“赛”和“负”同名，“平”也未正确本地化

[`ru/Localizable.strings:366`](../jifen/Resources/ru.lproj/Localizable.strings#L366)：`points_table_played = П`；368 行 `points_table_draw = Д`；369 行 `points_table_loss = П`。

这些缩写在 `PointsTableView.swift:320` 起的同一行表头并排显示，用户无法区分两个 `П`。建议采用清楚的俄语表头缩写 `И / В / Н / П`（场次/胜/平/负），并为缩写保留完整无障碍名称。

### 6. P2：法语、葡萄牙语、俄语“打满局数”单数文案仍含复数限定词

影响 `record_format_sets_play_all` 和 `record_format_sets_play_all_tennis` 的 `.one` 分支：

| 语言 | 实际 n=1 结果 | 问题 |
| --- | --- | --- |
| 法语 fr | `Jouer les 1 set` | `les` 与单数不一致 |
| 加拿大法语 | 普通赛制 `Jouer les 1 set` | 同上；网球虽为 `Jouer le 1 set`，表达仍不自然 |
| 巴西/葡萄牙葡语 | `Jogar todos os 1 set` | `todos os` 与单数不一致 |
| 俄语 | `Играть все 1 партию` / `Играть все 1 сет` | `все` 与单数不一致 |

文件：上述语言 `Localizable.stringsdict` 的 59/77 行附近；俄语为 65/85 行附近。`ScoreboardRecordDetailPage.swift:983,1023` 确实使用复数格式调用，且赛制允许 1 局。

建议采用不依赖限定词性数的表达，如法语 `Nombre de sets à jouer : %d`、葡语 `Total de sets: %d`，俄语 `Количество партий: %d` / `Количество сетов: %d`；或逐类别正确处理。俄语 `.one` 还涵盖 21、31 等，不能只把 `все` 改成一个固定单数词就结束。

### 7. P2：掼蛋“双上”被翻译成“翻倍”

`guandan_pass_a_double_up`（各语言 175 行）：德语 `Verdoppeln (+3)`、加拿大法语 `Doublez (+3)`、俄语 `Удвоение (+3)` 都表达翻倍。

原文是过 A 的“双上”条件，不是得分乘二。`GuandanScoreboardView.swift:237` 中对应 `.doubleUp`，判断 `step == 3`。建议按“两位队友包揽前两名”的条件描述；例如德语 `Beide Spieler auf Platz 1 und 2 (+3)`，法语 `Les deux partenaires finissent en tête (+3)`，俄语 `Первое и второе места у команды (+3)`，再检查按钮宽度。

### 8. P2：西班牙语把 set 当作“设定的”，丢失盘分含义

[`es-ES/Localizable.strings:859`](../jifen/Resources/es-ES.lproj/Localizable.strings#L859) 和墨西哥版本相同：

`scoreboard_game_score_overflow = Se alcanzó el límite de puntuación establecido`

这变成“达到设定的得分上限”，没有表达 `Set score limit reached` 的盘分上限，与局分提示无法区分。建议 `Se alcanzó el límite del marcador de sets`。阿拉伯语同键也丢失了组/盘层级（只说“达到得分上限”），应同步补回。

### 9. P2：魔方计时的触屏要求在部分语言中含糊或偏离原意

`cube_timer_no_touchscreen_hint`（136 行）：中文是“没有触摸屏无法工作”；法语两版本却写成“不需要专用触摸屏”（`Aucun écran tactile dédié requis`），加入了原文没有的“专用设备”概念。德语、葡萄牙葡语、阿拉伯语则只说“没有触摸屏可用”，未明确没有触屏就不能使用。

英文源文本 `No touchscreen available, works on phones and tablets` 本身缺少限制关系，是共同根因。`CubeTimerView.swift:92` 的中文 fallback 仍明确要求触屏。

建议先澄清英文为 `A touchscreen is required. Use a phone or tablet.`，再更新受影响的翻译、源哈希和审核状态。法语建议 `Un écran tactile est nécessaire. Utilisez un téléphone ou une tablette.`。

### 10. P2：日语把 30 分钟内开赛写成“近日开始”

[`ja/Localizable.strings:638`](../jifen/Resources/ja.lproj/Localizable.strings#L638)：`schedule_time_status_starting_soon = 近日開始予定`。

`ScheduleTimeStatusHelper.swift:125` 表明这是距开赛 1–30 分钟时的状态；“近日”偏向未来几天。建议 `まもなく開始`。

### 11. P2：法语把日期筛选误写成时长筛选

[`fr/Localizable.strings:1114`](../jifen/Resources/fr.lproj/Localizable.strings#L1114)：`time_filter = Durée`。

`RecordsTab.swift:32–38,178` 下实际是“今天/本周/本月/全部”，不是比赛持续时长。建议 `Période`，加拿大法语已经使用这个译法。

### 12. P3：德语篮球投篮训练使用了射门词汇

[`de/Localizable.strings:148`](../jifen/Resources/de.lproj/Localizable.strings#L148) 的 `game_basketball_training` 和 149 行 `shot_training_setup_title` 均为 `Schusstraining`，而同页分享文案 `shot_training_share` 已使用 `Wurftraining`。

建议统一为 `Wurftraining`，使篮球投篮与射门/射击含义区分，并消除同一功能名称不一致。

### 13. P3：阿拉伯语倒计时分钟快捷键单位不一致

[`ar/Localizable.strings:948`](../jifen/Resources/ar.lproj/Localizable.strings#L948) 起：1/3/5/10 分钟显示为 `1 م`、`3 م` 等；同文件 `minute`、`timer_custom_minutes`、`countdown_compact_m` 则使用 `د`。

建议统一分钟为 `د` 或完整分钟词；避免 `م` 与其他含义混淆，并复查 RTL 下数字和单位的顺序。

### 14. P2：九球设置无障碍文案把事件名称占位符当成点数

`nine_ball_decrease_points` / `nine_ball_increase_points`（924/926 行）。西班牙语如 `Incrementar %@ puntos`，加拿大法语 `Ajouter %@ points`，阿拉伯语 `إضافة %@ نقطة`，句法均把 `%@` 放到了数量位置。

实际 `NineBallSetupDialogView.swift:168,196` 传入的是 `title`（例如“大金”事件名称），不是点数，会读成“增加 大金 个点”。英文 `Increase %@ points` 也含糊。

建议英文改成 `Increase the point value for %@`，其他语言表达“提高 %@ 的分值”。例如西语 `Aumentar el valor en puntos de %@`、加拿大法语 `Augmenter la valeur en points de %@`、阿拉伯语 `زيادة قيمة النقاط لـ %@`。减号对应使用降低分值表达。

## 初次检查时的 UI 验证缺口

- 昨天的 `build/localization/visual-audit/本地化UI截图审查.md` 明确记录首页截断、协议粘连及 RTL 列表箭头问题，并非全通过。
- `scripts/run_localization_visual_audit.sh` 当前默认矩阵及 `case` 分发都没有 `fr`、`fr-CA`、`ru`；仅设环境变量加入这些语言会直接报无 XCTest 入口。法语和俄语的窄屏及 iPad 显示仍需要补测试入口后验证。
- 上述布局问题与本报告语义问题分开处理；旧截图不能证明当前工作区 UI 全部正常。
- 其他候选润色项，例如多语言斯诺克罚分标签仍为英文颜色缩写 `R/Y/G/Br`、日语行棋日志 `%@ が移動しました`，可在下一轮术语统一时处理，未计入以上 14 组。

## 修复顺序建议

先修协议拼接、赛点/红牌/局分误译和俄语表头，再修复数及源文案歧义，最后统一术语并补法语/俄语 UI 覆盖。修改时通过审核目录更新最终值并重新生成资源，避免只改 `.strings` 导致下次生成覆盖修复。

## 修复记录

- 1：修复协议前缀、连接词、逗号的边界空格；使用冒号避免协议名称性数不匹配。目录写入保留这三个片段的人工审核值，校验仅允许每侧一个普通空格；普通文案仍拒绝异常边界空白。
- 2–5、7–14：修复对应误译、表头、时间范围、单位和九球事件分值描述；日语行棋日志顺便改为 `%@が着手しました`。
- 6：法语、葡语和俄语的普通资源及所有复数类别一起更新，避免 1、21 等数量再次出现错误限定词。
- 三条英文源文案已澄清：魔方需要触屏，以及九球增加/减少的是某个事件的分值。已对全部 14 个新增且已晋级语言重新核对这三条并更新源哈希；未晋级语言仍受源哈希审核门禁约束，没有自动批准旧译文。
- 同类协议空格问题也修复到已晋级的希伯来语、乌尔都语、乌克兰语，保持共享流程一致。
- 共更新 143 条审核记录及 3 条英文源文案；逐条前后对照（已于2026-10-04清理）。
- 已补法国法语、加拿大法语、俄语的 XCTest 入口、地区配置、运行脚本和报告生成器；新截图使用独立输出目录，保留昨日证据。
- 修改前备份：ZIP（已于2026-10-04清理）。保留修改前已有的其他业务代码和项目配置改动；会员页另补协议文字按完整高度展开，以及权益标题使用自身宽度、两侧分隔线让出空间。方案卡增加测试标识以验证订阅三项协议。

验证：

- Python 本地化测试 14/14 通过，含新增的目录保存→资源生成→协议四种组合测试，以及普通文案/异常空白仍被拒绝的回归测试。
- 所有 17 套已打包语言的 51 个资源文件 `plutil` 通过；14 个新增已晋级语言的完整目录校验通过，生成资源与目录逐字节一致。
- 清理后执行 iOS 模拟器 `xcodebuild clean test` 成功：`LocalizationIntegrityTests` 19/19、`ScoreboardRecordV4Tests` 64/64，共 83 项通过。
- Foundation 实际加载 `.stringsdict` 并按语言格式化：5 种地区语言 × 2 个局数键 × 1/2/5/21，共 40 个结果通过；输出（已于2026-10-04清理）。
- 残留扫描核对 143 个修改位置均为新值，旧错误值在对应键消失；最终结构报告（已于2026-10-04清理）。
- 编译并非零告警：告警涉及 actor/Sendable 隔离、旧 API、可选值转换和测试代码风格，所在源文件未由本轮修改。本轮未取得修改前的完整 clean 编译告警基线，不宣称已清除或逐项证明所有历史告警。
- 法语（法国/加拿大）、俄语、阿拉伯语：iPhone 17e 与 iPad Pro 11-inch 的 8 组完整截图流程通过。会员页布局调整后，再次编译并重跑 83 项单元测试及两台设备的会员页定向测试，全部通过；定向测试覆盖四种地区语言的终身/订阅两种协议组合。
- 最新截图共 80 张；重点人工查看会员页：俄语标题完整、不再在单词中间断行；法语/俄语/阿拉伯语协议空格正常，三条链接完整显示。最终证据：截图报告（已于2026-10-04清理）、iPhone 最终日志（已于2026-10-04清理）、iPad 最终日志（已于2026-10-04清理）。
- 本轮 UI 人工复查重点是修改涉及的会员页，不把自动截图成功等同于所有页面验收。此前独立记录的首页截断、RTL 列表箭头及未纳入本轮的斯诺克颜色缩写，仍保留为后续布局/术语事项；实机未测。
