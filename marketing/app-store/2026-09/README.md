# 多语言 App Store 截图(2026-09)

截图即代码：文案在 `locales/<语言>.json`，版式在 `render.mjs`，源图在 `sources/`，无头 Chrome 渲染出 1320×2868 的 6.9 英寸 PNG。改文案只碰 JSON，不碰代码。

风格（2026-09-29 定稿：蓝色方案）：背景统一 `#0B61FB`。第 1 张为 slogan 卡（`layout: "slogan"`：纯色背景 + 超大标语 + 巨型比分水印 + 底部品牌名，无场景图，Sofascore 式首图）；第 2、3 张为手绘记分板大牌卡（实际比例约 1.13，描边分级、圆角、出血到画布边缘，Lucide 白色线性图标，发球三角 #30D158，红/蓝面板色取自 App 真实色值 #C62828/#007AFF）；第 7 张为投屏场景（手绘电视 + 带壳手机）；其余为真实截图。标题文案不带逗号句号。曾经的黑底双版本已弃用并删除。

截图里的状态栏（时间/电量/灵动岛）**不**由管线处理——源图先自行把状态栏区域涂成页面背景色再放进来。横屏图（basketball/go_timer）无状态栏。

英文标题 Poppins ExtraBold Italic 大写；中文标题优设标题黑（自带斜势，免费可商用），回退思源黑体 Black。字体在 `fonts/`（优设标题黑、Poppins、Noto Sans SC 均为可商用协议），渲染脚本自动检测注入 @font-face。

## 浅色主题源图抓取（2026-09-29 流程）

1. 模拟器强制浅色：`xcrun simctl ui <udid> appearance light` + `xcrun simctl spawn <udid> defaults write com.douhua.jifen.ios "jifen-v2.appAppearanceMode" light`（App 内置外观键，抓完记得删回）。
2. 营销 4 图：`xcodebuild test -only-testing:jifenUITests/FullAppScreenshotUITests/testCaptureAppStoreSourceScreenshots`（zh-Hans 由测试内 launchArguments 保证），附件从 xcresult 用 `xcresulttool export attachments` 导出，映射 sports / badminton_setup / basketball / go_timer。
3. 记录页：`xcrun simctl launch <udid> com.douhua.jifen.ios -UITestRecordFixtures -UITestRecordDetail pingpong` 后 `simctl io screenshot`（输出到 /tmp 再拷贝，直接写仓库目录会权限失败）。
4. 显示端快照：launch 参数 `-DisplaySnapshotFixture pingpong_live`，同样 simctl 截屏。
5. 横屏图（basketball/go_timer）无状态栏，不需盖条。

## 用法

```bash
node render.mjs                # 渲染 locales/ 下全部语言
node render.mjs --locale en    # 只渲染一个语言
open preview.html              # 所有语言并排总览
```

输出：`<语言>/01.png…`（每张同目录有对应 .html 可微调预览）。

## 卡片与源图

文案按 8 个重点页面组织（见 locales JSON 的 `cards`），顺序即上传顺序。源图缺失的卡片自动跳过并重新编号，目前缺 2 张：

| 卡片 | 需要的源图 | 怎么补 |
| --- | --- | --- |
| Apple Watch | `watch.png` | Watch App 模拟器截图 |
| 裁判小工具 | `tools.png` | 工具页 UI 测试截图 |

补齐后重跑 `node render.mjs` 即出满 8 张。

第 6 张投屏卡：电视画面按显示端 `DisplayTwoSideSurface` 的真实版式手绘（50/50 双面板、队名紧贴主分整体居中、顶部「第 N 节」+「犯规」浮层、底部时钟条「节次 | 比赛时间 | 进攻时间」，显示端无操控按钮），手机用 `sources/basketball.png` 真截图装进横置手机壳，两边比分/队名/时钟一致。想要像素级真实的电视画面，可给 `DisplaySnapshotFixture` 加一个 basketball fixture（该入口确实渲染在 iPhone 屏上，DEBUG only），截屏后替换手绘层。握持版备选文件为 `<语言>/cast-B.png`，默认出图不含手。

## 各语言源图

源图按**文件粒度**解析：先找 `sources-<code>/<文件>`（如 `sources-en/`），没有就回退共享 `sources/`。共享目录是简体中文 UI，所以回退即"这张语言包里混了中文画面"，渲染结束会按语言打印一份清单（zh-Hans 除外）。

英文源图用 UI 测试抓取（英文界面 + 有意义的队名/比分/时钟）：

