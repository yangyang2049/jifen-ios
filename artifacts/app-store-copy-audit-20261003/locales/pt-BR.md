# pt-BR — Portuguese (Brazil) 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/pt-BR.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1004 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，25 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Cada ponto conta. Transforme seu iPhone ou iPad em um placar claro e fácil de usar para partidas, treinos e jogos com amigos.

Marque pontos em mais de 26 esportes e jogos, incluindo tênis, pickleball, badminton, tênis de mesa, basquete, futebol, vôlei e bilhar. Nos esportes compatíveis, ajuste as regras de pontuação, o formato da partida e a ordem de saque em duplas.

Salve suas partidas e reveja a evolução do placar, a linha do tempo e as notas de voz. Use relógios de xadrez e go, um temporizador para cubos e um cronômetro. Mostre o placar em uma tela grande e compartilhe um código de partida para seus amigos acompanharem à distância.

Cara ou coroa, equipes aleatórias, cartões vermelhos e amarelos e divisão de despesas: tudo em um só lugar. Menos trabalho para contar, mais tempo para jogar.

Termos de uso:
https://jifenqi.com/terms

Política de privacidade:
https://jifenqi.com/privacy

Contrato de licença padrão da Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Pontos, tempos e partidas

JSON 中的 Slogan：

```text
Cada ponto
conta
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
CADA PONTO
CONTA
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | CADA PONTO<br>CONTA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/01-slogan.png) |
| 02 | score | TODO O PLACAR<br>NUM PISCAR DE OLHOS | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/02-score.png) |
| 03 | catalog | UM PLACAR<br>PARA MAIS DE 26 ESPORTES | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/03-catalog.png) |
| 04 | recap | REVEJA<br>CADA PARTIDA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/04-recap.png) |
| 05 | setup | SUAS REGRAS<br>SEU JEITO DE JOGAR | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/05-setup.png) |
| 06 | multiplayer | JOGOS MULTIJOGADOR<br>E DE TABULEIRO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/06-multiplayer.png) |
| 07 | cast | SEU PLACAR<br>NA TELA GRANDE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-BR/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Cada ponto<br>conta |
| score | Todo o placar<br>num piscar de olhos |
| catalog | Um placar<br>para mais de 26 esportes |
| recap | Reveja<br>cada partida |
| setup | Suas regras<br>seu jeito de jogar |
| timer | Muito além dos<br>esportes com bola |
| cast | Seu placar<br>na tela grande |
| tools | Ferramentas de arbitragem<br>em um só app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`150b269be3f4b8ee2985758306830b9c79e2e9fd325bec321a085b5e4b045733`。
