# fi — Finnish 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/fi.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1030 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，28 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Jokainen piste merkitsee. Muuta iPhone tai iPad selkeäksi ja helppokäyttöiseksi tulostauluksi otteluihin, harjoitteluun ja peleihin ystävien kanssa.

Pidä kirjaa pisteistä yli 26 urheilulajissa ja pelissä, kuten tenniksessä, pickleballissa, sulkapallossa, pöytätenniksessä, koripallossa, jalkapallossa, lentopallossa ja biljardissa. Muokkaa tuetuissa lajeissa pistelaskun sääntöjä, ottelumuotoa ja nelinpelin syöttöjärjestystä.

Tallenna ottelut ja tarkastele pistetilanteen kehitystä, aikajanaa ja äänimuistiinpanoja. Käytä shakki- ja go-kelloja, kuutioajastinta ja sekuntikelloa. Näytä tulostaulu isolla näytöllä ja jaa ottelukoodi, jotta ystävät voivat seurata tulosta etänä.

Kolikonheitto, satunnaiset joukkueet, punaiset ja keltaiset kortit sekä kulujen jakaminen löytyvät samasta paikasta. Vähemmän vaivaa pisteistä, enemmän iloa pelistä.

Käyttöehdot:
https://jifenqi.com/terms

Tietosuojakäytäntö:
https://jifenqi.com/privacy

Applen vakiolisenssisopimus:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Tulokset, ajastimet ja pelit

JSON 中的 Slogan：

```text
Jokainen piste
merkitsee
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
JOKAINEN PISTE
MERKITSEE
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | JOKAINEN PISTE<br>MERKITSEE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/01-slogan.png) |
| 02 | score | KAIKKI TULOKSET<br>YHDELLÄ SILMÄYKSELLÄ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/02-score.png) |
| 03 | catalog | YKSI TULOSTAULU<br>YLI 26 URHEILULAJIIN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/03-catalog.png) |
| 04 | recap | PALAA<br>JOKAISEEN OTTELUUN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/04-recap.png) |
| 05 | setup | SINUN SÄÄNTÖSI<br>SINUN PELISI | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/05-setup.png) |
| 06 | multiplayer | MONINPELIT<br>JA LAUTAPELIT | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/06-multiplayer.png) |
| 07 | cast | TULOSTAULUSI<br>ISOLLA NÄYTÖLLÄ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fi/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Jokainen piste<br>merkitsee |
| score | Kaikki tulokset<br>yhdellä silmäyksellä |
| catalog | Yksi tulostaulu<br>yli 26 urheilulajiin |
| recap | Palaa<br>jokaiseen otteluun |
| setup | Sinun sääntösi<br>sinun pelisi |
| timer | Enemmän kuin<br>pallopelejä |
| cast | Tulostaulusi<br>isolla näytöllä |
| tools | Erotuomarin työkalut<br>yhdessä sovelluksessa |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`b3a934becb4b365b21e9b474c5aeba9b76055749cfd532842b5fc9be941989cd`。
