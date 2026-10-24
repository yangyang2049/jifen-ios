# iOS 未提交改动审查（2026-10-24）

范围：以本轮 `git status`、已跟踪文件 diff 和全部未跟踪文件为入口，检查掼蛋终局保护、升级／投篮训练手势、统一扫码、微信登录、绑定／账号合并、认证与 Cookie 隔离、常用数据同步、小组历史成员映射、主题／行高、工程配置、本地化资源及相关测试。审查期间新增的掼蛋 Setup 两处标题居中也已纳入；该处仅改布局，未发现逻辑问题。

当前结论：原审查的前三项中问题已修复并通过回归；第四项按用户确认的方案补全失败提示，真实微信往返待用户验收。下文保留初次审查证据，均为修复前状态；具体修复及验证见「二次复核与修复」。不存在尚待决定的授权 API 方向。

## 已直接修复

1. **退出后迟到的绑定状态查询仍启动账号同步。** `SessionStore.restore` 和 `performAuth` 在新增的 `reloadWechatBindingStatus` 等待之后没有重新检查会话。受控 HTTP 回归证明：查询中退出，迟到请求结束后仍调用 warmup。现在在恢复／登录的状态查询后核对认证 revision 和会话 generation，登录成功统计前也再次核对；旧登录的 defer 只释放自己的 `isWorking`。新增两项回归，修复前均失败，修复后通过。
2. **绑定页初始化期间关闭／取消可遗留绑定锁。** `start` 创建 context 时可发生页面退出，原 `close` 因尚未接到 context 而直接返回。现在从初始化开始标记 busy，关闭标记在 context 判断前生效，迟到 context 遇关闭或任务取消立即交还 `SessionStore`。新增两项直接调用 FlowModel 的受控时序回归。
3. **预览请求期间还能切换模式或保留账号。** 原回包会与更改后的选择不匹配而报错。现在内容选项随 busy 禁用，确认仍使用服务端预览 token。
4. **扫码器无相机时白色控件在浅色背景上不可读。** 关闭、相册和识别进度指示在占位界面使用主题正文色；相机画面继续使用白色。
5. **相册多二维码图片放弃有效业务码。** 统一扫码后原来的有效小组码筛选退化成取第一条。现在调用方可提供候选判据，小组页优先邀请码，我的扫码优先有效邀请码／登录码；没有可处理内容时仍把第一条交给业务层返回原有无效／过期错误。新增三项候选回归。

测试修复：静态本地化检查识别显式 `tableName`，分别检查 QRScan／WechatBinding 表、英文 fallback、已有翻译的 key 集与占位符；规则标题测试使用当前 App 语言，并保留简繁中文具体文案契约。首轮全量测试的 71 条失败断言来自这两类测试假设，不是 71 个独立产品问题。另清理扫码文件末尾多余空行，`git diff --check` 通过。

## 原审查中问题（历史证据，处理结果见后文）

### 1. 常用数据的旧暂停任务能冻结同账号的新会话（已修复）

修复前位置：`CommonDataCloudSyncManager.pauseForAccountLink`（原约 159–194 行）、`WechatBindingFlowModel.loadPreview/close`。当时暂停只比较 userID，没有绑定流程或认证会话的所有权。

可达时序：iPad 多窗口 A 开始预览，旧暂停正在等待常用数据请求；窗口 B 退出并重新登录同一账号；旧请求结束后的 followup 已使用新会话完成同步。旧暂停随后只看 userID 相同、phase 为 synced，就取消任务并把新会话的 activeUserId 清为 nil。离屏关闭若发生于暂停返回前，也拿不到尚未设置的 commonDataPaused 标记。

初审用 URLProtocol 请求闸门实际复现：旧暂停跨越 `sessionDidChange(nil)`、新 token 安装和 `sessionDidChange(同一 userID)`，最终 `forceSync` 得到 signedOut。证据：`/tmp/jifen-stale-pause-probe-20261024.xcresult`、`.log`；探针源码 `/tmp/jifen-stale-pause-probe-20261024.swift`。对应场景现已纳入正常通过的回归套件。

原建议：暂停绑定 context ID、同步 sessionRevision 和 authRevision；每次 await 后检查归属；取消／完成只消费本流程暂停；页面关闭使正在等待的暂停失效。该方案已落实，详见后文。

### 2. 合并预览遗漏双方自动续费提示（已修复）

修复前：`WechatBindingModels.swift` 的 `AccountLinkPreview.Assets`（原约 146 行）和 `WechatBindingView` 的预览内容遗漏资产续费提示。后端本地 `accountMergeAssets.ts:153–154` 返回 `summary.assets.automaticRenewalCount` 及 `summary.assets.warnings`，双方存在多个活跃自动续费时明确说明合并不会取消任何续费。当时客户端未解析这两个字段，预览只展示择优保留的会员权益。

影响：用户确认合并时看不到多份订阅继续各自续费的提示。顶层 warnings 不是这个字段，单独展示顶层通用提示不能解决。

