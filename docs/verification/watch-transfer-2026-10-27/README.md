# Apple Watch 恢复与迁移签名复现

日期：2026-10-27（Asia/Shanghai）。用途：恢复包含原手表 Bundle ID 的构建，获取 Apple 分发签名阶段的实际错误，供用户向 Apple Developer Support 提交工单。

## 恢复范围

- 从 `aa24d1f3^` 恢复 Apple Watch App、Watch 单测源码、Watch target、手机包内 `Embed Watch Content`、共享 LinkCore 协议和两端记录 DTO。
- 保留原仓库手表标识 `com.douhua.jifen.ios.watchkitapp`，伴侣 App 为 `com.douhua.jifen.ios`，团队 `X9VDZZL3C3`；手机和手表均为 3.4（83）。App Store Connect Apple ID：6759768784。
- 适配当前共享模块新增的篮球训练类型、羽毛球违例事件、九球让杆／分数转移／开球人事件，解决历史手表源码编译不兼容。
- 本轮用于恢复打包、复现分发问题。手机端 WatchConnectivity 服务与手机联动入口尚未恢复；没有执行真机手表或模拟器运行回归，不能据此认定完整手表功能已通过验收。
- 用户原有的测试产物管理脚本修改保留。

## 已确认事实

- 当前团队的 `/v1/bundleIds?filter[identifier]=com.douhua.jifen.ios` 返回手机标识。
- 同账号查询 `com.douhua.jifen.ios.watchkitapp` 返回空列表。
- 恢复后的手表 App 可使用 `iOS Team Provisioning Profile: *` 开发通配描述文件签名，其 application-identifier 为 `X9VDZZL3C3.*`，`get-task-allow=true`。
- 手表 App 的包标识、版本、构建号、伴侣标识与最低 watchOS 11.6 校验通过；`codesign --verify --deep --strict` 通过。
- 用户说明应用从另一开发者账号转移而来。“关联 Watch App ID 是否遗漏迁移／归属异常”是需要 Apple 核查的假设，不能把证书未迁移写成已证实根因。

## 产物位置与保留

归档：`/Users/yangyang/Library/Developer/Xcode/Archives/2026-10-27/jifen 3.4 (83) Watch restored.xcarchive`。

分发相关文件：`/Users/yangyang/Library/Developer/jifen-ios-release-artifacts/2026-10-27-watch-restore-3.4-83/`，与临时测试批次分开保存。

原始日志、xcresult 和查询诊断：`/Users/yangyang/Library/Developer/jifen-ios-test-artifacts/runs/20261027T143934373768Z-watch-restore-signing-20261027/`。该目录属于有清理期限的外部测试证据；存在未解决分发错误时使用 `.keep` 固定保留，问题解决后方可解除。

Apple 官方说明应用转移时保留 Bundle ID：https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer/ 。这并不能独立证明本次 Watch App ID 的归属，应以本次分发错误和 Apple 支持查询结果为准。

## 最终结果

- Release Archive：`ARCHIVE SUCCEEDED`；手机和手表签名严格检查均通过。
- 微信框架最低系统声明校验仍通过（plist / Mach-O 均为 26.0）。
- App Store 分发导出：退出码 **70**，`EXPORT FAILED`；未生成 IPA，尚未进行实际二进制上传、App Review 提交或发布。
- 首要错误：`DeveloperAPIServiceErrorDomain Code=5`，`Failed Registering Bundle Identifier`。Apple 返回 HTTP 409、`ENTITY_ERROR.ATTRIBUTE.INVALID`、resultCode 9401，说明手表标识不可用于当前团队注册。
- 后续错误：`IDEProfileLocatorErrorDomain Code=1`，无法找到该手表标识的 App Store provisioning profile。
- 主 App 的分发签名资产评估通过；拒绝来自手表标识。服务端没有披露该标识的实际所有者，因此只能请求 Apple 核查归属或迁移关联，不能断言仍归原团队。

可直接复制的工单：[中文](apple-support-zh.txt)、[English](apple-support-en.txt)。精简原始错误：[export-errors.txt](export-errors.txt)；Apple 响应：[apple-service-error.json](apple-service-error.json)。

