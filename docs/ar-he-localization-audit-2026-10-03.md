# 阿语、希伯来语本地化核查（2026-10-03）

截图中的 `Badminton`、`First server`、`Best of`、`games` 在当前 Google Android 源码中已有阿语、希伯来语译文，但当前模拟器安装的 Google 包没有这四项译文，会回退为英文。读取模拟器安装包确认最后更新时间为 **2026-09-30 22:22:59**，版本 `3.3 / 330`，包名 `com.bolo.jifen`。最新资源编译结果包含四项的阿语和希伯来语值。这与截图表现一致；尚未确认截图是否来自该模拟器。

## 覆盖范围

读取本地可用的 **110 个分支引用**，包括本地分支和远端跟踪引用；同时核查当前工作区的未提交资源，以及 iOS `feat/mahjong-ios` 的现有工作区。远端跟踪引用是本地快照，本轮没有拉取远端。资源缺键检查、英文残留检查及实际安装包检查分别记录，避免将工作区的完整资源误当成已安装包或历史提交的内容。

| 项目 / 当前分支 | 分支引用数 | 阿语、希伯来语界面资源 | 当前工作区结果 |
| --- | ---: | --- | --- |
| iOS / `3.3` | 23 | 两种均支持 | 每种 1,441 个普通键、4 个 Info.plist 键、28 个复数键、194 个语音键；无缺键 |
| Google Android / `main` | 5 | 两种均支持 | 每种 1,742 个资源键；补齐后无缺键 |
| 国内 Android / `3.3` | 15 | 尚未加入 | 没有这两种界面翻译可核查 |
| 鸿蒙 / `3.3` | 67 | 尚未加入 | 手机界面资源为中文、英文，没有这两种界面翻译 |

iOS 有阿语、希伯来语资源的本地分支是 `3.3`、`main`、`group`、`feat/mahjong-ios`，另有 `origin/group` 跟踪引用；各提交的普通资源键完整。旧版本分支没有这两种资源。

Google 的 `main`、`backup/pre-refresh-20260927`、`worktree-agent-general-purpose-03b9ec79` 提交快照都有这两种语言，但普通翻译并不完整；当前工作区包含此前尚未提交的补译。历史快照缺键清单见机器报告。本轮修正在 **iOS 当前 `3.3` 工作区、Google 当前 `main` 工作区**，历史分支提交未改写。

从右往左显示的语言还包括项目已支持的 **乌尔都语 `ur`**；本轮逐项补译范围为用户指定的 `ar`、`he`。

## 本轮修正

- Google：阿语、希伯来语各新增 **121 条麻将资源**，共 242 条，涵盖入口、设置、结算、记录、分享、帮助及错误提示；保留原来各 1,621 个资源的值和格式。
- Google 验收白名单：增加两个只包含运行时参数和标点的麻将模板 `mahjong_seat_player_label`、`mahjong_wind_round`。模板本身没有待翻译的英文词句。
- iOS 阿语：修正升级帮助中的 `Take Dealer` 残留；将斯诺克四种球色的英文缩写译为阿语，共 2 条。
- iOS 希伯来语：修正两条桌上足球帮助中的 `Settle / Finish`、休息帮助中的 `Pickleball` 及错误的秒数译法、加时中的 `OT`、斯诺克球色缩写，以及斗地主、毽球名称，共 7 条。
- iOS 审阅目录：同步上述 9 条修正；重新核对每种语言 12 条因英文源文案更新而过期的审阅记录，以及资源中已有、目录中缺失的两条反馈标签。确认译文符合当前源文案后更新审阅状态；没有直接跳过 freshness 校验。

品牌、公司正式名称、`VIP`、`UNO`、`GP / SP / MP` 等缩写保留；用户输入的姓名属于内容，不作为未翻译的界面标签。

## 验证及实际边界

- iOS `validate_locale(ar/he, require_reviewed=True)`：审阅阻断 0；资源与 final 审阅值一致；键、格式参数及复数检查通过。
- iOS `promote --locale ar/he`：通过，包含 Apple 资源 `plutil -lint` 校验。
- Google `check_locales` 的定向比较：两种语言缺键 0、XML 错误 0、格式错误 0、非批准英文同文 0。
- Google `:app:processGoogleplayDebugResources`：**BUILD SUCCESSFUL**；AAPT 回读已编译资源，确认截图四个标签及新增麻将资源包含阿语、希伯来语。
- 修改文件的 `git diff --check`：通过；本轮 9 条 iOS 资源修正以编辑前快照逐键对比确认，Google 原有资源全部保留。

本轮为资源和审阅数据修正，没有构建完整 iOS App、完整 Android APK/AAB，也没有替换模拟器安装包或重新截取修正后的运行界面。要让运行画面使用当前译文，需要从最新工作区重新构建并更新安装包；本轮资源编译不是完整运行界面验收。

## 证据

- [分支及工作区机器报告](../artifacts/ar-he-localization-20261003/audit.json)
- [iOS 审阅与修正键报告](../artifacts/ar-he-localization-20261003/ios-validation.json)
- [已安装 Google 包的四个标签](../artifacts/ar-he-localization-20261003/installed-resource-evidence.json)
- [最新编译资源的实际译文](../artifacts/ar-he-localization-20261003/compiled-resource-evidence.json)
- [Google 麻将新增译文](../artifacts/ar-he-localization-20261003/google-mahjong-translations.json)
- 资源编译日志（已于2026-10-04清理）

编辑前备份：`../.codex-snapshots/ar-he-localization-20261003/`。本轮未提交或推送。
