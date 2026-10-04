# fr-CA — French (Canada) 文案审校

审校日期：2026-10-03。结论：需修正。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/fr-CA.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 需修正 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1097 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，27 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### fr-CA-1 · 需修正 · description.footerLabels

置信度：高。三个法律链接标签的冒号前缺少法语所需空格。建议插入不换行空格 U+00A0；保留 URL 独立行及现有段落。正文已有普通空格，也可统一为不换行空格。

原文／实际排版：

```text
Conditions d’utilisation:
https://jifenqi.com/terms

Politique de confidentialité:
https://jifenqi.com/privacy

Contrat de licence standard Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

建议文案／目标排版：

```text
Conditions d’utilisation :
https://jifenqi.com/terms

Politique de confidentialité :
https://jifenqi.com/privacy

Contrat de licence standard Apple :
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/fr-CA.json)

[术语或排版依据](https://vitrinelinguistique.oqlf.gouv.qc.ca/23325/la-ponctuation/deux-points/emplois-courants-du-deux-points)

## Description 原文

```text
Chaque point compte. Transformez votre iPhone ou iPad en tableau de pointage clair et facile à utiliser pour vos matchs, entraînements et parties entre amis.

Comptez les points pour plus de 26 sports et jeux : tennis, pickleball, badminton, tennis de table, basketball, soccer, volleyball et billard. Pour les sports compatibles, adaptez les règles de pointage, le format du match et l'ordre de service en double.

Enregistrez vos matchs et revivez-les grâce à l'évolution du pointage, à la chronologie et aux notes vocales. Profitez des pendules d'échecs et de go, du minuteur pour cube et du chronomètre. Affichez le pointage sur grand écran et partagez un code de match pour que vos proches le suivent à distance.

Pile ou face, équipes aléatoires, cartons rouges et jaunes, partage des frais : vos outils pratiques sont réunis. Moins de temps à compter, plus de plaisir à jouer.

Conditions d’utilisation:
https://jifenqi.com/terms

Politique de confidentialité:
https://jifenqi.com/privacy

Contrat de licence standard Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Pointage, chronos et matchs

JSON 中的 Slogan：

```text
Chaque point
compte
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
CHAQUE POINT
COMPTE
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | CHAQUE POINT<br>COMPTE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/01-slogan.png) |
| 02 | score | TOUT LE POINTAGE<br>EN UN COUP D’ŒIL | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/02-score.png) |
| 03 | catalog | UN TABLEAU DE POINTAGE<br>POUR PLUS DE 26 SPORTS | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/03-catalog.png) |
| 04 | recap | REVIVEZ<br>CHAQUE MATCH | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/04-recap.png) |
| 05 | setup | VOS RÈGLES<br>VOTRE FAÇON DE JOUER | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/05-setup.png) |
| 06 | multiplayer | JEUX MULTIJOUEURS<br>ET JEUX DE SOCIÉTÉ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/06-multiplayer.png) |
| 07 | cast | VOTRE POINTAGE<br>SUR GRAND ÉCRAN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/fr-CA/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Chaque point<br>compte |
| score | Tout le pointage<br>en un coup d’œil |
| catalog | Un tableau de pointage<br>pour plus de 26 sports |
| recap | Revivez<br>chaque match |
| setup | Vos règles<br>votre façon de jouer |
| timer | Bien plus que<br>des jeux de ballon |
| cast | Votre pointage<br>sur grand écran |
| tools | Les outils d’arbitrage<br>dans une seule app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`7045e997b1742fbdb507756c7e235d26e2ad28272ed47489682e97a241414660`。