```bash
xcrun simctl boot <iPhone 17 Pro Max UDID>        # 多台同名设备已 Booted 时先按 UDID 指定
xcodebuild test -project jifen.xcodeproj -scheme jifen -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:jifenUITests/FullAppScreenshotUITests/testCaptureAppStoreSourceScreenshotsEnglish \
  -resultBundlePath /tmp/en-capture.xcresult
# 截图是 XCTest 附件，落在 xcresult 里；UI 测试跑在模拟器沙盒内，
# 传 TEST_RUNNER_UITEST_SCREENSHOT_DIR 不会在宿主机产出文件，别指望它。
xcrun xcresulttool export attachments --path /tmp/en-capture.xcresult --output-path /tmp/en-att
# /tmp/en-att/manifest.json 是 [{attachments:[{exportedFileName, suggestedHumanReadableName}]}]
# 按 suggestedHumanReadableName 去掉 iPhone_marketing_en_ 前缀，拷进 sources-en/：
#   record_detail / tennis_setup / volleyball / snooker / uno_live / multi_live / chess / go_timer / basketball（均 .png）
```

场景与数据在 `FullAppScreenshotUITests.swift` 的「英文商店源图」一节：网球设置 Sam/Steven、排球 Home/Away 24:23、斯诺克 Sam/Steven、UNO Emma/Liam/Mia/Noah（实时计分板，不改夹具）、多人记分 Alex/Jordan/Mia、棋类计时两侧各真实走一段（交权要点**当前行棋方**那侧，点对面无效）、篮球 Home/Away 71:68 打到第四节（点节次胶囊选 Q4，再让比赛时钟真实跑 20s）。记录详情页用夹具 + `-UITestRecordTeamName1/2` 覆盖队名（`UITestRecordFixtures`，不传参仍是红/蓝方）。赛前设置的姓名框预填了占位名，必须 `clearTextField` 后退格清空再输入，否则截出 "Player ASam"；输入完 `dismissKeyboard()`（按 Home 回桌面再回前台）才能拍到无键盘的设置弹窗。

拼贴卡（第 5 张）现在是整齐斜排：等高行 + 统一倾角 + 左右出血由画布裁切。素材清单在 locale JSON 的 `card.tiles`（不给就用 `render.mjs` 的 `DEFAULT_TILES`），倾角/每行张数用 `card.collage = { tilt, perRow, bleed, gap }` 覆盖；`card5-B/C.png` 是倾角备选。素材尽量用横屏截图，竖屏图在同一行里会被压得很窄。

上传前核对：手机内画面语言必须和商店语言一致，比分数据用测试夹具，不用真实用户对局。

当前英文包里除 `sources-en/` 已抓到的图之外，仍来自共享 `sources/` 的会在渲染日志里点名——上传前把清单清零。

## 新增语言

1. 复制 `locales/en.json`，改 `code`（ASC 语言代码）、`eyebrow`（品牌名）、文案、字体栈。
2. 德/俄/法等文字比英文长 30%+，超长时渲染脚本会自动缩字号兜底；出图后仍要逐张看 `preview.html`。
3. 阿拉伯语/希伯来语是 RTL，`dir` 设为 `rtl` 后仅做了基础镜像，需人工检查版式。

建议分批：第一批 zh-Hans / zh-Hant / en；第二批 ja / ko / de / fr / es / pt-BR / ru；其余语言可直接复用英文截图兜底，不比配齐。

## App Store Connect 对照

代码语言 → ASC 语言：en→en-US，de→de-DE，fr→fr-FR（另有 fr-CA），es→es-ES / es-MX，pt→pt-BR / pt-PT，ar→ar-SA，he→he，ru / uk / ja / ko / zh-Hans / zh-Hant 直用。**ur（乌尔都语）不在 ASC 支持列表，不用做图。**

iPhone 只需 6.9 英寸一套（ASC 可自动适配其他机型）；iPad 若上架需另出 13 英寸一套。上传可手动拖拽，量大了可引入 fastlane `deliver` 按语言目录直传。

## 可视化编辑器与参数

`editor.html`：右侧面板实时调节描边宽度/颜色/不透明度、两类圆角，点「下载 settings.json」存到本目录，再跑 `node render.mjs` 出图即应用同参数。参数默认描边 16px、白色 75% 不透明。后续新增调节项（字体等）在 render.mjs 的 DEFAULT_SETTINGS + 编辑器表单里各加一行。

## 与旧方案的关系

`../zh-Hans-2026-09/`（A/B 两套×5 张）保留为产品页优化对照组；本目录是统一的 8 卡结构，A/B 测试如需继续，复制本目录按语言调 `cards` 顺序即可。
