# App Store Description 与 Slogan 逐语言审校

> 完成状态（2026-10-03）：本报告保留修订前审校记录。确定问题及高置信度建议已直接修正到原始 JSON、Pen 和 PNG，并上传 App Store Connect。最新 3.2.3 草稿回读：50 个 Description、49 套 343 张 iPhone 截图全部匹配；vi／ja／pa-IN 的初次验证异常已解决。详见 [最终核验](../app-store-copy-fix-20261003/final-verification.json)。

2026-10-03 · iScoreboard／全能计分器 · App Store 3.3 · app ID 6759768784

已逐文件审读 50 个语言的 Description、副标题及启用标题；逐张检视本批 48 个语言共 336 张 PNG 的营销标题。生成 50 份独立语言报告，保留原文、建议、置信度和文件定位。

## 本轮结论

- 3 个语言的 Description 需修正：fr-FR、fr-CA、ur-PK。法语法律标签补冒号前不换行空格；乌尔都语改正“支持该功能的项目”的表达。
- 6 个语言共 12 张 PNG 存在确定排版问题：el、ml-IN、ms、ta-IN、uk、ur-PK。希腊语 7 张处理全大写重音，乌尔都语第 3 张修正 RTL 数字顺序，其余为首图词内断行。
- 日语首图「得 / 点」列为可读性优化。日语一般汉字之间可换行，不按西方单词规则判为拼写错误。
- 全部 50 个 Description 与当前线上草稿完全一致，均为 7 个段落、3 个独立完整 URL。结构、长度和副标题检查通过；其余优化/待确认项见逐语言报告。

本轮未修改源文案、Pen、PNG 或 App Store 内容。先前截图上传的技术验证通过，仍需处理本报告中的文案／排版问题。

## 需要修正的项

| 语言 | 位置 | 问题与处理方向 |
| --- | --- | --- |
| [fr-FR](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/fr-FR.md) | Description（fr-CA 同样） | 三个法律标签的冒号前补 U+00A0；URL 继续独立成行。 |
| [fr-CA](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/fr-CA.md) | Description | 同上。 |
| [ur-PK](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ur-PK.md) | Description；03-catalog.png | 支持范围表达不准；26 落在 RTL 句子的错误一端。修正段落方向，RLM 候选方案须重新渲染验证。 |
| [el](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/el.md) | 七张 PNG 标题 | 全大写希腊语删除普通 tonos，保留需要的分音符；不改正常大小写 JSON 的重音。 |
| [uk](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/uk.md) | 01-slogan.png | ВАЖЛИВЕ 被拆为 ВАЖЛИВ / Е。 |
| [ms](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ms.md) | 01-slogan.png | BERMAKNA 被拆为 BERMAKN / A。 |
| [ml-IN](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ml-IN.md) | 01-slogan.png | പോയിന്റും、പ്രധാനമാണ് 词内自动断行。 |
| [ta-IN](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ta-IN.md) | 01-slogan.png | ஒவ்வொரு、புள்ளியும் 被拆开。 |

