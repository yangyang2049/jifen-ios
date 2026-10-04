# cs — Czech 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/cs.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，986 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，27 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Každý bod se počítá. Proměňte iPhone nebo iPad v přehlednou a snadno ovladatelnou výsledkovou tabuli pro zápasy, tréninky i hry s přáteli.

Zapisujte skóre pro více než 26 sportů a her, včetně tenisu, pickleballu, badmintonu, stolního tenisu, basketbalu, fotbalu, volejbalu a kulečníku. U podporovaných sportů upravte pravidla bodování, formát zápasu a pořadí podání ve čtyřhře.

Ukládejte zápasy a prohlížejte vývoj skóre, časovou osu a hlasové poznámky. Používejte šachové hodiny, hodiny pro go, časovač pro kostku a stopky. Zobrazte tabuli na velké obrazovce a sdílejte kód zápasu, aby přátelé mohli sledovat skóre na dálku.

Hod mincí, náhodné rozdělení do týmů, červené a žluté karty i rozdělení nákladů — vše na jednom místě. Méně starostí s počítáním, více radosti ze hry.

Podmínky použití:
https://jifenqi.com/terms

Zásady ochrany osobních údajů:
https://jifenqi.com/privacy

Standardní licenční smlouva Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Skóre, čas a záznamy zápasů

JSON 中的 Slogan：

```text
Každý bod
se počítá
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
KAŽDÝ BOD
SE POČÍTÁ
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | KAŽDÝ BOD<br>SE POČÍTÁ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/01-slogan.png) |
| 02 | score | VŠECHNA SKÓRE<br>NA PRVNÍ POHLED | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/02-score.png) |
| 03 | catalog | JEDNA TABULE<br>PRO VÍCE NEŽ 26 SPORTŮ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/03-catalog.png) |
| 04 | recap | OHLÉDNĚTE SE<br>ZA KAŽDÝM ZÁPASEM | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/04-recap.png) |
| 05 | setup | VAŠE PRAVIDLA<br>VAŠE HRA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/05-setup.png) |
| 06 | multiplayer | HRY PRO VÍCE HRÁČŮ<br>A DESKOVÉ HRY | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/06-multiplayer.png) |
| 07 | cast | VAŠE TABULE<br>NA VELKÉ OBRAZOVCE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/cs/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Každý bod<br>se počítá |
| score | Všechna skóre<br>na první pohled |
| catalog | Jedna tabule<br>pro více než 26 sportů |
| recap | Ohlédněte se<br>za každým zápasem |
| setup | Vaše pravidla<br>vaše hra |
| timer | Více než<br>míčové hry |
| cast | Vaše tabule<br>na velké obrazovce |
| tools | Nástroje rozhodčího<br>v jedné aplikaci |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`4e3a07b823aa3e63ecf9abeda5da543dfaa11335b65dd956a4cb80d80b3bde45`。
