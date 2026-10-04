# hr — Croatian 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/hr.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1022 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，29 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Svaki bod vrijedi. Pretvorite iPhone ili iPad u pregledan semafor jednostavan za korištenje tijekom utakmica, treninga i igara s prijateljima.

Bilježite rezultate za više od 26 sportova i igara, uključujući tenis, pickleball, badminton, stolni tenis, košarku, nogomet, odbojku i biljar. U podržanim sportovima prilagodite pravila bodovanja, format utakmice i redoslijed servisa u parovima.

Spremite utakmice i pregledajte kretanje rezultata, vremenski slijed i glasovne bilješke. Koristite satove za šah i go, mjerač vremena za kocku i štopericu. Prikažite semafor na velikom zaslonu i podijelite kod utakmice kako bi prijatelji mogli pratiti rezultat na daljinu.

Bacanje novčića, nasumična podjela u ekipe, crveni i žuti kartoni te podjela troškova — sve na jednom mjestu. Manje brige oko bodova, više uživanja u igri.

Uvjeti korištenja:
https://jifenqi.com/terms

Pravila privatnosti:
https://jifenqi.com/privacy

Standardni Appleov ugovor o licenci:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Rezultati, vrijeme i utakmice

JSON 中的 Slogan：

```text
Svaki bod
vrijedi
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
SVAKI BOD
VRIJEDI
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | SVAKI BOD<br>VRIJEDI | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/01-slogan.png) |
| 02 | score | SVI REZULTATI<br>NA PRVI POGLED | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/02-score.png) |
| 03 | catalog | JEDAN SEMAFOR<br>ZA VIŠE OD 26 SPORTOVA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/03-catalog.png) |
| 04 | recap | PREGLEDAJTE<br>SVAKU UTAKMICU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/04-recap.png) |
| 05 | setup | VAŠA PRAVILA<br>VAŠA IGRA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/05-setup.png) |
| 06 | multiplayer | IGRE ZA VIŠE IGRAČA<br>I DRUŠTVENE IGRE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/06-multiplayer.png) |
| 07 | cast | VAŠ SEMAFOR<br>NA VELIKOM ZASLONU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hr/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Svaki bod<br>vrijedi |
| score | Svi rezultati<br>na prvi pogled |
| catalog | Jedan semafor<br>za više od 26 sportova |
| recap | Pregledajte<br>svaku utakmicu |
| setup | Vaša pravila<br>vaša igra |
| timer | Više od<br>igara s loptom |
| cast | Vaš semafor<br>na velikom zaslonu |
| tools | Sudački alati<br>u jednoj aplikaciji |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`cbaeb0e880d5ec6a04dc573cd68c5496f343446917389cb6ad5267efda87f11e`。
