# iOS 全项目与未提交修改审计（2026-10-22）

> **修复状态更新（2026-10-22）：** 本文保留修复前的审计快照与复现。已确认问题的代码修复及自动回归已完成；当前状态、证据和真机待验项见 [iOS 修复记录](remediation.md)。

本次确认 **1 项 P1、2 项 P2**，另有测试契约与本地化错误映射欠账。49 个原始未提交文件未发现确认的新业务回归；下面的问题均在当前 HEAD 已存在，不能归因于本次英语标题大小写修改。**当前不能给出“全项目通过、可以发布”的结论。** 未修改业务源码，未提交代码。

## 1. 快照与覆盖边界

- 工程：`/Users/yangyang/Desktop/jifenqi/jifen-ios`；分支 `3.3`；HEAD `658e8d67a6864a6596606037cfa1aa9ae23f4501`。
- 起点：49 个 tracked、unstaged 修改，0 个 staged，0 个 untracked。起点清单不包含本次新建报告。[原始状态](evidence/ios-initial-status.txt)、[逐文件 SHA256 清单](evidence/ios-uncommitted-manifest.json)、[diff 统计](evidence/ios-initial-diff-stat.txt)。
- 起点全项目盘点：3,695 个 tracked 文件；283 个生产 Swift 文件（253 个 app、30 个 Core）；47 套实际 `.lproj`，44 套外语 JSONL catalog。[生产源码清单](evidence/ios-source-inventory.json)。这些数量是目录清点，不是逐行精读数量。
- 全部原始未提交文件都进行了差异/语义审阅；已精读高风险的小组举报、资料/活动/排阵保存、账户会话、网络请求/重试、WebSocket、计时持久化、StoreKit 与记录提交关键路径。其他现有模块通过源码结构盘点、风险搜索和已有回归覆盖，**没有声称逐行审完所有既有源码或逐屏验收所有语言**。
- 收尾发现外部工作推进HEAD至`474d0c614a8f0d5eafd6c941d6a97f1a11a8c589`，将原49个资源/脚本改动及本审计早期部分证据纳入提交。本代理未执行`git add/commit`，未回退外部提交。额外3个图标样式源码已补审，见下节与[结束快照](evidence/ios-end-snapshot.json)；测试结果对应各命令执行时磁盘内容，不冒充冻结快照验证。
- 后端、Android、HarmonyOS 仅作本地契约对照。未访问生产接口，未实际举报/购买/恢复购买，未连接真实外屏或手表。

## 2. 确认问题

### IOS-01 / P1：首次读取旧举报失败后，空表单仍可覆盖旧案件的当前附件与说明

类型：HEAD 已有；与 Android/HarmonyOS 同族。成员与按组号访客入口共用此实现。

- 位置：[GroupEvidenceReportSheet.swift:117](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupEvidenceReportSheet.swift:117)、[提交请求:173](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupEvidenceReportSheet.swift:173)、[提交门禁:62](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Core/Components/ReportSheet.swift:62)。
- 触发：账号已对某组提交带图片的举报；重新打开时首次 `GET .../report` 连续失败；网络恢复后，用户在仍为空的表单中填写并提交。
- 当前行为：`reload` 的 catch 只设置错误，defer 将 `loading=false`；没有成功读取过案件的状态门禁。默认原因已选择，`images=[]`、`current=nil` 仍可提交。请求显式带 `attachmentIds: []`，`expectedVersion: current?.version` 为 nil，编码时省略。
- 后端证据：[reports.ts:124](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/api-server/src/lib/groups/reports.ts:124) 仅在传版本时比较；[附件选择:129](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/api-server/src/lib/groups/reports.ts:129) 将显式空集合视为替换；[更新:146](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/api-server/src/lib/groups/reports.ts:146) 更新当前案件。结果是未看见旧案件就覆盖当前说明/附件，并跳过版本保护。
- 影响边界：旧 submission 仍保留原证据，不是永久删除图片，也不是跨账号越权。正常成功读取旧案件时存在版本字段，不能把所有提交都描述成无版本保护。
- 验证强度：本端完成 UI 状态到序列化/后端更新的完整静态路径复核；同族 HOS 场景已由其报告中的真实方法提取执行复现。本端未注入系统网络故障做原生 UI 复现。
- 建议：明确“成功读取无举报 / 已读到举报 / 读取失败 / 旧接口不支持”。读取失败时禁写并提供重试；新版创建发送版本 0；未获取现有附件时不得无条件发送空集合。回归覆盖已有附件、GET 失败后恢复、并发处理、成员/访客两入口。

