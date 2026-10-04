# 本地化机器初稿校验 · 30 套 · 2026-09-29

## 2026-09-30：G2–G7 全部深审并晋级

原剩余 27 套已完成全部 40,669 行实际读审，按本轮备份口径修正 11,396 条有效译文；全部 hash 新鲜、0 blockers，已晋级到应用。当前包内 47 套语言；三个 FAQ 源文也按实际 iOS 行为校正。最终构建和 511 项应用单测、23 项流水线测试通过；两设备 594 张代表页最终截图已实际复核。详见[最新交付报告](localization-deep-review-2026-09-30.md)。下文 2026-09-29 的队列与阶段数据保留为历史快照。

## 2026-09-30：U-1 / U-2 / U-3 收尾

以下更新覆盖本文后面的历史“待拍板”状态：

- **U-1 设置功能卡片**：按实际等分宽度测量完整标签，以最长标签决定整行卡片高度；保留最低 74pt，取消两行截断，德语/意大利语/荷兰语长文案完整换行。原先仅增加固定高度仍会让意大利语显示省略号，因此改为内容自适应。
- **U-2 记录时长**：`formatScoreboardDuration` 使用 Foundation `Duration.UnitsFormatStyle`，秒/分/小时单位、数字和分隔符按 locale 格式化，不再手拼 `h/m/s`。保留整秒显示，负数和非有限值显示零。计分记录和计时记录共用此修复；无需新增 20 套单位键。
- **U-3 局数术语**：英文 `record_recap_set_format` 与射箭 `scoreboard_set_end_format` 改为 `Set`，17 套已晋级语言同步采用“每局分数”对应的术语（例如 de `Satz`、ru `Партия`、uk `Партія`），中文继续使用“局”。网球“盘”、台球 frame、回合使用各自独立键。
- 对应翻译目录和包内资源已同步。另逐套复核六个网球抢七键：现有译文仍符合 `Tiebreak to 7/10`，更新过期的源文审核 hash，恢复完整校验。
- 验证：164 项应用单测、22 项 Python 本地化测试、17 套已晋级目录 `validate --require-reviewed`、繁体生成器 `--check` 均通过。iPhone SE（第三代）与 iPad Pro 11-inch (M5)，iOS 26.5，定向 UI 测试各 1 项通过，共 16 张截图；已人工复核长标签、记录时长和局标题。本轮截图（已于2026-10-04清理），入口为 `testCaptureSetupAndRecordLocalizationFixes`。

本节为 U-1/U-2/U-3 完成时的阶段记录；G2–G7 的后续深审、当前源文变更复核与晋级现已全部完成，见顶部最新交付报告。

范围：iOS 3.2.2 (52) 收口期，把剩余 30 套 `status=machine` 的机器初稿语言按语法家族+市场分 7 组推进。本轮完成 **G1（it/nl/sv）逐行深审并晋级进包**，以及 **30 套全量硬缺陷清底**；G2–G7 尚未深审，本文末尾给出可直接接续的排产队列。

口径沿用 [2026-09-26 复查](localization-review-2026-09-26.md)：P2 = 语义或可读性必须修，P3 = 术语/表达质量。四类反复出现的缺陷：拼接粘连、多义词误译、体育术语漂移、复数 `one` 里残留数量词。

## 结论摘要（机器可复证）

| 项 | 结果 |
| --- | --- |
| 无稿行撰写 | 30 套 × 42 行 = **1,260 串**，全部人工撰写并 `apply-review`（机翻都没有的同一组键） |
| Odia(or) 数据损坏 | 1,194 行句尾游离 `\|` 确定性剥离 + **112 行受损长文逐行重写**（引擎把多候选塞进同句并混拉丁字母） |
| 长英文残留 | hr 4、nb 1、sl 1、hu 10、ro 15 = **31 行**人工改写；30 套残留计数现为 0 |
| 新增确定性门禁 | `provider-artifact`（译文多出 `\|`）、`internal-multi-space`（CJK 词间双空格被复制进译文）、`punctuation-glue`（标点后漏空格，句子黏成一个词），[localize.py](../scripts/localization/localize.py)、[test_localize.py](../scripts/localization/test_localize.py) |
| Python 门禁 | `python3 scripts/localization/test_localize.py` → **22 tests OK**（每条新门禁都在修复前报红并逐条点名，属自我证伪）。第 22 条 `test_visual_audit_report_covers_every_promoted_locale` 见 6.8，写出来第一次跑就报出真缺口 uk |
| uk 首次入镜裁决 | 两条疑点落数据后：**"партія/Гра 混用"不成立**（与已晋级 ru 完全同形，根因在 en 源文 `set` vs `Game`，20 套一起继承）→ uk 零改动；**"时长 `21m 27s`"成立但属代码未本地化**（`Utils.swift:5` 硬编码拉丁单位，20 套全中，`duration_ms` 键有 20 套正确译文却无人调用）→ 报 U-2 待你拍板，见 6.9 |
| G1 晋级 | it / nl / sv 三套 `validate --require-reviewed` blockers=0 → `promote` 成功，包内完整 `.lproj` 由 17 套增至 **20 套** |
| G1 逐行量 | it 1,479 行（988 批准 / 491 改写）、nl 1,451（1,047 / 404）、sv 1,451（1,014 / 437） |
| 晋级后自查返修 | it 6、nl 7、sv 2、**he 3**（he 为已晋级语言，同类缺陷由新门禁扫出）= 18 行，见「晋级后自查」 |
| 二审全量返修 | nl 20、sv 26、it 7、**he 17** = **69 行**，全部有"同套已审行"或"≥6 套参照语共识"作依据，见第 6 节。含 3 个新缺陷类：幻影标签名、`controller` 假朋友、错义词（`סיר`=锅、`חיסול`=歼灭、`Buda`=佛陀） |
| 跨表同名键分裂 | nl 1、es-ES 2 = **3 行**（见 6.6）。同类启发式全仓命中 334 行，逐条核对只有这 3 行是真缺陷，**不做门禁**，留在人工预检第 3 条 |
| re-promote 落地 | 返修合计 **91 行**（18 + 69 + 3 + 截图审计 1）已随 it/nl/sv/he/es-ES 五套 re-promote 进包：15 个 `.lproj` 文件 `plutil -lint` 全 OK，bundle_delta.py（已于2026-10-04清理） 由 88 降到 **TOTAL 0**（包内字符串与 catalog 逐行一致） |
| Xcode 门禁 | 返修 re-promote **之后**复跑 `LocalizationIntegrityTests`：**19 tests / 0 failures**，跑两次 —— 14:35（`build/localization-integrity-promoted.log`，覆盖前 90 行）与 15:16（`build/localization-integrity-final91.log`，覆盖第 91 行 it 同意行落进 `it.lproj`（14:58）之后的最终包）。`timer_go` 字典与 `promotedLocales` 集合相等（20 套）。第一次跑是环境失败不是断言失败：`Timed out trying to boot simulator after waiting 60.00s`（当时他刚跑完营销截图，已有 2 台 Booted），先 `simctl boot` 再复跑才有效——**看到这条超时就先起设备，别当成回归** |
| 复证三件套（收口时点） | `python3 scripts/localization/test_localize.py` → **22 OK**；`python3 build/localization/g1/bundle_delta.py` → **TOTAL 0**（it/nl/sv/he/es-ES 逐行 0 diff）；`LocalizationIntegrityTests` → **19/0** |
| 剩余队列 | G2–G7 共 27 套、**39,230 行** machine 状态未深审 |
| 包体 | 单套 `.lproj` 约 120–156KB；G1 三套约 **+400KB**，30 套全晋制约 +4.2MB |

