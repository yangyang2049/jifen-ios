# iScoreboard Google Play 本地化材料 · 2026-10-02

> 2026-10-04 清理说明：旧图像/画布备份、过程预览、运行日志及重复交付 ZIP 已清理；当前 `exports/` 定稿、Pen 模板、素材、字体/许可证、文案、上传记录和流程脚本均保留。下文旧预览、备份和 ZIP 路径属于历史操作记录。

> **最终材料索引（2026-10-04 离线自检）。** [现有 metadata](metadata.json) 有 **50 套**本地材料，包含 zh-CN 及不可上传的奥里亚语草稿；其中 **49 套可上传、343 张**，完整本地画布为 350 张。已有 2026-10-03 提交及独立回读记录见 [最终 API 报告](api-verification.json) 和 [简中及 UI 上传报告](zh-cn-and-localized-ui-upload-verification.json)。下文 48／47 套、临时 edit 未 commit、简繁中文未生成等是早期过程；以文末“简体中文及全部截图正式上传”为最终记录。本次仅离线对照，没有重新上传、commit 或在线回读，未确认商店公开展示或审核状态。

`play_api.py` 默认只做本地计划，`--stage` 创建临时编辑，只有显式 `--commit` 才提交；历史段落的“不会 commit”不代表现有脚本没有此能力。已过期或已提交的历史 edit 不用于恢复新的上传。

包名 `com.bolo.jifen`，开发者 ID `6102652090463005491`。默认英语 `en-US`。

## 交付文件

- `metadata.json`：50 份名称、简短描述、完整描述；其中 49 份可上传（包含 zh-CN），奥里亚语仅保留草稿。
- `locales/*.json`：逐语言文案；`names-and-descriptions.csv` 便于对照。
- `copy.json`：7 张图的营销标题、第一页标语、字体、示例姓名。
- `locale-map.json`：App Store → Google Play 语言代码映射。
- `iScoreboard-GooglePlay-localized.pen`：独立的可编辑 Pen 文档；最终本地材料 50×7 张，早期制作时为 48×7 张。
- `exports/<language>/01.png` 至 `07.png`：按顺序上传的 RGB PNG。
- `fonts/`：21 个开源字体文件、各自 OFL 1.1 许可证。
- `layout-adjustments.json`：针对窄画幅的字号和人工换行；保留原文含义。
- `auth-status.json`：当前账户、Cloud 项目和 API 配置检查结果，不含私钥。
- `api-verification.json`：已有 2026-10-03 的 49 个语言、343 张图提交及独立回读记录。
- `play_api.py`：本地检查、读取线上备份、创建临时 API 编辑；显式 `--commit` 可提交编辑。

## 素材来源与适配范围

Figma `鸿蒙`，页面 `全能计分器`，`Style02-googleplay` (`1358:51`)；7 个 frame 均为 1080×1920，即竖版 9:16。英文原图来自下载目录 `鸿蒙 (6) 2/GP-SCREENSHOTS01.png` 至 `07.png`，也与 Play Console 当前 7 张英文图的文件名吻合。原文件和 SHA-256 见 `source/source-manifest.json`。

Figma MCP 免费额度已耗尽，因此本轮未写入 Figma，使用独立 Pen 文档生成。主线程的 iOS/Pen 文档未切换或修改。背景为原英文图；营销标题、第一页标语、第二/第三张示例姓名及第六/七张篮球队名均是可编辑文字。原图中其余应用 UI 仍为英语，包括第四/第五张界面和第六张非篮球计分板姓名。篮球队名已在第六张篮球、第七张电视及手机上本地化，使用原生可编辑文字和与原画面同色的遮盖层。本轮没有重新操作 Android 应用截取本地化 UI。

沿用 iOS 的文案和已选人物。简体、繁体中文未生成；奥里亚语不在 Google Play 官方语言列表中，因此 API 默认排除。西语墨西哥映射至 `es-419`；其他映射参见 `locale-map.json`。

