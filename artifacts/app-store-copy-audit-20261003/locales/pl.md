# pl — Polish 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/pl.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 有优化建议 |

Description 与当前 App Store 3.3 完全一致；7 个段落，976 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，30 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### pl-1 · 可选优化 · screenshotTitles.recap and cards.recap.text

置信度：高。文意和语法正确，但手动换行把介词do留在上一行，建议让do与każdego meczu同一行以保持短语完整；当前PNG也这样断行，调整后须测量行宽。实际cards应保留全大写形式。

原文／实际排版：

```text
Wróć do
każdego meczu
```

建议文案／目标排版：

```text
Wróć
do każdego meczu
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/pl.json)

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/copy.json)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/04-recap.png)

## Description 原文

```text
Każdy punkt się liczy. Zamień iPhone'a lub iPada w czytelną, wygodną tablicę wyników na mecze, treningi i rozgrywki ze znajomymi.

Zapisuj punkty w ponad 26 dyscyplinach i grach, takich jak tenis, pickleball, badminton, tenis stołowy, koszykówka, piłka nożna, siatkówka i bilard. W obsługiwanych dyscyplinach dostosuj zasady punktacji, format meczu i kolejność serwowania w deblu.

Zachowuj mecze i przeglądaj zmiany wyniku, oś czasu oraz notatki głosowe. Korzystaj z zegarów szachowych i do go, timera do kostki oraz stopera. Wyświetlaj wynik na dużym ekranie i udostępniaj kod meczu, aby znajomi mogli śledzić go zdalnie.

Rzut monetą, losowanie drużyn, czerwone i żółte kartki oraz dzielenie kosztów — wszystko w jednym miejscu. Mniej liczenia, więcej przyjemności z gry.

Warunki użytkowania:
https://jifenqi.com/terms

Polityka prywatności:
https://jifenqi.com/privacy

Standardowa umowa licencyjna Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Wyniki, zegary i historia gier

JSON 中的 Slogan：

```text
Każdy punkt
się liczy
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
KAŻDY PUNKT
SIĘ LICZY
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | KAŻDY PUNKT<br>SIĘ LICZY | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/01-slogan.png) |
| 02 | score | WSZYSTKIE WYNIKI<br>NA PIERWSZY RZUT OKA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/02-score.png) |
| 03 | catalog | JEDNA TABLICA WYNIKÓW<br>DLA PONAD 26 DYSCYPLIN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/03-catalog.png) |
| 04 | recap | WRÓĆ DO<br>KAŻDEGO MECZU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/04-recap.png) |
| 05 | setup | TWOJE ZASADY<br>TWOJA GRA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/05-setup.png) |
| 06 | multiplayer | GRY WIELOOSOBOWE<br>I PLANSZOWE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/06-multiplayer.png) |
| 07 | cast | TWOJE WYNIKI<br>NA DUŻYM EKRANIE | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pl/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Każdy punkt<br>się liczy |
| score | Wszystkie wyniki<br>na pierwszy rzut oka |
| catalog | Jedna tablica wyników<br>dla ponad 26 dyscyplin |
| recap | Wróć do<br>każdego meczu |
| setup | Twoje zasady<br>twoja gra |
| timer | Więcej niż<br>gry z piłką |
| cast | Twoje wyniki<br>na dużym ekranie |
| tools | Narzędzia sędziego<br>w jednej aplikacji |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`5828db00ce3ffa223a197da4c2ad3b51d6cf7a4e6622719e4bbcbd9e8ac48d9f`。
