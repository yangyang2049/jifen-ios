# pa-IN — Punjabi 文案审校

审校日期：2026-10-03。结论：待母语确认。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/pa-IN.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 有优化建议 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 待母语确认 |

Description 与当前 App Store 3.3 完全一致；7 个段落，873 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，24 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### pa-IN-1 · 可选优化 · renderedSlogan

置信度：高。PNG系词ਹੈ孤行。所有词都完整，属于可改善的排版，建议使完整谓语ਮਾਇਨੇ ਰੱਖਦਾ ਹੈ同一行。

原文／实际排版：

```text
ਹਰ ਅੰਕ
ਮਾਇਨੇ ਰੱਖਦਾ
ਹੈ
```

建议文案／目标排版：

```text
ਹਰ ਅੰਕ
ਮਾਇਨੇ ਰੱਖਦਾ ਹੈ
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/01-slogan.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/01-slogan.png)

### pa-IN-2 · 待母语确认 · cards.multiplayer.text

置信度：中。第一项形容结构缺少显式游戏名词；两项可能共享末尾ਗੇਮਾਂ，建议母语评估是否应补全第一项，暂不判确定错。

原文／实际排版：

```text
ਕਈ ਖਿਡਾਰੀਆਂ ਵਾਲੀਆਂ
ਅਤੇ ਬੋਰਡ ਗੇਮਾਂ
```

建议文案／目标排版：

```text
ਕਈ ਖਿਡਾਰੀਆਂ ਵਾਲੀਆਂ ਗੇਮਾਂ
ਅਤੇ ਬੋਰਡ ਗੇਮਾਂ
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/copy.json)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/06-multiplayer.png)

## Description 原文

