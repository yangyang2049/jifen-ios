# uk — Ukrainian 文案审校

审校日期：2026-10-03。结论：需修正。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/uk.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 需修正 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1015 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，27 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### uk-1 · 需修正 · renderedSlogan

置信度：确定。源copy为КОЖНЕ ОЧКО\nВАЖЛИВЕ，人工换行没有拆词；实际PNG因标题宽度/字号把ВАЖЛИВЕ自动拆为ВАЖЛИВ和孤立Е。保留现有文案，缩小字号或增大文字容器至完整单词可放下。

原文／实际排版：

```text
КОЖНЕ
ОЧКО
ВАЖЛИВ
Е
```

建议文案／目标排版：

```text
КОЖНЕ
ОЧКО
ВАЖЛИВЕ
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/01-slogan.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/01-slogan.png)

## Description 原文

```text
Кожне очко важливе. Перетворіть iPhone або iPad на зручне й наочне табло для матчів, тренувань та ігор із друзями.

Ведіть рахунок у понад 26 видах спорту та іграх: теніс, піклбол, бадмінтон, настільний теніс, баскетбол, футбол, волейбол і більярд. Для підтримуваних видів спорту можна налаштувати правила підрахунку, формат матчу та порядок подачі в парній грі.

Зберігайте матчі й переглядайте зміни рахунку, хронологію подій та голосові нотатки. Користуйтеся шаховими годинниками, годинниками для ґо, таймером для кубика й секундоміром. Показуйте табло на великому екрані та діліться кодом матчу, щоб друзі стежили за рахунком віддалено.

Підкидання монети, випадковий розподіл на команди, червоні й жовті картки, поділ витрат — усе в одному застосунку. Менше клопоту з рахунком, більше задоволення від гри.

Умови використання:
https://jifenqi.com/terms

Політика конфіденційності:
https://jifenqi.com/privacy

Стандартна ліцензійна угода Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Рахунок, час та записи ігор

JSON 中的 Slogan：

```text
Кожне очко
важливе
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
КОЖНЕ ОЧКО
ВАЖЛИВЕ
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | КОЖНЕ ОЧКО<br>ВАЖЛИВЕ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/01-slogan.png) |
| 02 | score | УВЕСЬ РАХУНОК<br>З ПЕРШОГО ПОГЛЯДУ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/02-score.png) |
| 03 | catalog | ОДНЕ ТАБЛО<br>ДЛЯ 26+ ВИДІВ СПОРТУ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/03-catalog.png) |
| 04 | recap | ПЕРЕГЛЯНЬТЕ<br>КОЖЕН МАТЧ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/04-recap.png) |
| 05 | setup | ВАШІ ПРАВИЛА<br>ВАША ГРА | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/05-setup.png) |
| 06 | multiplayer | ІГРИ ДЛЯ КОМПАНІЇ<br>ТА НАСТІЛЬНІ ІГРИ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/06-multiplayer.png) |
| 07 | cast | ВАШЕ ТАБЛО<br>НА ВЕЛИКОМУ ЕКРАНІ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/uk/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Кожне очко<br>важливе |
| score | Увесь рахунок<br>з першого погляду |
| catalog | Одне табло<br>для 26+ видів спорту |
| recap | Перегляньте<br>кожен матч |
| setup | Ваші правила<br>ваша гра |
| timer | Більше, ніж<br>ігри з м’ячем |
| cast | Ваше табло<br>на великому екрані |
| tools | Інструменти судді<br>в одному застосунку |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`73f7c8cb58a0d03f9453416135173c9de722e93b80139626f29565ed98736927`。