附件包位于外部正式产物目录的 `Apple-Watch-transfer-support-2026-10-27.zip`，包含工单正文、原始 export 日志及精简验证材料；完整 xcdistributionlogs 保存在固定保留的外部批次。

## Apple 工单后续回复（2026-10-27 23:24，Asia/Shanghai）

已在原邮件线程回复 `devprograms@apple.com`，工单号 **102950865484**，实际 Gmail 发件人为 `newbolomobile@gmail.com`。正文注明发生问题的 Apple Developer / App Store Connect 账号为 `yangyang@bolo.earth`。Gmail 已显示发送后的邮件、收件人、时间和两份附件。

- 附件：用户提供的 32 秒录屏 `录屏2026-10-27 23.10.41.mov`；`Apple-Support-Case-102950865484-evidence.zip`（全窗口错误截图、日志、服务端响应和验证摘要）。
- 逐项补齐：复现步骤、带时区时间、主／手表标识、团队、浏览器／Xcode／macOS 版本、Mac 型号、相关构建变化。
- 实时核实 App Store Connect 合约：Free Apps Agreement 与 Paid Apps Agreement 均为 Active；转移记录为 John Jin → Bolo mobile, Inc.，状态 Active。
- 说明 IPA 因分发签名失败而无法生成；已有约 200 MB 的 `.xcarchive`，请 Apple 确认能否接受并提供安全上传方式。未将归档或任何签名私钥附入邮件。
- 回复正文及发送记录：外部正式产物目录 `case-102950865484/reply-en.txt`、`case-102950865484/send-receipt.json`。

录屏解析临时证据批次为 `~/Library/Developer/jifen-ios-test-artifacts/runs/20261027T151313787483Z-apple-support-reply-video-20261027/`，按测试产物保留规则到期清理；必要截图已保存在外部工单材料包，原录屏保留于用户桌面。

## 后续：2026-10-30 二次移除（3.4.1 (84) 只发手机端）

苹果到 2026-10-30 15:42 仍未回复工单 102950865484。用户决定本版不带 Watch 上架，已再次移除恢复出来的手表工程接线与源码（`project.pbxproj`/`Package.swift` 回退，删除 `jifenWatch Watch App`、`jifenWatch Watch AppTests`、LinkCore 两个源文件与两个单测）。

- 删除前备份：`~/Library/Developer/jifen-ios-release-artifacts/2026-10-27-watch-restore-3.4-83/watch-restored-source-2026-10-30.tar.gz`，sha256 `a9b89b9e380baa544a25d0a031b4b4726f5609e2faa5615019e22af7ced6e73f`。
- 恢复方式：解包覆盖回仓库对应路径，再按本文件前文的打包流程重签；手机侧联动入口仍未恢复。
- 移除后 Debug 构建通过，产物不再嵌入 `Watch/jifenWatch Watch App.app`；详见 `docs/2026-10-30-ios-3.4.1-android-parity.md`。
- 苹果回信后若要重启手表功能，需先确认 `com.douhua.jifen.ios.watchkitapp` 归属与注册，再决定是否恢复。

## 后续：2026-11-21 苹果回复与本团队实时核查

苹果就工单 102950865484 回复：转移时手表部分可能没有一并转移，请用户确认是否存在该手表应用。当天用团队 API key（`VW87YVJ355`，Admin）实测：

- `GET /v1/bundleIds?filter[identifier]=com.douhua.jifen.ios` → 本团队持有（`L62G7WTAR7`）。
- 同查询 `com.douhua.jifen.ios.watchkitapp` → 空；`GET /v1/apps?filter[bundleId]=…watchkitapp` → 空；团队全部 App 列表无手表应用。
- `POST /v1/bundleIds` 尝试注册该标识（与 Xcode 分发签名时的服务端注册动作等价）→ **HTTP 409 / resultCode 9401**，"An App ID with Identifier 'com.douhua.jifen.ios.watchkitapp' is not available"，与 2026-10-27 导出失败完全一致。

