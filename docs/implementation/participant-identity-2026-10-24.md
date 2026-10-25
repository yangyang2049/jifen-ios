# 本人身份、关联名称与私人记录实施记录

方案日期：2026-10-24。实施与本地验证：2026-10-24 至 2026-10-25。后端于 2026-10-25 10:35 经用户授权、二次复核后增量上线，见末节；客户端未安装真机或发布，未创建 PR。保留各仓实施前已有改动。

## 已落地的产品口径

- 统一入口名称为“我的记录”。沿用账号昵称，不增加 Display Name，本轮不新增小组昵称配置。
- 未登录已有稳定的“本机的我”。Setup 可直接选“我”；登录后自动承接尚未归属账号的本机身份和私人全库，含代记、计时、文字及语音。私人库归属与本人参赛身份分开。
- 常用名称的选手页直接展开本人分组，`0 / 3` 也保留入口；历史名称按名字整批确认，落库锚定具体 library、record、seat。保留历史名字、比分、动作和回放。
- 最多 3 个 active 关联名。自动置顶的当前昵称不占关联名额；隐藏名称仍占名额，解除才释放。合并或承接超额名称保留为 pending，不阻断账号绑定或其他记录同步。
- 选人时本人入口置顶、关联名显示“我”。同一 PersonRef 只能占一个有效个人位置，当前位置可换自己的别名；手动同名不自动带身份，编辑姓名会清除原身份。
- 解除只撤销 alias 形成的历史关联，直接以本人身份保存的新记录保留。新导入旧记录须再次按名字确认。歧义记录不计入本人统计。
- TEAM、PERSON、训练结果标签保持分离。显式团队赛（含踢毽 3+3）不做个人名字关联。
- 小组私人备份不进入私人本人统计。个人页按现有小组权限读取正式账号成员的已确认成绩，处理 canonical/legacy member ID，排除临时成员、代录者与多个本人位置。跳转既有赛果详情。
- 记录根页正文第一项长期保留“我的记录”；个人页、历史名称页为二级页，隐藏主 Tab bar。
- 全部／计分／计时收入“更多 → 筛选”，和时间、项目一起应用或取消。生效时左侧条件换行，右侧“清除筛选”固定宽度并保持可点击；保留搜索词。更多按钮无额外筛选绿点。
- 空筛选结果保留状态行和一键清除；根页、个人页筛选独立，切换账号清空，筛选不上传云端。

## 代码入口

| 范围 | 主要入口 |
| --- | --- |
| iOS 规则与侧表 | `Packages/JifenCore/Sources/ScoreCore/ParticipantIdentity.swift`；`jifen/Features/Identity/ParticipantIdentityStore.swift` |
| iOS 同步与数据适配 | `PersonalRecordsCloudSync.swift`、`PersonalRecordAdapter.swift`、`PersonalGroupRecords.swift` |
| iOS 展示和读取隔离 | `ParticipantIdentityViews.swift`、`PersonalRecordAccessPolicy.swift`；常用名称、Setup、记录、首页、续局与详情已接线 |
| 后端 | [接口契约](../../../jifenqi-backend/doc/participant-identity-private-records-api-2026-10-24.md)；`api-server/src/lib/participantIdentity/`、路由、账号资产注册、删除与附件清理 |
| Android 国内／Google | [国内交接](../../../jifen-android/docs/participant-identity-private-records-implementation-2026-10-24.md)；[Google 交接](../../../jifen-android-google/docs/participant-identity-private-records-implementation-2026-10-24.md) |
| HarmonyOS | `jifen-hos/entry/src/main/ets/managers/participantIdentityManager.ts`、`privateRecordsSyncManager.ts`、`privateRecordStore.ts`、`personalGroupRecordsManager.ts`；既有手机／手表桥接增量传递身份 |
| 网页与小程序 | `jifenqi-website`、`iscoreboard-website`、`jifen-wechat` 的实际选人、保存、名称管理、记录与登录入口，共用私人身份同步核心 |

## 同步与账号绑定边界

私人写入先落持久队列，再带 mutationId 与 expectedRevision 发出；同步游标、删除墓碑、历史 claims、音频任务都按 owner/library 隔离。未知网络结果重放相同请求；明确过期的 adoption 才重新 prepare。历史 claims 写入使用服务端严格六字段输入，不直接上传读取模型。

全库保存原始 nativePayload 与未知 JSON。删除已知备注或语音用显式 null，并清理音频引用，避免合并恢复已删内容。语音独立执行 manifest／二进制上传／complete，跨端下载走鉴权接口。未知平台或不支持的原生版本使用通用只读详情。

多端编辑冲突保留版本并提供处理入口；云端已删除的记录只能另存新副本。原生文件即使保留为备份，也会被统一展示权限与墓碑策略隐藏，包含首页、续局和详情入口。

