# 比分口令复核与实现（2026-10-03）

2026-10-24 更新：完成乒乓球、羽毛球、网球、壁球结束用语的英文／中文二次确认，并逐项接通三端中文结果播报。详细依据、适用边界和验证见[结果播报记录](verification/official-result-voice-2026-10-24/README.md)。下文保留 10 月 3 日的原始审查记录；这四类运动的中文结束场景以新记录为准。

用户要求：遵循实际比赛的专业／规范口令；没有查到可靠表达时直接播两个数字。专业口令的依据按项目、语言和场景分别认定，不能把翻译目录里的 `reviewed` 状态当作裁判口令已获认证。

## 范围与生效路径

清点了 ScoreCore 的全部 34 个项目类型。现有语音入口覆盖 15 个类型：羽毛球单／双打、乒乓球单／双打、网球单／双打、软式网球、板式网球、匹克球单／双打、排球、沙排、气排球、毽球、壁球。下表覆盖这些项目。

App 的唯一比分语音文本入口 `SportsVoiceSupport.message` 已改用 `LocalizedVoiceAnnouncementBuilder.buildReviewed(payload, localization:)`。先选项目与语言的已查证规则，再渲染 ScoreVoice 模板，结果直接传给 AVSpeechUtterance。旧的英文／中文 builder 保留作兼容性对照，App 不再直接使用它们。

数字兜底通过独立 `score.numbers` 模板输出。根据 2026-10-04 的产品要求，简体和繁体中文的两个比分之间使用“比”（例如 1比0、2比0）；匹克球传统双打的第三个发球员序号仍用顿号分隔。其他语言保持标点停顿，不增加连接词。乒乓球中文平分仍读“几平”，网球平分／占先保留现有规则；其他数字兜底的平分仍播两个数字。发球方先报、网球抢七领先方先报等有依据的顺序保留；排球类及毽球采用稳定的左右顺序。网球常规分先把内部计分步数转换为 0/15/30/40；结束事件里的局数不做此转换。

未查证的暂停提醒及换边口令保持静默；比分、开局、结束及恢复场景采用数字兜底。避免在换边等控制事件中重复插入比分，也不借用其他项目的口令。

## 现有语音项目的处理