结构化数据：build/localization/review/metrics-30locales.json（已于2026-10-04清理）。备份：`build/localization/before-30locales-20260929-120948.zip`、`before-g1-apply-20260929-130751.zip`、`before-g1-rework-20260929-133327.zip`、`before-g1-rework3-20260929-135324.zip`（catalogs 未纳入 git，ZIP 是唯一回滚路径）。

## 分组

| 组 | 语言 | 状态 |
| --- | --- | --- |
| G1 | it, nl, sv | **已深审 + 已晋级**（含晋级后返修） |
| G2 | ca, pl, ro | **已深审 + 已晋级**（2026-09-30） |
| G3 | cs, sk, sl, hr | **已深审 + 已晋级**（2026-09-30） |
| G4 | da, nb, fi, hu, el | **已深审 + 已晋级**（2026-09-30） |
| G5 | hi, bn, mr, gu, pa | **已深审 + 已晋级**（2026-09-30） |
| G6 | ta, te, kn, ml, or | **已深审 + 已晋级**（2026-09-30） |
| G7 | tr, vi, th, id, ms | **已深审 + 已晋级**（2026-09-30） |

晋级是逐套原子交付：`promote --locale X` 要求该套 0 行 `status=machine`，通过后渲染 3 个 `.lproj` 文件、`plutil -lint`，并把 locale 追加进 `knownRegions`（[localize.py:1289](../scripts/localization/localize.py#L1289) 幂等，重复 promote 不重复追加）。

## 逐项修订清单

### 1. 无稿 42 行（每套 42 串，30 套）

`review-packet` 只发有机翻稿的行（[localize.py:1019](../scripts/localization/localize.py#L1019) 要求 `machine_candidate(row)` 非空），这 42 行不在任何 packet 里，属流水线盲区，必须单独撰写。键集固定：badminton/tt 红黄牌与判罚族、`me_profile_avatar_*`、`scoreboard_usage_hint_anim_*`、`record_training_*`、`common_next/previous`、`medical_break`、`web_load_failed`。

撰写与校验工具：[author-empty-rows-30locales-2026-09-29.py](../docs/audits/reference/author-empty-rows-30locales-2026-09-29.py)（先跑 preflight：拒绝未知身份、已有稿或已审行、占位符漂移、`\|`），成品值 [new-keys-30locales-2026-09-29.json](../docs/audits/reference/new-keys-30locales-2026-09-29.json)。

结构口径（30 套一致，仅语域按语言调整）：
- `badminton_card_red`（名词"红牌"）与 `badminton_action_red`（动词"出示红牌"）必须区分，沿用 de/ja/ru 已审 final 的分档，不得音译照搬；
- 带格式的 7 键逐套核对占位符：`%1$d%% accuracy`、`%1$d pt %2$@`、`%@ yellow card`；
- `record_bd_red` 的"(对手 +1)"限定语保留，属规则事实而非风格。

### 2. Odia(or)：污染剥离 + 受损长文重写

| 阶段 | 行数 | 手段 |
| --- | --- | --- |
| 句尾单 `\|` | 1,194 | 确定性脚本双层同修（catalog + `build/localization/cache/google-web/or.json`），见 [or-pipe-residue-repair-2026-09-29.py](../docs/audits/reference/or-pipe-residue-repair-2026-09-29.py)；剥离后已验证不为空串 |
| 引擎把多候选塞进同句（`ଯେକ any ଣସି`、`ପୁନ ry ଚେଷ୍ଟା`） | 112 | 逐行人工重写，成品 or-rewritten.json（已于2026-10-04清理），落 `build/localization/review/empty-rows/or-residue.jsonl` 后 apply |

同坏形态实测**只在 or**，其余 29 套 0 行。or 现 machine 1,339 行（其余套 1,451 左右），仍待 G6 深审。

### 3. 长英文残留 31 行

判定式：整句未译（译文含字母且与英文源等值）且不在 `protected-terms.json:literal_terms` 白名单。清单与成品：[english-residue-2026-09-29.json](../docs/audits/reference/english-residue-2026-09-29.json)。

| 地区 | Key | 修订前 | 修订后 |
| --- | --- | --- | --- |
| ro | timer_exit_confirm_message | `Exiting ends the current timer.`（整句未译） | `Ieșirea încheie cronometrul în curs.` |
| ro | scoreboard_style_usage_hint_more_styles | 英文原文 | `⚙️ Folosește butonul de stil din dreapta jos pentru fundaluri, teme, fonturi și altele` |
| hu | sync_display_disconnected_title | 英文原文 | `Megszakadt a kapcsolat a megosztó eszközzel` |
| hr / nb / sl | 其余 6 行 | 英文原文 | 见 JSON（逐行 note 记录来源） |

修后 30 套 `english_residue_left` 全部为 0（含在 `metrics-30locales.json` 中）。

### 4. G1 深审（it / nl / sv）

逐套流程：分块出包 → A/B 分档（A 档绝不自动批准：复数表、critical-domain/permission/format/multiline/long-copy 标记、无稿、`draft==en`、零目标字符块、含 `\|`、长度 >3×、短同形）→ 逐行判定 → `apply-review`（串行单写者）→ `validate --require-reviewed` → `promote`。

分档脚本 `build/localization/g1/triage.py`，独立复核器 `check_decisions.py`，审校记录 `build/localization/review/{it,nl,sv}/findings.md`（含每套术语表，G2–G7 可复用）。

改写量：it 491/1,479、nl 404/1,451、sv 437/1,451。

### 5. 晋级后自查（本轮最重要的部分，含已晋级语言）

promote 之后我用确定性扫描复查了已进包的内容，抓出 4 类机器初稿存活 + 1 类我自己引入的缺陷。**结论：审后再抽查一遍不能省，且抽查项必须做成门禁。**

| 地区 | Key | 修订前 | 修订后 | 级别 | 依据 |
| --- | --- | --- | --- | --- | --- |
| it | Localizable/sync_sets_format | `%d imposta` | `%d set` | P2 | 机翻把 "set" 译成"税/窗帘"；该套自己的 `Plural/sync_sets_format.*` 已是 `%d set`，只有 Localizable 行漏改 |
| it | Localizable/tennis_sync_sets_format | `%d imposta` | `%d set` | P2 | 同上 |
| it | Localizable/sync_games_format | `Giochi␣␣%d` | `%d giochi` | P2 | 复制中文源的双空格 + 标签前置语序 |
| it | Localizable/tennis_sync_games_format | `Giochi␣␣%d` | `%d giochi` | P2 | 同上 |
| it | Localizable/sync_players_format | `Giocatori␣␣%d` | `%d giocatori` | P2 | 同上 |
| it | Localizable/setup_suffix | `Impostazione` | `: Impostazione` | P2 | [DualTimerSetupView.swift:38](../jifen/Features/Timer/DualTimerSetupView.swift#L38)、[MultiScoreSetupDialogView.swift:169](../jifen/Features/Home/Components/MultiScoreSetupDialogView.swift#L169) 直接相加无分隔符；已晋级 7 套全部是冒号形态。原值会渲染成 `PallavoloImpostazione` |
| nl | Localizable/game_eight_ball | `8-ball chase` | `8-ball puntenjacht` | P2 | 英文残留，而 de/sv/fr/es/pt/ru/ja 都已译出模式名 |
| nl | Localizable/game_nine_ball | `9-ball chase` | `9-ball puntenjacht` | P2 | 同上 |
| nl | Localizable/sync_games_format + Plural one/other + tennis 版 | `%d partijen` / `%d partij` | `%d games` / `%d game` | P2 | **我上一轮的判断错误**：[ScoreboardTemplate.swift:961](../jifen/Features/Scoreboard/Shared/ScoreboardTemplate.swift#L961) 里这个计数是"一场比赛之内"与 set 并列的子计数，`partij`（盘/场比赛）语义放大；荷兰语羽毛球/乒乓球/网球该子计数就用借词 `game` |
| sv | Localizable/game_eight_ball | `8-Ball-poangjakt` | `8-Ball-poängjakt` | P2 | **我写 corrections 文件时把 ä 折成 ASCII**，并随 promote 进了 `sv.lproj`（`grep -c poängjakt` = 0） |
| sv | Localizable/game_nine_ball | `9-Ball-poangjakt` | `9-Ball-poängjakt` | P2 | 同上 |
| he | Localizable/qr_login_expired | `פג תוקף הקוד␣␣QR` | `פג תוקף קוד ה-QR` | P2 | 已晋级语言里同样的 CJK 双空格，且拉丁尾巴悬挂 |
| he | Plural/sync_players_format.two / .other | `נגני␣%d` | `%d␣שחקנים` | P2 | `נגן` = 演奏者/播放器，机器初稿存活到线上；计分玩家是 `שחקן` |

返修决策文件：`build/localization/g1/rework-{it,it-2,sv,nl,he}.jsonl`（18 行，已 apply，`validate --require-reviewed` 四套 blockers=0，待 re-promote）。

新门禁在返修前的自证输出（1 项 FAIL，逐条点名）：

```
FAIL: test_no_reviewed_final_ships_double_spaces
('he', Localizable, qr_login_expired, 'פג תוקף הקוד  QR')
('it', Localizable, sync_games_format, 'Giochi  %d')
('it', Localizable, tennis_sync_games_format, 'Giochi  %d')
('it', Localizable, sync_players_format, 'Giocatori  %d')
```

`internal-multi-space` 只判 `status in {reviewed, fixed}` 的行——机器草稿允许带着这个形态等待深审，避免污染"剩余可晋行数"这一排产指标。全 44 套命中 4 行，无误报。

### 6. 二审全量返修（新增 69 行，含已晋级的 he）

上一节只是第一批。这次把 it/nl/sv 三套 + 参照语 de/fr/es/pt/ru/ja 逐键对拉，并用代码调用点复核语义，另清出 69 行。**每一行都有两类证据之一：同套其他已审行的既有写法，或 6 套以上参照语的共识。** 我没有引入任何"我觉得荷兰语/瑞典语应该这么说"的孤立判断。

决策文件：`build/localization/g1/rework-{nl-3,sv-3,it-3,he-2}.jsonl`。

新门禁 `punctuation-glue`（本轮加，同样只判已审行）返修前的自证：

```
it  4 行  confirm_delete_record_message  'partita?Questa'
            Plural/schedule_participants_limit.{one,many,other}  'persona;i nomi'
sv  2 行  tennis_short_set_help  'två;vid'
            faq_answer_5  8 处 ';anslut' '.Håll' ';om' '.Öppna' ';när' '.Appen' '.Olika' ');slutför'
```

排除项是设计的一部分，否则会把合法文本判红：单字母缩写（`t.ex`、`n.b`）、罗曼语序数（`1.º y 2.º` —— es-ES/es-MX/pt-BR/pt-PT 各 1 行，共 4 行差点误报）、URL 与 TLD。加排除后全 44 套命中 6 行、误报 0，返修后 `test_no_reviewed_final_ships_punctuation_glue` 转绿。`test_localize.py` 现在 **21 tests / OK**。

#### 6.1 nl（20 行）

| 地区 | Key | 修订前 | 修订后 | 级别 | 依据 |
| --- | --- | --- | --- | --- | --- |
| nl | Localizable/tails | `Staart` | `Munt` | P2 | 与 `heads=Kop` 配对；荷兰语硬币是 Kop/Munt，`Staart` 是动物尾巴 |
| nl | faq_question_6 | `vinden.Wat` | `vinden. Wat` | P2 | 标点粘连 |
| nl | schedule_delete_booking_message | `gemaakt.Doorgaan?` | `gemaakt. Doorgaan?` | P2 | 同上 |
| nl | scoreboard_save_failed | `opslaan.Probeer` | `opslaan. Probeer` | P2 | 同上 |
| nl | archery_repeat_shoot_off | `afstand.Ga` | `afstand. Ga` | P2 | 同上 |
| nl | sync_intro_note | `(https: //jifenqi.com)` | `(https://jifenqi.com)` | P2 | **深审阶段自己写坏的 URL**，浏览器与系统都不会补这个空格 |
| nl | cast_ready_message | `op de controller` | `op het bedieningsapparaat` | P2 | 荷兰语 `controller` = 游戏手柄；de 用 `Steuergerät`。该套已有 `Scorebordbediening` 一词族 |
| nl | cast_controller_away | `Controller afwezig` | `Bedieningsapparaat niet beschikbaar` | P2 | 同上 + `afwezig` 用于人缺席 |
| nl | sync_controller_disconnected | `met de controller` | `met het bedieningsapparaat` | P2 | 同上 |
| nl | faq_answer_5 | `vanaf de controllerzijde`、`als je` | `vanaf het bedieningsapparaat`、`als u` | P2 | 同一个答案里 `u`/`je` 混用；该套其余长文用 `u` |
| nl | game_over_records | `Records bekijken` | `Historie bekijken` | P2 | **幻影标签名**：`tab_records=Historie`，界面上不存在 "Records" 标签 |
| nl | clear_records_tab_message | `op het tabblad Records` | `op het tabblad Historie` | P2 | 同上；de 的同类行就是 `im Tab „Verlauf“` |
| nl | faq_answer_3 | `in Records`、`Records zijn voornamelijk` | `in Historie`、`Historie is voornamelijk` | P2 | 同上 + 换成不可数名词后动词要跟着改单数 |
| nl | faq_answer_4 | `in Records` | `in Historie` | P2 | 同上 |
| nl | tab_timer_record | `Timeropname` | `Timerrecord` | P3 | 该套 30+ 行都用 `record`（`Wis alle records`、`Geen records`），只有这两行漂成 `opname` |
| nl | clear_data_category_timer | `Timeropnamen` | `Timerrecords` | P3 | 同上 |
| nl | timer_section_other | `Anders` | `Overig` | P3 | `Anders` 是副词（"otherwise"），分类标签用 `Overig`；de=`Sonstiges`、es=`Otro`、it=`Altro` |
| nl | schedule_sport_other | `Anders` | `Overig` | P3 | 同上 |
| nl | feedback_form_content_placeholder | `Beschrijf uw feedback in detail…` | `…zo gedetailleerd mogelijk…` | P2 | 英文残留 `in detail` |
| nl | record_note_text_placeholder | `…vast...` | `…vast…` | P3 | 英文源该行用的是单字符省略号；只对齐源，不发明全局风格 |

#### 6.2 sv（26 行）

| 地区 | Key | 修订前 | 修订后 | 级别 | 依据 |
| --- | --- | --- | --- | --- | --- |
| sv | snooker_frames / eight_ball_frames | `Ramar` | `Frames` | P2 | 瑞典语 `ram` = 画框/边框；台球 frame 沿用借词。de/fr/nl/it/ru 全部保留 Frame，`record_recap_frame_format` 同批 |
| sv | snooker_next_frame | `Nästa ram` | `Nästa frame` | P2 | 同上 |
| sv | snooker_frame_result_title | `Ram %d komplett` | `Frame %d komplett` | P2 | 同上 |
| sv | snooker_frame_winner_label | `Ramvinnare: %@` | `Framevinnare: %@` | P2 | 同上（复合词尾巴） |
| sv | snooker_frame_result_frames | `Ramar %d : %d` | `Frames %d : %d` | P2 | 同上 |
| sv | snooker_settle_frame | `Avgör ram` | `Avgör frame` | P2 | 同上 |
| sv | snooker_settle_frame_title | `Välj ramvinnare` | `Välj framevinnare` | P2 | 同上 |
| sv | record_recap_frame_format | `Ram %d` | `Frame %d` | P2 | 同上 |
| sv | snooker_current_frame_short | `Ram %d/%d` | `Frame %d/%d` | P2 | 同上 |
| sv | setup_snooker_break_left / _right | `Vänster/Höger sida bryter den första ramen` | `…gör breaket i första frame` | P2 | `bryta` 是 break 的直译（瑞典语"打断"），台球开球是 `göra break`；同套 `setup_opening_break_side` 已用借词 `break` |
| sv | setup_opening_break_side | `Första ramens break` | `Break i första frame` | P2 | Frame 词族 + 属格结构读不通 |
| sv | schedule_max_sets | `Set / ramar` | `Set / frames` | P2 | 同上 |
| sv | Plural/schedule_sets_summary.one / .other | `%d set / ram` / `%d set / ramar` | `%d set / frame` / `%d set / frames` | P2 | 同上；复数行与 Localizable 行必须同一口径，这是本轮第 N 次同类缺陷 |
| sv | tennis_short_set_help | `Först till 4 matcher av två;vid 4-4, spela ett tiebreak med 7 poäng` | `Först till 4 games med två i favör; vid 4-4 spelas ett tiebreak till 7 poäng` | P2 | `matcher av två` 不成句（"两场的比赛"）；网球 game 是 `game`；粘连标点 |
| sv | shengji_claim_dealer | `Buda dealer` | `Bjud som dealer` | P2 | `Buda` 是人名（佛陀），动词是 `bjud`；同套 `Ta dealern` 已正确 |
| sv | scoreboard_usage_hint_shengji | `…trycka på Buda dealer…` | `…trycka på Bjud som dealer…` | P2 | 使用说明必须指向界面真实按钮文字，否则指引不可执行 |
| sv | nine_ball_current_points | `%@ aktuella punkter: %d` | `%@ aktuella poäng: %d` | P2 | 分数是 `poäng`；`punkter` 是点/项。同套 40+ 行用 `poäng` |
| sv | shot_training_share | `%d gjorda av %d` | `%d av %d träffar` | P2 | `gjorda av` = "由…制成"（材质），英文 `made of %d` 是命中数 |
| sv | multi_score_portrait / _landscape | `Porträtt` / `Landskap` | `Stående` / `Liggande` | P2 | 屏幕方向瑞典语说 stående/liggande；`Landskap` 是风景，`Porträtt` 是人像画。de=Hochformat/Querformat、nl=Staand/Liggend |
| sv | match_count（+ Plural .other） | `%d matchar` | `%d matcher` | P2 | `en match` 的复数是 `matcher`；`.one=%d match` 保持不变 |
| sv | faq_answer_5 | 8 处粘连 | 补 8 个空格 | P2 | `;anslut`、`.Håll`、`;om`、`.Öppna`、`;när`、`.Appen`、`.Olika`、`);slutför` —— 含括号后的粘连，正则必须允许 `)` 前置 |

#### 6.3 it（7 行）

| 地区 | Key | 修订前 | 修订后 | 级别 | 依据 |
| --- | --- | --- | --- | --- | --- |
| it | sync_intro_note | `(https://jifenqi. com)` | `(https://jifenqi.com)` | P2 | 深审阶段把域名从中间拆开 |
| it | confirm_delete_record_message | `partita?Questa` | `partita? Questa` | P2 | 标点粘连 |
| it | Plural/schedule_participants_limit.{one,many,other} | `persona;i nomi` | `persona; i nomi` | P2 | 同一缺陷在 3 个复数类别各存活一次 |
| it | feedback_form_content_placeholder | `in dettaglio...` | `in dettaglio…` | P3 | 与英文源的省略号字符对齐 |
| it | timer_thinking_format | `%@ sta pensando...` | `%@ sta pensando…` | P3 | 同上 |

it 的其余对拉结果（不需要改，写下来免得下次重复怀疑）：`tails/heads`=Croce/Testa 正确；`multi_score_portrait/landscape`=Verticale/Orizzontale 正确；Frame 词族本来就是 `Frame`；`Cronologia` 词族在 `tab_records`、`game_over_records`、`clear_records_tab_message`、`faq_answer_3/4` 五处一致（**nl 正是因为不一致才被判为幻影标签**）；`boxing_*` 保留借词 `Round`；`controller` 在意大利语科技文案里是常用借词，未改。

#### 6.4 he（17 行 —— 已晋级语言的漏网错义）

这批不在 30 套计划内，是我拿 G1 的对拉方法扫已晋级套时抓到的。每一行都对照了 6 套参照语 + 该套自己的另一处已审写法。

| 地区 | Key | 修订前 | 修订后 | 级别 | 依据 |
| --- | --- | --- | --- | --- | --- |
| he | snooker_record_pot | `סיר` | `הכנסת כדור` | P2 | `סיר` = 锅。de=Gelocht、ru=Забитый шар、ar=إسقاط كرة，都是"进球" |
| he | record_tt_forfeit | `%@ חיסול` | `%@ פרישה` | P2 | `חיסול` = 歼灭。de=Aufgabe、ar=انسحاب（退赛） |
| he | record_recap_full_match | `התאמה מלאה` | `משחק מלא` | P2 | `התאמה` = 适配/匹配；同套 `match_record=רשומת משחק` 已确立 משחק |
| he | record_correction_set_score | `קבע ציון` | `תוצאת המערכה` | P2 | 直译成了祈使句"设定分数"；de=Satzstand、fr=Score des sets。该套 `תוצאת יעד`、`מערכה %d` 已分别确立"比分/盘" |
| he | timer_record_time | `הוקלט בשעה` | `נרשם בשעה` | P2 | `הוקלט` = 被录音；这是记录写入时间。同套 `לא נרשמו פעולות` 用 רשם |
| he | records_batch_deselect_all | `בטל את הבחירה בהכל` | `בטל הכל` | P2 | `בהכל` 拼写错误；且与已审的 `בחר הכל` 不成对 |
| he | record_correction_hint | `נשאר בתקליט…על השידור החוזר` | `נשאר ברשומה…על המשחק החוזר` | P2 | `תקליט` = 黑胶唱片、`שידור חוזר` = 电视重播；同套 `רשומה`/`משחק חוזר` 已是正解 |
| he | Plural/match_count.{two,other} | `התאמות %d` | `%d משחקים` | P2 | 与同套已审 `Localizable/match_count=%d משחקים` 同一口径；`התאמות` = 适配 |
| he | Plural/players_count_format.{two,other} | `נגני %d` | `%d שחקנים` | P2 | `נגן` = 乐手（构造状态 `נגני`）；与 `Localizable/players_count_format` 一致 |
| he | Plural/random_team_team_count_format.{two,other} | `צוותי %d` | `%d קבוצות` | P2 | 构造状态错 + 该套 `points_table_teams=קבוצות`、`2 קבוצות לפחות` 已确立词 |
| he | Plural/random_team_team_count_format.one | `צוות %d` | `קבוצה אחת (%d)` | P3 | 同族对齐；形态抄同套已审的 `match_count.one=משחק אחד (%d)` |
| he | Plural/record_format_pickleball_score.{two,other} | `מקד לנקודות %d` | `יעד: %d נקודות` | P2 | `מקד` 不成词；与 `Localizable/record_format_pickleball_score` 同值 |
| he | Plural/record_format_pickleball_score.one | `נקודת יעד %d` | `יעד: %d נקודה` | P3 | 家族内统一 |

**he 我没有动的两处，需要他拍板（不是我能靠对拉证明的）**：
1. `Localizable/record`：he=`שיא`（最高纪录）、it=`Cronologia`、nl=`Frames`、de=`Eintrag`、fr=`Enregistrement`、ja=`記録`。调用点只有 [SnookerScoreboardView.swift:360](../jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift#L360) 与 [:913](../jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift#L913)（斯诺克逐局日志，action 名 `frameRecord`）。也就是说 6 套把它译成"条目/记录"、he 译成"最佳纪录"、it/nl 译成"历史/局数"——**同一个入口三种语义**，建议先定英文源是否改成 `Frame Log`，再一次性回 17 套。
2. `timer_increment`：sv=`Ökning`、nl=`Verhoging`（都是"增加"直译）、de=`Zeitgutschrift`、ja=`加算`、zh=`加秒`。棋类"每秒累加"术语瑞典语更常用 `tillägg`，但改这一行会让 sv 与 nl 分叉，属于术语表决策不是缺陷修复，所以留着。

#### 6.5 幻影标签名 —— 可以复用的检查

新增语言要跑的第 6 条预检（清单见文末"G2–G7 排产队列"的第 1~8 条）：**任何提到"某标签页/某按钮"的长文案，其名称必须与该 tab/button 自己的最终值逐字一致**。nl 一次中 4 行（`Records` vs `Historie`），it/he 一致所以 0 行。可机器化：先从 `tab_*`、`*_button`、`menu_*` 建"可见名称表"，再在长文案里找大小写敏感的裸英文源词或与名称表不同的候选名词。

判定靠的是"同套内部一致性"而不是参照语：it 的 `Cronologia` 词族在 `tab_records`、`game_over_records`、`clear_records_tab_message`、`faq_answer_3/4` 五处一致，所以 0 行；nl 的 `tab_records=Historie` 却在小标题里写 `Records bekijken`，才是幻影。

#### 6.6 跨表同名键分裂（已晋级语言，3 行）

同一 key 在 `Localizable.strings` 与 `Localizable.stringsdict` 各有一行，运行时按复数规则取 dict、按 `%@` 拼装取 strings —— **两张表必须同词**。本轮抓到 3 行分裂：

| 地区 | Key | 修订前 | 修订后 | 级别 | 依据 |
| --- | --- | --- | --- | --- | --- |
| nl | Localizable/feedback_comment_count_label | `Opmerkingen (%d)` | `Reacties (%d)` | P2 | 该套 `Opmerking(en)` 已经固定用于 Notes（`record_note`、`schedule_notes`）；反馈评论是 `Reactie`，同键的 Plural `.one/.other` 与 `feedback_comment_placeholder` 都写 `reactie` |
| es-ES | Localizable/sync_sets_format | `%d conjuntos` | `%d sets` | P2 | `conjunto` = 组/群；该套 14 行（`match_completion_sets`、`points_per_set`、`key_point_set`…）与同键全部 Plural 行都用 `set`；es-MX 两套表本来就一致 |
| es-ES | Localizable/tennis_sync_sets_format | `%d conjuntos` | `%d sets` | P2 | 同上 |

**但这类检查做不成门禁**：我用词元重叠度跑了一遍全 17 套，命中 334 行，逐条看完只有上面 3 行是真缺陷。剩下 331 行是合法形态差——`Spiele` vs `Spiel`、`joueur` vs `joueurs`、`Гравців:` vs `%d игрок`、ja 的 `%d件の試合` vs `%d試合`（同类只是量词与语序差）。要判"同词"需要每语言的名词词典/词干归一，成本高于收益。**结论：这条留在人工预检清单（第 3 条），不要写进 `localize.py`。** 真正值得机器化的是它的特例：**Plural 家族内部**同类别行与 Localizable 行完全无重叠时告警，本轮 sv 的 `schedule_sets_summary`（`ram` vs Localizable 的 `ramar`）与 it 的 `sync_sets_format`（`imposta` vs `%d set`）就是这么抓到的 —— 那两类已经由 `provider-artifact` / `punctuation-glue` / `internal-multi-space` 之外的**人工对拉**覆盖，机器化留给 G2 之后再评估。

新增语言要跑的第 6 条预检（原 5 条见下一节）：**任何提到"某标签页/某按钮"的长文案，其名称必须与该 tab/button 自己的最终值逐字一致**。nl 一次中 4 行（`Records` vs `Historie`），it/he 一致所以 0 行。可机器化：先从 `tab_*`、`*_button`、`menu_*` 建"可见名称表"，再在长文案里找大小写敏感的裸英文源词或与名称表不同的候选名词。

#### 6.7 截图审计再抓 1 行（返修合计升到 91）

promote 之后按第 8 条预检抽查包内实际渲染，会员同意行暴露出一个 catalog 里看不出来的语法错：

| 地区 | Key | 修订前 | 修订后 | 级别 | 依据 |
| --- | --- | --- | --- | --- | --- |
| it | Localizable/vip_agreement_plain_prefix | `Ho letto e accetto i ` | `Ho letto e accetto: ` | P2 | 该片段与两个链接直接拼成一句，线上实际渲染成 `Ho letto e accetto i Contratto per l'utente e Contratto di iscrizione` —— 复数冠词 `i` 修饰两个单数合同名。已晋级 8 套里 de/fr/fr-CA/es-ES/pt-BR/sv/ru **七套都是冒号形态**（`…akzeptiert:`、`…j'accepte :`、`…acepto:`、`…concordo com:`、`…godkänner:`、`…принимаю:`），只有 it 带冠词。冒号形态把性数配合从片段里彻底移出，是唯一不需要改链接标题就能正确的写法 |

nl 的 `Ik ga akkoord met de …` 未改：荷兰语 `de` 不分单复数，接两个同冠词名词合法。

**同一次截图看到的一条非本地化问题（不改文案，交他决定）**：乒乓球设置弹窗底部三张开关卡的标签行被卡片高度裁掉半行 —— de `Automatischer`/`Sprachansagen`、it `Mostra l'ora`/`Annuncio vocale`、nl `Tijd weergeven`/`Spraakaankondiging` 三种语言同样被切，英文短词恰好躲过。这是布局定高问题，不是译文过长；改任何一套文案都治不了。已作为 U-1 记进 `build/localization/visual-audit/本地化UI截图审查.md` 的问题表（生成器会保留已填写的问题段，不会被下次复跑冲掉）。

#### 6.8 截图审计链自己漏了语言 —— 第 4 条门禁

复跑审计时发现的第二个"假绿"面：`.lproj` 进包 ≠ 有人看过。三处列表各自硬编码，promote 只更新第一处：

| 位置 | 漏掉的 | 已补 |
| --- | --- | --- |
| [LocalizationVisualAuditUITests.swift](../jifenUITests/LocalizationVisualAuditUITests.swift) 的 `priorityLocales` + 专用入口 | **uk**（乌克兰语）从来没有入口，磁盘上 0 张图 | 补 `UITestLocale.uk`、`AuditLocale(code:"uk")`、`testCaptureUk` |
| [run_localization_visual_audit.sh](../scripts/run_localization_visual_audit.sh) 的 `locales` 数组与 case 映射 | uk | 两处都补 |
| [generate_localization_visual_audit.js](../scripts/generate_localization_visual_audit.js) 的报告语言表 | **it / nl / sv / uk 四套**：图采了 54 张，报告里一个章节都没有 | 补四行，报告从 13 套增至 17 套 ×18 图 |

新门禁 `test_visual_audit_report_covers_every_promoted_locale`：扫 `jifen/Resources/*.lproj/Localizable.strings` 得到"已进包"集合，减去 `en/zh_Hans/zh_Hant`（开发源语言，截图证明不了什么），必须全部出现在报告生成器的语言表里。**这条就是"逐套晋级"在视觉层的卡口** —— 下次 G2 晋级只补 catalog 不补报告列表会直接红。写它的过程本身就self-proved：第一次跑就报出 `['en','uk','zh_Hans','zh_Hant']`，其中 uk 是真缺口。

Python 门禁因此从 21 → **22 tests OK**。

#### 6.9 uk 首审：两条"看着像缺陷"的观察，落数据后一条不成立、一条升级成跨 20 套

uk 是这次才被门禁抓进截图链的语言，第一次人眼看它的图提了两条疑点。我没有直接改译文，而是先把键值、代码路径和 20 套对照拉全：

**观察 A —— 记录详情时长显示 `21m 27s`（拉丁单位）。成立，但不是 catalog 缺陷，是代码没本地化。**

- 同屏左侧日期是本地化的（`29 вер. 2026 р., 15:06`），所以拉丁时长格外刺眼；
- 拉代码：`jifen/Core/Utils.swift:5` `formatScoreboardDuration` 是纯字符串插值 `"\(minutes)m \(seconds)s"`，**没有 `NSLocalizedString`**，被 `ScoreboardRecordDetailPage.swift:276` 与 `Utils.swift:21 formatDuration`（→ `TimerRecordDetailPage.swift:87`）共用；
- 对照组自证这不是 uk 独有：ja 同一张图显示 `35s`，ko/zh/ar/he 同理 —— **20 套全中**；
- 讽刺的地方：`duration_ms` 这个键 20 套 `.strings` 里都有正确译文（uk `%d хв %d с`、ja `%d分%d秒`、de `%d Min. %d Sek.`、ur `%d منٹ %d سیکنڈ`），但全仓 Swift 里它只出现在 `AppAnalytics.swift:52` 当埋点属性名（`as? Int`），**是一条活在其资源文件里的死键**。`minutes_format` 有调用点（`SportsSetupSettingsSection.swift:116`）、`countdown_compact_ms` 有调用点（`TimeoutCountdownView.swift:757`），只有 `duration_ms` 没人读。
- 归属：**没动代码**。改它 = 20 套包内可见文案同时变 + 小时分支要新键（现有 20 套只有分秒形态）+ 纯秒 `%ds` 要定形，属你拍板范围。已记为报告 U-2。

**观察 B —— uk 同屏"партія / Гра"混用。不成立为 uk 缺陷，真相是 20 套一起继承源文。**

最初怀疑是本轮定义的"跨表同名键分裂"。拉了 20 套这一对键的对照表后结论反转：

| locale | `record_format_points_per_set`（头部） | `record_recap_set_format`（芯片/图表切换） |
| --- | --- | --- |
| uk | `%d очок за партію` | `Гра %d` |
| ru | `%d очков за партию` | `Игра %d` |
| de | `%d Punkte pro Satz` | `Spiel %d` |
| ja | `1セット%d点` | `第%dゲーム` |
| zh-Hans | `每局%d分` | `第 %d 局` |
| en | `%d points per set` | `Game %d` |

规律非常整齐：**头部那一行各家都用自己的官方项目术语**（德 Satz、俄 партия、日 セット、中 局），**芯片那一行各家都只是照 en `Game %d` 直译**。也就是说 uk 的"混用"与已晋级、且已全量审过的 ru 一模一样（`11 очков за партию` + `Игра 1`，ru 的 09 图我同批看过，同现象），zh 自己也是"每局…分"配"第 N 局"但 ja 又写"ゲーム"。根子在源文层：`record_format_points_per_set` 的 en 是 "points per **set**"，`record_recap_set_format` 的 en 是 "**Game** %d"，zh 源文两处都叫"局" —— 英文一个概念两个词，20 套各自把它译成了两个词。

所以：**uk 零改动**（它与参照语 ru 一致，改它反而制造分裂）。真正的选择是要不要把 `record_recap_set_format` 源文统一成 `Set %d`，那会波及已晋级 17 套 + 四端口径，不在本轮 catalog 审查范围内。已记为报告 U-3，连同第三个键 `scoreboard_set_end_format`（只在 `ArcheryScoreboardView.swift:350` 用，ru=`Партия`/uk=`Гра`/zh=`第 %d 局`）一起等你定术语表。

顺带清掉一个误判：`set_ended_winner`（`RallyScoreboardView.swift:2705`，uk/ru 都写 `Сет %d заверш…`）与上面两个键是**三个不同屏、不同运动**的键，不是同一处文案的两个版本；rally 视图同时服务网球与乒乓球，一个键天然无法两套术语都对，这也是它为什么在 ru/uk 都取"сет"。

## 每套进度

| 组 | locale | 总行 | 已审 | machine 待审 | authored | blockers | 可晋级 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| G1 | it | 1,527 | 1,527 | 0 | 42 | 0 | **已晋级**（二审 7 行返修待 re-promote） |
| G1 | nl | 1,499 | 1,499 | 0 | 42 | 0 | **已晋级**（二审 20 行返修待 re-promote） |
| G1 | sv | 1,499 | 1,499 | 0 | 42 | 0 | **已晋级**（二审 26 行返修待 re-promote） |
| G2 | ca | 1,527 | 48 | 1,479 | 42 | 0 | 否 |
| G2 | pl | 1,555 | 48 | 1,507 | 42 | 0 | 否 |
| G2 | ro | 1,527 | 63 | 1,464 | 42 | 0 | 否 |
| G3 | cs / sk / sl / hr | 1,555 / 1,555 / 1,555 / 1,527 | 48 / 49 / 49 / 52 | 1,507 / 1,507 / 1,506 / 1,475 | 42 | 0 | 否 |
| G4 | da / nb / fi / hu / el | 1,499 ×5 | 48 / 49 / 48 / 58 / 48 | 1,451 / 1,450 / 1,451 / 1,441 / 1,451 | 42 | 0 | 否 |
| G5 | hi / bn / mr / gu / pa | 1,499 ×5 | 48 ×5 | 1,451 ×5 | 42 | 0 | 否 |
| G6 | ta / te / kn / ml | 1,499 ×4 | 48 ×4 | 1,451 ×4 | 42 | 0 | 否 |
| G6 | or | 1,499 | 160 | 1,339 | 154 | 0 | 否 |
| G7 | tr | 1,499 | 48 | 1,451 | 42 | 0 | 否 |
| G7 | vi / th / id / ms | 1,471 ×4 | 48 ×4 | 1,423 ×4 | 42 | 0 | 否 |

`metrics-30locales.json` 里的 `short_ambiguous_rows ≈ 945–1,002` 是 flags 产物（短标签同形计数），不代表待审行数；`blockers=0` 是**不带** `--require-reviewed` 的结构层结果，深审完成前不可 promote。

## G2–G7 排产队列

待深审总量 27 套 / 39,230 行；按 G1 实测系数（真需手看 ≈ 750–870 行/套，实际改写 ≈ 400–490 行/套）：

| 组 | 语言 | machine 行 | 单套成本要点 | 复用 G1 的资产 |
| --- | --- | --- | --- | --- |
| G2 | ca, pl, ro | 4,450 | pl 复数 one/few/many/other 最难，单套承担成本；ca/it 复数同形（one/many/other） | it 的术语表 + `%d set/giochi` 借词口径 |
| G3 | cs, sk, sl, hr | 5,995 | one/few/(two)/many 簇：数量词规则一次写好复用 4 套 | `sync_*` 家族形态 |
| G4 | da, nb, fi, hu, el | 7,244 | 黏着语 + 希腊语；英文残留曾最集中（已清底）；fi/el 无复数类别坑 | `new-keys` 里已撰写的 da/nb/fi/hu/el 42 行 |
| G5 | hi, bn, mr, gu, pa | 7,255 | 天城文家族术语复用（hi/mr 同字符块，防串块） | — |
| G6 | ta, te, kn, ml, or | 7,241 | or 已清污，仍需 1,339 行深审；达罗毗荼长文案长度膨胀告警多 | `or-rewritten.json` |
| G7 | tr, vi, th, id, ms | 7,064 | 仅 `other` 或单一类别，成本最低放最后；**ms 的 `setup_suffix` 草稿是 `Persediaan`（=库存），须改 `Penyiapan` 形态** | — |

每组开工前必做的确定性前置（G1 已验证有效，写进流程而不是靠记性）：
1. `setup_suffix` 必须是 `": <词>"` 形态（源文带前导空格而门禁禁止首尾空格，代码直接相加）；全项目源文带边界空白的只有 7 个键：`account_login_agreement_and`、`doudizhu_winner_separator`、`setup_suffix`、`vip_agreement_link_middle_separator`、`vip_agreement_link_separator`、`vip_agreement_plain_prefix`、`vs_separator`。
2. 与已晋级同族语言对同一 key 做一次 diff，凡是"只有我这套保留英文单词"的行一律看一遍（本轮就是这么抓到 `8-ball chase`、`poängjakt`）。
3. `Plural/*.one|many|other` 与同名 `Localizable/*_format` 必须同词同数（本轮 it 是复数表改对了、Localizable 行漏改；he 是复数表里藏着 `נגני`）。
4. 非拉丁语系：译文中不允许出现目标字符块外的拉丁字母（or 的 `ଯେକ any ଣସି` 形态）。
5. 已晋级语言也扫：`internal-multi-space`、`punctuation-glue`、`grep` 缺变音符号（`poangjakt` 型）。
6. **幻影名称核对**（本轮新增，nl 一次中 4 行）：长文案里提到"某标签页/按钮/菜单项"的名称，必须与 `tab_*`、`*_button`、`menu_*` 自己的最终值逐字一致。de/it 一致，nl 因为 `tab_records=Historie` 却在文案里写 `Records` 才暴露。
7. **假朋友家族**（本轮新增）：`controller`/`pot`/`record`/`increment`/`free`/`miss`/`made of`/`away`/`singles`/`wins`/`matches`/`break` 这类"短英文词在体育与设备语境里有另一义"的键，要成批对拉参照语而不是逐条凭感觉。nl 的 `controller`、he 的 `סיר`(锅) / `חיסול`(歼灭) 都是这一类。
8. **promote 之后必须再抽查一次包里实际渲染的字符串**（上一轮我写的 `poangjakt` 就是这么被发现的：catalog 已改但 `.lproj` 是旧值；返修行在 re-promote 前对线上包无效）。机器口径：`python3 build/localization/g1/bundle_delta.py` 必须打 `TOTAL pending re-promote diffs: 0`。
9. **每晋级一套要同批补三处截图入口**：`LocalizationVisualAuditUITests` 的 `priorityLocales` + `testCaptureXx`、`run_localization_visual_audit.sh` 的数组与 case、`generate_localization_visual_audit.js` 的语言表。第三处已有门禁 `test_visual_audit_report_covers_every_promoted_locale` 卡着（uk 就是这么被抓出来的：进包很久但 0 张图）。
10. **同意/协议类拼接句优先用冒号形态**（`…: `），别在片段里带冠词或量词：it 的 `Ho letto e accetto i …` 在 catalog 里看不出问题，只有截图能看到复数冠词修饰单数合同名。已晋级 8 套里 7 套本来就是冒号形态。
11. **死键 = 界面在代码里硬拼**（本轮新增，见 6.9）。一个键在 20 套 `.strings` 里都有正确译文、却在 Swift 里查不到 `NSLocalizedString("<key>"` 调用点，几乎必然意味着那块 UI 是字符串插值拼出来的、根本没走本地化。`duration_ms` 就是这一类：`Utils.swift:5` 直接 `"\(minutes)m \(seconds)s"`，于是 ja/ko/zh/uk 全部显示拉丁单位字母，而同一张卡上的日期是本地化的。G2 每套深审时顺手跑一次 `grep -rn 'duration_ms' --include='*.swift'`，把"有值无调用点"的键列出来，比在译文里挑错更能发现用户真看得见的缺陷。
12. **同屏两个键称呼同一概念时，先拉 20 套对照再判缺陷**（本轮新增，见 6.9）。uk 的"партію/Гра"看着像本轮定义的"跨表同名键分裂"，拉完对照表才发现：已全量审过的 ru 一模一样，各家都照 en `Game %d` 直译 —— 根因在源文层（en 一处叫 set、一处叫 Game）。**只改 uk 反而会制造与参照语的新分裂**，这类要上报术语表而不是就地返修。

## 需上机验证（我无法机器代证）

1. 91 行返修已全部 re-promote，窄屏 + iPad 审计也已在**返修后的包**上重采：it/nl/sv/he 各 18 张（15:00 那批），uk 首次入镜 18 张；报告 `build/localization/visual-audit/本地化UI截图审查.md` 现有 17 套 ×18 图。**图我看过，问题表现在 4 行：L-1 已修并确认渲染正确；U-1（卡片定高裁半行）、U-2（时长未本地化）、U-3（set/Game 源文混用）三条待你拍板** —— 而"人眼过一遍"这件事仍然只有你能做，尤其 uk 是第一次出现在报告里。
2. 多设备同步行的计数显示：`%d set · %d giochi`（it）、`%d sets · %d games`（nl）是否粘连或换行。
3. 围棋/棋类计时页 `timer_go` = `Go` 三套都保持"围棋"义（Xcode 门禁已断言字面一致，但语义要看屏）。
4. 台球记录页标题 `record`：代码侧已确认调用点只有斯诺克逐局日志（[SnookerScoreboardView.swift:360](../jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift#L360)、[:913](../jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift#L913)，action `frameRecord`），所以 nl=`Frames`/sv=`Post`/it=`Cronologia`/he=`שיא`/de=`Eintrag` 五种语义要在该页实机各看一眼再定英文源；我未改（属术语表决策，见 6.4 末尾）。
5. 希伯来语 QR 登录过期提示：RTL 中 `קוד ה-QR` 的拉丁嵌入方向。
6. **本轮二审改动的新增实机面**（这些是包内可见字符串，机器无法代证）：
   - sv 斯诺克/八/九球逐局日志的 `Frame`/`Frames` 标签（6.2 改了 6 行计数词形）与 `Omgång` 保留是否读得通。
   - it/nl/sv 三套竖横屏切换标签（`multi_score_portrait/landscape`：nl `Staand/Liggend`、it `Verticale/Orizzontale`）。
   - nl 抛球决胜的 `Kop/Munt`（Heads/Tails，6.1）在九球面板上的落位。
   - nl 反馈页评论计数 `Reacties (%d)`（6.6 跨表统一）与输入框占位符是否同词。
   - he 斯诺克 `הכנסת כדור`、乒乓球 `פרישה`（6.4 错义词）在比赛日志芯片里的宽度与 RTL 断行。
7. 首页/计分/我的/会员四屏各语言一遍；会员协议三片段拼接处（`vip_agreement_*`）无粘连。
8. **他这边需要重跑的一次**：`testCaptureMarketingDataScreenshots` 于 14:13 因 app 启动崩溃失败（不是本地化问题）。崩溃点 `UITestRecordFixtures.swift:56` 用局数下标写 2 元素的局分数组，3 局乒乓球剧本第三次迭代越界；我已改为按获胜方累加（结果 2:1，与同块 `winner: .team1` 一致），`swiftc -parse` 通过，但他那份营销数据截图仍需用修后的包重跑一次。

## 风险与未做

- 30 套全晋制约 +4.2MB 包体；`locales.json` 的 `app_store` 码已配好，**App Store Connect 本地化清单由他自己动**。
- catalogs / `localize.py` / `locales.json` / `protected-terms.json` 仍未纳入 git（`git ls-files scripts/localization` 只有 4 个文件），durable 状态只在磁盘 + ZIP；本轮不 commit，等他测完。
- G2–G7 未深审的 39,230 行仍是机器初稿，`promote` 硬门禁会拒绝，不存在"部分晋级混进包"的路径（`test_promoted_resources_never_ship_an_unreviewed_catalog_row` 已卡）。
