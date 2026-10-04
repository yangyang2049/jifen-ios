# 安卓与鸿蒙比分语音同步（2026-10-03）

遵循 [iOS 逐项目／逐语言原始依据](sports-voice-score-calls-2026-10-03.md)：有可靠依据的场景使用规范表达，未查证组合只播数字。未新增项目语音开关或语音语言。

## 生产入口与语言

| 项目 | 语言 | 生效路径 |
| --- | --- | --- |
| 国内安卓 `jifen-android` | 中文、英文 | Manager → MessageBuilder.build → ReviewedVoiceAnnouncementMessageBuilder → TTS |
| Google 安卓 `jifen-android-google` | 现有全部 13 种语言 | 同上；日／韩／法／西／葡语只启用已有依据的项目及场景 |
| 鸿蒙 `jifen-hos` | 中文、英文 | voiceAnnouncement.ts → buildVoiceAnnouncementMessage → 已查证分支／数字兜底 → TTS |

覆盖现有 15 个语音项目类型。排球、沙排、气排球及毽球不借用羽毛球的换发球、局点、开局和结束口令；其他未查证语言组合也只播数字。匹克球传统双打保留发球员序号。无法确认的暂停、换边口令静默，只有有依据的口令才播。

保留各端计分模型：安卓常规网球分为 0/15/30/40/45，鸿蒙和 iOS 为内部步进数；局／盘结束的局数不做分数转换。新增 returnedToDeuce 事件事实，避免归一化后的平分丢失上下文：法语返回平分使用 Égalité，软网使用 Deuce again。安卓及鸿蒙把换边附在得分 payload，只附加已查证的英语／日语羽毛球及软网换边用语。

旧 builder 显式命名为 buildLegacy／buildLegacyVoiceAnnouncementMessage，仅用于历史格式对照。新增测试检查公开的生产入口。保留语音开关、TTS 引擎选择、语言选择及播放队列。

## 同步与验证

在 iOS 仓库执行 `python3 scripts/localization/sync_reviewed_voice_catalogs.py --fixtures`，导出各端 ReviewedVoicePhrases.kt／reviewedVoicePhrases.ts，并临时运行 Swift buildReviewed 导出实际生产报文，自动删除临时测试。模板仅替换原始模板中的参数一次，姓名中的 `%2$@`、`3-2` 不会再作为模板处理。

固定输入 378 个场景：15 个语音项目、左右发球、开局、逐分、局／盘／比赛结束、休息／恢复、四种提醒、再次平分、临界分、Padel Star/Golden Point、抢七、匹克球发球员序号及有依据的换边口令。

- 国内安卓：756 条报文与 iOS 对照；shared-core 生产入口、真实 reducer → mapper 返回平分及队列测试；Official Debug App 语音事件、历史格式、开局和结束比分历史专项测试。
- Google 安卓：4,914 条报文与 iOS 对照，包含全部 13 种现有语言；同类 shared-core 和 Googleplay Debug App 专项测试。
- 鸿蒙：756 条报文与 iOS 对照，保留历史格式及官方休息纯函数测试；新增 Hypium 生产入口用例；完成 entry@default Debug HAP 编译。Hypium 用例未在设备上执行。

安卓任务：`:shared-core:testDebugUnitTest`、`:app:testOfficialDebugUnitTest`、`:app:testGoogleplayDebugUnitTest`，筛选语音及相关事件测试。鸿蒙任务：`node scripts/test_voice_announcement_messages.mjs`；`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon`（使用 DevEco 自带 hvigorw）。

日志：`/tmp/domestic-reviewed-voice-final.log`、`/tmp/domestic-reviewed-voice-app-final.log`、`/tmp/google-reviewed-voice-final.log`、`/tmp/google-reviewed-voice-app-final.log`、`/tmp/hos-reviewed-voice-parity-final.log`、`/tmp/hos-reviewed-voice-build-final.log`。前两端的 combined 日志记录 shared-core 通过后遇到旧 App 断言；最终 App 日志记录更新期望后的验证结果。

自动报文对照不能代替不同设备和 TTS 引擎的实际听测。本次改动未提交，未安装设备，未发布。

## 乒乓球可选发球者播报（2026-10-03）

四个手机客户端（iOS、国内安卓、Google 安卓、鸿蒙）在 Setup 的语音卡片和记分板操作菜单中增加浮动选项「播报发球方」。开启语音时显示，5 秒自动收起，点击箭头可以重新打开；操作选项会重新计时。浮层不参与原对话框的高度计算。

此偏好默认开启，按设备保存，关闭语音及开始新比赛时保留。语音主开关控制是否播放。开局、逐分及恢复比赛时追加下一分发球者的名字；双打使用具体发球人。比赛、局及盘结束的播报沿用现有规则，其余项目不受此选项影响。用户自定义名称直接作为参数使用，不做翻译或再次解析。

纯报文 builder 的可选参数仍默认关闭，维持裁判规则及对照 fixtures 的原始报文；实际播放器显式读取设备偏好，首次使用默认开启。国内/Google 安卓先把接受的计分操作写入轮转历史，再取得双打发球人的姓名。

已验证：iOS 编译、46 种语音语言资源的名字参数专项测试、47 种界面语言资源一致性；iOS 模拟器 Setup 和操作菜单的浮层高度、自动收起、重新打开及语音关闭后保留偏好；安卓 Official/Huawei/Googleplay Debug Kotlin 编译、报文专项、双打轮转和窄窗口 Popup 边界测试；鸿蒙 entry Debug HAP 编译及 756 条现有报文对照、新增发球者开关用例。安卓和鸿蒙本次未做真机界面验收。Google 旧 LocalizedVoiceAnnouncementMessageBuilderTest 的 12 项用例仍按先前报文预期断言，与当前 Reviewed 入口不一致，未在本功能中改动。
