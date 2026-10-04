# hu — Hungarian 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/hu.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1062 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，29 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Minden pont számít. Alakítsd iPhone-odat vagy iPadedet átlátható, könnyen használható eredményjelzővé meccsekhez, edzéshez és baráti játékokhoz.

Vezesd az eredményt több mint 26 sportban és játékban, például teniszben, pickleballban, tollaslabdában, asztaliteniszben, kosárlabdában, fociban, röplabdában és biliárdban. A támogatott sportoknál állítsd be a pontozás szabályait, a mérkőzés formáját és a páros adogatási sorrendet.

Mentsd el a meccseket, és nézd vissza a pontok alakulását, az idővonalat és a hangjegyzeteket. Használj sakk- és goórát, kockaidőzítőt és stoppert. Jelenítsd meg az eredményjelzőt nagy képernyőn, és oszd meg a meccskódot, hogy barátaid távolról is követhessék az állást.

Pénzfeldobás, véletlenszerű csapatok, piros és sárga lapok, költségmegosztás — minden egy helyen. Kevesebb gond a számolással, több öröm a játékban.

Felhasználási feltételek:
https://jifenqi.com/terms

Adatvédelmi szabályzat:
https://jifenqi.com/privacy

Az Apple szabványos licencszerződése:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Eredmények, időmérés, meccsek

JSON 中的 Slogan：

```text
Minden pont
számít
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
MINDEN PONT
SZÁMÍT
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | MINDEN PONT<br>SZÁMÍT | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/01-slogan.png) |
| 02 | score | MINDEN EREDMÉNY<br>EGY PILLANTÁSRA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/02-score.png) |
| 03 | catalog | EGY EREDMÉNYJELZŐ<br>TÖBB MINT 26 SPORTHOZ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/03-catalog.png) |
| 04 | recap | NÉZZ VISSZA<br>MINDEN MECCSET | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/04-recap.png) |
| 05 | setup | A TE SZABÁLYAID<br>A TE JÁTÉKOD | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/05-setup.png) |
| 06 | multiplayer | TÖBBSZEREPLŐS<br>ÉS TÁRSASJÁTÉKOK | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/06-multiplayer.png) |
| 07 | cast | AZ EREDMÉNYJELZŐD<br>NAGY KÉPERNYŐN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hu/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Minden pont<br>számít |
| score | Minden eredmény<br>egy pillantásra |
| catalog | Egy eredményjelző<br>több mint 26 sporthoz |
| recap | Nézz vissza<br>minden meccset |
| setup | A te szabályaid<br>a te játékod |
| timer | Több mint<br>labdajátékok |
| cast | Az eredményjelződ<br>nagy képernyőn |
| tools | Bírói eszközök<br>egy alkalmazásban |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`3ca55f227adcdcbe19ae69127bd8b0ddc92eb93e7d721695b455f02706c472cf`。
