# sv — Swedish 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/sv.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，938 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，25 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Varje poäng räknas. Gör din iPhone eller iPad till en tydlig och lättanvänd resultattavla för matcher, träning och spel med vänner.

Håll koll på poängen i över 26 sporter och spel, bland annat tennis, pickleball, badminton, bordtennis, basket, fotboll, volleyboll och biljard. Anpassa poängregler, matchformat och serveordning i dubbel för de sporter som stöder det.

Spara matcher och se poängutveckling, tidslinjer och röstanteckningar. Använd schack- och go-klockor, en kubtimer och ett stoppur. Visa resultattavlan på en stor skärm och dela en matchkod så att vänner kan följa ställningen på distans.

Slantsingling, slumpmässiga lag, röda och gula kort och delning av kostnader — allt på ett ställe. Mindre tid på att räkna, mer glädje i spelet.

Användarvillkor:
https://jifenqi.com/terms

Integritetspolicy:
https://jifenqi.com/privacy

Apples standardlicensavtal:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Resultat, tid och matcher

JSON 中的 Slogan：

```text
Varje poäng
räknas
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
VARJE POÄNG
RÄKNAS
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | VARJE POÄNG<br>RÄKNAS | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/01-slogan.png) |
| 02 | score | ALLA RESULTAT<br>MED EN BLICK | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/02-score.png) |
| 03 | catalog | EN RESULTATTAVLA<br>FÖR ÖVER 26 SPORTER | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/03-catalog.png) |
| 04 | recap | SE TILLBAKA PÅ<br>VARJE MATCH | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/04-recap.png) |
| 05 | setup | DINA REGLER<br>DITT SPEL | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/05-setup.png) |
| 06 | multiplayer | FLERSPELARSPEL<br>OCH BRÄDSPEL | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/06-multiplayer.png) |
| 07 | cast | DIN RESULTATTAVLA<br>PÅ STORSKÄRMEN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sv/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Varje poäng<br>räknas |
| score | Alla resultat<br>med en blick |
| catalog | En resultattavla<br>för över 26 sporter |
| recap | Se tillbaka på<br>varje match |
| setup | Dina regler<br>ditt spel |
| timer | Mer än<br>bollspel |
| cast | Din resultattavla<br>på storskärmen |
| tools | Domarverktyg<br>i en app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`1a867826b588e2eb7198b2d0c3b53e08d72d50da4c84f311ab1f89cd36353627`。
