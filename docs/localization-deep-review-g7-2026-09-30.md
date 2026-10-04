# G7 翻译深审：tr / vi / th / id / ms

日期：2026-09-30。按项目 localization README 与 30locale 审查门禁，对完整 catalog 按 15 个约 100 源行包逐条读 EN 和五种候选译文，保留合格译文、修正不合格译文，再通过 `apply-review` 写入每行明确决策。没有调用任何翻译服务，没有修改共享脚本、工程、UI 或其他组的 catalog，也没有 promote。

| locale | Localizable | InfoPlist | Plural | 全覆盖 / fresh reviewed | 改动译文 | blockers | warnings |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tr | 1439 | 4 | 56 | 1499 / 1499 | 390 | 0 | 53 |
| vi | 1439 | 4 | 28 | 1471 / 1471 | 409 | 0 | 41 |
| th | 1439 | 4 | 28 | 1471 / 1471 | 302 | 0 | 22 |
| id | 1439 | 4 | 28 | 1471 / 1471 | 341 | 0 | 58 |
| ms | 1439 | 4 | 28 | 1471 / 1471 | 360 | 0 | 66 |

共 7383 行，1802 条最终译文变化。逐语言覆盖集合和当前源 identity 集合严格相等；每行 source_hash 当前，状态 reviewed。五套 CLI `validate --require-reviewed --output ...` 均通过。

主要语义修正：

- 比赛 match 与匹配、保存记录与纪录/档案、运动玩家与播放器、棋钟 move 与搬移、骰子 die 与死亡，逐处按实际语境处理。
- 投篮训练改为篮球投篮；Free 指自由选择分值，Miss 指未投中，Made 指投中。修正女士、免费、制造、射击、拍摄等误译，并同步训练帮助与分享结果。
- Set 指体育局/盘，Game 指网球局，Frame 指台球局，不能译为设置/图框。修正计分板、设置、同步、记录复盘、复数表的名词和数值单位。土耳其语数词后使用单数名词，one / other 分别读过再定稿；其他四套依项目 plural categories 只有 other。
- 修正无占先 No-ad 被译为无广告；单打被译为单身；匹克球被译为腌菜；壁球被译为南瓜；桌上足球被译为足球；台球 Pot 被译为锅；UNO Wild 被译为野生；掼蛋双上被译为翻倍；升级 Dealer 被译为零售商；Draw 被译为绘图或抽签。
- 统一投屏 Cast / Casting 与控制设备角色，避免演员或铸造。FAQ5 与当前 iOS 源重写，分享端登录生成 6 位码，显示端登录输入分享端码；第二段使用 AirPlay、Control Center、Screen Mirroring 和单外接屏限制。同步介绍的 QR 扫码方向与实际网页登录流程核对。
- FAQ10 只承诺已保存团队/玩家名称和地点跨设备同步；比赛记录、计时记录和未完赛在本机，不承诺记录云备份或换机恢复。FAQ11 和相机权限加入头像拍摄，删除旧“仅扫码/仅本地”承诺。上述源变更均重读后刷新 hash。
- 时长短格式使用当地小时/分钟/秒词或常用缩写；官方休息帮助的 60s/90s/120s 按秒翻译，删除年代误译；精确保留换行结构。
- 左/右指界面方位，不能译为剩余/正确；横屏不是风景；暂停与继续不是简历；Apply 是应用设置，不是报名/求职。
- 设置 suffix 保留冒号；VIP 三协议 fragments 的前缀末尾、and 两侧、逗号之后，以及斗地主赢家逗号后保留必要空格。审批门禁包括 placeholders、源 freshness、换行、NFC、受控空白、保护字面量与标点间距。
- `timer_go` 定稿为 tr Go / vi Cờ vây / th โกะ / id Go / ms Go。保留官方中文公司名称、象棋帅/将符号、产品名、平台名与台球缩写作为有意字面量。

全部 warnings 已读：目前仅 source-equality，均为有意产品/棋种/运动借词、Frame/Set 借词、缩写、默认示例名字等，不存在未审核行或结构 blocker。视觉适配与真实设备复核由根代理统一完成，本报告不声称截图验证。

审计证据位于 `build/localization/deep-review-20260930/g7/`：原 catalog 快照、15 个完整 packet、按包 authored fix 字典与每种语言的 approve/revise JSONL、最终二审修正和 current-source evidence、逐语种 delta / coverage、CLI validation 与 summary JSON。该 build 路径作为过程证据，不要求提交仓库；本报告与五套 catalog 保留在仓库。

总负责人收尾：本组已统一晋级并纳入 47 套包内资源，44 套审核目录的新鲜 hash/严格门禁均通过，目录与资源逐字节一致。本组报告上文记录分组交接时点；返修后的统一备份比较口径、构建、回归和视觉结果以[主报告](localization-deep-review-2026-09-30.md)为准。

最终视觉返修：vi 月/年计划紧凑标题采用 `Gói tháng` / `Gói năm`，id/ms 全场选择采用 `Semua`；均经实际使用键 apply-review 与重新晋级，最终两设备补拍证据见主报告。
