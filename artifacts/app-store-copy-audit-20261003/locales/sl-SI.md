# sl-SI — Slovenian 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/sl-SI.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1000 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，23 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Vsaka točka šteje. Spremenite iPhone ali iPad v pregleden semafor, ki je preprost za uporabo na tekmah, treningih in pri igrah s prijatelji.

Beležite rezultate za več kot 26 športov in iger, vključno s tenisom, pickleballom, badmintonom, namiznim tenisom, košarko, nogometom, odbojko in biljardom. Pri podprtih športih prilagodite pravila točkovanja, obliko tekme in vrstni red servisa v dvojicah.

Shranite tekme ter preglejte potek rezultata, časovnico in glasovne opombe. Uporabljajte ure za šah in go, časovnik za kocko in štoparico. Prikažite semafor na velikem zaslonu in delite kodo tekme, da lahko prijatelji spremljajo rezultat na daljavo.

Met kovanca, naključna razdelitev v ekipe, rdeči in rumeni kartoni ter delitev stroškov — vse na enem mestu. Manj dela s štetjem, več veselja pri igri.

Pogoji uporabe:
https://jifenqi.com/terms

Pravilnik o zasebnosti:
https://jifenqi.com/privacy

Standardna licenčna pogodba Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Rezultati, čas in tekme

JSON 中的 Slogan：

```text
Vsaka točka
šteje
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
VSAKA TOČKA
ŠTEJE
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | VSAKA TOČKA<br>ŠTEJE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/01-slogan.png) |
| 02 | score | VSI REZULTATI<br>NA PRVI POGLED | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/02-score.png) |
| 03 | catalog | EN SEMAFOR<br>ZA VEČ KOT 26 ŠPORTOV | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/03-catalog.png) |
| 04 | recap | POGLEJTE NAZAJ<br>NA VSAKO TEKMO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/04-recap.png) |
| 05 | setup | VAŠA PRAVILA<br>VAŠA IGRA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/05-setup.png) |
| 06 | multiplayer | IGRE ZA VEČ IGRALCEV<br>IN NAMIZNE IGRE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/06-multiplayer.png) |
| 07 | cast | VAŠ SEMAFOR<br>NA VELIKEM ZASLONU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/sl-SI/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Vsaka točka<br>šteje |
| score | Vsi rezultati<br>na prvi pogled |
| catalog | En semafor<br>za več kot 26 športov |
| recap | Poglejte nazaj<br>na vsako tekmo |
| setup | Vaša pravila<br>vaša igra |
| timer | Več kot<br>igre z žogo |
| cast | Vaš semafor<br>na velikem zaslonu |
| tools | Sodniška orodja<br>v eni aplikaciji |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`4ef0ab419c480c9eae069e1a77a5a195287ddb457f23243d954a5b837d86d994`。
