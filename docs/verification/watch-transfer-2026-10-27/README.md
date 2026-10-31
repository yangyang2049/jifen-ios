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
