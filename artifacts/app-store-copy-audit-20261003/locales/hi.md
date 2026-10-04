# hi — Hindi 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/hi.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 有优化建议 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 有优化建议 |

Description 与当前 App Store 3.3 完全一致；7 个段落，937 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，25 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### hi-1 · 可选优化 · renderedSlogan

置信度：高。PNG自动多出第三行，句尾系词है独占一行。未拆词，语法仍正确；建议缩小字号/加宽框，使完整谓语मायने रखता है保持一行。

原文／实际排版：

```text
हर अंक
मायने रखता
है
```

建议文案／目标排版：

```text
हर अंक
मायने रखता है
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/01-slogan.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/01-slogan.png)

### hi-2 · 可选优化 · cards.multiplayer.text

置信度：高。第一项“多名玩家的/多名玩家参与的”修饰语后缺少游戏名词；补出गेम可避免后项与前项结构不平行。

原文／实际排版：

```text
कई खिलाड़ियों वाले
और बोर्ड गेम
```

建议文案／目标排版：

```text
कई खिलाड़ियों के गेम
और बोर्ड गेम
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/copy.json)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/06-multiplayer.png)

## Description 原文

```text
हर अंक मायने रखता है। अपने iPhone या iPad को मैच, अभ्यास और दोस्तों के साथ खेलने के लिए एक स्पष्ट और आसान स्कोरबोर्ड में बदलें।

टेनिस, पिकलबॉल, बैडमिंटन, टेबल टेनिस, बास्केटबॉल, फुटबॉल, वॉलीबॉल और बिलियर्ड्स सहित 26 से अधिक खेलों में स्कोर रखें। समर्थित खेलों में अंक गिनने के नियम, मैच का प्रारूप और डबल्स में सर्विस का क्रम तय करें।

मैच सहेजें और स्कोर के उतार-चढ़ाव, घटनाक्रम और वॉइस नोट्स से उनकी समीक्षा करें। शतरंज और गो की घड़ियाँ, क्यूब टाइमर और स्टॉपवॉच इस्तेमाल करें। स्कोरबोर्ड बड़ी स्क्रीन पर दिखाएँ और मैच कोड साझा करें, ताकि दोस्त दूर से स्कोर देख सकें।

सिक्का उछालने, यादृच्छिक टीमें बनाने, लाल और पीले कार्ड दिखाने और खर्च बाँटने के उपयोगी साधन एक ही ऐप में पाएँ। स्कोर रखने में कम समय लगाएँ और खेल का अधिक आनंद लें।

उपयोग की शर्तें:
https://jifenqi.com/terms

गोपनीयता नीति:
https://jifenqi.com/privacy

Apple का मानक अंतिम उपयोगकर्ता लाइसेंस समझौता:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：स्कोर, समय और मैच रिकॉर्ड

JSON 中的 Slogan：

```text
हर अंक
मायने रखता है
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
हर अंक
मायने रखता है
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | हर अंक<br>मायने रखता है | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/01-slogan.png) |
| 02 | score | पूरा स्कोर<br>एक नज़र में | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/02-score.png) |
| 03 | catalog | एक स्कोरबोर्ड<br>26 से अधिक खेलों के लिए | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/03-catalog.png) |
| 04 | recap | हर मैच<br>फिर से देखें | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/04-recap.png) |
| 05 | setup | आपके नियम<br>आपका खेल | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/05-setup.png) |
| 06 | multiplayer | कई खिलाड़ियों वाले<br>और बोर्ड गेम | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/06-multiplayer.png) |
| 07 | cast | आपका स्कोरबोर्ड<br>बड़ी स्क्रीन पर | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/hi/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | हर अंक<br>मायने रखता है |
| score | पूरा स्कोर<br>एक नज़र में |
| catalog | एक स्कोरबोर्ड<br>26 से अधिक खेलों के लिए |
| recap | हर मैच<br>फिर से देखें |
| setup | आपके नियम<br>आपका खेल |
| timer | सिर्फ गेंद वाले<br>खेल ही नहीं |
| cast | आपका स्कोरबोर्ड<br>बड़ी स्क्रीन पर |
| tools | रेफ़री के उपयोगी साधन<br>एक ही ऐप में |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`862b0be9fa100fa3ab54c161b04e1b9c6f8f89dcc574964c79d3f378bdf4870d`。