### IOS-02 / P2：WebSocket 在握手前重置重试次数，失败上限和指数退避失效

类型：HEAD 已有；Android 当前实现没有相同的握手前归零问题。

- 位置：[MatchWebSocketManager.swift:216](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Core/CloudSync/MatchWebSocketManager.swift:216)、[断线与重试:271](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Core/CloudSync/MatchWebSocketManager.swift:271)。
- `URLSessionWebSocketTask.resume()` 只启动连接；紧接着就设为 connected、`reconnectAttempts=0`。握手失败后重试次数加到 1，下次 `openSocket` 又归零，因此永远无法达到 5 次上限，退避反复停在约 1 秒。
- 独立复现：提取当前实际 manager，在 macOS 上仅去掉 UIKit 设备信息辅助、替换等价墙钟辅助，保留连接/队列/重试逻辑；loopback HTTP 服务每次握手返回 401。**7.62 秒发起 7 次握手**，时间为 0.087/1.161/2.202/3.276/4.381/5.431/6.497 秒。未请求生产服务。[执行结果](evidence/ios-ws-reconnect-reproduction.json)、[可重跑脚本](evidence/ios-ws-reconnect-repro.py)。
- 影响：过期或被拒绝的连接、持续网络失败会反复连接；connected 状态也会短暂失真。未量化真机耗电或流量。
- 跨端对照：Android [onOpen:410](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/cloudsync/ws/MatchWebSocketManager.kt:410) 在真实 open 回调中才归零，并用 generation 隔离旧 socket 回调。
- 建议：真实握手成功后才 connected/归零，握手前失败应保留累计次数；同时用 socket 身份隔离回调。补持续拒绝、断网、旧连接延迟失败和成功后再断线的生命周期回归。

### IOS-03 / P2：44 个本地化 catalog 与实际资源失配，完整生成/审核门禁失败

类型：HEAD 已有；本次仅标题大小写刷新未造成此缺口。

- 位置：[英语资源:293](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Resources/en.lproj/Localizable.strings:293)、[catalog 严格取键:1269](/Users/yangyang/Desktop/jifenqi/jifen-ios/scripts/localization/localize.py:1269)，44 个 `scripts/localization/catalogs/*.jsonl`。
- 每个 catalog 都缺 `Localizable/setup_auto_odd_sets`，实际 47 语言 `.strings` 中已有该键。完整渲染读取 `catalog[(table,key)]` 会抛 KeyError，不能安全重生成/推广资源。
- 每个 catalog 另外有 4 个过期 source hash：`home_tool_coin`、`tool_flip_coin`、`tap_to_flip`、`flip_coin_recent`。44 语言合计 **220 个 blocker**（44 缺键 + 176 stale-source），44 个 catalog 均未通过 `require_reviewed=True`。
- 证据：[全部 catalog 验证](evidence/ios-all-catalog-validation.json)、[资源盘点](evidence/ios-resource-inventory.json)、[本地化测试日志](evidence/ios-localization-tests.log)。同时用 `git show HEAD:...` 确认 HEAD 的英语资源已含该键、HEAD 的 ar catalog 已缺该键。
- 影响边界：**没有证据表明已打包界面因该键缺译**；现有资源含翻译。本问题阻断完整再生成、审核与可信的本地化门禁，不能把 catalog 缺行说成运行时缺行。
- 建议：把新增键的已审译文录入全部 catalog；人工确认 4 条硬币源文变化后同步 hash/审核状态；完整 `render/check` 后确认包内资源没有意外变化。不要仅修改计数或批量把未审核内容标成 reviewed。

## 3. 验证欠账与需裁决项（不另计产品缺陷）

### QA-IOS-01：暂时重试状态与 failureMessage 测试契约冲突

签名且固定中文环境复跑 151 项应用测试，**150 通过、1 失败**：

`GroupPortParityTests.testPersistedUploadFailuresResolveCurrentCopyInAll47Languages`，断言位置 [GroupPortParityTests.swift:541](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifenTests/GroupPortParityTests.swift:541)。

