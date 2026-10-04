# en-GB — English (U.K.) 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/en-GB.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 有优化建议 |

Description 与当前 App Store 3.3 完全一致；7 个段落，927 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，30 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### en-GB-1 · 可选优化 · screenshotTitles.score.title

置信度：高。at a glance 表示快速看清信息，与 See every score 搭配更自然。当前 PNG 已使用 SEE EVERY SCORE，仅建议同步 JSON 的旧标题。

原文／实际排版：

```text
Keep every score
at a glance
```

建议文案／目标排版：

```text
See every score
at a glance
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/en-GB.json)

## Description 原文

```text
Every point counts. Turn your iPhone or iPad into a clear, easy-to-use scoreboard for matches, training and games with friends.

Keep score for 26+ sports and games, including tennis, pickleball, badminton, table tennis, basketball, football, volleyball and billiards. Adjust scoring rules, match formats and doubles serving order for supported sports.

Review saved matches with score trends, timelines and voice notes. Use built-in chess and Go clocks, a cube timer and a stopwatch. Display your scoreboard on a larger screen and share a match code so friends can follow the score remotely.

Get practical tools for coin tosses, random teams, red and yellow cards, and splitting the bill. Spend less time keeping track and more time enjoying the game.

Terms of Use:
https://jifenqi.com/terms

Privacy Policy:
https://jifenqi.com/privacy

Apple Standard EULA:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Scores, timers & match records

JSON 中的 Slogan：

```text
Every point
counts
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
EVERY
POINT
COUNTS
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | EVERY<br>POINT<br>COUNTS | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/01-slogan.png) |
| 02 | score | SEE EVERY SCORE<br>AT A GLANCE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/02-score.png) |
| 03 | catalog | ONE SCOREBOARD<br>FOR 26+ SPORTS | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/03-catalog.png) |
| 04 | recap | REVIEW<br>EVERY MATCH | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/04-recap.png) |
| 05 | setup | SET YOUR RULES<br>PLAY YOUR WAY | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/05-setup.png) |
| 06 | multiplayer | MULTI-PLAYER &<br>BOARD GAMES | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/06-multiplayer.png) |
| 07 | cast | YOUR SCOREBOARD<br>ON THE BIG SCREEN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/en-GB/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Every point<br>counts |
| score | Keep every score<br>at a glance |
| catalog | One scoreboard<br>for 26+ sports |
| recap | Review<br>every match |
| setup | Set your rules<br>play your way |
| timer | More than<br>ball games |
| cast | Your scoreboard<br>on the big screen |
| tools | Every referee<br>tool in one app |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`709549c75149f9ffbe392a6db83486e787e1699b82cf8226ed461e43b3c330a8`。
