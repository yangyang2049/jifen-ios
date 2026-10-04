# ur-PK — Urdu 文案审校

审校日期：2026-10-03。结论：需修正。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ur-PK.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 需修正 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 需修正 |

Description 与当前 App Store 3.3 完全一致；7 个段落，922 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，25 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### ur-PK-1 · 需修正 · description

置信度：确定。معاون意为协助者/辅助者（主动义），不能准确表达supported sports（支持该功能的项目）；改为“在这些功能可用的运动中”以保留功能支持范围。

原文／实际排版：

```text
معاون کھیلوں میں پوائنٹس کے اصول، میچ کا طریقہ اور ڈبلز میں سروس کی ترتیب طے کریں۔
```

建议文案／目标排版：

```text
جن کھیلوں میں یہ سہولت دستیاب ہے، ان میں پوائنٹس کے اصول، میچ کا طریقہ اور ڈبلز میں سروس کی ترتیب طے کریں۔
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ur-PK.json)

[术语或排版依据](https://www.rekhtadictionary.com/meaning-of-muaavin?lang=ur)

### ur-PK-2 · 需修正 · renderedTitles.catalog

置信度：确定。源第二行逻辑顺序正确，但实际PNG的26落在整行最左端；从右往左读时“多于26”的数词与سے زیادہ被分开。须设置该段落为RTL，或尝试行前U+200F；保留数字内部26的LTR顺序，修复后再验PNG。

原文（逻辑字符串；视觉错序见 PNG）：

```text
ایک اسکور بورڈ
26 سے زیادہ کھیلوں کے لیے
```

建议文案／目标排版：

```text
ایک اسکور بورڈ
‏26 سے زیادہ کھیلوں کے لیے
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/03-catalog.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/03-catalog.png)

## Description 原文

```text
ہر پوائنٹ اہم ہے۔ میچوں، مشق اور دوستوں کے ساتھ کھیلنے کے لیے اپنے iPhone یا iPad کو ایک واضح اور آسان اسکور بورڈ میں بدلیں۔

ٹینس، پکل بال، بیڈمنٹن، ٹیبل ٹینس، باسکٹ بال، فٹ بال، والی بال اور بلیئرڈز سمیت 26 سے زیادہ کھیلوں میں اسکور رکھیں۔ معاون کھیلوں میں پوائنٹس کے اصول، میچ کا طریقہ اور ڈبلز میں سروس کی ترتیب طے کریں۔

میچ محفوظ کریں اور اسکور کی تبدیلیوں، واقعات کی ترتیب اور صوتی نوٹس سے دوبارہ جائزہ لیں۔ شطرنج اور گو کی گھڑیاں، کیوب ٹائمر اور اسٹاپ واچ استعمال کریں۔ بڑی اسکرین پر اسکور بورڈ دکھائیں اور میچ کوڈ شیئر کریں تاکہ دوست دور سے اسکور دیکھ سکیں۔

سکہ اچھالنے، بے ترتیب ٹیمیں بنانے، سرخ اور پیلے کارڈ دکھانے اور اخراجات بانٹنے کے کارآمد اوزار ایک ہی ایپ میں۔ اسکور رکھنے میں کم وقت، کھیل کا زیادہ لطف۔

استعمال کی شرائط:
https://jifenqi.com/terms

رازداری کی پالیسی:
https://jifenqi.com/privacy

Apple کا معیاری آخری صارف لائسنس معاہدہ:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：اسکور، وقت اور میچ ریکارڈ

JSON 中的 Slogan：

```text
ہر پوائنٹ
اہم ہے
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
ہر پوائنٹ
اہم ہے
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | ہر پوائنٹ<br>اہم ہے | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/01-slogan.png) |
| 02 | score | پورا اسکور<br>ایک نظر میں | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/02-score.png) |
| 03 | catalog | ایک اسکور بورڈ<br>26 سے زیادہ کھیلوں کے لیے | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/03-catalog.png) |
| 04 | recap | ہر میچ کا<br>دوبارہ جائزہ لیں | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/04-recap.png) |
| 05 | setup | آپ کے اصول<br>آپ کا کھیل | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/05-setup.png) |
| 06 | multiplayer | کئی کھلاڑیوں کے کھیل<br>اور بورڈ گیمز | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/06-multiplayer.png) |
| 07 | cast | آپ کا اسکور بورڈ<br>بڑی اسکرین پر | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ur-PK/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | ہر پوائنٹ<br>اہم ہے |
| score | پورا اسکور<br>ایک نظر میں |
| catalog | ایک اسکور بورڈ<br>26 سے زیادہ کھیلوں کے لیے |
| recap | ہر میچ کا<br>دوبارہ جائزہ لیں |
| setup | آپ کے اصول<br>آپ کا کھیل |
| timer | صرف گیند والے<br>کھیل ہی نہیں |
| cast | آپ کا اسکور بورڈ<br>بڑی اسکرین پر |
| tools | ریفری کے کارآمد اوزار<br>ایک ہی ایپ میں |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`a6ebfbcf390751063d197d320f53fe892146694b0f9ae5eb53b530fdff1ca7dd`。
