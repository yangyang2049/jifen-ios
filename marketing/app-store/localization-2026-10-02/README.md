# App Store 全语言本地化准备 · 2026-10-02

> **状态索引（2026-10-04 离线自检）。** 现有 2026-10-03 上传记录对应同一版本 ID 的 **iOS 3.2.3** 草稿：文本 50 个商店语言／地区；iPhone 截图 49 套、343 张；iPad 素材 49 套、245 张，均排除已有简中截图的替换。依据 [文本与 iPhone 上传状态](upload-state.json)、[iPad 说明](../ipad-screenshots-2026-10-03/README.md) 及相应 manifest／历史上传报告。本次仅对照本地记录，没有在线回读、上传、选择构建、提审或发布；不将历史上传成功视作本次修复已进入旧发行包。下文 3.3、尚未制作截图等描述属于早期流程；最终状态以上述入口及截图包的后续完成记录为准。

工程界面资源是 47 套，运动语音资源是 46 套；文本 50 套包括四个英语地区版本，截图 49 套另排除简中，三者的统计范围不同。

已准备 Apple 当前支持的全部 **50 个商店语言／地区**，对应工程的 47 个 iOS 本地化目录。英文包含美国、英国、加拿大、澳大利亚四个地区；法语、西班牙语、葡萄牙语分别保留地区版本。

每个语言都包含：

- 名称：简体中文为 `全能计分器`，繁体中文为 `全能計分器`，均不加品牌前缀或冒号；其他语言使用 `iScoreboard: ` 前缀，后接本地化名称。
- 副标题：完整本地化，不加品牌前缀。
- Description：完整本地化的纯文本描述，覆盖计分、规则设置、记录复盘、计时、大屏／远程看分及工具；正文按现有工程功能新写；后续读取了线上 3.2.2 描述，保留其中使用条款、隐私政策和 Apple EULA 链接，并本地化链接标题。
- 截图 Title：按现有 `slogan / score / catalog / recap / setup / timer / cast / watch / tools` 卡片 ID 整理，保留建议换行。英文、简体中文原有标题原样保留，简体中文补了一张 slogan 的标题。

所有翻译仍是待审阅草稿。`reviewStatus: draft` 表示尚未逐语言由母语用户确认，字符校验通过不等于文案或截图视觉审核通过。

2026-10-03 中文名称修正：简体为 `全能计分器`，繁体为 `全能計分器`，长度均为 5 字；对照表、CSV、聚合 JSON 和 API 模板已同步，校验规则明确排除中文名称的品牌前缀。App Store Connect 草稿回读确认这两个名称已一致，其他字段保持原值，见 [名称核对报告](../../../artifacts/app-store-chinese-name-fix-20261003/verification.json)。

2026-10-02 19:38（北京时间）已通过公开 API 将全部 50 个语言的名称、副标题、Description 写入 **iOS 3.3 / Prepare for Submission** 草稿，重新读取确认 150 个文本字段与本地 JSON 完全一致，两类语言列表均为 50 个。没有提交审核或发布，也没有上传新截图。原有两种语言的其他字段保持原值；新增语言补充同一个现有支持网址，关键词、版本更新说明和截图本地化尚未处理。详见 [上传状态](upload-state.json) 和 [API 核对报告](../../../artifacts/app-store-localization-20261002/upload-report.json)。

## 文件入口

| 文件 | 用途 |
| --- | --- |
| [names-and-subtitles.md](names-and-subtitles.md) | 50 个语言的名称／副标题对照，优先看这个 |
| [copy-review.md](copy-review.md) | 每个语言的完整描述、截图标题与使用状态 |
| [names-and-subtitles.csv](names-and-subtitles.csv) | 可在表格软件中逐语言筛选的名称／副标题对照 |
| [locales/](locales/) | **文案编辑源**：每个商店 locale 一个 JSON |
| [metadata.json](metadata.json) | 聚合全部文案，便于后续 API 程序读取 |
| [screenshot-titles.json](screenshot-titles.json) | 独立截图标题包，供后续出图程序按卡片 ID 合并 |
| [locale-map.json](locale-map.json) | Apple 商店代码 ↔ iOS 语言目录的完整映射 |
| [api-requests.template.json](api-requests.template.json) | 100 个离线 POST 请求模板，父资源 ID 为显式占位符 |
| [validation-report.json](validation-report.json) | 50 个语言的字符长度及卡片完整性结果 |
| [upload-state.json](upload-state.json) | 已有 2026-10-03 记录的 3.2.3 草稿字段及 49 套 iPhone 截图状态 |

字段结构示例：