现有微信绑定的直接绑定、merge／keep、主账号昵称和会员选择、小组确认、已有阻断项与结果回执逻辑保留。新身份与私库队列加入现有暂停／恢复边界；不要求绑定前上传完整记录或音频。新域失败不能把已成功绑定显示成失败。

merge 保留可归并库并统一 canonical 身份，主账号有效名称优先，额外名称待整理；keep 归档来源库与队列，不能通过账号家族列表或新游客承接重新取得。迟到回包须核对原 owner 和会话。iOS／鸿蒙的新域本机后处理有可恢复状态；Android 原产品没有微信绑定 UI，本轮仅保留可信回执的接入钩子，没有新增绑定 UI。

## 本地验证

- iOS：88 项 app 定向测试通过，包括既有微信绑定／会话隔离、Setup、清本地数据，以及新增身份、离线承接范围与账号切换屏障、历史 claims 严格请求、丢回执重放、过期承接、备注／语音清除和读取隔离，以及远端新 revision 替换旧本机展示；ScoreCore 5 项身份测试通过。
- iOS UI：iPhone SE 3 与 iPad Pro M5 跑通筛选、空结果、一键清除、左右区域不重叠、44 点清除按钮，以及个人页隐藏主 Tab bar。SE 另作最终长条件回归。属于模拟器验证。
- 后端：隔离 PostgreSQL 中真实 HTTP／事务回归 54 项通过、0 跳过；包括现有微信 merge／keep、丢回执、会话撤销、私人库和音频隔离。TypeScript 类型检查通过。仅测试库应用新迁移。
- Android／Google：对应变体 Kotlin 编译通过；最终复核后的定向测试每仓 44 项通过，真实 HTTP 捕获的 20 份请求通过后端 Zod schema（另有旧全字段 claim 负向对照）。先前 Setup、认证／小组和记录回归同样已通过，详见各仓交接。
- HarmonyOS：entry 与 wearable 编译通过，新增本人、私库、音频、小组、owner 竞态、承接、撤销、空值删除和离线游客库归属等真实逻辑回归通过。entry 最终日志 `/tmp/jifen-hos-clear-guest-pin-closeout-build.log`。
- 网页／小程序：双站 TypeScript 通过，共享核心及真实 Session 28/28，小程序最终全量 208/208，WXML 69／WXSS 73 文件编译通过；使用隔离测试库及 loopback HTTP 验证承接、记录、历史关联、音频、冲突与账号隔离，未访问生产数据。

iOS 最新单测日志：`implementation-baseline/ios-identity-closeout.log`；小屏与 iPad UI 日志：`ios-final-ui-closeout.log`（早期压力回归：`ios-filter-stress-ui.log`、`ios-final-se-stress.log`）；这些位于本任务 visualization 的 `implementation-baseline` 目录。后端最新日志：`/tmp/jifen-participant-root-regression.log`。各端临时日志由对应交接给出。

## 验证限制

本轮没有真机 UI、折叠屏或真实微信授权回调回归；iOS／Android／鸿蒙原生客户端尚未完成新后端的实际设备联调。编译、模拟器和 mock transport 不等同于设备联调。后端代码和迁移现已上线并完成专用临时账号 HTTP 验证；客户端尚未发布。

鸿蒙既有 `test_linked_setup_timeout_recovery.cjs` 的 lost READY 用例仍失败；内存移除本轮协议增量后的基线同样失败。未扩展或改写原手表控制流，日志 `/tmp/jifen-hos-linked-baseline-test.log`。因此不能把既有联动全部回归标成通过。

跨端基础数据已具备，年终总结和 AI 分析不在本轮。独立手表不增加账号生态。正式交付包仍需按实际渠道和目标设备回归后再发布。

## 后端上线补记（2026-10-25 10:35，Asia/Shanghai）

用户授权二次复核后部署。后端当前源码与最终增量运行组合分别通过真实 Postgres/HTTP 54 项、0 跳过；生产纯结构副本迁移演练确认原 78 张表定义不变、新增 10 张表。正式服务器只发布本功能 7 个运行模块、对应源码、schema/migration 与生成后的 Prisma Client，其他运行文件和环境配置哈希未变。

正式 `https://api.jifenqi.com/api/health` 为 200；新增身份/私库路由已上线，未登录返回 401。专用临时账号的身份承接、历史关联、记录 push/pull、筛选、权限隔离、冲突、删除及音频上传下载校验通过，测试账号和音频已清理。

生产 Nginx 仍为 3 MiB：60 秒 AAC 测试文件 494,756 字节，公网往返通过；3,840,044 字节 WAV 在公网被 413 拦截，内网服务往返通过。契约的 10 MiB 公网兼容仍需 sudo 调整网关后复测；配置与安全应用脚本已备好，本次未修改 Nginx。完整部署证据和私有备份位置见 [后端交付核验](../../../jifenqi-backend/doc/participant-identity-private-records-verification-2026-10-24.md)。
