# no — Norwegian 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/no.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，916 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，25 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Hvert poeng teller. Gjør iPhone eller iPad til en tydelig og brukervennlig resultattavle for kamper, trening og spill med venner.

Før poeng i over 26 idretter og spill, blant annet tennis, pickleball, badminton, bordtennis, basketball, fotball, volleyball og biljard. Tilpass poengregler, kampformat og serverekkefølge i double for idrettene som støtter det.

Lagre kamper og se poengutvikling, tidslinjer og talenotater. Bruk sjakk- og go-klokker, en tidtaker for kuber og en stoppeklokke. Vis resultattavlen på en stor skjerm, og del en kampkode slik at venner kan følge stillingen på avstand.

Myntkast, tilfeldige lag, røde og gule kort og fordeling av utgifter — alt på ett sted. Mindre tid på telling, mer glede av spillet.

Bruksvilkår:
https://jifenqi.com/terms

Personvernerklæring:
https://jifenqi.com/privacy

Apples standardlisensavtale:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Resultater, tid og kamper

JSON 中的 Slogan：

```text
Hvert poeng
teller
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
HVERT POENG
TELLER
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | HVERT POENG<br>TELLER | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/01-slogan.png) |
| 02 | score | ALLE RESULTATER<br>MED ETT BLIKK | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/02-score.png) |
| 03 | catalog | ÉN RESULTATTAVLE<br>FOR OVER 26 IDRETTER | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/03-catalog.png) |
| 04 | recap | SE TILBAKE PÅ<br>HVER KAMP | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/04-recap.png) |
| 05 | setup | DINE REGLER<br>DITT SPILL | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/05-setup.png) |
| 06 | multiplayer | FLERSPILLER-<br>OG BRETTSPILL | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/06-multiplayer.png) |
| 07 | cast | RESULTATTAVLEN DIN<br>PÅ STORSKJERMEN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/no/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Hvert poeng<br>teller |
| score | Alle resultater<br>med ett blikk |
| catalog | Én resultattavle<br>for over 26 idretter |
| recap | Se tilbake på<br>hver kamp |
| setup | Dine regler<br>ditt spill |
| timer | Mer enn<br>ballspill |
| cast | Resultattavlen din<br>på storskjermen |
| tools | Dommerverktøy<br>i én app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`ff6afb04451623e2ae5a8cd567173f82e67ca1c141d88c5f403fb9725c9aa21a`。