| 项目族 | 规范依据及结论 | 当前实现 |
| --- | --- | --- |
| 羽毛球单／双打 | BWF 2025 Vocabulary、ITTO；日本羽协 2026 口令表 | 英语／日语用各自正式数字与 love 词表、换发球、临界分、开局及继续比赛口令。29 平且临界分报“29, game point, all”，不重复第二个 29。英语结束句保留 BWF 口径；其他未查证场景播数字。 |
| 乒乓球单／双打 | ITTF HMO 第十八版 2026，18.1、附录 D；香港乒总中文本；日本卓协术语表 | 英语发球方先报，平分可 all，零分可 zero/love。中文平分报“4平”；日语开局的 0:0 用“ラヴオール”。其余缺少本地口令依据的场景播数字。英语中途恢复报当前比分，不再硬编码 love all。 |
| 网球单／双打 | ITF Duties and Procedures 2026 英／法／西文版；TTC 日语教学原表；韩网协规则；体育总局网球中心公开规则 | 英／法／西语用正式常规分、平分、优势、抢七及结束表达。法语第一次 40 平用 Quarante A，返回平分用 Égalité。日语采用已查证的常规分、Deuce／Advantage 词汇；韩语仅采用正式文件明确给出的 듀스／어드밴티지，其余分数播数字；中文采用平分／占先，普通分播数字。其余未查证组合播数字。 |
| 软式网球 | ISTF／ASTF 裁判用语表；日本软式网球协会裁判手册 | 英语／日语使用独立 zero 词表；优势按 server/receiver 报，不用姓名替代。返回平分用 Deuce again／デュースアゲン。结束报 Game／Game set，恢复报 No time／ノータイム。日语七／九局制开局使用 セブン／ナイン。其他语言播数字。 |
| 板式网球 | FIP Rules of Padel，2025 年末发布，Rule 1 | 英语常规分用 love/15/30/40 和 Deuce；Star Point 模式保留 deuce 1/2/3，并补正 advantage 1/2；Golden Point 依接发方选择规则。没有查证的抢七完整口令／结束句及其他语言用数字，不借用网球结束句。 |
| 匹克球单／双打 | USA Pickleball 2026，6.B、14.A.3、17.D | 单打和回合计分双打报两个数字；传统双打保留第三个发球员序号，不能删掉。各语言都保留这个已明确规定的数字结构；英语保留 Side out／Second server／Time in。没有查证的完整结束句用数字。 |
| 壁球 | WSF Singles Rules，2025-09-01，3.5、附录 2；官方法／西／葡译本 | 英语报分、开局及结束按壁球专用规则，不再套羽毛球结束句；0 用 love。法语 Changement／Balle de jeu／Balle de match，西语 Cambio／Pelota de juego／Pelota de partido，葡语 Troca／Game ball／Match ball，以及各自平分／10平口令按原表。非英语目前只启用已查证逐分口令，其他场景播数字。英语恢复只报 Time，不误报 0:0。 |
| 排球 | FIVB 2025–2028 规则、裁判与记录员职责 | 未找到可据以生成逐分语音句式的官方口令表，全部语言播两个数字。修复此前落入羽毛球分支而带出 Service over、game point 等口令的问题。 |
| 沙滩排球 | FIVB Beach Volleyball 2025–2028 | 同上，全部语言播两个数字。 |
| 气排球 | 中国排协规则下载目录及公开规则检索 | 未取得可信的逐分口令表，全部语言播两个数字，不推定羽毛球口令适用。 |
| 毽球 | ISF Official Shuttlecock Sport Rules 3.03，裁判／记录员职责 | 文件规定记录员通知局末及决胜局换边分数，未给出可确认的逐分播报句式。全部语言播两个数字，删除羽毛球开局／结束口令的借用。 |

不同语言的启用范围保持稀疏：拿到法语壁球依据不代表法语羽毛球也已查证；拿到韩语网球术语不代表韩语羽毛球或全部网球句式已查证。未找到可靠本地表达的组合都走数字兜底。数字兜底不附加未经查证的优势分、姓名或比赛口令；网球基分到 40 后维持数字基分表达。

## 其余 19 个项目类型

这些项目当前没有比分语音入口，本次没有新增开关或事件接线。检查了它们的路由身份及可参考的规范来源；合成的二方比分 payload 也不会再落到羽毛球 builder。

| 类型 | 检索／参考与边界 |
| --- | --- |
| football、football_5v5 | IFAB Laws of the Game、FIFA Futsal Laws 2025–26；未据此新增逐球口播。 |
| basketball、three_basketball、basketball_training | FIBA 官方规则下载中心、3x3 规则；训练次数不是双方比赛比分。 |
| archery_dual | World Archery Rulebook、裁判资料；箭值／组分／局分是不同数据，未套用球类口令。 |
| boxing | World Boxing 比赛规则与技术文件；判定成绩不是球类逐分呼报。 |
| billiards、eight_ball、nine_ball、snooker | WPA 2026 Rules of Play、WPBSA Rules；斯诺克单杆得分呼报不能从当前两方比分 payload 推造。 |
| foosball、foosball_doubles | ITSF Rules；没有新增未经查证的当地报分口令。 |
| guandan、shengji、doudizhu、uno | 体育总局棋牌中心公开竞赛资料、Mattel 官方规则；比赛等级／积分及多人结算不同于网球／羽毛球报分。 |
| simple_score、multi_scoreboard | 用户自定义计分，没有统一比赛裁判词表；多人分数也没有强行压成二方语音。 |

如以后接入这些项目的语音，必须传入该项目实际的计分数据；不能把当前 renderer 的二方数字兜底误当成完整的新语音功能。

## 原始依据