`updateRetry(... code: RATE_LIMITED, failure: nil, next: future)` 保留 `failureCode`；[failureMessage:44](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupLocalPersistence.swift:44) 仍返回“操作太频繁，请稍后再试”，测试预期 nil。UI 的两处 GroupNotice 会展示这条消息。需要裁决：自动退避期间是否允许显示原因；再同步实现或测试，不能因为测试失败直接宣称上传重试已坏。没有修改源码或删除断言来掩盖失败。[签名复跑日志](evidence/ios-signed-targeted-tests.log)。

### QA-IOS-02：本地化测试与新举报后端错误集合未同步

- `test_source_inventory` 固定断言 2,106 个 Localizable 条目，现状 2,117；这属于过时测试计数，不是 11 条资源故障。[test_localize.py:69](/Users/yangyang/Desktop/jifenqi/jifen-ios/scripts/localization/test_localize.py:69)。
- `test_current_backend_business_errors_all_have_an_ios_mapping` 发现未映射：`NOT_FOUND`、`IMAGE_TOO_LARGE`、`INVALID_EVIDENCE`、`INVALID_IMAGE_TYPE`、`INVALID_IMAGE`、`IMAGE_REQUIRED`、`IMAGE_DIMENSIONS_EXCEEDED`、`INVALID_ATTACHMENTS`、`EVIDENCE_BOUND`、`REPORT_VERSION_CONFLICT`。本机后端新错误集与 iOS 表不一致。
- [GroupErrorMessage.swift:114](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupErrorMessage.swift:114) 对未知错误：中文可用后端 message，其他语言使用本地化通用失败提示。因此缺专用文案**不是乱码/一定崩溃/无兜底**。但证据过期、版本变化的下一步不明确，建议补对应操作提示与跨端错误映射。此处不把每个缺映射码拆成 bug。

### 低风险维护观察

`group-copy-20261017.json` 近 3 万行 diff 主要是格式重排，实际只有 10 个 reviewed_sources 语义变化；`retained_wording` 重复记录标题大小写变更。建议以后将格式整理与文案修改分开，并让审核说明幂等。这不影响本轮产品功能，不计确认故障。

## 4. 所有未提交修改的审阅结果

| 文件簇 | 数量 | 已完成审阅与判断 |
| --- | ---: | --- |
| `en.lproj/Localizable.strings` | 1 | 10 个英语小组标题/按钮大小写；键、占位符、换行未变，无确认业务回归 |
| `catalogs/*.jsonl` | 44 | 每语言恰好 10 行改变，仅 `source_hash`、`note`；外语 final 值未改。既有 catalog blocker 单列 IOS-03 |
| `group-copy-20261017.json` | 1 | JSON 解析后递归对比，仅 10 个 reviewed_sources 值变化，无翻译/共享词白名单改值；[语义diff](evidence/ios-group-copy-semantic-diff.json) |
| `group-copy-review-20261021.json` | 1 | 3 个源文同步与 retained_wording 说明追加；显式源文与已打包英语匹配 |
| `group_audit_copy_20261020.py` | 1 | RECONCILED_SOURCES 跟随已审核英文标题/标签，未改变业务规则 |
| `group_heading_case_20261022.py` | 1 | 增补 10 个标题/辅助动作；alias 解析与资源存在性断言仍生效，`--check` 无待写文件 |

完整49路径及哈希在起点manifest。外部提交后原49项已成为HEAD内容；补审该提交新增的3个生产差异：

- `Theme.swift:215` 增加图标边长插值，≤84pt卡片维持28pt、128pt及以上45pt，区间内线性过渡。
- `QuickStartEditView.swift:144` 把原比例传参改为该函数；`SportOptionView.swift:9` 用可选尺寸闭包替代iconRatio，其余调用沿用原默认算法。全app搜索无残留`iconRatio:`调用。
- 差异仅影响局部图标尺寸，无状态、数据或协议改动，未发现确认缺陷；按项目验证策略跳过额外构建，未把此前单元测试当成该后续提交的专门视觉验收。新增截图/说明清点为外部图标任务证据，未借此宣称本审计做过视觉验收。

结束状态与原49基线分别保存，没有把本次报告目录算作用户原始修改。

