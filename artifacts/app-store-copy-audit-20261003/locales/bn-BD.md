# bn-BD — Bengali 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/bn-BD.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 有优化建议 |

Description 与当前 App Store 3.3 完全一致；7 个段落，927 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，28 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### bn-BD-1 · 可选优化 · cards.multiplayer.text

置信度：高。第一项只写“多个玩家的”，接“与桌游”前省略গেম，使两项不平行；建议补出游戏名词。不是slogan问题。

原文／实际排版：

```text
একাধিক খেলোয়াড়ের
ও বোর্ড গেম
```

建议文案／目标排版：

```text
একাধিক খেলোয়াড়ের গেম
ও বোর্ড গেম
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/copy.json)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/06-multiplayer.png)

## Description 原文

```text
প্রতিটি পয়েন্টই গুরুত্বপূর্ণ। ম্যাচ, অনুশীলন এবং বন্ধুদের সঙ্গে খেলার জন্য আপনার iPhone বা iPad-কে একটি স্পষ্ট ও সহজ স্কোরবোর্ডে পরিণত করুন।

টেনিস, পিকলবল, ব্যাডমিন্টন, টেবিল টেনিস, বাস্কেটবল, ফুটবল, ভলিবল ও বিলিয়ার্ডসসহ ২৬টির বেশি খেলা ও গেমের স্কোর রাখুন। সমর্থিত খেলায় পয়েন্টের নিয়ম, ম্যাচের ধরন ও ডাবলসের সার্ভিসের ক্রম বদলাতে পারবেন।

ম্যাচ সংরক্ষণ করে স্কোরের পরিবর্তন, ঘটনাক্রম ও ভয়েস নোট দিয়ে ফিরে দেখুন। দাবা ও গো খেলার ঘড়ি, কিউব টাইমার এবং স্টপওয়াচ ব্যবহার করুন। বড় পর্দায় স্কোরবোর্ড দেখান এবং ম্যাচের কোড শেয়ার করুন, যাতে বন্ধুরা দূর থেকে স্কোর দেখতে পারেন।

কয়েন টস, এলোমেলোভাবে দল ভাগ, লাল ও হলুদ কার্ড এবং খরচ ভাগ করার দরকারি সরঞ্জাম এক অ্যাপেই পাবেন। স্কোর রাখার ঝামেলা কমান, খেলায় আনন্দ বাড়ান।

ব্যবহারের শর্তাবলি:
https://jifenqi.com/terms

গোপনীয়তা নীতি:
https://jifenqi.com/privacy

Apple-এর মানক ব্যবহারকারী লাইসেন্স চুক্তি:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：স্কোর, সময় ও ম্যাচের রেকর্ড

JSON 中的 Slogan：

```text
প্রতিটি পয়েন্টই
গুরুত্বপূর্ণ
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
প্রতিটি পয়েন্টই
গুরুত্বপূর্ণ
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | প্রতিটি পয়েন্টই<br>গুরুত্বপূর্ণ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/01-slogan.png) |
| 02 | score | সব স্কোর<br>এক নজরে | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/02-score.png) |
| 03 | catalog | এক স্কোরবোর্ড<br>২৬টির বেশি খেলার জন্য | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/03-catalog.png) |
| 04 | recap | ফিরে দেখুন<br>প্রতিটি ম্যাচ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/04-recap.png) |
| 05 | setup | আপনার নিয়ম<br>আপনার মতো খেলা | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/05-setup.png) |
| 06 | multiplayer | একাধিক খেলোয়াড়ের<br>ও বোর্ড গেম | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/06-multiplayer.png) |
| 07 | cast | আপনার স্কোরবোর্ড<br>বড় পর্দায় | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/bn-BD/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | প্রতিটি পয়েন্টই<br>গুরুত্বপূর্ণ |
| score | সব স্কোর<br>এক নজরে |
| catalog | এক স্কোরবোর্ড<br>২৬টির বেশি খেলার জন্য |
| recap | ফিরে দেখুন<br>প্রতিটি ম্যাচ |
| setup | আপনার নিয়ম<br>আপনার মতো খেলা |
| timer | শুধু বলের<br>খেলা নয় |
| cast | আপনার স্কোরবোর্ড<br>বড় পর্দায় |
| tools | রেফারির দরকারি সরঞ্জাম<br>এক অ্যাপেই |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`8d229598855ee57243001db307d334cd8257fd83cb388ccaba74771ad38bf390`。