- [BWF Vocabulary, 8 November 2025](https://badminton.dk/wp-content/uploads/2025/12/Section-4.1.5-Vocabulary-8-November-2025-V7.0.pdf)、[BWF ITTO, 17 November 2025](https://badminton.dk/wp-content/uploads/2025/11/Section-4.1.1-Instructions-to-Technical-Officials-ITTO-17-November-2025-V8.0.pdf)，由丹麦羽协公开提供。
- [日本羽协 BAJ Rule Book 2026](https://www.badminton.or.jp/asset/pdf/corporate/concerned/referee/baj_rulebook_2026_rules.pdf)，審判用語、Scoring 数字原表。
- [ITTF HMO 2026 英文本](https://www.hktta.org.hk/referee/application/HMO_18thEdition_2026.pdf)、[香港乒总中文本](https://www.hktta.org.hk/referee/application/HMO_Chinese_2026.pdf)，18.1，附录 D。
- [日本卓协术语表](https://jtta.or.jp/glossary-category)，ラヴオール。
- [ITF 2026 英文](https://www.itftennis.com/media/2509/duties-procedures-for-officials-2026.pdf)、[法文](https://www.itftennis.com/media/14207/2026-duties-procedures-for-officials-fra.pdf)、[西文](https://www.itftennis.com/media/12653/duties-and-procedures-for-officials-2026-esp.pdf)，Score／Le score／Tanteo。
- [TTC 日语网球资料](https://tennis-ttc.or.jp/wp-content/uploads/2023/10/7368c35af9ff5c4c37ad855b9b6a13b9-1.pdf)，纸面 49–50 页。属于教练教学原始资料，并非 JTA 裁判手册。
- [韩网协 ITF Rules of Tennis 2020](https://www.kortennis.or.kr/upload/TAH/docs/ITF_Rules_of_Tennis_2020.pdf)，纸面 12 页。该版较旧，本次只用它明确列出的稳定词汇，不据其认定新赛制或全部韩语读法。此前目录中的 피프틴／서티／포티 转写没有用作生产路由的认证依据。
- [体育总局网球中心公开规则](https://www.sport.gov.cn/wqzx/n5345/c636548/part/355153.pdf)，常规局计分、平分、占先。是较早的青少年比赛文件，仅用于这些稳定术语，不用于新的比赛形式。
- [ASTF 裁判口令原表](https://www.astf.asia/files/40_Colls_on_Judgments_and_Scre_Counting.pdf)，通过[官方裁判资料目录](https://www.astf.asia/organization.html)取得；[ISTF Technical Rules](https://softtennis-istf.com/technical-rules/)；[日本软网裁判手册](https://www.jsta.or.jp/wp-content/uploads/rule/manual_amp_jr.pdf)，纸面 44–52 页。手册出版于 2021 年，现行协会页面仍公开提供。
- [FIP Rules of Padel](https://www.padelfip.com/wp-content/uploads/2025/12/FIP_Rules-of-Padel.pdf)，Rule 1，含 Star Point 的编号优势／平分口令。
- [USA Pickleball Official Rulebook 2026](https://usapickleball.org/docs/rules/USAP-Official-Rulebook.pdf)，6.B、14.A.3、17.D。
- [WSF 2025 官方规则及译本目录](https://worldsquashofficiating.com/rules-of-squash/)，3.5、附录 2；[法文](https://worldsquashofficiating.com/wp-content/uploads/2025/08/Regles-du-jeu-officielles-WSF-2025.pdf)、[西文](https://worldsquashofficiating.com/wp-content/uploads/2025/08/2025-Reglas-de-Singles-Squash-2025-V1.2-2025-09-01-CSS.pdf)、[葡文](https://worldsquashofficiating.com/wp-content/uploads/2025/08/Regras-Mundiais-Squash-Individual-2025_V1.2.pdf)。葡文本的连续局开局例句有混入西文的现象，因此没有将它整段照搬；只采用已核对的逐分术语。
- [FIVB 室内排球 2025–2028](https://www.fivb.com/wp-content/uploads/2025/01/FIVB-Volleyball_Rules2025_2028-EN-v05.pdf)、[沙排 2025–2028](https://www.fivb.com/wp-content/uploads/2025/02/FIVB-BeachVolleyball_Rules2025_2028-EN-v01.pdf)、[中国排协规则目录](https://www.volleyballchina.com/gzxz)。未查到逐分呼报表不等于断言任何比赛都没有播报。
- [ISF 毽球规则目录](https://www.shuttlecock-world.org/shuttlecock)，链接的 Version 3.03，24.3。官网公开版本较旧，未将其当成已确认最新的全部赛事规范。
- 其他项目参考入口：[IFAB](https://www.theifab.com/laws-of-the-game-documents/?language=en&year=all)、[FIFA 五人制规则（AFC 公开原文）](https://assets.the-afc.com/downloads/referees/Futsal---Laws-of-the-Game-2025-2026---Sep-12-update.pdf)、[FIBA 下载中心](https://about.fiba.basketball/en/services/resource-hub/downloads)、[World Archery](https://www.worldarchery.sport/rulebook/article)、[World Boxing](https://worldboxing.org/competitions/general-competition-documents/)、[WPA 2026](https://www.wpapool.com/wp-content/uploads/2026/01/2026.01.02-WPA-Rules.pdf)、[WPBSA](https://www.wpbsa.com/rules/)、[ITSF](https://www.tablesoccer.org/rules/documents/ITSFRulesEnglish.pdf)、[棋牌中心掼蛋资料](https://www.sport.gov.cn/qpzx/n27319064/n27319058/c27429584/content.html)、[升级资料](https://www.sport.gov.cn/dw/n5106/c668515/content.html)、[二打一竞赛资料](https://www.sport.gov.cn/n20001280/n20067662/n20067613/c22901551/content.html)、[Mattel UNO](https://service.mattel.com/instruction_sheets/42001.pdf)。这些入口的检索不能替代具体语言口令的认证。

## 实现与验证

- 给生产入口增加项目／语言／场景的证据门控；未查证的路径使用数字模板，而不是把旧文案全部当作官方口令。
- 英语数分使用停顿，不使用“three to two”作为逐分呼报。
- 独立的网球、羽毛球、软网和壁球词条防止 zero/love、all/deuce 及关键分术语互相污染。
- TennisVoiceAnnouncementMapper 保留“从优势返回平分”的事件事实。计分内核会将 4:4 归一为 3:3，因此不能仅看输出数字区分法语首次平分和再次平分。新增事实字段只用于语音，不修改计分规则或持久化模型。
- `voice-phrases.json` 与 `voice_localization.py` 是生成源；已同步 46 套目录及 ScoreVoice.strings。目录的审核状态只保证模板工程一致性，专业用途由上面的证据门控约束。
- Core 全包 250 项测试通过。新增断言涵盖规范与兜底、发球顺序、各类零分、临界平分、软网优势／再次平分、法语平分事件、壁球结束、匹克球第三数字及非零恢复。另有全部 34 项目 × 46 语言 × 9 阶段的固定样例渲染检查。
- Python 流水线 6 项通过；46 套源哈希、参数、键集合、生成资源逐值一致。
- App 层 4 项针对性测试覆盖编译资源、15 项目语言矩阵、实际生产入口的专业／兜底路由、功能过滤及系统音色地区库存。
- 旧 builder 对照测试作为兼容性检查保留，不将“与旧实现一致”当作口令正确性的证明。
- 日志：`/tmp/jifen-all-sports-core.log`、`/tmp/jifen-all-sports-app-final.log`；最终 App 结果：`/tmp/jifen-all-sports-reviewed-releasecheck-20261003.xcresult`。
- 未进行 iOS 真机音色实听。文本和资源检查不等同于所有系统音色的实际发音验收。

改动在工作区，未提交、未归档、未上传商店。