## 5. 全项目覆盖矩阵

| 领域 | 本次实际证据 | 未覆盖的关键边界 |
| --- | --- | --- |
| 计分/比赛规则 | JifenCore 全部 251 项通过；34 个 exact game 类型的工厂/记录/恢复/比分投影等现有覆盖；规则/终局/双打/撤销主要依赖生产 reducer 测试 | 未人工逐行重审每项运动规则，未真机完成所有赛制 |
| 小组 | 举报完整状态/请求链；资料字段差异、活动/排阵/训练保存；签名复跑 GroupContract 24、GroupPortParity 112（111过1失败）；通知脚本通过 | 原生相册/实际举报/推送抵达/双账号并发UI未跑 |
| 网络/账户 | APIClient/TokenStore 精读；签名复跑会话隔离15项通过；GET幂等重试、401重放、同会话刷新/换号取消现有测试 | 生产token到期/跨设备注销/真实弱网未测 |
| 云同步/显示 | REST DTO、DisplayState codec、队列及manager复核；本地WS失败握手复现；应用完整尝试中相关投影/34类覆盖有通过记录 | 完整应用测试进程曾退出，不能以局部通过推断全链路通过；无真实Android/HOS外屏配对 |
| 计时/工具 | TimerToolStateStore、Stopwatch/Countdown基于截止时刻恢复；首轮 TimerAndToolOffline 8项、相关工具/计时现有测试通过 | 未真实锁屏过夜、系统时钟修改、通知实际抵达、WebView触控验证 |
| 记录/持久化 | FinishedSessionCommitCoordinator先写正式记录再清恢复档；atomic文件/补偿清理、outbox关键路径；核心Persistence/Record测试通过 | 无磁盘耗尽/权限失效/升级迁移真机故障注入 |
| 会员/StoreKit | 商品集合、JWS pending、同交易gate、未登录购买、currentEntitlements/到期刷新静态复核，相关已有单测局部通过 | 无真实交易/退款/家庭共享/生产服务验单，不能作支付上线背书 |
| watchOS/跨设备记录 | Xcode现有target只有jifen、jifenTests、jifenUITests；源码未找到WCSession/WatchConnectivity。watch来源记录标识和LinkCore是记录基础能力 | 此checkout没有Apple Watch target；与Android/HOS手表端不等功能不能直接报回归；未审独立手表repo |
| 本地化/主题/响应式 | 全部47套资源相关组键/格式已有测试；44 catalog逐一验证；全部49变更语义审阅；现有主题/样式/布局测试局部通过 | 无47语言逐屏、人类翻译质量全审、RTL/大字体/VoiceOver/原生截图视觉验收 |
| 构建/配置 | `xcodebuild -list`确认3 targets；Simulator Debug编译并运行真实app测试，未修改构建配置 | 未Archive/Release签名/App Store校验、依赖漏洞扫描或真机验收；未提交/上传 |

源码风险搜索覆盖 app/Core 全部生产 Swift 的强制抛错、fatalError、强制类型转换与 TODO/FIXME；没有以搜索无命中证明所有模块正确。旧文档只作线索，未重复计入已经修复的旧问题。

## 6. 跨端契约快照（供总报告合并）

