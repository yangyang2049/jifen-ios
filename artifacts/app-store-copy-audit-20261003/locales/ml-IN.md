# ml-IN — Malayalam 文案审校

审校日期：2026-10-03。结论：需修正。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ml-IN.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 未见问题 |
| Slogan（首图标题） | 需修正 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1130 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，24 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### ml-IN-1 · 需修正 · renderedSlogan

置信度：高。PNG在പോയിന്റും和പ്രധാനമാണ്内部自动断行。源文拼写没有问题；需要足够宽度/较小字号使每个单词完整，再重新渲染，不应改成同音英语。

原文／实际排版：

```text
ഓരോ പോ
യിന്റും
പ്രധാനമാ
ണ്
```

建议文案／目标排版：

```text
ഓരോ
പോയിന്റും
പ്രധാനമാണ്
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/01-slogan.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/01-slogan.png)

## Description 原文

```text
ഓരോ പോയിന്റും പ്രധാനമാണ്. മത്സരങ്ങൾക്കും പരിശീലനത്തിനും സുഹൃത്തുക്കളോടൊപ്പമുള്ള കളികൾക്കും നിങ്ങളുടെ iPhone അല്ലെങ്കിൽ iPad വ്യക്തവും എളുപ്പത്തിൽ ഉപയോഗിക്കാവുന്നതുമായ സ്കോർബോർഡാക്കി മാറ്റൂ.

ടെന്നീസ്, പിക്കിൾബോൾ, ബാഡ്മിന്റൺ, ടേബിൾ ടെന്നീസ്, ബാസ്കറ്റ്ബോൾ, ഫുട്ബോൾ, വോളിബോൾ, ബില്യാർഡ്സ് എന്നിവ ഉൾപ്പെടെ 26-ലധികം കായിക ഇനങ്ങളിലും കളികളിലും സ്കോർ രേഖപ്പെടുത്തൂ. പിന്തുണയ്ക്കുന്ന ഇനങ്ങളിൽ സ്കോറിങ് നിയമങ്ങൾ, മത്സരരീതി, ഡബിൾസ് സർവിന്റെ ക്രമം എന്നിവ ക്രമീകരിക്കാം.

മത്സരങ്ങൾ സേവ് ചെയ്ത് സ്കോറിലെ മാറ്റങ്ങൾ, സംഭവക്രമം, വോയ്സ് നോട്ടുകൾ എന്നിവയിലൂടെ വീണ്ടും പരിശോധിക്കൂ. ചെസ്, ഗോ ക്ലോക്കുകൾ, ക്യൂബ് ടൈമർ, സ്റ്റോപ്പ്വാച്ച് എന്നിവ ഉപയോഗിക്കൂ. വലിയ സ്ക്രീനിൽ സ്കോർബോർഡ് കാണിക്കൂ; സുഹൃത്തുക്കൾക്ക് ദൂരെയിരുന്ന് സ്കോർ പിന്തുടരാൻ മത്സര കോഡ് പങ്കിടൂ.

നാണയം ടോസ് ചെയ്യൽ, ക്രമരഹിതമായി ടീമുകൾ തിരിക്കൽ, ചുവപ്പും മഞ്ഞയും കാർഡുകൾ, ചെലവ് പങ്കിടൽ എന്നിവയ്ക്കുള്ള ഉപകരണങ്ങൾ ഒരേ ആപ്പിൽ. സ്കോർ രേഖപ്പെടുത്താൻ കുറച്ച് സമയം, കളി ആസ്വദിക്കാൻ കൂടുതൽ സമയം.

ഉപയോഗ നിബന്ധനകൾ:
https://jifenqi.com/terms

സ്വകാര്യതാ നയം:
https://jifenqi.com/privacy

Apple സ്റ്റാൻഡേർഡ് അന്തിമ ഉപയോക്തൃ ലൈസൻസ് കരാർ:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：സ്കോർ, സമയം, മത്സര രേഖകൾ

JSON 中的 Slogan：

```text
ഓരോ പോയിന്റും
പ്രധാനമാണ്
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
ഓരോ പോയിന്റും
പ്രധാനമാണ്
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | ഓരോ പോയിന്റും<br>പ്രധാനമാണ് | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/01-slogan.png) |
| 02 | score | എല്ലാ സ്കോറുകളും<br>ഒറ്റനോട്ടത്തിൽ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/02-score.png) |
| 03 | catalog | ഒരു സ്കോർബോർഡ്<br>26-ലധികം കായിക ഇനങ്ങൾക്ക് | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/03-catalog.png) |
| 04 | recap | ഓരോ മത്സരവും<br>വീണ്ടും പരിശോധിക്കൂ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/04-recap.png) |
| 05 | setup | നിങ്ങളുടെ നിയമങ്ങൾ<br>നിങ്ങളുടെ കളി | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/05-setup.png) |
| 06 | multiplayer | ഒന്നിലധികം കളിക്കാരുടെ<br>ഗെയിമുകളും ബോർഡ് ഗെയിമുകളും | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/06-multiplayer.png) |
| 07 | cast | നിങ്ങളുടെ സ്കോർബോർഡ്<br>വലിയ സ്ക്രീനിൽ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ml-IN/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | ഓരോ പോയിന്റും<br>പ്രധാനമാണ് |
| score | എല്ലാ സ്കോറുകളും<br>ഒറ്റനോട്ടത്തിൽ |
| catalog | ഒരു സ്കോർബോർഡ്<br>26-ലധികം കായിക ഇനങ്ങൾക്ക് |
| recap | ഓരോ മത്സരവും<br>വീണ്ടും പരിശോധിക്കൂ |
| setup | നിങ്ങളുടെ നിയമങ്ങൾ<br>നിങ്ങളുടെ കളി |
| timer | പന്തുകളികൾക്ക്<br>അപ്പുറവും |
| cast | നിങ്ങളുടെ സ്കോർബോർഡ്<br>വലിയ സ്ക്രീനിൽ |
| tools | റെഫറിയുടെ ഉപകരണങ്ങൾ<br>ഒരേ ആപ്പിൽ |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`80125ca52cc6ca7656883e872e777eb624fedffb9306fda2362c73d477e8a3ec`。