```json
{
  "locale": "ja",
  "iosLocale": "ja",
  "direction": "ltr",
  "reviewStatus": "draft",
  "name": "iScoreboard: 万能スコアボード",
  "subtitle": "得点記録・試合タイマー・振り返り",
  "description": "纯文本，段落用换行分隔",
  "screenshotTitles": [
    {"id": "score", "title": "試合のスコアが\nひと目でわかる", "enabled": true}
  ]
}
```

上面只演示字段，实际 JSON 含完整描述及 9 个卡片标题。修改 `locales/<ASC-locale>.json` 后重新生成聚合文件和对照文档：

```sh
python3 marketing/app-store/localization-2026-10-02/validate.py --refresh
python3 marketing/app-store/localization-2026-10-02/validate.py
python3 marketing/app-store/localization-2026-10-02/export_api_payloads.py \
  --out marketing/app-store/localization-2026-10-02/api-requests.template.json
```

校验范围：50 个 locale 的覆盖、固定品牌前缀、名称／副标题 ≤30、描述 ≤4000、JSON 重复键、标题卡片完整性、RTL 方向、历史 Watch 禁用标记以及中英文源标题一致性。长度同时记录 Unicode 码点和 UTF-16 单元，按较保守的 UTF-16 值判定。

## 后续 API 对接

本仓库是 iOS 工程，此包按 **App Store Connect API（Apple）** 准备。用户提到的 AppGallery Connect 是 Huawei 平台；如果后续还要华为商店，可以复用文本，但需另做字段和语言代码适配。

名称／副标题写 `appInfoLocalizations`，描述写 `appStoreVersionLocalizations`。两类资源分别有自己的本地化 ID，不能用 App Apple ID 代替。新增使用 POST，已有语言使用 PATCH。

导出脚本只生成离线请求，不读取凭证、不调用网络。获取可编辑 AppInfo、AppStoreVersion 和现有语言资源 ID 后：

```sh
python3 marketing/app-store/localization-2026-10-02/export_api_payloads.py \
  --app-info-id '<实际 AppInfo ID>' \
  --version-id '<实际 AppStoreVersion ID>' \
  --existing-ids /tmp/existing-localization-ids.json \
  --out /tmp/app-store-localization-requests.json
```

`existing-localization-ids.json` 的格式：

```json
{
  "appInfoLocalizations": {"zh-Hans": "实际名称本地化资源 ID"},
  "appStoreVersionLocalizations": {"zh-Hans": "实际版本本地化资源 ID"}
}
```

可加 `--locale ja --locale en-US` 仅导出指定语言。生成结果的每条 `body` 才是 API 请求正文；外层的 `scope`、`notes` 和 `requests` 是本地管理字段，不传给 API。

请求仅包含本次准备的名称、副标题和描述。已有关键词、支持网址、隐私网址、推广文字、版本更新说明保持原值；新增语言要在提审前按要求补齐这些字段，并核对 AppInfo 与版本的语言集合一致。线上名称可用性和商店可编辑状态需要实际调用时确认。

## 截图后续处理

目前只翻译 **Title**，未替换截图里的 App 画面、其他小字或辅助文案，也未渲染新商店图。`\n` 是建议断行，长文字和阿拉伯语／希伯来语／乌尔都语还需要选字体并检查排版。`screenshot-titles.json` 按 `locale` 和卡片 `id` 合并入现有 renderer 的 `cards`；API 接收最终图片，截图标题不是商店文本 API 字段。

当前 iOS target 已移除 Apple Watch 支持，源图文案仍留有 Watch 卡片。因此全部 50 个语言的 `watch` 标题均保留翻译，但标记 `enabled: false`，不得在当前版本出图／上传。共翻译 450 个标题，其中 400 个可用于后续截图制作，50 个是历史 Watch 文案。工具卡虽有翻译，仍要补对应源图。现有英文／中文素材目录保持原样。

日语截图玩家姓名仍可沿用现有方向：`伊達政宗 / 真田幸村` 等，见 [现有截图说明](../2026-09/README.md)；本次没有改截图中的姓名。

## 已核对的 Apple 官方资料

