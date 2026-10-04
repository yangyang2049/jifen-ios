# ja — Japanese 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ja.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 有优化建议 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，531 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，16 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### ja-1 · 可选优化 · renderedSlogan

置信度：高。实际 PNG 将「得点」拆成「得 / 点」。日语一般汉字之间可换行，这不构成拼写或禁则错误；但短标题可读性较差，建议改为三行「すべての / 得点に / 意味がある」，再测量字号和文本框。

原文／实际排版：

```text
すべての得
点に
意味がある
```

建议文案／目标排版：

```text
すべての
得点に
意味がある
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/01-slogan.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/01-slogan.png)

[术语或排版依据](https://www.w3.org/TR/jlreq/)

独立复核后降为可读性建议；不以西方单词断行规则套用日语。

## Description 原文

```text
すべての得点を、大切に。iPhone や iPad が、試合や練習、友達とのゲームで使える見やすいスコアボードになります。

テニス、ピックルボール、バドミントン、卓球、バスケットボール、サッカー、バレーボール、ビリヤードなど、26 種類以上のスポーツやゲームに対応。対応する競技では、得点ルールや試合形式、ダブルスのサービス順を設定できます。

試合記録を保存し、得点の推移、タイムライン、音声メモで振り返り。チェスや囲碁の対局時計、キューブ用タイマー、ストップウォッチも搭載しています。スコアボードを大きな画面に表示したり、試合コードを共有して離れた友達に得点を見てもらったりできます。

コイントス、ランダムなチーム分け、レッドカード・イエローカード、割り勘計算などの便利なツールもひとつに。記録の手間を減らして、もっと試合を楽しみましょう。

利用規約:
https://jifenqi.com/terms

プライバシーポリシー:
https://jifenqi.com/privacy

Apple 標準使用許諾契約:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：得点記録・試合タイマー・振り返り

JSON 中的 Slogan：

```text
すべての得点に
意味がある
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
すべての得点に
意味がある
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | すべての得点に<br>意味がある | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/01-slogan.png) |
| 02 | score | 試合のスコアが<br>ひと目でわかる | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/02-score.png) |
| 03 | catalog | 26 種類以上の競技を<br>ひとつのスコアボードで | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/03-catalog.png) |
| 04 | recap | すべての試合を<br>振り返ろう | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/04-recap.png) |
| 05 | setup | ルールを決めて<br>自分たちらしい試合を | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/05-setup.png) |
| 06 | multiplayer | 多人数ゲームも<br>ボードゲームも | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/06-multiplayer.png) |
| 07 | cast | 大きな画面で<br>みんなにスコアを | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ja/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | すべての得点に<br>意味がある |
| score | 試合のスコアが<br>ひと目でわかる |
| catalog | 26 種類以上の競技を<br>ひとつのスコアボードで |
| recap | すべての試合を<br>振り返ろう |
| setup | ルールを決めて<br>自分たちらしい試合を |
| timer | 球技以外にも<br>便利な機能が満載 |
| cast | 大きな画面で<br>みんなにスコアを |
| tools | 審判に便利なツールを<br>ひとつのアプリに |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`bad3a5bd40a8db2e984a1b4dad87e16f53850605a1f37a8dfeba7bcf76766c5c`。
