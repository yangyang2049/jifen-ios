# iOS／鸿蒙国内账号关联交付 · 2026-10-24

本次实现完整绑定、预览和账号关联流程。服务端已于 10 月 24 日凌晨部署，`WECHAT_ACCOUNT_BINDING_ENABLED` 仍关闭；客户端暂不向真实用户显示新入口。没有执行生产账号合并，没有上传或提交本轮客户端。

文末保留当日多轮实现和安装记录，各轮“未安装”仅描述当时状态。iOS 后续审计修复包已保留数据安装至 iPhone SE（安装回执 2540）；最新修复与验证以 [未提交改动审查](audits/uncommitted-review-2026-10-24.md#二次复核与修复) 为准。微信打不开时的处理方案已确认并补全具体失败提示，真实授权往返由用户验收。

## 交互与规则

- iOS 仅当前 Apple 登录会话、鸿蒙仅当前华为原生登录会话，在简体／繁体中文的个人资料页开放绑定入口；已绑定只读显示。未登录、微信登录、其他语言无新绑定入口。国内 Android 客户端本轮未改。
- iOS 3.4 冷启动恢复已有 Apple 登录时，一次性提醒绑定；不在未登录或手动新登录后补弹。绑定入口及绑定授权不以是否安装微信为前置条件。
- 微信未有业务账号则直接绑定；已有账号先选择数据处理模式及保留账号，再查看服务端预览，最后确认。两种模式**都需要选择保留的账号**，保留其 ID、昵称和头像。
- “合并双方数据”合并支持的云端小组、名称、地点和记录；“只保留所选账号的数据”将另一侧业务数据留档。取消保持两账号独立。两种模式都保留更优会员：终身优先，否则到期更晚者优先，不叠加天数。
- 同组双成员合为一人，历史席位和比分保留。自己对自己的场次不计该成员个人战绩，其他双打成员不受影响；待确认赛果不能借旧身份自我确认。
- iOS 使用系统大型 Sheet，iPad 使用 page 尺寸及可滚动内容；鸿蒙使用独立账号关联页面。标题不显示步骤编号，登录方式用 ` / ` 分隔，成功按钮为“好的”。

## 实现入口

- iOS：`WechatBindingModels.swift`、`WechatBindingService.swift`、`WechatBindingUpgradePrompt.swift`、`WechatBindingView.swift`；个人资料及主界面接入口。新增独立 `WechatBinding.strings` 简繁英资源，未扩展全局翻译表。
- 微信授权与微信登录分离，绑定不会意外登录／新建另一业务账号。准备时固定原 JWT，确认幂等，回包丢失先查询同请求回执，再恢复结果；普通接口不能使用已撤销旧会话。
- 合并后以原会话版本做原子凭据替换，清空小组缓存、重拉常用数据基线。清理期间保持登录串行；退出或过期会阻止旧合并流程重启缓存同步。
- 本机常用数据先检查配额、同步并暂停，保留恢复检查点；本机未上传的小组记录需先处理。服务端预览明确只统计云端数据，本机草稿不冒充已合并成果。
- 历史成员展示、筛选、等待确认名单和确认权限统一识别 canonical／legacy 成员映射，原始席位 ID 不改。
- UI 截图使用 `#if DEBUG` 隔离测试数据；Release 不包含假登录或假成功路径。

## 本机验证

| 验证 | 结果与证据 |
| --- | --- |
| iPhone 全部单元测试 | 注册 748 项，1 项条件跳过，0 失败；`/tmp/jifen-binding-final-v4.log` |
| 最后会话中断／契约回归 | 7/7，包括清理期间真实调用 logout，不复活 token／旧账号同步；`/tmp/jifen-binding-session-final.log` |
| iPhone 简繁流程 UI | 2/2；选择微信账号为主、结果预览、完成、组长阻断与返回改合并 |
| iPad 简繁流程 UI | 2/2；`/tmp/jifen-binding-ipad-ui-v3.log` |
| 三份绑定资源及 diff | plutil lint、git diff --check 通过 |
| 旧 iOS Release 归档（已撤销候选资格） | `ARCHIVE SUCCEEDED`；`build/account-linking-2026-10-24/jifen-3.4-78.xcarchive`，开发签名，3.4（78）；`/tmp/jifen-binding-final-archive.log`。未包含下述微信回调修复，不得用于分发 |
| 旧 TestFlight 分发包（已撤销候选资格） | 云分发导出与 17 项静态核验通过，但真机发现微信回调路由缺口；尚未上传，不得上传旧包 |
| 鸿蒙 | default 调试签名 HAP 构建及认证、恢复、历史成员定向回归通过 |

UI 证据保存在 [verification/account-linking-2026-10-24](verification/account-linking-2026-10-24)，均为模拟器隔离示例数据，不代表生产账号已绑定。

鸿蒙记录：`/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/huawei_account_backend_integration.md` 末尾 2026-10-24 章节；产物 `entry/build/default/outputs/default/entry-default-signed.hap`，`com.douhua.jifen / 3.3 (330)`，**默认调试产品**。

旧分发包 `build/account-linking-2026-10-24/app-store/jifen.ipa`（`com.douhua.jifen.ios / 3.4 (78)`，16,112,838 字节，SHA-256 `9832a099da3895f86c8a67f0c7af5026a816cc0679bd40283ecaff4f02ad4126`）**已撤销候选资格，不得上传**。此前云 Apple Distribution 签名、权限、关联域名／scheme 配置、Release 测试数据隔离等静态核验有效，但不证明微信真实往返能完成。历史核验见 `build/account-linking-2026-10-24/app-store-verification.json`。此前 ASC 只读查询时 3.4（78）尚未占用、内部组允许全部构建；尚未上传或提交审核。

## 微信授权回调修复与替换产物（本机通过，待真机验证）

真机旧 Release 3.4（78）已能显示微信登录并调起微信授权；返回 App 后仍显示 loading，服务端同时段没有收到此次微信换票请求。此现象尚不属于真实登录或绑定验收通过。

代码根因：SwiftUI 将 Universal Link 交给 `onOpenURL`；旧 `handle(url:)` 只接受微信自定义 scheme，忽略 `https://jifenqi.com/app/...`。另设的 `onContinueUserActivity` 不能覆盖 SwiftUI 这条 URL 路径。[Apple 文档](https://developer.apple.com/documentation/swiftui/view/onopenurl%28perform%3A%29)明确说明 Universal Link 在 SwiftUI 中直接作为 URL 传递。线上 AASA 已只读确认包含本 Team／bundle 及 `/app/*`。

本次最小修复让严格匹配本域名及 `/app/` 的 HTTPS URL 构造 BrowsingWeb `NSUserActivity`，送入微信 SDK 的 Universal Link 入口；旧 scheme 路径、授权 state 精确匹配和绑定策略保留。小组邀请、伪域名及非授权路径不送微信 SDK。新增 `[WechatAuth]` 安全阶段日志，只记录路由 kind／handled、响应 errCode／stateMatches 和超时，不记录完整 URL、query、code、state 或 token，不启用 SDK 原始日志。

| 本次新增验证 | 当前状态 |
| --- | --- |
| 回调／绑定／会话定向回归 | 25/25、0 失败：新 router 4 项、Binding 8 项、Prompt 6 项、AccountLinkContract 7 项；`/tmp/jifen-wechat-callback-fix-tests.log`，结果包 `/tmp/jifen-wechat-callback-fix-20261024.xcresult` |
| 语法及 diff | `swiftc -frontend -parse`、`git diff --check` 通过 |
| 新 Release 归档 | `ARCHIVE SUCCEEDED`：`build/account-linking-2026-10-24/jifen-3.4-78-callback-fixed.xcarchive`；`/tmp/jifen-wechat-callback-fixed-archive.log` |
| 新云分发 IPA | 导出成功，本机 17/17 项通过：`build/account-linking-2026-10-24/app-store-callback-fixed/jifen.ipa`；导出日志 `build/account-linking-2026-10-24/app-store-callback-fixed-export.log`，核验记录 `build/account-linking-2026-10-24/app-store-callback-fixed-verification.json` |
| 真机授权往返／登录／绑定 | 待新 Release 保留数据覆盖安装后验证；尚未通过，不得声称修复已完成真机闭环 |

本次仅准备新归档及分发包，不上传 TestFlight，不提交 App Store 审核。

新分发包仍为 `com.douhua.jifen.ios / 3.4 (78)`，16,114,264 字节，SHA-256 `b552c010cdcb2550f1de0a80023cd92f2b26c494b265659db11f9c5c5b965a2e`；可执行 UUID `D5E083F6-60C4-3237-9447-4A11EF1A82EB` 与 callback-fixed 归档一致，且与旧归档不同。云 Apple Distribution 签名严格核验通过，`get-task-allow=false`、APNs production、Apple 登录、微信 scheme／关联域名齐全，测试夹具字符串与 staging 地址无残留，包含本次 `[WechatAuth]` 安全诊断前缀。简繁英绑定资源均为 63 项。上述核验覆盖本机产物，真实微信回调、换票及绑定尚待真机完成。

## 服务端已部署状态

详见 [服务端发布报告](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/deploy/account-linking-2026-10-24.md) 和 [接口契约](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/doc/account-linking-api-2026-10-23.md)。核心 18/18、小组 70/70、财务 34/34、Huawei 23/23，候选 TypeScript 编译通过。新增迁移已应用，代码、数据库和条件元数据回滚材料齐全。

华为 1138 条身份经官方校验并只补空 UnionID 元数据，原 userId／provider／providerId 逐项确认未变；仍为 16 组双号。10647／11213 已确认同一 verified UnionID。没有自动合并任何用户。iOS AppID 与生产默认微信凭证匹配，服务端可正常解析，未输出密钥。

## 尚需真机验收与已知边界

- iPhone SE 2 解锁后 DDI 可用，已保留数据安装并启动旧 Release 3.4（78），日志 `/tmp/jifen-binding-device-install.log`、`/tmp/jifen-binding-device-launch.log`。系统 iPhone 镜像已连通；微信已调起授权，但返回后卡在 loading，等待上文新回调修复包真机复测。Device Hub 新屏幕共享要求 iOS 27，故改用系统镜像。鸿蒙 `hdc` 无连接设备，未安装本次 HAP。
- 按既定发布要求，提审前须在 Pura X 或等效折叠真机验证本轮实际差异：绑定页折叠／展开与窗口切换、授权往返、确认中断、重新登录、小组历史和常用数据刷新；保留计分、计时及未上传草稿。当前门禁未通过。
- 旧版实时 Match／Event 资产完整迁移、未支持资产、进行中比赛、未来同场双席位、仅保留时放弃组长账号、常用数据超额、特殊会员问题由服务端明确阻断，不能承诺任意账号都能自动合并。
- iOS 同进程网络丢包可查回执恢复；若进程被杀，需重新 Apple／微信登录进入保留账号。后端已提交合并不会因此丢失。
- 总开关仍关闭；00:40:21 另完成精确内部 User.id＋绝对到期时间的测试白名单部署，24/24 回归及候选编译通过。当前名单为空，到期时间未设置，所有真实用户仍关闭；收到真机业务 UID 并核对 Apple 身份后，只配置该账号的两小时测试窗口。无需重发客户端。完成真实授权、两个模式、会员和小组闭环后再扩大开放，不把部署成功等同于功能已向用户开放。

## 微信登录真机仍超时 · 排查进展（01:00–01:45）

回调修复包 00:54 覆盖安装成功后，用户 00:55 左右真机点「微信登录」仍报超时。排查结论（证据均为只读查询）：

- 服务端无嫌疑：`POST /api/auth/login/wechat` 本机直测（无效 code）0.27s 返回 400；生产 PM2 日志里 Android 微信登录持续 200（约 500–650ms）；00:04 新部署以来**未收到任何真机 iOS 换票请求**，而同机其他 iOS 3.4（78）请求正常到达。超时发生在客户端授权回调环节，换票从未发出。
- 配置链路无嫌疑：源站与 Apple CDN 的 AASA 均含 `X9VDZZL3C3.com.douhua.jifen.ios` 的 `/app/*`；微信开放平台 UL 已由用户确认填写 `https://jifenqi.com/app/`；安装容器 00:54 已更新且 App 启动过。
- 无线日志采集三条路均不可用：`log collect --device` 需 sudo；sysdiagnose 无线传输两次超时；xctrace Logging 模板下无线 CoreDevice 连接数秒即断（与装包时断连同源）；usbmuxd 不见 Wi-Fi 设备。
- 已改为诊断包方案：`WechatAuthProvider.swift` 新增 `WechatDiag`（仅 `WECHAT_DIAG` 编译条件生效，正常构建为空操作）：文件日志写入沙盒 `Documents/wechat-diag.log`（只记路径／参数名／state／errCode，不记 code），并接微信 SDK 日志与官方 Universal Link 自检 `checkUniversalLinkReady`（真实拉起微信再返回，逐步报告错误与建议）；`jifenApp` 启动埋一行标记。诊断 Release 已于 01:36 构建并保留数据安装到 iPhone（databaseSequenceNumber 2436）。
- 手机 01:40 起锁屏，远程无法前台拉起，探测与日志拉取待用户解锁后执行：普通启动→拉文件验证埋点，再以 `--payload-url https://jifenqi.com/app/?ulcheck=zcode` 触发 UL 自检，最后用户重试一次微信登录并拉日志定位。
- 注意：为编译诊断包曾在 `project.pbxproj` App target Release 配置临时加 `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "WECHAT_DIAG"`，已还原；备份在 `/tmp/project.pbxproj.bak-wechat-diag`。正式打包前必须确认该设置不存在（当前已确认无残留）。诊断代码本身在正常构建中编译为空，不影响交付行为。

## 真机闭环通过与超时根因（10:40 复盘）

- 回调修复在真机完整验证通过：微信官方 UL 自检 6 步全过（含「微信经 Universal Link 拉起本 App」回跳）；真实授权回调 `path=/app/wx945ba56799035847/oauth` 正确路由、state 匹配、code 换票 200（551ms），服务端落库 userId `cmpnlosl2001gv5dw5oy2cdgw`（微信业务账号 uid 10545「杨阳26」，2026-05-27 已有账号，3 个小组成员身份、1 个组长、41 条旧版实时比赛参与记录）。
- 此前真机「请求超时」的根因是两层叠加：① 当时微信 App 本身未登录，授权无法完成；② 01:47 那次授权成功后换票 POST 恰逢手机到 api.jifenqi.com 的网络中断（URLError -1001「请求超时。」，等待约 5 分钟，服务器全程未收到），01:54 网络恢复后重试即成功。客户端换票超时 20s + waitsForConnectivity 的表现已记录。
- 诊断基建：`WechatDiag`（`WechatAuthProvider.swift`，仅 `WECHAT_DIAG` 条件生效）输出 `Documents/wechat-diag.log`；`devicectl device copy from --domain-type appDataContainer` 可无线拉取；`devicectl device process openURL` 可远程触发 UL 探测。诊断包当前仍在 iPhone 上（替代正式回调修复包，行为一致）。
- 绑定测试窗口（已被全局开放取代）：`api-server/.env` 曾配置 Apple 账号 uid 12569「石 洋洋」的两小时白名单；产品决定改为全员开放后，已移除白名单变量并设置 `WECHAT_ACCOUNT_BINDING_ENABLED=true`（2026-10-24 上午，PM2 重启生效，任意用户 gate=true）。依据：3.4 客户端未上传应用商店，绑定 UI 仅存在于测试设备诊断包，全局开放无真实用户暴露；3.4 发布前仍须完成既定真机验收清单。.env 备份在 `/home/yy/backups/env-backup-global-bindings-*.txt`（此前的 `env-backup-whitelist-*.txt` 已被本备份覆盖语义）。
- 预期路径：Apple 会话 → 资料页绑定微信 → 预览 → 「只保留所选账号的数据」并保留杨阳26 可完整走通（Apple 侧为空账号、无组长放弃问题）；「合并双方数据」会被 `LEGACY_ACCOUNT_ASSETS_REQUIRE_REVIEW` 阻断（微信侧 41 条旧版实时比赛资产需人工核验），属已知边界。

## 遗留实时比赛阻断已移除（10-24 中午，产品决定）

- 现象：真机绑定预览对「合并」与「只保留」两种模式都返回 `ACTIVE_LIVE_MATCH`（客户端文案「请先结束正在进行的计分或跨设备同步」）。
- 根因：旧版实时比赛功能从不写终态（代码无 `status='ENDED'` 流转，生产库 1703 场全部永久 ACTIVE，其中最近 7 天仍有 34 场被更新——旧版比赛有真实用户在用），该检查对全体老用户永久拦截。
- 处理（产品决定：彻底去掉检查，接受「合并确认时被放弃账号会话失效、正在用该账号计分的设备会中断且 keep 模式下比赛冻结」的极小概率风险；比赛数据本身在归档／迁移中均不丢失）：`accountMergeAssets.ts` 移除 `ACTIVE_LIVE_MATCH` 查询、阻断与指纹输入；本地 `tsc --noEmit` 通过；仅替换服务器 `dist/lib/accountMergeAssets.js`（服务器无 TypeScript 无法全量编译）。备份与哈希：`/home/yy/backups/active-live-match-removal-20261024/`（旧 dist `33f908dc…`、旧 src `69c60f2e…`），新 dist `a1d4815e…`；PM2 重启后健康正常。回滚＝恢复备份 dist 并重启。仓库源码同步更新（未提交）。
- 数据修复记录：测试账号对（Apple uid 13073「洋洋」+ 微信 uid 10904「石狮子」）名下 13 场 2026-06-30 弃置比赛曾置 ENDED 以绕过旧检查；检查移除后该数据修复非必需但无害（保留 ENDED 状态，备份同前）。
- 修复后预期：该账号对「只保留」两方向可完整走通；「合并双方数据」仍因旧版比赛资料要求人工核对（`LEGACY_ACCOUNT_ASSETS_REQUIRE_REVIEW`，预期内）。

## 合并确认后被踢出登录的竞态（10-24 下午，真机复现，首次补丁）

- 现象：确认合并成功后 App 被踢出登录并提示「登录已失效，请重新登录」；随后的首次微信登录再次被踢，Apple 登录一次并退出后微信登录才正常。
- 服务端证据：confirm 200；其后 login/apple、login/wechat 均 200；错误日志为成片 401（auth/me、common-data、groups、bindings、refresh）——旧令牌在途请求在确认作废旧会话后集中撞 401。服务端确认路径本身正确（替换令牌 `iat = 撤销秒+1`，`completedResponse`）。
- 客户端根因：旧令牌请求的 401 → APIClient 原子过期 + `apiSessionExpired` → `expireSession` 踢出。该防御无法区分「旧令牌的 401」与「新会话失效」，在确认返回前后的窗口把 `applyLinkedAccount` 刚换上的保留账号会话一并终止，设计中的无缝换凭据（stay logged in as survivor）被打断。
- 修复（客户端）：`SessionStore` 新增 `isWechatBindingSessionActive`，在 `validateWechatBinding` 置位、`endWechatBinding` 无条件清除；`.apiSessionExpired` 观察者在绑定活跃期间抑制踢出，由 confirm/recover 的 `applyLinkedAccount`（`stillOriginal`/`expiredOriginal` 两分支）接管会话结果。Release 构建通过并安装真机（databaseSequence 2508）。
- 自查修正与验证（无第二账号对，按用户要求自测）：抑制踢出后令牌被清而 user 仍在，`expiredOriginal` 分支同步放宽为「user 为 nil，或绑定活跃且 user 仍为原账号」；新增契约测试 `testAtomicExpiryDuringActiveBindingDoesNotKickAndApplyStillSwaps`（清空令牌后 applyLinkedAccount 仍完成换凭据、流程结束恢复踢出），AccountLinkContractTests 全套 8/8 通过（含既有的清理期 logout、确认竞态、恢复路径契约），最终构建安装真机（databaseSequence 2516）。
- 账号终态：保留微信账号 uid 10904「石狮子」，已携带 apple+wechat 双身份（bindings 返回 providers=[apple,wechat]、bound=true）；Apple/微信登录均进入该账号。归档侧 uid 13073「洋洋」mergedIntoUserId 指向 10904。
- 待完整回归：该修复需在下一个未绑定账号对（或绑定 UI 测试）上验证确认后不再被踢出；本账号对已完成合并无法重复。

## 两端会话复核与补强（2026-10-24）

本次复核确认，前述仅在绑定期间忽略 `apiSessionExpired` 的补丁不足，不能据此认定完整问题已解决。原有原子过期测试只直接清空 token，没有走真实 HTTP 401、refresh 或失效通知；本次已补这些请求时序的自动回归。

- **iOS Cookie 冲突**：Apple 登录及 refresh 会设置 `jwt_token` Cookie，服务端认证优先读 Cookie；合并回包、原生微信登录只返回 JSON token，旧 Cookie 因此可能持续覆盖新 Bearer。这一代码路径可以复现，但本轮未重新抓取原真机 Cookie。APIClient 默认 session 停用 Cookie 存储，并对所有请求（含 refresh、注入 session 和原 JWT 恢复请求）禁用自动 Cookie、移除 Cookie 请求头。
- **iOS 失效处理**：用唯一的绑定 context 统一接管来源会话失效，覆盖通知和资料刷新直接调用退出的路径；只允许原会话版本及紧接的一次原子清除。成功换凭据立即解除保护，新会话真正失效仍正常退出；未成功而关闭流程会补处理原失效。旧流程的关闭或校验不能影响同账号后来新开的流程，显式退出也不会被迟到确认复活。
- **iOS 原子替换**：`AuthTokenStore.setLinkedAuth` 在同一 actor 操作中判断来源版本并安装新凭据，覆盖「读取快照之后、安装之前」恰好收到旧 401 的窗口。
- **鸿蒙队列及恢复**：pending 恢复记录与 token 替换、401 清理共用队列，并核对会话版本、实际 JWT 及本次绑定归属；旧页面不能暂停/恢复后来登录的刷新和常用数据同步。缓存写入或 pending 清理失败后保留可重试恢复路径，页面异步等待后再次校验生命周期与会话。当前原生请求没有保存/自动携带 Cookie 的证据，未添加 Cookie 相关改动。
- **服务端同秒签发**：登录/refresh 和合并回包共用 `createLoginSession`，新 token 的 iat 严格晚于账号撤销时间；RT token 三处已认证签发同样应用该边界，避免合并同秒重登、刷新或重连后新凭据立即被判撤销。保留旧凭据撤销及后续再次撤销的校验规则，没有新增数据库查询。

本轮实际验证：

| 范围 | 结果 |
| --- | --- |
| iOS 定向构建与单元测试 | **50/50、0 失败**，涵盖旧 401 在确认前/后返回、确认回包丢失后查询恢复、Cookie 隔离、新会话真实失效、关闭补偿、旧流程清理及显式退出；日志 `/tmp/jifen-binding-race-audit-20261024-r2.log`，结果包 `/tmp/jifen-binding-race-audit-20261024-r2.xcresult` |
| 鸿蒙定向回归 | `test_account_link_race_regression.mjs`、`test_account_link_session.mjs`、`test_group_session_isolation.mjs`、`test_account_merge_group_identity.mjs` 通过；新增行为用例也能检出恢复旧实现后的两个负对照错误 |
| 鸿蒙模块构建 | `hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon` 成功；日志 `/tmp/hos-account-link-race-build.log` |
| 服务端 | **24/24、0 跳过**，固定时钟及 mock Prisma，覆盖登录、真实本机 HTTP refresh/RT 签发、撤销边界和既有绑定/Apple/Google 安全回归；`tsc --noEmit` 通过 |

服务端可复跑命令（工作目录 `jifenqi-backend/api-server`）：`pnpm exec tsx --test src/lib/authSession.test.ts src/lib/accountBindings.test.ts src/lib/appleSecurity.test.ts src/lib/googleSecurity.test.ts`；测试输出未另存日志。

本轮只修改源码并完成上述验证：未安装真机、未部署服务端、未发布商店包；之前手机安装包不包含本轮补强。新的未绑定账号对的真实授权与合并验收仍待真机完成。

## 鸿蒙字符串误删与完整恢复（10-24 下午）

- 事故：排查期间执行 `git checkout -- entry/src/main/resources/`，回退了鸿蒙仓库 7 个语言 string.json 中**未提交**的账号关联字符串（54 键 × 7 语言：account_link_*、profile_binding_*、profile_login_huawei 等），而 ets 代码文件（未被回退）仍引用它们。
- 恢复源：13:28 构建的 HAP 内 `resources.index`（该构建合并了完整丢失前状态）。二进制记录布局为 `[id:2][0001:2][值表偏移:4][键长:4][键名]`，值表为 `[blob长:4][条目数:4][条目 (语言索引:4, 值偏移:4)]`，值池为 `[长:2][UTF-8]` 序列；语言索引 0=base、2=en_US、3=zh_CN、4-7=zh_TW/Hant/HK/MO。注意：id 在键名**之前**，逐记录解析须先读 id 再读名字（首轮解析曾把值表配给字母序后一个键，造成「串值」假象，实为解析错误而非构建缺陷）。
- 验证：正确解析后与 HEAD 已提交值全量比对 **2608/2608（100%）**；恢复的 54 键值与当日晨间直读原文（choose_master、keep_detail、profile_login_huawei）逐字一致；清构建（78/78 任务）后从新 HAP 的 index 复检 10 项全部通过。期间手工重建的值与原件也逐字一致（同源 iOS 镜像文案）。
- 其余 351 条 index 记录为颜色等非字符串资源，本就不属于 string.json。7 个语言文件现已完整（base/en_US 2659 键、中文四变体 2662 键），ets 引用零缺失，clean 构建 78/78 通过。

## 账号卡片登录方式角标（10-24 下午，两端）

绑定流程账号卡片（选择保留账号与结果确认页）的登录方式从信息行改为昵称行右上角胶囊：14px 半粗、中性填充（iOS `tertiarySystemFill`／鸿蒙 `app_surface_muted`），信息行相应少一行。图标：Apple 用 SF Symbols `apple.logo`；微信新增自绘双气泡图标（iOS `WechatLogo.imageset`、鸿蒙 `media/wechat_logo.svg`，品牌绿 #07C160）；鸿蒙华为账号用既有 `huaweilogo.png`。HTML Demo 对比过现状／纯文字／胶囊带图标／图标无底四方案，用户选定胶囊带图标。iOS Release 构建通过并保留数据安装真机（databaseSequence 2476）；鸿蒙 hvigor `assembleHap` 通过（`entry-default-signed.hap` 12:28 重新生成，未安装设备）。资料页「登录方式」信息行（主卡片内）不变。