商店名称遵循本次要求：`iScoreboard: ` 后接本地化内容。描述替换为 Android 手机/平板，删除 Apple EULA 链接；当前 Google Play Android 构建关闭账号、后端和远程同步，因此删除“分享比赛码远程看分”的承诺，保留大屏展示。所有文案仍标为 `adapted-draft`；API 临时上传校验不代表已完成最终文案校阅。

## Google Play API 凭据

Google Cloud 项目 `pc-api-6102652090463005491-968` 已启用 Google Play Android Developer API。用户已创建 `store-localization@pc-api-6102652090463005491-968.iam.gserviceaccount.com`，手动下载 JSON 私钥，并在 Play Console 授权。实账号 OAuth、创建编辑和读取 `com.bolo.jifen` 的权限测试均已通过；本轮未验证其他应用或未来应用的权限。

私钥目前位于用户下载目录，未复制到本素材目录、Git 或交付 ZIP。上传使用服务账号 JSON 私钥换取短期 OAuth access token，scope 为 `https://www.googleapis.com/auth/androidpublisher`。不使用 iOS `.p8`、APK/AAB 签名证书或 Firebase `google-services.json`。凭据文件、JWT 和 access token 不写入报告。

## 检查与上传

```sh
python3 play_api.py
python3 play_api.py --credentials /absolute/path/service-account.json --inspect --locales en-US
python3 play_api.py --credentials /absolute/path/service-account.json --stage --workers 3
python3 play_api.py --credentials /absolute/path/service-account.json --stage --resume --workers 3
```

默认只做本地检查，输出 `upload-plan.json`。`--inspect` 创建临时 edit、读取并备份现有文案/图片元数据，然后删除该临时 edit。`--stage` 在临时 edit 中更新文案和 7 张图并 validate，保存 edit ID 与完成情况，不 commit、不送审。临时 edit 会过期，并且 Console 的其他操作可能使 edit 失效；正式上传需要明确决定如何提交该 edit。实账号联调已通过。2026-10-03T00:21:43+08:00 已在临时编辑中上传并校验 47 个语言、329 张图；逐语言文案回读、图片数量/顺序/SHA-256 均匹配，Google Play validate 成功。报告见 `api-verification.json`。该编辑尚未 commit 或送审，预计于 2026-10-03T02:03:15+08:00 过期；临时编辑并不是永久保存在 Console 中的草稿。过期后需重新上传，本地交付素材永久保留。原有线上英语文案和 7 张图元数据已备份到本目录 gitignore 的 `console-backup-*.json`。`--resume` 恢复未过期编辑；已完成语言重新核对，未完成语言清空临时截图后重传；多个语言可并行处理，失败语言随后串行重试。

脚本运行需要 Python 3、Pillow、cryptography。生成原生 Pen 使用官方 `@pen.dev/cli` 的 headless 模式，字体预览通过本目录本地 HTTP 服务读取；`offline-fonts.mjs` 仅将默认 Google 字体下载解析为已导入的 OFL 字体，其他网络请求不变。生成后的 Pen 文件使用本地相对字体路径，可与本目录一起移动。

仅更改本目录的营销素材和辅助脚本，未更改应用源码，未运行 iOS/Android 编译。API 临时编辑不会修改线上商店资料；本轮没有 commit、发布或送审。

## 官方依据

