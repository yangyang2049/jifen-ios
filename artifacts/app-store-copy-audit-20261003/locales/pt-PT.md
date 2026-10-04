# pt-PT — Portuguese (Portugal) 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/pt-PT.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1006 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，22 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Cada ponto conta. Transforma o teu iPhone ou iPad num marcador claro e fácil de usar para jogos, treinos e partidas com amigos.

Regista pontos em mais de 26 desportos e jogos, incluindo ténis, pickleball, badminton, ténis de mesa, basquetebol, futebol, voleibol e bilhar. Nos desportos compatíveis, ajusta as regras de pontuação, o formato do jogo e a ordem de serviço em pares.

Guarda as partidas e revê a evolução do marcador, a cronologia e as notas de voz. Usa relógios de xadrez e go, um temporizador para cubos e um cronómetro. Mostra o marcador num ecrã grande e partilha um código de jogo para os teus amigos acompanharem à distância.

Cara ou coroa, equipas aleatórias, cartões vermelhos e amarelos e divisão de despesas: tudo num só lugar. Menos trabalho a contar, mais tempo para jogar.

Termos de utilização:
https://jifenqi.com/terms

Política de privacidade:
https://jifenqi.com/privacy

Contrato de licença padrão da Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Pontos, tempos e jogos

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

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | CADA PONTO<br>CONTA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/01-slogan.png) |
| 02 | score | TODO O MARCADOR<br>NUM RELANCE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/02-score.png) |
| 03 | catalog | UM MARCADOR<br>PARA MAIS DE 26 DESPORTOS | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/03-catalog.png) |
| 04 | recap | REVÊ<br>CADA PARTIDA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/04-recap.png) |
| 05 | setup | AS TUAS REGRAS<br>A TUA FORMA DE JOGAR | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/05-setup.png) |
| 06 | multiplayer | JOGOS MULTIJOGADOR<br>E DE TABULEIRO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/06-multiplayer.png) |
| 07 | cast | O TEU MARCADOR<br>NO GRANDE ECRÃ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pt-PT/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Cada ponto<br>conta |
| score | Todo o marcador<br>num relance |
| catalog | Um marcador<br>para mais de 26 desportos |
| recap | Revê<br>cada partida |
| setup | As tuas regras<br>a tua forma de jogar |
| timer | Muito mais do que<br>jogos de bola |
| cast | O teu marcador<br>no grande ecrã |
| tools | Ferramentas de arbitragem<br>numa só app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`eb3083466540aa63853865933ca84d82fa15177a24e35d077cbf4348f61e145e`。
