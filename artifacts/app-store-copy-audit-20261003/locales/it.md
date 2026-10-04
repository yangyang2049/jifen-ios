# it — Italian 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/it.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1039 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，22 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Ogni punto conta. Trasforma il tuo iPhone o iPad in un tabellone chiaro e facile da usare per partite, allenamenti e giochi con gli amici.

Segna i punti per oltre 26 sport e giochi, tra cui tennis, pickleball, badminton, ping pong, basket, calcio, pallavolo e biliardo. Per gli sport compatibili, imposta le regole di punteggio, il formato della partita e l'ordine di servizio nel doppio.

Salva le partite e riguardale con l'andamento del punteggio, la cronologia e le note vocali. Usa orologi per scacchi e go, un timer per cubi e un cronometro. Mostra il tabellone su un grande schermo e condividi un codice partita per far seguire il punteggio agli amici a distanza.

Lancio della moneta, squadre casuali, cartellini rossi e gialli e divisione delle spese: tutto in un unico posto. Meno tempo a contare, più tempo per divertirti.

Condizioni d’uso:
https://jifenqi.com/terms

Informativa sulla privacy:
https://jifenqi.com/privacy

Contratto di licenza standard Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Punti, tempi e partite

JSON 中的 Slogan：

```text
Ogni punto
conta
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
OGNI PUNTO
CONTA
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | OGNI PUNTO<br>CONTA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/01-slogan.png) |
| 02 | score | TUTTI I PUNTEGGI<br>A COLPO D’OCCHIO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/02-score.png) |
| 03 | catalog | UN TABELLONE<br>PER OLTRE 26 SPORT | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/03-catalog.png) |
| 04 | recap | RIVEDI<br>OGNI PARTITA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/04-recap.png) |
| 05 | setup | LE TUE REGOLE<br>IL TUO MODO DI GIOCARE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/05-setup.png) |
| 06 | multiplayer | GIOCHI MULTIGIOCATORE<br>E DA TAVOLO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/06-multiplayer.png) |
| 07 | cast | IL TUO TABELLONE<br>SUL GRANDE SCHERMO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/it/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Ogni punto<br>conta |
| score | Tutti i punteggi<br>a colpo d’occhio |
| catalog | Un tabellone<br>per oltre 26 sport |
| recap | Rivedi<br>ogni partita |
| setup | Le tue regole<br>il tuo modo di giocare |
| timer | Non solo<br>giochi con la palla |
| cast | Il tuo tabellone<br>sul grande schermo |
| tools | Gli strumenti dell’arbitro<br>in una sola app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`7265b67d643e7e46f3dabd0b5a983b6733ef508a6eaf08fa80932175bacb9376`。