- [设置 Google Play Developer API](https://developers.google.com/android-publisher/getting_started?hl=en)
- [Play Console 用户权限](https://support.google.com/googleplay/android-developer/answer/9844686?hl=en)
- [Google Play 支持语言](https://support.google.com/googleplay/android-developer/answer/9844778?hl=en)
- [商店资料字段长度](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en)
- [预览素材和截图规格](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
- [上传图片 API](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.images/upload)

## 篮球队名修订（2026-10-03）

48 个语言／地区的第 6、7 张共 96 张图更新。队名沿用 iOS 已采用的 Home / Away 本地化译法（`basketball-teams.json`），不使用个人姓名。第 6 张篮球、第 7 张电视和手持手机采用相同队名；电视原生文字从 y=630 上移到 y=576，共 54 像素，对应 iOS 上移 64 像素的画幅比例。手机队名沿原手机的 15.8 度倾斜方向排列，长队名适当缩小字号。

这次使用 Pen MCP 原生文档接口修改和导出，未重新截取应用 UI。`pen-nodes-snapshot.json` 是接口导出的节点快照，供验证脚本使用；维护时先从接口刷新该快照，不直接读取 `.pen` 文件结构。`basketball-update-template.js` 与 `basketball-teams.json` 保存本轮修改依据，`preview-basketball-update.png` 可直接预览第 6/7 张主要语言。

验证覆盖 288 个篮球队名图层；无缺字、剪裁或溢出问题。第 1–5 张共 240 张保持原文件 SHA-256；第 6/7 张除批准的队名文字与遮盖区域外，原画面保持不变。四人计分等非篮球场景仍保留原选手名字。修订前的 96 张图和节点快照保存在 gitignore 的 `before-basketball-teams/`。

`refresh_basketball_api.py` 只替换未过期临时编辑中的第 6、7 张，通过图片 ID 删除旧尾部再顺序追加，保留第 1–5 张和名称／描述，并回读 SHA-256 与顺序；永远不会 commit。同步结果见 `api-verification.json`。

本轮 API 同步完成于 2026-10-03T00:46:01.659112+08:00：47 个可上传语言的 94 张第 6/7 张已替换，235 张第 1–5 张和全部名称／描述保留；全部 329 张截图的顺序和 SHA-256 回读匹配，再次 validate 成功。仍为未 commit、未送审的临时编辑，预计 2026-10-03T02:03:15+08:00 过期。

## Google Play 本地化自检（2026-10-03）

逐一检查 48 个语言／地区的名称、简短描述、完整描述和 7 张截图的可编辑文案；不读取 iOS 正在自检的新结果，也不修改 iOS 素材。保留完整描述的正常段落和政策链接换行，确认没有把 `\\n` 误当文字显示、控制字符、空白段落或名称／简短描述中的换行。条款和隐私链接均通过 HTTP 200 检查。

直接修复丹麦语魔方计时的含糊术语、泰语匹克球拼写及多余空格、两个法语地区的冒号间距。截图修复印尼语和匈牙利语的多人／桌游术语，以及 8 个南亚语言标题缺失的名词；越南语、印地语、旁遮普语、马拉地语和斯洛伐克语首页按完整短语重新断行。共重新导出 15 张截图，其余 321 张文件 SHA-256 保持一致。`copy.json` 中遗留的平台／尺寸字段已修正为 Google Play、1080×1920。

336 个营销标题／标语均通过原生 Pen 动态高度测量，无意外增加行数或文字框高度溢出；所有 336 张图通过字形、规格和批准文字区域以外的像素检查。字号依实际字形宽度调整，保留既有篮球队名和电视姓名位置。审校明细见 `self-audit-fixes.json`，逐语言检查记录与限制见 `self-audit-report.json`，修改预览见 `preview-self-audit.png`。这是一轮逐语言自检，不等同于独立母语编辑认证。原有图片内嵌的应用 UI 和非篮球示例姓名仍为英语，未扩展到重新截取应用 UI。

`refresh_self_audit_api.py` 只同步当前未过期临时编辑。中间顺序位置的图片变更会保留不变前缀、重传后缀，再校验 47 个语言的文字及 329 张图顺序／SHA-256；不调用 commit。当前同步状态及过期时间以 `api-verification.json` 为准。自检前材料保存在 gitignore 的 `before-self-audit/`，交付 ZIP 不含私钥、临时编辑状态或备份。

自检修订 API 同步完成于 2026-10-03T01:07:59.417293+08:00：4 个语言描述和 14 张可上传截图已更新；为保持原图顺序重传了 47 张有序后缀图片。全部 47 个语言／329 张图回读匹配，Google Play validate 成功，未 commit、未送审；临时编辑过期时间仍为 2026-10-03T02:03:15+08:00。奥里亚语修改仅保存本地。

## 标题缩短与繁体居中修订（2026-10-03）

第三张图 6 个语言（ru-RU、fr-FR、fr-CA、pl-PL、ml-IN、ta-IN）标题超宽被原生渲染自动折成 3 行。按"先缩短文字、再调字号"处理：俄语首行改为 `26+ ДИСЦИПЛИН` 保持 96；两个法语地区统一为 `UN TABLEAU DE SCORES` 并降到 84；波兰语改为 `26+ DYSCYPLIN / JEDNA TABLICA` 保持 96；马拉雅拉姆语和泰米尔语保留原文降到 82，与各自语言族字号一致。其他页面特别长的 3 行小字标题一并精简为 2 行：德语第 7 张 `AUF DEM FERNSEHER`（96）、马来语第 6 张 `BERBILANG PEMAIN / DAN PAPAN PERMAINAN`（84）、马拉雅拉姆语第 6/7 张（78/96）、泰米尔语第 4/6 张（82/68）。共更新 12 个标题，`layout-adjustments.json` 已同步；脚本 `shorten_long_titles_gp.py`，全部行宽经 HarfBuzz 实测 ≤ 970px。

zh-TW 的 15 个文字图层原为 `fixed-width` 加手调 y（其余 47 个语言为 `fixed-width-height` 垂直居中），导致第 1 张"每一分都值得"纵向不居中、选手名/队名偏离原生位置。已按 en-US 逐卡归一 growth/height/valign/y 并重导 7 张；繁体字体核查为 Noto Sans TC（OFL 可变字重），即港台通用开源字体，无需更换。脚本 `center_zhtw_gp.py`。

9 个受影响语言（63 张）已重传至新临时编辑 `10534647243502416432` 并 validate，回读顺序/SHA-256 匹配；仍未 commit、未送审，过期后需重传。修改前 .pen 备份在 `artifacts/google-play-copy-fix-20261003/before-zhtw-centering/`。英语与中文（zh-TW 文案）未改动。

## 繁体首页标语补全并正式上传（2026-10-03）

zh-TW 第 1 张标语按简体对应补全为「每一分都值得 / 每一場都精彩」(108pt,HarfBuzz 实测行宽 648 ≤ 650,纵向居中不变);脚本 `update_zhtw_slogan_gp.py`,修改前备份在 `artifacts/google-play-copy-fix-20261003/before-zhtw-slogan/`。繁体字体确认为 Noto Sans TC,即思源黑体的 Google 同源版本,按要求无需另换。

`play_api.py` 新增显式 `--commit`(默认仍不 commit)。9 个语言、63 张图 stage + validate 后正式 commit(edit `11873797954184038618`),Google Play 线上已生效;`api-edit-state.json` 记录 `committed=true`。

## 画布按区域／语族分区（2026-10-03）

`group_sections_pen.py` 把 Pen 画布 49 行截图重排为 9 个带分隔标题条的分区（横条底色取自背景蓝，文字为 Noto Sans TC 粗体；因文档唯一中文字体是 TC,标题用繁体字形）：英語區 4、東亞區 3、東南亞區 4、南亞區 11（含本地专用的奥里亚语）、西亞區 3、日耳曼語族 5、拉丁語族 9、斯拉夫語族 7、歐洲其他語言 3。只改帧坐标、新增分隔帧与 children 顺序，不改动任何截图内容和导出文件；脚本可重复运行（旧分隔条自动清理），分区前备份在 `artifacts/google-play-copy-fix-20261003/before-section-groups/`。iOS 同步处理（备份 `artifacts/ios-screenshots-20261002/before-section-groups/`）。

## 繁体首页标语定稿上传（2026-10-03）

用户在 Pen 桌面应用中把 zh-TW 第 1 张标语改为 4 行「每一分／都值得／每一場／都精彩」（144pt，实測每行 432px 无溢出）。通过 `pen interactive --app desktop` 直连运行中的应用 `save()` 把内存中的修改落盘，重导 `exports/zh-TW/01.png`，`play_api.py --stage --commit --locales zh-TW` 上传并 commit（edit `03986340040257843898`），已上线。iOS 由用户自行处理，未改动。

## 第 4／5 张应用界面本地化（2026-10-03）

本节替代前文“第四／第五张仍为英语 UI”的旧状态。处理 48 个可上传语言／地区，共 96 张 1080×1920 RGB PNG；不支持上传的奥里亚语草稿继续保留原图。只替换第 4 张的比分走势卡片、比赛详情手机内屏，以及第 5 张的羽毛球设置手机内屏。营销标题与其他图形沿用现有版本，第 1／2／3／6／7 张保持文件 SHA-256 不变。

示例姓名沿用 `copy.json` 已有的两个人名，在设置输入框、比赛详情及曲线图例中保持一致。通过仅安装在模拟器的 accessibility instrumentation helper 原生输入 Unicode；没有用位图覆盖英文名字或重新绘制本地化文字。比赛使用固定的乒乓球演示记录，三局两胜、2:1、每局 11 分；保存截图与 UI 层级验证证据，按当前原生位置截取完整曲线图例。阿拉伯语、希伯来语及乌尔都语保留原生 RTL 排列。

旧脚本在部分语言切换后仍显示英文：当前 Android 包没有全部商店语言的界面译文。此次从项目已有 iOS 翻译和当前 Google Play Android 译文生成**仅用于模拟器截图的资源样包**，补齐缺失的界面文案，并处理 Indonesian `in` / Hebrew `iw` 的 Android 资源别名。样包保留原 APK 的全部 35 个 dex 文件，签名证书与原调试包相同；仅资源重打包，未修改任一 Android/iOS 应用源码，未生成正式发布包。截图用补充译文尚未移植到 Google Play 正式应用；这轮素材完成不代表正式应用已增加 48 种界面语言。

维护入口：

- `prepare_capture_resources.py`：根据已有项目译文准备模拟器截图用资源；辅助 APK 和 accessibility helper 源码位于 gitignore 的 `tools/`。
- `capture_localized_gp.py`：逐语言重置演示数据库、验证实际界面语言和姓名，再截取设置页、详情页及完整走势图；SQLite WAL 必须 checkpoint 并关闭后才回写模拟器。
- `composite_localized_bg.py`：把原生截屏合成到 `assets/localized/<language>-04.png` / `-05.png`；不绘制文案。
- `capture-frame-snapshot.json`：通过 Pen MCP 导出的第 4／5 张原生节点快照。画布只更新这些帧的背景图片，标题仍可编辑。
- `finalize_capture_exports.py`：原生 Pen 导出后，保留旧导出图在批准应用 UI 区域以外的像素，避免字体渲染缓存差异造成额外变化。
- `verify_localized_ui.py` / `localized-ui-verification.json`：核对原生 UI 语言标签、Unicode 姓名、图像尺寸／模式、背景路径、批准像素区域、其他截图 SHA-256；更新图片清单并生成仅含 96 张变更截图的 ZIP。

本次未运行 Gradle：只处理截图资源、营销素材与工具脚本。截图样包资源编译、模拟器原生截图及变更范围检查替代应用构建验证。Google Play 上传状态以 `localized-ui-verification.json` 的 `googlePlayUploaded` 字段为准；本地文件生成与打包不代表已经上传。

## 简体中文及全部截图正式上传（2026-10-03）

新增本地 zh-CN：全能计分器／运动计分、比赛计时与赛后回顾，以及适配 Android 的完整描述；不包含 Apple 许可协议或未开放的远程分享承诺。7 张 RGB 1080×1920 图片使用 Noto Sans SC，第四／第五张来自真实简体 Android 界面；陈冠廷、林雅婷与曲线图例保持一致。第六张补齐四位玩家、主客队及第 4 节标签；第七张手机队名保持 15.8 度旋转。简体中文排在 East Asia 分区内，画布现为 50 个语言行、350 张（含不可上传的奥里亚语草稿 7 张）。可上传素材为 49 个语言、343 张。

上传前 Google Play 实际只有 11 个语言页面，zh-CN 页面尚无独立截图；此前其他语言的临时编辑没有永久保存。本次补齐缺少的 38 个语言页面，更新 zh-CN 文案和全套 7 张图，英语同步全套本地定稿；另外 9 个已有语言只替换第 4／5 张并保持第 1／2／3／6／7 张及原有商店文案。其他已有文案保持原样。

`upload_localized_ui.py` 在修改前备份全部文字和截图元数据，按 ID 删除旧图片并顺序追加；失败重试在未提交 edit 中进行。全部语言的文字、7 张图数量／顺序／SHA-256 校验通过后 validate，再显式 commit；另建只读 edit 回读全部 49 个页面和 343 张图，与本地定稿逐一匹配后删除该检查 edit。已提交商店资料更新；没有上传应用二进制、变更测试／正式轨道或发布新客户端。商店公开展示与审核状态未通过 Console 单独检查。

当前正式记录：`api-verification.json` 与 `zh-cn-and-localized-ui-upload-verification.json`；简体图检查见 `zh-cn-verification.json`，预览为 `preview-zh-CN.png`。历史 API 报告保存在 `source/*-before-ui-upload.json`，本节替代前文仍为临时编辑／未 commit 的状态。完整素材 ZIP 为 `package/google-play-49-locales-2026-10-03.zip`，不包含私钥、APK 或在线备份。

## 捕获证据与失败恢复（2026-10-04）

每次 `capture_localized_gp.py` 开始采集某个语言时，会先移除该语言的旧 `verification.json`。全部场景通过后，原子写入包含当前姓名、导航标签及六个原始 PNG/XML 文件 SHA-256 和大小的成功报告。合成与简中／其他语言最终验证都先核对这些证据；失败或只完成部分场景的采集不能沿用旧的成功标记。

旧报告缺少文件哈希时，须先用可信的既有快照确认六个原始文件，再显式离线升级；不能对来源不明的当前文件直接计算哈希并当作旧验证成功。升级命令必须同时提供 `--inventory` 和 `--backup-dir`，会先校验全部选定语言、备份旧报告，再改写报告元数据。inventory 为 JSON 数组，每项包含仓库相对 `file`、`bytes` 和 `sha256`；备份目录保留原仓库相对路径。该操作不采集、不改图片、不访问 Google Play。

本次 49 套旧报告的升级还以已自检交付背景为交叉依据：当前 raw 的内存重合成结果与 98 张原交付背景逐像素一致，交付背景哈希匹配自检快照；原始文件及交付 PNG 均未改变。证据与旧报告备份保存在仓库忽略的 `build/remediation-20261004/`。

验证：48 个旧语言的 96 张更新图通过原生 UI 标签、姓名、尺寸、Pen 路径及像素区域检查，247 张其他本地导出文件 SHA-256 保持一致；简体 7 张通过文案长度、原生 UI、字形外观、文字框边界及截图规格检查。辅助 Python 脚本语法检查通过。未运行 Gradle：本次只更新营销素材、商店文案和辅助工具，无应用代码改动。模拟器已恢复原 APK、演示数据库与原应用语言，输入 helper 已卸载。
