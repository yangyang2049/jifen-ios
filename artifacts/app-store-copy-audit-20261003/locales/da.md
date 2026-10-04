# da — Danish 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/da.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 有优化建议 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，919 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，24 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### da-1 · 可选优化 · description.cubeTimer

置信度：高。丹麦语 terning 可以表示骰子或立方体，未明确魔方。可采用词典中的 professorterning 明确对象；属于术语清晰度建议，完整表达可再由母语者确认。

原文／实际排版：

```text
en terningetimer
```

建议文案／目标排版：

```text
en timer til professorterninger
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/da.json)

[术语或排版依据](https://ordnet.dk/ddo/ordbog/professorterning)

## Description 原文

```text
Hvert point tæller. Gør din iPhone eller iPad til en tydelig og brugervenlig måltavle til kampe, træning og spil med venner.

Hold styr på point i mere end 26 sportsgrene og spil, blandt andet tennis, pickleball, badminton, bordtennis, basketball, fodbold, volleyball og billard. Tilpas pointregler, kampformat og serverækkefølge i double for de sportsgrene, der understøtter det.

Gem kampe, og se pointudvikling, tidslinjer og stemmenoter. Brug skak- og go-ure, en terningetimer og et stopur. Vis måltavlen på en stor skærm, og del en kampkode, så venner kan følge stillingen på afstand.

Møntkast, tilfældige hold, røde og gule kort samt deling af udgifter — det hele er samlet ét sted. Mindre tid på at tælle, mere tid til spillet.

Brugsvilkår:
https://jifenqi.com/terms

Privatlivspolitik:
https://jifenqi.com/privacy

Apples standardlicensaftale:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Resultater, tid og kampe

JSON 中的 Slogan：

```text
Hvert point
tæller
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
HVERT POINT
TÆLLER
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | HVERT POINT<br>TÆLLER | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/01-slogan.png) |
| 02 | score | ALLE RESULTATER<br>MED ÉT BLIK | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/02-score.png) |
| 03 | catalog | ÉN MÅLTAVLE<br>TIL OVER 26 SPORTSGRENE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/03-catalog.png) |
| 04 | recap | SE TILBAGE PÅ<br>HVER KAMP | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/04-recap.png) |
| 05 | setup | DINE REGLER<br>DIT SPIL | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/05-setup.png) |
| 06 | multiplayer | FLERSPILLER-<br>OG BRÆTSPIL | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/06-multiplayer.png) |
| 07 | cast | DIN MÅLTAVLE<br>PÅ DEN STORE SKÆRM | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/da/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Hvert point<br>tæller |
| score | Alle resultater<br>med ét blik |
| catalog | Én måltavle<br>til over 26 sportsgrene |
| recap | Se tilbage på<br>hver kamp |
| setup | Dine regler<br>dit spil |
| timer | Mere end<br>boldspil |
| cast | Din måltavle<br>på den store skærm |
| tools | Dommerens værktøjer<br>i én app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`ff4415bc18c2ca5941235b4e33e6a5fb905df098e82951b0fa1729e04d9ee5e4`。
