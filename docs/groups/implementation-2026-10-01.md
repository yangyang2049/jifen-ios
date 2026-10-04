# 小组功能实现与验收记录

2026-10-01。三仓库代码和兼容迁移已实现，自检、本地自动验证及 iOS / HOS 模拟器双账号联调通过。真机回归尚未完成，不能把本记录视为发布验收通过。联调发现的问题及证据见 [自检与模拟器联调记录](self-review-and-cross-app-2026-10-01.md)。

## 已实现

| 范围 | 实现 |
| --- | --- |
| iOS 入口与页面 | 首页“我的球局”前的横向“我的小组”；概览、活动、战绩、成员四页签；创建、加入预览、审批撤回、管理员、临时成员、退出、转让、归档与恢复。复用现有登录与 APIClient。 |
| 四项目计分 | 羽毛球、乒乓球、网球、匹克球单 / 双打；明确选择 A/B 成员和席位，复用原生运动设置。活动可从更多报名者中选择实际参赛者，仍是一活动一场比赛。 |
| 会话与上传 | 稳定会话 ID 在首次计分前保存小组、账号、活动、席位、规则；零分中断也可续打。个人记录先落盘，再写持久队列；完赛触发上传，网络恢复 / 回前台 / 手动同步重试，本地记录可修复中断的队列写入。重启 / 换边保留成员身份。 |
| 离线与账号 | 自由局可离线完赛，首次上传原子建局；活动在线开局。缓存和队列按账号隔离；退出登录及 groupsEnabled 关闭暂停上传并保留待传数据。注销后清理小组本地数据并阻止旧记录重新入队。 |
| 战绩 | 补记与冻结规则、结果确认 / 作废、详情和分页；平局显示、单 / 双打分榜、满五场显示胜率；旧个人记录可选字段兼容，历史缺失规则显示“规则未记录”。 |
| 扫码与分享 | iOS VisionKit 相机、PhotosPicker + Vision 相册，Vision 运行环境失败时回退到 Core Image CPU 二维码检测；HOS ScanKit 相机 / 相册；统一 v1 JSON，兼容八位小组号；识别后预览再明确加入。已是成员可查看小组，待审批显示审批状态；两端白底静区二维码图片分享。 |
| 后端 | 版本化规则及席位快照、终局校验修正、比赛详情、平局和时间统计、分页游标、事务幂等 / 容量 / 结果状态、账号注销与审批并发修正。 |
| HOS | 自由计分关联、显式分队、原生规则传入、稳定草稿、首次开局中断恢复、可靠队列、平局 / 分页 / 真实扫码；演示仓储同步新校验。 |

共享上传体按字段白名单构建，仅含赛制、比分、参赛席位、规则与完成时间；个人备注、语音和完整计分过程留在本机。小组比赛结束后的菜单返回小组，避免在同一冻结比赛 ID 下重新开一局。

历史认领、轮转、联赛和网页承接按计划留待后续。旧规划保留，当前范围以本次批准计划及本记录为准。

## 代码位置

- iOS：`jifen/Features/Groups/` 为 DTO、规则、Repository、账号缓存、会话 / 上传队列、四页签、表单和扫码分享。首页、SessionStore、BookingStartPersistence、ScoreboardRecordManager 及 Rally / Tennis 计分板完成接入。
- HOS：`entry/src/main/ets/model/group/GroupMatchRules.ts`、`api/group/RemoteGroupRepository.ts`、`managers/group/`、`pages/group/`；八个项目计分板与记录管理器接入稳定会话和草稿。`scripts/test_group_rules_v1.mjs` 验证契约与队列，`scripts/test_group_remote_paths.mjs` 验证关联路径。
- 服务端：`api-server/src/lib/groups/`、`api-server/src/routes/groups.ts`、账号注销路由、Prisma schema 与 `20261001010000_group_rules_and_draws` 迁移；契约说明见后端仓库 `docs/groups-contract-v1.md`。
- 三端规则样例：各自 `rules-v1.json` 内容相同，17 个案例覆盖自定义分数、封顶、盘制 / 抢七、打满局数、平局、负数、终局超分及未完赛。

## 已执行验证