| 契约 | iOS当前实现/对照结论 |
| --- | --- |
| 小组项目/座位 | badminton/table_tennis/tennis/pickleball；singles/doubles每边1/2座，与兄弟主工程模型一致 |
| 资料编辑 | `PATCH /api/groups/:id`，只编码变化字段，空description能清空；不带If-Match；owner才可改joinPolicy。符合本轮last-save-wins |
| 活动/排阵/训练编辑 | activity PATCH、lineup PUT、training PATCH不传revision；取消/完成等条件动作仍保留对应revision，不能统一删除所有If-Match |
| 文字长度 | 加入留言200、举报500、请假100按UTF16；成员名1–24按Unicode scalars；活动地点80/备注300按UTF16。不要把Swift Character计数与服务端UTF16混用 |
| 举报提交 | 成员与按组号两个POST；reason/detail/attachmentIds/expectedVersion；最多3图；同一draft指纹复用幂等key；IOS-01为共同缺口 |
| 举报能力/图片 | capability严格true才添加图；来源20MiB限制；prepareJPEG长边最多2560、输出≤2MiB、重新编码JPEG。可避免HOS/Android“低字节超12MP”问题；未验证所有EXIF/超大解码内存场景 |
| DisplayState | schemaVersion1；styleV2；teamId/winnerId/clock/rest由集中codec转换；football injuryTimeText现在已编解码，不能重复引用9月旧报告缺失结论 |
| 云同步项目范围 | 当前CloudSyncGameTypes集合有34项（含basketball_training、multi_scoreboard，无mahjong）；这是当前源码计数，不沿用旧报告33项。源码注释仍写训练仅iOS，已被当前后端catalog否定：backend scoreboardCatalog.ts:187-190允许Android≥320、HOS≥313、iOS无附加版本门槛。Android/HOS当前codec也包含训练8字段；应按当前后端能力表判断，旧注释仅是文档欠账 |
| WebSocket | 信封type/payload/timestamp，离线队列16；快照只留最新，GAME_OVER/LEAVE同类去重，状态事件保序。iOS握手前归零与Android真实onOpen归零不同，见IOS-02 |
| 平台支付/手表/语言 | iOS StoreKit+Apple登录、47语言、本repo无watchOS target；不能要求平台SDK/商品ID/构建号完全一致 |

## 7. 实际验证命令、结果和限制

| 验证 | 结果 |
| --- | --- |
| `git diff --check` | PASS |
| `swift test --package-path Packages/JifenCore` | PASS，251项；[日志](evidence/ios-swift-core-tests.log) |
| `python3 -m unittest discover -s scripts/localization -p 'test_*.py'` | FAIL，46项，3失败2错误；IOS-03缺catalog行导致2个KeyError/1键集合失败，另外错误码映射/源计数各1失败 |
| `python3 scripts/localization/group_heading_case_20261022.py --check` | PASS，115个heading/168个runtime与alias键，0文件待写 |
| 44种语言逐个`localize.validate_locale(... require_reviewed=True)` | FAIL，44/44不通过，共220 blocker，见IOS-03 |
| `python3 -m unittest discover -s scripts -p 'test_group_notice*.py'` | PASS；脚本导入时执行8个production-method场景与通知目的地检查，unittest本身登记0项，不能写成8个XCTest |
| 实际WS manager + loopback拒绝握手 | 缺陷成功复现，7.62秒7次；这是复现成功，不是修复通过 |
| 全部`jifenTests`首次尝试 | Debug编译/安装成功；675条case通过记录、36条失败记录、一个快照测试进程退出；诊断收集卡住后主动终止，exit143。**不能标全量通过** |
| 签名+中文环境定向复跑 | 151项、150过1失败，exit65；APIClientSessionIsolation15过、GroupContract24过、GroupPortParity112中1失败。首轮Keychain(-34018)/中文硬断言受默认英语影响在此复跑已排除 |

签名复跑完整命令（使用当时已启动的iPad Simulator；没有改项目签名配置）：

```sh
xcodebuild test -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,id=1BAD35E9-B714-4AD9-BEF3-EBFD7F943FF1' \
  -only-testing:jifenTests/APIClientSessionIsolationTests \
  -only-testing:jifenTests/GroupContractTests \
  -only-testing:jifenTests/GroupPortParityTests \
  -testLanguage zh-Hans -testRegion CN -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  -resultBundlePath /tmp/ios-audit-signed-20261022.xcresult CODE_SIGN_IDENTITY=-
```

首次全量命令为`xcodebuild test ... -only-testing:jifenTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`，iPhone Simulator ID `86871B65-E0ED-4FBD-9F93-F3FB6246A895`。[首轮原始日志](evidence/ios-xcode-unit-tests.log)、[首轮case清单](evidence/ios-xcode-first-run-summary.json)。未签名参数不适合本工程的Keychain测试；已用上方签名命令复查，未将环境故障计为产品缺陷。

本轮已实际编译Simulator应用并执行测试，因此没有额外重复跑Archive/Release。报告/证据为本代理唯一新增内容；原49个业务/资源修改已由外部提交纳入HEAD，外部新增图标样式已补审，未做回退。修复优先级：IOS-01三端同步收口 → IOS-02握手生命周期 → IOS-03生成链路/QA门禁 → 真机与跨端配对验收。
