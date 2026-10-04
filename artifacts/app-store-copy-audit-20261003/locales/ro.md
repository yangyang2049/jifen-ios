# ro — Romanian 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ro.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 有优化建议 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1080 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，24 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### ro-1 · 可选优化 · screenshotTitles.recap and cards.recap.text

置信度：高。文意和语法正确，但手动换行把介词la留在上一行，建议与fiecare meci同一行。实际cards应保留全大写形式。

原文／实际排版：

```text
Revino la
fiecare meci
```

建议文案／目标排版：

```text
Revino
la fiecare meci
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ro.json)

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/copy.json)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/04-recap.png)

### ro-2 · 可选优化 · renderedTitles.catalog

置信度：高。copy人工第二行完整；实际PNG自动扩为三行并把de与sporturi分开，数词短语中介词悬空。建议缩小该标题字号/调整框宽，使26 de sporturi连续显示；非语义硬错。

原文／实际排版：

```text
O SINGURĂ TABELĂ
PENTRU PESTE 26 DE
SPORTURI
```

建议文案／目标排版：

```text
O SINGURĂ TABELĂ
PENTRU PESTE 26 DE SPORTURI
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/03-catalog.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/03-catalog.png)

## Description 原文

```text
Fiecare punct contează. Transformă iPhone-ul sau iPad-ul într-o tabelă de scor clară și ușor de folosit pentru meciuri, antrenamente și jocuri cu prietenii.

Ține scorul pentru peste 26 de sporturi și jocuri, inclusiv tenis, pickleball, badminton, tenis de masă, baschet, fotbal, volei și biliard. În sporturile compatibile, adaptează regulile de punctaj, formatul meciului și ordinea serviciului la dublu.

Salvează meciurile și urmărește evoluția scorului, cronologia și notele vocale. Folosește ceasuri pentru șah și go, un cronometru pentru cub și un cronometru obișnuit. Afișează tabela pe un ecran mare și distribuie un cod de meci pentru ca prietenii să urmărească scorul de la distanță.

Aruncarea monedei, echipe aleatorii, cartonașe roșii și galbene și împărțirea cheltuielilor — toate într-un singur loc. Mai puțin efort cu scorul, mai multă bucurie în joc.

Condiții de utilizare:
https://jifenqi.com/terms

Politica de confidențialitate:
https://jifenqi.com/privacy

Acordul de licență standard Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Scoruri, timp și meciuri

JSON 中的 Slogan：

```text
Fiecare punct
contează
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
FIECARE PUNCT
CONTEAZĂ
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | FIECARE PUNCT<br>CONTEAZĂ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/01-slogan.png) |
| 02 | score | TOATE SCORURILE<br>DINTR-O PRIVIRE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/02-score.png) |
| 03 | catalog | O SINGURĂ TABELĂ<br>PENTRU PESTE 26 DE SPORTURI | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/03-catalog.png) |
| 04 | recap | REVINO LA<br>FIECARE MECI | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/04-recap.png) |
| 05 | setup | REGULILE TALE<br>JOCUL TĂU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/05-setup.png) |
| 06 | multiplayer | JOCURI MULTIPLAYER<br>ȘI DE SOCIETATE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/06-multiplayer.png) |
| 07 | cast | TABELA TA<br>PE ECRANUL MARE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ro/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Fiecare punct<br>contează |
| score | Toate scorurile<br>dintr-o privire |
| catalog | O singură tabelă<br>pentru peste 26 de sporturi |
| recap | Revino la<br>fiecare meci |
| setup | Regulile tale<br>jocul tău |
| timer | Mai mult decât<br>jocuri cu mingea |
| cast | Tabela ta<br>pe ecranul mare |
| tools | Instrumente pentru arbitri<br>într-o singură aplicație |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`9749ef892e405723602e0fd44ce57a6a2f7ec9c6edf3307db3ca849d7714b90f`。
