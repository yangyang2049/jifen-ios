# es-MX — Spanish (Mexico) 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/es-MX.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1074 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，26 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Cada punto cuenta. Convierte tu iPhone o iPad en un marcador claro y fácil de usar para partidos, entrenamientos y juegos con amigos.

Lleva el marcador de más de 26 deportes y juegos, como tenis, pickleball, bádminton, tenis de mesa, básquetbol, futbol, voleibol y billar. En los deportes compatibles, ajusta las reglas de puntuación, el formato del partido y el orden de saque en dobles.

Guarda tus partidos y revísalos con la evolución del marcador, la línea de tiempo y las notas de voz. Usa relojes de ajedrez y go, un temporizador para cubos y un cronómetro. Muestra el marcador en una pantalla grande y comparte un código de partido para que tus amigos lo sigan a distancia.

También tienes herramientas para lanzar una moneda, formar equipos al azar, mostrar tarjetas rojas y amarillas y dividir gastos. Menos esfuerzo contando, más tiempo disfrutando del juego.

Términos de uso:
https://jifenqi.com/terms

Política de privacidad:
https://jifenqi.com/privacy

Acuerdo de licencia estándar de Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Puntos, tiempos y partidos

JSON 中的 Slogan：

```text
Cada punto
cuenta
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
CADA PUNTO
CUENTA
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | CADA PUNTO<br>CUENTA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/01-slogan.png) |
| 02 | score | TODO EL MARCADOR<br>DE UN VISTAZO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/02-score.png) |
| 03 | catalog | UN MARCADOR<br>PARA MÁS DE 26 DEPORTES | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/03-catalog.png) |
| 04 | recap | REVISA<br>CADA PARTIDO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/04-recap.png) |
| 05 | setup | TUS REGLAS<br>TU FORMA DE JUGAR | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/05-setup.png) |
| 06 | multiplayer | JUEGOS MULTIJUGADOR<br>Y DE MESA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/06-multiplayer.png) |
| 07 | cast | TU MARCADOR<br>EN PANTALLA GRANDE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/es-MX/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Cada punto<br>cuenta |
| score | Todo el marcador<br>de un vistazo |
| catalog | Un marcador<br>para más de 26 deportes |
| recap | Revisa<br>cada partido |
| setup | Tus reglas<br>tu forma de jugar |
| timer | Mucho más que<br>deportes de pelota |
| cast | Tu marcador<br>en pantalla grande |
| tools | Herramientas de arbitraje<br>en una sola app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`6db07d4b96b2957a1a6b44c5cfc5d922ca6580e9e3eeb1ca5d685eae64951109`。