| 验证 | 结果与边界 |
| --- | --- |
| 服务端类型检查 | `pnpm run type-check` 通过。 |
| 规则 / HTTP / 数据库测试 | 50/50 通过，无跳过；在一次性本地 PostgreSQL 执行。包含并发建组、重复上传、JSON 键顺序重放、成员及报名容量、越权 / 跨组、冻结快照、确认 / 作废、归档只读、分页、完成时间统计、注销、审批与注销并发。 |
| 实际 SQL 迁移回归 | 通过。旧比分、胜方和空规则保留，迁移后新平局可提交；可重复脚本在后端 `api-server/scripts/verify-group-migration.ts`。 |
| iOS 单测 | GroupContractTests 5 项、NetworkResilienceTests 9 项及本地化资源一致性检查通过。覆盖三端样例、二维码协议、无封顶显式 null、首次零分草稿 / 换边席位、队列重启 / 去重 / 账号隔离 / 私有字段、仅抢七记分及注销后的队列修复隔离。 |
| iOS 构建与 UI | xcodebuild test 通过；iPhone SE 小屏浅色 / 深色、iPad 11 英寸浅色四页签、平局、分享页面回归通过。UI 使用 DEBUG 隔离夹具，不计作双账号网络联调。 |
| HOS 构建 | `hvigorw assembleApp --no-daemon` 通过；使用 SDK 父目录 `/Applications/DevEco-Studio.app/Contents/sdk`。 |
| HOS 脚本 | 17 个同源规则样例与扫码 / 自定义设置通过；队列重启、账号隔离、功能开关、去重、仅抢七及隐私白名单通过；关联路径检查通过。 |
| 双端模拟器真实 API | 两个本地账号走正常登录、正式 Repository 和真实服务端路由；iOS 创建 / 审批 HOS，HOS 创建 / 审批 iOS；鸿蒙二维码经 iOS 系统相册识别、预览并申请加入。两端活动报名、HOS 原生计分及补记、iOS 确认、平局排行均通过。共两组各两成员、三条已确认结果、一个完成活动。 |
| HOS 中断与离线 | 首次零分草稿强退 / 续打、自动换边保留成员身份、停止本地 API 后完赛 / 恢复后上传、多次重启去重均通过。离线采用 API 不可达模拟，不等价于真机飞行模式。 |
| iOS 真机尝试 | 检测到 iPhone SE，源码完成真机构建；测试运行器安装被设备拒绝，错误 `0xe8008018`，签名身份无效。允许 Xcode 自动更新 provisioning 后重试，仍得到相同错误；未执行真机 UI 测试，不能计作通过。 |
| 图片解码 | 用 Apple Vision 从 iOS 与 HOS 实际界面二维码图片成功识别 `JIFEN_GROUP`、v1 与八位小组号；不等价于相机真机交叉扫码。 |
| 工作区检查 | 相关文件 diff 空白检查通过。原有三仓库未提交修改保留；未提交 Git、部署生产或执行生产迁移。 |

日志及 UI 证据位于 [artifacts/2026-10-01](artifacts/2026-10-01/)，新增网络联调证据在 [cross-app](artifacts/2026-10-01/cross-app/)。截图只含隔离夹具、演示或本地测试账号。一次性本地数据库清理状态见自检记录；日志与可重复脚本保留。

## 后续发布前验收

以下项目仍需测试环境及真实设备验证：

1. 相机真机互扫、HOS 相册识别 iOS 图片，以及系统分享后接收图片再识别；目前已验证 HOS 图片经 iOS PhotosPicker 识别 / 加入 / HOS 审批。
2. 两端真机首次开局中断、强退续打、换边、飞行模式完赛 / 恢复上传、账号切换及开关关闭 / 恢复；iOS 原生计分现场流程及四运动双打设备回归。当前现场网络联调使用 HOS 羽毛球单打，其他项目由同源规则测试、持久化测试和构建覆盖。
3. HOS 折叠实体设备回归，iOS 相机权限与 VisionKit 支持设备回归；当前模拟器通过不能替代这些检查。iPhone 测试需要先恢复设备认可的开发签名，HOS 当前未连接真机。
4. 在测试环境应用迁移并部署服务端，再用安装包联调。线上发布 / 提审前按既有发布门槛执行设备回归。

新资源接入现有 47 语言资源表；新增小组文案提供英文、简体中文与繁体中文，其他语言当前采用英文回退，尚未逐语种人工审校。

## 复现命令

从 iOS 根目录：

```sh
xcodebuild -project jifen.xcodeproj -scheme jifen -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' -derivedDataPath /tmp/jifen-group-derived CODE_SIGNING_ALLOWED=NO -only-testing:jifenTests/GroupContractTests -only-testing:jifenTests/NetworkResilienceTests -only-testing:jifenTests/LocalizationIntegrityTests/testLocalizedResourcePairsStayInSync -only-testing:jifenUITests/GroupFeatureUITests test
```

从 HOS 根目录：

```sh
node scripts/test_group_rules_v1.mjs
node scripts/test_group_remote_paths.mjs
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleApp --no-daemon
```

服务端数据库测试与迁移回归命令见其契约文档；脚本会检查本地数据库名称，测试数据不得指向生产。
