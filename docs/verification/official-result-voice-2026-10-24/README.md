# 比赛结果语音：二次确认与逐项落地（2026-10-24）

用户确认按官方依据实施，按乒乓球 → 羽毛球 → 网球 → 壁球逐项修改，每项通过针对性验证后进入下一项。覆盖 iOS、国内安卓（含华为渠道）、Google 安卓、鸿蒙手机客户端。

## 二次确认

| 项目 | 英文原始依据 | 中文依据 | 本次启用的结束信息 |
| --- | --- | --- | --- |
| 乒乓球单／双打 | [ITTF HMO 2026，附录 D，PDF 第 44 页](https://www.hktta.org.hk/referee/application/HMO_18thEdition_2026.pdf#page=44) | [香港乒总编译本，纸面第 106—107 页](https://www.hktta.org.hk/referee/application/HMO_Chinese_2026.pdf#page=110)，译本注明以英文原版为准 | 局末：比分、胜者、局次；全场：最后一局结果、比赛胜者、总局分 |
| 羽毛球单／双打 | [BWF Vocabulary 2025-11-08，6.1—6.5](https://badminton.dk/wp-content/uploads/2025/12/Section-4.1.5-Vocabulary-8-November-2025-V7.0.pdf#page=6) | [CTBA 中英对照规则 2025-11-17，纸面第 54 页，6.1—6.5](https://www.ctb.org.tw/upload/files/%E7%BE%BD%E7%90%83%E8%A6%8F%E5%89%87%E6%8C%87%E5%BC%95%E9%99%84%E9%8C%84-20251117.pdf#page=55) | 局末：局次、胜者、比分；1:1 时宣布一局平；全场：胜者及按时间顺序排列的各局比分 |
| 网球单／双打 | [ITF Duties and Procedures 2026，II.G.4(e—h)](https://www.itftennis.com/media/2509/duties-procedures-for-officials-2026.pdf#page=27) | [中国网协审定、网球中心公开资料，第八部分，纸面第 39 页](https://www.sport.gov.cn/wqzx/n5345/c636548/part/355153.pdf#page=44) | 局末：本局胜者、当前盘局数与领先方；盘末：盘次、胜者、局数、总盘数；全场：胜者、总盘数、各盘局数 |
| 壁球 | [WSF Singles Rules 2025，附录 2.1](https://worldsquashofficiating.com/rules-of-squash/) | [体育总局小球中心审定中英对照版，2025-09-01 生效，PDF 第 31 页](https://www.sport.gov.cn/xqzx/n5354/c29023785/part/29023795.pdf#page=31) | 局末：比分、本局胜者、大比分领先或平局；全场：比分、胜者、大比分、各局小比分 |

中文按已核实资料的用语和信息顺序制作参数模板，简繁体分别维护。网球中文资料较早，仅用于稳定的中文宣报术语；赛制与结束事件以现有计分内核及 ITF 2026 为准。没有把翻译目录的 `reviewed` 标记作为官方认证。

本轮没有启用软网、匹克球、板式网球、排球类或毽球的新增结束句式，也没有为其他项目新增比分语音入口。

## 实现

- 四类运动的中文结束事件接入生产入口 `buildReviewed`；英文保持各项目专用结果结构，另纠正下述独立抢七模式的单位与胜者信息。
- 单局比分、总局分、盘数、各盘局数分别从事件事实读取；结果比分按胜者方向排列，各局／各盘历史保持时间顺序。网球本局胜者可以仍在盘内落后，单独按局数确定领先方。
- 乒乓球自然终局由 reducer → mapper 生成一个 `match_end`，不再同时排入普通报分和单局结束报文。语音主开关控制结果播报，发球方选项不追加到结果报文。
- 没有明确胜者时不凭队名或同分数据推断获胜。iOS 手动结束保留中性结果，不套用自然结束的最后一局／盘流程。
- 新增 18 个中文结果模板；简体、繁体目录、源哈希和编译资源一起更新，并导出安卓、鸿蒙模板。
- 网球独立抢七／抢十不产生常规局、盘计数。安卓 mapper 补传该赛制事实，并从实际终局得分确定胜者；鸿蒙单／双打模型在终局报文补传该标记。中英文均不将抢七得分播成局数，也不宣布虚构的零盘比零盘。Swift／安卓用真实 reducer 的最后一分操作覆盖该路径，鸿蒙新增单／双打模型的 Hypium 回归用例及可执行报文断言。
- 安卓在 Setup 语音卡片及记分板菜单内，对中文界面提供普通话／英语选项；默认跟随应用，显式选择按设备保存。乒乓球仍可独立选择是否播报发球方，其他项目不显示该选项。
- 安卓英文播报将汉字姓名片段转为无声调拼音，已有拉丁字符、重音、名称中的格式符和计分状态保持不变；常见多音姓与现有 iOS／鸿蒙映射一致。转换不可用时保留原名。此处只改播报副本。

## 验证

按项目依次完成了 Swift 生产报文、安卓两仓库生产报文及鸿蒙生产报文检查。固定期望直接取自各项目已确认的结束结构；另保留所有项目、语言和场景的已有回归样例。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Swift 官方结果、语言矩阵、Rally/Tennis 事件映射 | 31 项通过 | `/tmp/jifen-results-squash-swift.log` |
| iOS 模拟器编译后的真实 ScoreVoice 资源及 App 入口 | 3 项通过 | `/tmp/jifen-results-ios-native.log`；`/tmp/jifen-official-results-20261024.xcresult` |
| 国内安卓语音单测及 Official/Huawei Debug Kotlin 编译 | 27 项语音单测通过；末轮整包复编译遇到下述投屏文件错误 | `/tmp/jifen-results-final-android-voice.log`、`/tmp/jifen-results-final-android.log` |
| Google 安卓语音单测及 Googleplay Debug Kotlin 编译 | 46 项语音单测通过；末轮整包复编译遇到同类投屏文件错误 | `/tmp/jifen-results-final-google-voice.log`、`/tmp/jifen-results-final-google.log` |
| 鸿蒙历史样例、756 条生产报文及四项目官方结果样例 | 通过 | `/tmp/jifen-results-squash-hos.log` |
| 鸿蒙 entry@default Debug HAP | 编译通过 | `/tmp/jifen-results-hos-build.log` |
| 46 套资源目录、格式参数、源哈希与生成资源 | 通过；流水线 12 项单测通过 | `/tmp/jifen-results-final-resources.log`、`/tmp/jifen-results-final-resource-tests.log` |

新增用例包括左右获胜、单／双打、12:10 延长局、最后一分结果合并、中文姓名／格式符、羽毛球逐局历史、网球局与盘的区别及单独抢七、壁球局末仍由对方在大比分领先、无明确胜者的中性结果。

未执行设备上的 Hypium 测试、真机 TTS 实听和折叠屏实机回归。本轮没有安装、提交或发布应用；各设备语音引擎及音色仍需真机验收。

### 当前工作区的安卓编译限制

安卓三个渠道在语言选项接入后的首次 Kotlin 编译均成功。最终收尾再次编译时，两个安卓仓库的 `app/src/main/java/com/douhua/jifen/display/ui/DisplaySurfaceHost.kt` 当前九球投屏改动出现 `.dp` 类型错误，位置为 611、624、1366、1384、1416、1426 行。该文件未由本轮修改；没有为通过编译而覆盖投屏改动。当前完整安卓工作区应视为编译未通过，语音模块单测仍为全部通过。详细错误保留在上述最终日志中。

## 可重复同步

全量重导出会覆盖兄弟仓库中独立维护的其他语言／逐分样例。为本次结果修改新增限定导出，只更新所列项目的中文期望，保留各端其余基线：

```sh
python3 scripts/localization/sync_reviewed_voice_catalogs.py --fixtures \
  --fixture-sport pingpong --fixture-sport pingpong_doubles \
  --fixture-sport badminton --fixture-sport badminton_doubles \
  --fixture-sport tennis --fixture-sport tennis_doubles \
  --fixture-sport squash --fixture-language ZH \
  --phrase-prefix pingpong.result. --phrase-prefix badminton.result. \
  --phrase-prefix tennis.result. --phrase-prefix squash.result.
```

差异复查确认：三个兄弟仓库的 fixture 只改变上述项目的中文结束期望；生成模板只新增中文结果键，其他语言模板不变。

本次相关文件的修改前副本和工作区状态保存在 `/tmp/jifen-official-results-20261024-baseline`。工作区原有的九球、选人和其他未提交改动保留。