结论：该 App ID 仍归原团队持有，苹果尚未做任何释放；现在恢复手表工程打包上传必然在同一注册步骤失败，未再执行整包验证。手表源码仍可从 `aa24d1f3^` 恢复（2026-10-30 的 tarball 备份已随原目录清理）。可用出路：① 原团队账号在其 Identifiers 中删除该 App ID 后本团队即可注册；② 由苹果在工单中释放；③ 手表 target 改用新的 bundle ID 后缀（只须保留手机包 ID 前缀）；④ 独立手表 App（兜底）。

## 后续：2026-11-21 应用户要求完整整包复测（3.4.3 (87)）

应用户要求仍执行了完整恢复与打包验证，确认结论不变：

- 恢复：从 `aa24d1f3^` 恢复 `jifenWatch Watch App`、`jifenWatch Watch AppTests`、LinkCore 两个源文件与 `Package.swift`/`RealtimeSync` 接线；pbxproj 由反向贴回手表移除补丁加 12 处冲突手工归并（手表专属条目全保留；FB1000…1/2 等 3.4.x 复用的 ID 丢弃；手机侧联动代码与入口仍不恢复）。
- 编译适配 3.4.3 共享模块：手表补 `.badmintonMisconduct`、`.chaseTransferred`、`.breakerChanged` 事件投影、`.basketballTraining` 默认队名、`.handoff`（让杆）文案口径同手机端；包在 macOS 与 watchOS Simulator 均编译通过，手机 scheme（嵌手表）编译通过。
- 版本：手机/手表对齐 3.4.3 (87)（watch 配置原残留 2.1 (21)）；`xcodebuild archive` 成功，手机与手表 `codesign --verify --deep --strict` 通过。
- `-exportArchive`（app-store-connect + API key 认证 + 自动签名）：**EXPORT FAILED，退出码 70，未生成 IPA**。错误与 10-27 完全一致：`Failed Registering Bundle Identifier`，服务端 HTTP 409 / resultCode 9401（`com.douhua.jifen.ios.watchkitapp` "is not available"），随后报 `No profiles for 'com.douhua.jifen.ios.watchkitapp' were found`。
- 三处独立证据（10-27 导出、11-21 API 注册预检、11-21 整包导出）指向同一结论：该 App ID 仍被原团队持有，等待删除/释放或改标识。
- 完整证据批次：`~/Library/Developer/jifen-ios-test-artifacts/runs/20261121T052408118659Z-watch-restored-signing-retest-343/`（`.keep` 固定，含 xcdistributionlogs、9401 原始响应、移除补丁与编译适配记录）。归档：`~/Library/Developer/Xcode/Archives/2026-11-21/jifen 3.4.3 (87) Watch restored.xcarchive`。

## 追加：2026-11-21 改名上传尝试被 ITMS-90477 拒绝（重要约束）

曾尝试把手表 Bundle ID 改为 `com.douhua.jifen.ios.watchapp` 绕开归属问题：archive 与 **EXPORT SUCCEEDED** 均通过（前缀规则成立、新 App ID 可注册、IPA 43.9 MB、微信框架 minos 26.0 正常），但 altool 上传被 **ITMS-90477** 拒绝："Attempting to change bundle identifier from com.douhua.jifen.ios.watchkitapp to com.douhua.jifen.ios.watchapp is disallowed for bundle jifen.app/Watch/jifenWatch Watch App.app"。

结论：**已上架应用的内嵌手表 Bundle ID 被历史构建锁定，不可改名**。因此对现有应用记录，内嵌手表路径只有原 `watchkitapp` 可用（必须原团队删除该 App ID 或苹果释放）；独立 watchOS App（新应用记录）不受此限制，是不依赖苹果的唯一兜底。已清理：`watchapp` App ID 记录删除、工程内 4 处配置回退为 `watchkitapp`；watchapp 归档与 IPA 留作证据（`jifen 3.4.3 (87) Watch watchapp.xcarchive`）。上传拒绝的原始 JSON 在证据批次 `apple-build-upload.json`。

## 最终解决：2026-11-22 原团队删除 App ID 后上传成功