- [全部商店语言及 API locale shortcodes](https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes)
- [名称和副标题：最多 30 字符](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Description：纯文本，最多 4000 字符](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [创建名称／副标题本地化](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-appinfolocalizations)、[修改名称／副标题本地化](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appinfolocalizations-_id_)
- [创建描述本地化](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-appstoreversionlocalizations)、[修改描述本地化](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstoreversionlocalizations-_id_)

2026-10-02 已读取官方完整代码表。特别注意：`de-DE`、`bn-BD`、`gu-IN`、`kn-IN`、`ml-IN`、`mr-IN`、`or-IN`、`pa-IN`、`sl-SI`、`ta-IN`、`te-IN`、`ur-PK` 与 iOS 目录代码不同；挪威语为 `no`（iOS 目录 `nb`）。乌尔都语目前已受支持。

## 已完成的 API 上传与密钥位置

按用户要求创建了 Admin 团队密钥 `iScoreboard-localization`，可供该团队其他应用复用。私钥统一保存在：

`/Users/yangyang/Documents/CERTIFICATES/AuthKey_VW87YVJ355.p8`

同目录的 `AppStoreConnect_iScoreboard-localization.json` 保存 Key ID、Issuer ID、角色和私钥文件名；不包含私钥正文。`.p8` 权限为 `0600`，未进入仓库。

实际上传程序为 [scripts/app_store_localization.py](../../../scripts/app_store_localization.py)，默认只读取和导出计划；加 `--apply` 才写入。它会校验 App ID 对应的 Bundle ID 和版本编辑状态，备份当前资料、按语言进行新增或更新，并重新读取逐字段核对。不会调用提审、发布、删除或截图上传接口。可用参数见 `python3 scripts/app_store_localization.py --help`。运行需要已有的 `requests` 与 `cryptography` Python 库。

实际 API 行为补充：新增名称语言时，Apple 可能自动生成同语言的版本记录。上传程序在名称新增后读取版本语言 ID，再写描述；若返回 locale 重复错误，也会重新读取并更新既有记录，避免重复新增。

本次修改前后的数据与运行报告在 `artifacts/app-store-localization-20261002/`。初次只有 `en-US / zh-Hans` 的备份也已保留。
# 3.3 发布资料补充（2026-10-02）

本次候选包为 **iOS 3.3（61）**：包含 47 套界面本地化及 46 套运动语音资源；小组和新麻将计分板暂缓，当前包不包含 Watch App。

[更新说明及关键词](release-fields-3.3.md) 已准备全部 50 个商店语言，并写入 3.3 的 Prepare for Submission 草稿。100 个字段回读一致，其余版本字段保持不变；当前名称、副标题、Description、更新说明、关键词五类文本均已本地化。关键词来自实际包含项目的已审校 App 名称，不包含旧英文关键词中的 cricket、baseball、racquetball 或 darts 等未实现项目。文案未经母语人员另行审校。

本轮未上传新商店截图、未上传新构建、未提交审核或发布。签名包与发布检查详见 [发布说明](../../../docs/ios_3_3_release_candidate_2026-10-02.md)。后文 19:38 的“更新说明和关键词未处理”是首次文本上传的历史状态，以本补充和 `upload-state.json` 为准。

## 截图上传完成（2026-10-03）

2026-10-03 00:13（北京时间）已把 48 个非中文语言／地区的完整第 1–7 张共 **336 张截图** 上传到同一 iOS 3.3 草稿的 Store Localization。Apple 处理状态全部为 `COMPLETE`；逐图 MD5、尺寸、大小和顺序回读通过，50 套文本字段与版本状态不变。en-US 整套替换，简繁中文及现有 iPad／Watch 素材保留。未提交审核或发布。

[截图材料及上传说明](../ios-screenshots-pen-2026-10-02/README.md) · [核验报告](../../../artifacts/app-store-screenshots-20261002/verification-report.json)。前文“未上传新截图”为先前文本上传时点的历史记录，以本节和 `upload-state.json` 的截图状态为准。

## 文案修正与最终回读完成（2026-10-03）

已直接修正原始材料并上传：8 个语言的 Description、15 个语言共 23 张营销标题截图，JSON／Pen／PNG 同步。vi、ja、pa-IN 的初次截图验证异常已解决。

同一个版本 ID `a118dc62-4303-4c03-ae92-b358c60438d5` 当前显示 **iOS 3.2.3**，状态仍为 `PREPARE_FOR_SUBMISSION`。最新回读 50 个 Description 与原稿一致，49 个语言共 343 张 iPhone 截图全部为 `COMPLETE`，MD5、尺寸、大小及 1–7 顺序均与当前原稿一致。其他任务后续补入的繁体中文和 24 张目录标题更新已保留。原先 3.3／48 套／336 张的记录是历史时点。

Google Play 已有独立任务处理，本任务未重复上传。未提交审核或发布。

[最终核验](../../../artifacts/app-store-copy-fix-20261003/final-verification.json) · 修订截图预览 1（已于2026-10-04清理） · 预览 2（已于2026-10-04清理）。