处理方案：解析续费数量及资产警告，以本地化提示明确展示“账号合并不会取消自动续费”，覆盖双订阅和单订阅夹具。已落实提示，不增加额外勾选。

### 3. 掼蛋终局后的正规编辑无法一次完成改级（已修复）

修复前位置：`GuandanScoreboard.swift:198–209`、`GuandanScoreboardView.swift:703–709` 和 `845–868`（原行号）。编辑入口不看终局状态；级数按钮走 adjustRank，被新 guard 拒绝。applyEdit 又忽略 leftScore／rightScore，读取 reducer 现有级数，因此提交 adminCorrect 仅把原级数带回 playing。用户当时必须先“完成”复活，再次编辑才能真正改级。

guard 本身正确，adminCorrect 的 reducer 单测也通过，但这不代表终局编辑 UI 已可用。

处理方案：保留终局 guard，编辑状态维护级数 draft，完成时通过一次 adminCorrect 原子提交。取消编辑不改终局；覆盖 A／A1／A2／A3、撤销和云端同步。已落实；掼蛋固定红左蓝右，没有换边入口。

### 4. 未安装微信时的绑定授权反馈（方案已确认，待真机验收）

位置：`WechatAuthProvider.swift:180–182,207`。绑定入口／授权刻意不以安装状态为前置条件，但仍调用 WXApi.send（Objective-C sendReq）。当前锁定的 SDK 2.0.7 单独提供 sendAuthReq:viewController:delegate:completion，头文件明确注明支持未安装微信。

本地 SDK 证据：DerivedData 中 `WechatOpenSDK.framework/Headers/WXApi.h:183–191`。已安装微信时的 state、回调、取消及超时处理未发现其他确定缺陷；未安装场景本轮未作真机授权。

用户已确认的处理：保留现有 SDK 授权尝试；打不开时按发送回调及实际安装状态明确提示“请先安装微信”或授权请求失败。该路径已修复并有策略／FlowModel 回归，不改为专用无安装授权 API。真实已安装／未安装场景由用户验收；头文件中的能力不能代替设备验证。

## 初审其他检查结果与验证边界（历史记录）

- 掼蛋 reducer 完整分支、管理员修正、重复 finish、重开和快照恢复已检查；除上面的终局编辑 UI 问题，未发现其他确定回归。
- 升级换边及编辑／终局手势阻断、投篮训练按分值和命中分区撤销已检查，未发现确定的重复计分或跨区误删。
- 小组 canonical／legacy member 映射与本地后端契约一致，未发现确定的自我确认或成员归属回归。
- 微信 Universal Link／scheme 路由、state、请求取消、超时、Cookie 隔离、旧 401 与凭据替换、版本／工程 SDK 配置、英简繁独立表及新增资源已检查。
- 状态接口失败时绑定入口会暂时隐藏，当前是保守降级；可后续增加独立加载失败／重试状态，不据此改变服务端开关策略。
- 真机微信授权、未安装微信的授权、相机权限往返及实体触控手势需要设备验证。截图夹具不能证明这些真实授权与请求流程。
- iPhone 访客加入／登录 UI 测试记录到 `Invalid frame dimension (negative or non-finite)` 运行时警告；Xcode 未提供源码位置，相关断言均通过。当前证据不足以归因到本轮改动，保留为布局观察项，尚未定位修复。

## 初审验证（历史记录，最新结果见后文）

- JifenCore：252 项通过。
- 修复前会话 warmup 探针：2 项均复现失败；修复后会话隔离定向套件 19 项通过。
- 常用数据旧暂停探针：1 项复现失败，作为待决缺陷证据保留。
- 主工程最终全量单测：775 项，774 通过、1 项条件跳过、0 失败；`/tmp/jifen-uncommitted-audit-final-r2-20261024.xcresult`。本地化静态引用改为源码只解析一次后，完整套件耗时约 30 秒。
- iPhone UI：首轮 6 项断言通过但 Xcode 收集模拟器诊断卡住，已结束该进程并用 test-without-building 独立复跑；最终 6 项通过、结果包完整，涵盖绑定 merge／keep 往返、访客扫码入口、三种扫码后小组跳转；`/tmp/jifen-uncommitted-ui-iphone-r2-20261024.xcresult`。
- iPad UI：绑定 merge／keep 两项通过；`/tmp/jifen-uncommitted-ui-ipad-20261024.xcresult`。
- 工程／Info.plist、六份新增 strings 文件 lint、图标 JSON 解析及 `git diff --check` 均通过。
- Release 配置的 iOS 无签名编译通过；日志 `/tmp/jifen-uncommitted-release-20261024.log`。

## 二次复核与修复

用户已授权逐项复核、修复前三项并安装设备；第四项按用户选择完善失败回调提示，实际微信授权往返由用户验收。

修改前快照：`/tmp/jifen-audit-remediation-20261024-baseline/`，含已跟踪修改 patch、修改文件及新增文件归档、原始 status。保持原有工作区改动，没有提交。

