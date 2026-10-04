# sk — Slovak 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/sk.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1010 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，28 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Každý bod sa počíta. Premeňte iPhone alebo iPad na prehľadnú a ľahko ovládateľnú výsledkovú tabuľu na zápasy, tréningy aj hry s priateľmi.

Zapisujte skóre pre viac ako 26 športov a hier vrátane tenisu, pickleballu, bedmintonu, stolného tenisu, basketbalu, futbalu, volejbalu a biliardu. Pri podporovaných športoch upravte pravidlá bodovania, formát zápasu a poradie podania vo štvorhre.

Ukladajte zápasy a prezerajte si vývoj skóre, časovú os a hlasové poznámky. Používajte šachové hodiny, hodiny na go, časovač na kocku a stopky. Zobrazte tabuľu na veľkej obrazovke a zdieľajte kód zápasu, aby priatelia mohli sledovať skóre na diaľku.

Hod mincou, náhodné rozdelenie do tímov, červené a žlté karty aj rozdelenie nákladov — všetko na jednom mieste. Menej starostí s počítaním, viac radosti z hry.

Podmienky používania:
https://jifenqi.com/terms

Zásady ochrany osobných údajov:
https://jifenqi.com/privacy

Štandardná licenčná zmluva Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Skóre, čas a záznamy zápasov

JSON 中的 Slogan：

```text
Každý bod
sa počíta
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
KAŽDÝ BOD
SA POČÍTA
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | KAŽDÝ BOD<br>SA POČÍTA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/01-slogan.png) |
| 02 | score | VŠETKY SKÓRE<br>NA PRVÝ POHĽAD | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/02-score.png) |
| 03 | catalog | JEDNA TABUĽA<br>PRE VIAC AKO 26 ŠPORTOV | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/03-catalog.png) |
| 04 | recap | VRÁŤTE SA<br>KU KAŽDÉMU ZÁPASU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/04-recap.png) |
| 05 | setup | VAŠE PRAVIDLÁ<br>VAŠA HRA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/05-setup.png) |
| 06 | multiplayer | HRY PRE VIACERÝCH<br>A STOLOVÉ HRY | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/06-multiplayer.png) |
| 07 | cast | VAŠA TABUĽA<br>NA VEĽKEJ OBRAZOVKE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sk/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Každý bod<br>sa počíta |
| score | Všetky skóre<br>na prvý pohľad |
| catalog | Jedna tabuľa<br>pre viac ako 26 športov |
| recap | Vráťte sa<br>ku každému zápasu |
| setup | Vaše pravidlá<br>vaša hra |
| timer | Viac než<br>loptové hry |
| cast | Vaša tabuľa<br>na veľkej obrazovke |
| tools | Nástroje rozhodcu<br>v jednej aplikácii |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`de0a5d47d919e66854603c3fcae50f300abd04591e2d33cc7aaca84da47aad2e`。