原转让方（John Jin，用户的朋友）在其账号的 Identifiers 中删除了 `com.douhua.jifen.ios.watchkitapp`。当日：

- API 注册验证：POST /v1/bundleIds 成功，本团队获得该 App ID（记录 `6HXQKLQ63F`）——阻塞 26 天的唯一一步解开。
- 复用 11-21 已验证的归档导出成功（`jifen-ios-releases/2026-11-22-3.4.3-87-watch/`，本版未上传，用户选择升版本）。
- 正式构建 **3.4.4 (88)**：archive + export 成功，包内手机/手表均 3.4.4 (88)、手表 `com.douhua.jifen.ios.watchkitapp`、签名严格校验通过；altool 上传成功（delivery UUID `5353de76-efe4-4655-97fb-60a923cefe8d`），产物在 `~/Library/Developer/jifen-ios-releases/2026-11-22-3.4.4-88-watch/`。
- 工程内版本已升至 3.4.4 (88)（手机+手表 × Debug/Release 共 4 处配置）。3.4.3 (86) 留在原审核流程中未动。
- 期间确认的完整约束链（供后续参考）：转户不带嵌入手表 App ID（9401）→ 已上架应用不可改内嵌手表标识（90477）→ 只能原团队删除或苹果释放 → 独立手表 App 无 WatchConnectivity（联动需走网络通道）。

## 手机侧联动恢复（2026-11-22 下午，3.4.4 (89)）

build 88 只恢复了手表端（按 2026-10-30 口径，手机侧联动服务未恢复）。当日按用户指示"从 git 历史抄回"补全手机侧：

- **整文件抄回**（`aa24d1f3^`，`jifen/` 为同步组无需改工程）：`Core/Link/PhoneWatchLinkService/Session/Reliability/SideChannels/MessageHandling`、`WatchLinkMenuSupport`、`Features/Me/WatchLinkSettingsView`、`Features/Home/Services/SportsSetupWatchSessionLauncher`。
- **集成点**：jifenApp（服务注入+强制接管弹窗）、AppFeatureFlags（联动判定，对齐鸿蒙 linkedScoreboardCapability）、HomeTab（手表比赛回传接续/linkedResumeDescriptor）、MenuDialog（resync/takeover/endLink）、CommonNamesManager（名词同步）、PreferencesManager（引导标记）、Info.plist（JifenWatchLinkEntryEnabled）、SettingsView（联动入口行）、LocalDataResetComposition（watchLinkState 清理步骤）、AppAnalytics（watchLinkStart/watchLinkResult 事件 + watchLinkPage 屏幕枚举 + scoreboardMenuAction）、HomeModels/UnfinishedGameBarView（linked 摘要与手表角标）。
- **计分板嫁接**（3.4.x 演进 + watch 代码并存）：EightBall/Snooker/NineBallChase/Archery/Tennis/Rally + SportsSetupDialogView/NineBallSetupDialogView 的"开赛上手表"分体按钮。冲突共 76+ 处，用 git merge-file（HEAD 为 ours、aa24d1f3 为 base、aa24d1f3^ 为 theirs）逐一归并；费点：menu extraItems 需 3.4.3 rack rules 与 WatchLinkMenuSupport.extraItems 拼接、toggleMatchTime toast 归位、ScoreboardTemplate 纯演进全保 ours。
- **store 适配**：3.4.x 重写后的 TennisSessionStore/RallySessionStore 补 `applyAuthoritativeState`/`mergeRemoteActions`/revision 门控（对齐 BilliardsSessionStore.rebase 语义），供手表权威快照/接管使用。
- strings：en + zh-Hans 各回补 271 个联动键（其余语言回退 value 兜底）。
- 结果：手机 scheme 编译通过，3.4.4 (89) 打包上传 TestFlight（产物 `~/Library/Developer/jifen-ios-releases/2026-11-22-3.4.4-89-watch-link/`）。
- 未做：jifenTests 的 PhoneWatchLinkServiceTests 等测试文件未恢复；真机手表回归待 TestFlight 安装后进行；鸿蒙侧仅用作能力对标清单，未逐条核对行为细节（换边确认弹窗、断连重连文案等建议真机对测）。