1. **常用数据暂停归属已修复。** 等待同步前登记绑定 context UUID 和同步 sessionRevision；每次 await 后再次核对归属、认证 authRevision 及任务取消。关闭即使发生在暂停完成前，也能使旧任务失效；取消和完成只处理本流程的暂停。同账号重登后，旧流程无法冻结新同步。确认请求实际执行期间的关闭延迟至凭据和新基线安装完成，重新授权等待不属于这段临界区。
2. **续费提示已修复。** Assets 兼容解析可选 automaticRenewalCount／warnings；多订阅时预览展示简繁英提示“多份订阅将继续分别自动续费，关联账号不会取消自动续费”。兼容旧响应，单订阅不误报，不新增勾选或提交阻断。
3. **掼蛋终局编辑已修复。** 保留 reducer 终局 guard，编辑改为独立级数草稿，完成一次 adminCorrect 并形成一个撤销节点。没有修改直接完成、退出或丢弃不复活终局；同步替换实际状态后旧草稿不能覆盖新状态；记录和同步只读取已提交状态。A1/A2/A3 编辑为下一次 A 机会，对应失败数 0/1/2；保持主面板原有显示和三次失败回退规则。掼蛋没有换边入口，仍使用红左蓝右固定映射。
4. **微信失败提示已完善。** 保持绑定主动尝试现有 SDK 发送接口；发送 completion=false 或发送失败回包 -3 时，根据 SDK 实际安装检测区分“请先安装微信”与“无法发起微信授权，请重试”。绑定页透传具体错误；取消、拒绝、超时和过期 state 分别处理。没有声称未安装设备已完成授权，真实往返留给用户验证。

本轮自动验证：

- JifenCore 全量 255 项 Swift Testing 加 3 项 XCTest 通过，包含 A3 下一次失败按第三次回退的回归。
- 第一轮定向 77 项通过；最终主工程全量 793 项，792 通过、1 项条件跳过、0 失败。结果 `/tmp/jifen-audit-remediation-full-20261024.xcresult`。
- 新增四项常用数据时序回归覆盖同账号重登、关闭等待中的 flush、旧关闭／完成不能消费新暂停，以及来源过期后合法完成新基线；原失败探针对应场景已纳入通过套件。
- 新增直接 FlowModel 回归覆盖确认中关闭完成换凭据与基线、确认过期后重新授权期间关闭及迟到 code、具体微信错误与取消分离。
- 掼蛋草稿、A 档、无改动完成、同步替换和记录不泄露的主工程回归通过；多订阅／单订阅／旧响应解码回归通过。
- iPhone／iPad 各 4 项绑定 UI 测试通过，覆盖单／多订阅提示及 merge／keep；结果 `/tmp/jifen-audit-remediation-ui-iphone-20261024.xcresult`、`/tmp/jifen-audit-remediation-ui-ipad-20261024.xcresult`。
- Release 已干净构建通过，默认参数的隔离告警修正后最终开发签名构建通过；与前轮 Release 比较无新增告警类别，`codesign --verify --deep --strict` 通过。签名包含目标 iPhone、Apple 登录与关联域名，微信 scheme 正确。
- 真机测试包：`build/audit-remediation-2026-10-24/jifen.app`，`com.douhua.jifen.ios / 3.4 (78)`。二进制 SHA-256 `f70194866f9734c1b0fc54d300492ff5303d7c249d5c22cec76cf9e34a30be19`；构建日志 `/tmp/jifen-audit-remediation-device-final-20261024.log`。
- **设备安装完成并已启动。** 首次无线连接失败，用户解锁后继续无线重试成功；已保留数据覆盖安装至 iPhone SE，`com.douhua.jifen.ios / 3.4 (78)`，安装回执 databaseSequenceNumber **2540**。日志 `/tmp/jifen-remediation-install-r2-20261024.log`、`/tmp/jifen-remediation-launch-20261024.log`；构建与验证清单 `build/audit-remediation-2026-10-24/verification.json`。微信真实授权、绑定及未安装场景由用户继续验收。

## 后续复查：文案与状态澄清

- 再次审查中的前三项已由上节修复，第四项沿用用户确认的“尝试授权并明确显示失败原因”方案，待真机验收，不再列为待拍板设计问题。
- 修复英文资料／绑定卡片将登录按钮文案 `WeChat Login` 当作方式名的情况。新增独立的 `wechat_binding_wechat` 文案（英文 WeChat、简繁中文 微信），保留按钮原有登录文案；不再从翻译结果中删除中文字。WechatBinding 三种语言现均为 66 键。
- 用独立 DerivedData 运行 `AccountLinkContractTests` 与 `LocalizationIntegrityTests`，**58 项、0 失败**；其中新增实际英简繁资源的方式名回归。Xcode 原始进程退出码 0，结果 `/tmp/jifen-scan-parity-ios-20261024.xcresult`，日志 `/tmp/jifen-scan-parity-ios-20261024.log`。这次是定向验证，不替代上轮 793 项全量结果。
- 三份修改的 strings 均通过 plutil，`git diff --check` 通过。媒体和 demo 原样保留，没有删除、忽略或提交；本次英文文案修复没有重新安装至手机。