```text
ਹਰ ਅੰਕ ਮਾਇਨੇ ਰੱਖਦਾ ਹੈ। ਮੈਚਾਂ, ਅਭਿਆਸ ਅਤੇ ਦੋਸਤਾਂ ਨਾਲ ਖੇਡਣ ਲਈ ਆਪਣੇ iPhone ਜਾਂ iPad ਨੂੰ ਇੱਕ ਸਾਫ਼ ਅਤੇ ਵਰਤਣ ਵਿੱਚ ਆਸਾਨ ਸਕੋਰਬੋਰਡ ਬਣਾਓ।

ਟੈਨਿਸ, ਪਿਕਲਬਾਲ, ਬੈਡਮਿੰਟਨ, ਟੇਬਲ ਟੈਨਿਸ, ਬਾਸਕਟਬਾਲ, ਫੁੱਟਬਾਲ, ਵਾਲੀਬਾਲ ਅਤੇ ਬਿਲੀਅਰਡਸ ਸਮੇਤ 26 ਤੋਂ ਵੱਧ ਖੇਡਾਂ ਦੇ ਸਕੋਰ ਰੱਖੋ। ਸਮਰਥਿਤ ਖੇਡਾਂ ਵਿੱਚ ਅੰਕਾਂ ਦੇ ਨਿਯਮ, ਮੈਚ ਦਾ ਢੰਗ ਅਤੇ ਡਬਲਜ਼ ਦੀ ਸਰਵਿਸ ਦਾ ਕ੍ਰਮ ਸੈੱਟ ਕਰੋ।

ਮੈਚ ਸੰਭਾਲੋ ਅਤੇ ਸਕੋਰ ਦੇ ਬਦਲਾਅ, ਘਟਨਾਕ੍ਰਮ ਤੇ ਵੌਇਸ ਨੋਟਾਂ ਰਾਹੀਂ ਮੁੜ ਵੇਖੋ। ਸ਼ਤਰੰਜ ਅਤੇ ਗੋ ਦੀਆਂ ਘੜੀਆਂ, ਕਿਊਬ ਟਾਈਮਰ ਅਤੇ ਸਟਾਪਵਾਚ ਵਰਤੋ। ਵੱਡੀ ਸਕ੍ਰੀਨ ਉੱਤੇ ਸਕੋਰਬੋਰਡ ਦਿਖਾਓ ਅਤੇ ਮੈਚ ਕੋਡ ਸਾਂਝਾ ਕਰੋ, ਤਾਂ ਜੋ ਦੋਸਤ ਦੂਰੋਂ ਸਕੋਰ ਵੇਖ ਸਕਣ।

ਸਿੱਕਾ ਉਛਾਲਣ, ਬੇਤਰਤੀਬ ਟੀਮਾਂ ਬਣਾਉਣ, ਲਾਲ ਤੇ ਪੀਲੇ ਕਾਰਡ ਦਿਖਾਉਣ ਅਤੇ ਖਰਚ ਵੰਡਣ ਦੇ ਸਾਧਨ ਇੱਕੋ ਐਪ ਵਿੱਚ। ਸਕੋਰ ਰੱਖਣ ਵਿੱਚ ਘੱਟ ਸਮਾਂ, ਖੇਡ ਦਾ ਵੱਧ ਆਨੰਦ।

ਵਰਤੋਂ ਦੀਆਂ ਸ਼ਰਤਾਂ:
https://jifenqi.com/terms

ਪਰਦੇਦਾਰੀ ਨੀਤੀ:
https://jifenqi.com/privacy

Apple ਦਾ ਮਿਆਰੀ ਅੰਤਿਮ ਵਰਤੋਂਕਾਰ ਲਾਇਸੈਂਸ ਸਮਝੌਤਾ:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：ਸਕੋਰ, ਸਮਾਂ ਤੇ ਮੈਚ ਰਿਕਾਰਡ

JSON 中的 Slogan：

```text
ਹਰ ਅੰਕ
ਮਾਇਨੇ ਰੱਖਦਾ ਹੈ
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
ਹਰ ਅੰਕ
ਮਾਇਨੇ ਰੱਖਦਾ ਹੈ
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | ਹਰ ਅੰਕ<br>ਮਾਇਨੇ ਰੱਖਦਾ ਹੈ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/01-slogan.png) |
| 02 | score | ਸਾਰਾ ਸਕੋਰ<br>ਇੱਕ ਨਜ਼ਰ ਵਿੱਚ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/02-score.png) |
| 03 | catalog | ਇੱਕ ਸਕੋਰਬੋਰਡ<br>26 ਤੋਂ ਵੱਧ ਖੇਡਾਂ ਲਈ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/03-catalog.png) |
| 04 | recap | ਹਰ ਮੈਚ<br>ਮੁੜ ਵੇਖੋ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/04-recap.png) |
| 05 | setup | ਤੁਹਾਡੇ ਨਿਯਮ<br>ਤੁਹਾਡੀ ਖੇਡ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/05-setup.png) |
| 06 | multiplayer | ਕਈ ਖਿਡਾਰੀਆਂ ਵਾਲੀਆਂ<br>ਅਤੇ ਬੋਰਡ ਗੇਮਾਂ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/06-multiplayer.png) |
| 07 | cast | ਤੁਹਾਡਾ ਸਕੋਰਬੋਰਡ<br>ਵੱਡੀ ਸਕ੍ਰੀਨ ਉੱਤੇ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/pa-IN/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | ਹਰ ਅੰਕ<br>ਮਾਇਨੇ ਰੱਖਦਾ ਹੈ |
| score | ਸਾਰਾ ਸਕੋਰ<br>ਇੱਕ ਨਜ਼ਰ ਵਿੱਚ |
| catalog | ਇੱਕ ਸਕੋਰਬੋਰਡ<br>26 ਤੋਂ ਵੱਧ ਖੇਡਾਂ ਲਈ |
| recap | ਹਰ ਮੈਚ<br>ਮੁੜ ਵੇਖੋ |
| setup | ਤੁਹਾਡੇ ਨਿਯਮ<br>ਤੁਹਾਡੀ ਖੇਡ |
| timer | ਸਿਰਫ਼ ਗੇਂਦ ਵਾਲੀਆਂ<br>ਖੇਡਾਂ ਹੀ ਨਹੀਂ |
| cast | ਤੁਹਾਡਾ ਸਕੋਰਬੋਰਡ<br>ਵੱਡੀ ਸਕ੍ਰੀਨ ਉੱਤੇ |
| tools | ਰੈਫ਼ਰੀ ਦੇ ਲਾਭਦਾਇਕ ਸਾਧਨ<br>ਇੱਕੋ ਐਪ ਵਿੱਚ |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`b49eaf2f1f79538a7662c09c5f50fa5dc0d4876b05e87986217e968ce9a4f5de`。