法语依据：[OQLF 两点号规范](https://vitrinelinguistique.oqlf.gouv.qc.ca/23325/la-ponctuation/deux-points/emplois-courants-du-deux-points)。希腊语依据：[官方现代希腊语语法 3.2](https://ebooks.edu.gr/ebooks/v/html/8547/2334/Grammatiki-Neas-Ellinikis-Glossas_A-B-G-Gymnasiou_html-apli/index_B_03.html)。日语分类依据：[W3C JLREQ](https://www.w3.org/TR/jlreq/)。

## 每个语言的独立报告

| 语言代码 | 语言 | Description | Slogan | 其他标题 | 完整报告 |
| --- | --- | --- | --- | --- | --- |
| ar-SA | Arabic | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ar-SA.md) |
| bn-BD | Bengali | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/bn-BD.md) |
| ca | Catalan | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ca.md) |
| cs | Czech | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/cs.md) |
| da | Danish | 有优化建议 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/da.md) |
| de-DE | German | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/de-DE.md) |
| el | Greek | 未见问题 | 需修正 | 需修正 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/el.md) |
| en-AU | English (Australia) | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/en-AU.md) |
| en-CA | English (Canada) | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/en-CA.md) |
| en-GB | English (U.K.) | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/en-GB.md) |
| en-US | English (U.S.) | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/en-US.md) |
| es-ES | Spanish (Spain) | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/es-ES.md) |
| es-MX | Spanish (Mexico) | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/es-MX.md) |
| fi | Finnish | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/fi.md) |
| fr-CA | French (Canada) | 需修正 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/fr-CA.md) |
| fr-FR | French | 需修正 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/fr-FR.md) |
| gu-IN | Gujarati | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/gu-IN.md) |
| he | Hebrew | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/he.md) |
| hi | Hindi | 未见问题 | 有优化建议 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/hi.md) |
| hr | Croatian | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/hr.md) |
| hu | Hungarian | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/hu.md) |
| id | Indonesian | 有优化建议 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/id.md) |
| it | Italian | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/it.md) |
| ja | Japanese | 未见问题 | 有优化建议 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ja.md) |
| kn-IN | Kannada | 未见问题 | 未见问题 | 待母语确认 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/kn-IN.md) |
| ko | Korean | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ko.md) |
| ml-IN | Malayalam | 未见问题 | 需修正 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ml-IN.md) |
| mr-IN | Marathi | 未见问题 | 有优化建议 | 待母语确认 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/mr-IN.md) |
| ms | Malay | 有优化建议 | 需修正 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ms.md) |
| nl-NL | Dutch | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/nl-NL.md) |
| no | Norwegian | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/no.md) |
| or-IN | Oriya | 未见问题 | 未见问题 | 待母语确认 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/or-IN.md) |
| pa-IN | Punjabi | 未见问题 | 有优化建议 | 待母语确认 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/pa-IN.md) |
| pl | Polish | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/pl.md) |
| pt-BR | Portuguese (Brazil) | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/pt-BR.md) |
| pt-PT | Portuguese (Portugal) | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/pt-PT.md) |
| ro | Romanian | 未见问题 | 未见问题 | 有优化建议 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ro.md) |
| ru | Russian | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ru.md) |
| sk | Slovak | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/sk.md) |
| sl-SI | Slovenian | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/sl-SI.md) |
| sv | Swedish | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/sv.md) |
| ta-IN | Tamil | 未见问题 | 需修正 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ta-IN.md) |
| te-IN | Telugu | 未见问题 | 未见问题 | 待母语确认 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/te-IN.md) |
| th | Thai | 有优化建议 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/th.md) |
| tr | Turkish | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/tr.md) |
| uk | Ukrainian | 未见问题 | 需修正 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/uk.md) |
| ur-PK | Urdu | 需修正 | 未见问题 | 需修正 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/ur-PK.md) |
| vi | Vietnamese | 有优化建议 | 有优化建议 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/vi.md) |
| zh-Hans | Chinese (Simplified) | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/zh-Hans.md) |
| zh-Hant | Chinese (Traditional) | 未见问题 | 未见问题 | 未见问题 | [查看](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/locales/zh-Hant.md) |

zh-Hans／zh-Hant 为 JSON 文案审校，不属于本批 48 套 PNG，未检查中文截图的实际自动换行。

## 证据与复核范围

- [机器可读合并报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.json)：全部 50 个语言、old/new、置信度及原图链接。
- [结构检查](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/structural-audit.json)、[当前线上 Description 快照](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/live-descriptions-before.json)、[功能范围核对](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/feature-facts.json)。
- 首图实际渲染总览：1（已于2026-10-04清理） / 2（已于2026-10-04清理） / 3（已于2026-10-04清理）。
- 区域独立记录：[western](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/western.json) / [central](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/central.json) / [asia](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/asia.json)。合并报告对日语断行作独立分类调整，以合并报告为准。

本轮检查营销文案及标题，不含截图内整个游戏 UI 的逐字审校。功能说明对照当前代码与目录，未重新做设备操作测试。PASS 表示本轮未发现问题；需母语确认的表达单独标记。
