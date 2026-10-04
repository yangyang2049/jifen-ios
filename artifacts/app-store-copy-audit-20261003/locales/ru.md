# ru — Russian 文案审校

审校日期：2026-10-03。结论：未见问题。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ru.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1040 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，27 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

本轮未发现需要修正或单独复核的问题。

## Description 原文

```text
Каждое очко важно. Превратите iPhone или iPad в удобное и наглядное табло для матчей, тренировок и игр с друзьями.

Ведите счёт в более чем 26 видах спорта и играх: теннис, пиклбол, бадминтон, настольный теннис, баскетбол, футбол, волейбол и бильярд. Для поддерживаемых видов спорта можно настроить правила подсчёта, формат матча и порядок подачи в парной игре.

Сохраняйте матчи и просматривайте динамику счёта, хронологию событий и голосовые заметки. Пользуйтесь шахматными часами, часами для го, таймером для кубика и секундомером. Показывайте табло на большом экране и делитесь кодом матча, чтобы друзья следили за счётом удалённо.

Подбрасывание монеты, случайное распределение по командам, красные и жёлтые карточки, разделение расходов — всё в одном приложении. Меньше хлопот со счётом, больше удовольствия от игры.

Условия использования:
https://jifenqi.com/terms

Политика конфиденциальности:
https://jifenqi.com/privacy

Стандартное лицензионное соглашение Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Счёт, таймеры и история игр

JSON 中的 Slogan：

```text
Каждое очко
важно
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
КАЖДОЕ ОЧКО
ВАЖНО
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | КАЖДОЕ ОЧКО<br>ВАЖНО | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/01-slogan.png) |
| 02 | score | ВЕСЬ СЧЁТ<br>С ПЕРВОГО ВЗГЛЯДА | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/02-score.png) |
| 03 | catalog | ОДНО ТАБЛО<br>ДЛЯ 26+ ВИДОВ СПОРТА | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/03-catalog.png) |
| 04 | recap | РАЗБЕРИТЕ<br>КАЖДЫЙ МАТЧ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/04-recap.png) |
| 05 | setup | ВАШИ ПРАВИЛА<br>ВАША ИГРА | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/05-setup.png) |
| 06 | multiplayer | ИГРЫ ДЛЯ КОМПАНИИ<br>И НАСТОЛЬНЫЕ ИГРЫ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/06-multiplayer.png) |
| 07 | cast | ВАШЕ ТАБЛО<br>НА БОЛЬШОМ ЭКРАНЕ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ru/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Каждое очко<br>важно |
| score | Весь счёт<br>с первого взгляда |
| catalog | Одно табло<br>для 26+ видов спорта |
| recap | Разберите<br>каждый матч |
| setup | Ваши правила<br>ваша игра |
| timer | Больше, чем<br>игры с мячом |
| cast | Ваше табло<br>на большом экране |
| tools | Инструменты судьи<br>в одном приложении |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`4cbd29a2a6e5d528924ee6a4a22472db1e26b924ecf0df5a0b9840271dbd36e8`。
