# 小组功能：前后端协同设计

版本：v0.6，2026-09-26。状态：待原型评审；本文是拟议契约，**所有新增实体、接口、组件均尚未实现**。本轮只写 HTML 和文档。

## 1. 产品边界与已确认入口

小组是固定一个项目、长期存在的熟人组织，账号成员与临时成员共享活动和比赛历史。自由比赛是基础能力；轮转、联赛是小组下的模块，不把小组分成互斥类型。

**2026-09-26 用户确认：首页现有约球版块之前新增一条横向“我的小组”入口。** 点击进入列表，无小组时进入创建/加入引导。入口可显示一行摘要；不在首页展开多个小组，不新增 Tab，不合并/替换现有“我的球局”。iPhone 与 iPad 均在对应 `buildScheduleSection()` 前放入口；首页其他区域顺序沿用当前平台布局。

小组详情为概览、活动、战绩、成员四个页签。概览的主操作为立即计分、约一场，组织活动提供轮转/联赛入口。底部继续使用首页、记录、计分、计时、我的五个标签。

### 我的小组空状态（2026-09-26）

首页横向入口进入“我的小组”；当已成功获取列表且没有任何可见小组时，展示完整空状态，不是只有一句“暂无数据”。版式为居中的小组线性图标、标题/介绍、三条简短能力说明、创建/加入两个入口。复用系统背景和卡片样式，不增加轮转、联赛等后续阶段的宣传入口。

固定文案：

- 标题：**还没有小组**。
- 介绍：**把常一起玩的朋友聚在这里，约一场、记比分，一起看战绩。**
- 约好每一次活动：确定时间和地点，成员报名参加。
- 记录每一场比赛：现场计分，也可以赛后补记。
- 积累共同战绩：查看比赛记录和小组排行榜。
- 主按钮“创建小组”，次按钮“加入小组”；次按钮下说明“已有朋友的小组？输入小组号或扫码加入”。

创建入口打开既有创建表单，加入入口进入同一小组号/扫码页面；取消或返回仍停在空状态。创建成功立即进入新组详情，并刷新首页摘要及列表；已有成员关系生效后同样退出空状态。不能因申请还待审批就假装已经加入，应另外保留待审批入口/状态。文案介绍的是小组功能，不是某个具体小组的用户自填简介。

UI 状态不能混用：加载中/网络请求失败/账号未登录不直接当作“无小组”。离线且已有缓存时显示缓存列表；确认空列表的离线缓存可以保留介绍并提示联网，创建/加入写操作不可用。未登录用户可看介绍，点创建/确认加入时走既有登录恢复。**原型 v10 已画加载中与请求失败两态**（含"失败 ≠ 无小组"文案与重试）；小组号查找结果页与结果详情页的对应态仍未画，见 PRD 第 14 节。

待审批必须有回访通路，且**不要求先成为成员**：`GET /groups` 的响应带 `pendingJoinRequests`（当前账号在审批中的申请摘要：groupId、groupNo、name、gameType、reviewedAt?），另提供 `GET /groups/join-requests/mine` 供单独拉取与撤回，两路由都注册在通用 `/:groupId` 之前。列表页与空状态在顶部显示"加入申请待审批 · 组名/小组号"卡片，提供"刷新审批状态"与"撤回申请"；首页横条摘要同一数据源显示一行待审批提示。刷新是显式按钮而不是下拉手势：iOS 现有工程全仓未使用 `.refreshable`（本地核验 2026-09-26），不为本功能新引一种刷新惯例。撤回成功后卡片消失、加入页回到预览，允许再次申请并受 §6 冷却/限流约束。

### 小组号与二维码：两种加入/分享方式（用户确认）

每个小组创建时分配唯一、长期不变的纯数字 `groupNo`。用户可选择「输入小组号 → 查找 → 查看简介 → 加入」或「扫描二维码 → 查看简介 → 加入」。分享对应复制小组号和分享二维码，底层都指向同一号码；这是用户明确的两个平行入口。普通加入不再提供第二套邀请码，不再有有效期、使用次数、重新生成或撤销邀请的设置。

- UI 统一称“小组号”，避免“邀请码”和“小组号”两个概念并存。列表、详情及分享页展示号码，普通成员也可复制分享。
- 建议首期 8 位十进制数字、不以 0 开头，如 `82603158`；**8 位是本稿建议，用户明确的是纯数字、固定号码。** API/客户端仍用 String 保存与传输，避免以后扩位受整数表示限制。
- `groupNo` 是公开查找标识，不是认证凭证；知道号码不等于拥有访问内部成员/战绩的权限。
- **创建时只有两种加入方式**：`OPEN` 直接加入、`APPROVAL` 需要审批；不能选择 `CLOSED`。创建者自动成为首位账号成员和唯一组主，创建成功后优先引导分享小组号/二维码邀请朋友。建议默认 APPROVAL，默认值仍是设计建议。
- **创建后**组主可在设置将加入方式改成 `CLOSED`（关闭加入），以后可重新开放。关闭仅暂停新账号成员的加入及待审通过，不解散小组、不移除已有成员、不妨碍已有成员活动和计分。临时成员只是未注册球友的参赛占位，与关闭加入无因果关系，不要求新组先使用临时队员。
- 首期只提供完整号码精确查找，不扩展为公开推荐或名称模糊搜索。查找只返回名称、项目、人数和加入方式，加入后才可看内部信息。
- 已登录用户直接加入/申请，不额外走登录页；未登录用户点击后登录，恢复号码上下文，再以最新状态重新校验。
- 临时球友历史认领不是普通加入：仍须本人确认与管理员核对，不能仅凭公开小组号认领任意成员历史。其内部一次性凭证不叫“小组邀请码”。

### 二维码交互与契约

- 加入页并列提供“查找小组”和“扫一扫”；扫描器支持相机扫描和从相册识别。不授权相机时仍可输入号码，不把相机授权设为加入前置。
- 小组详情/成员页进入“邀请朋友”，选择“复制小组号”或“分享二维码”。二维码页展示组名、清晰二维码、数字小组号，提供保存和系统分享；可保存的图片必须保留白色静区，深色模式不反色编码。
- 正式二维码编码自有域名的规范 HTTPS 加入链接，结构如 `/groups/join?groupNo=82603158`；准确域名及 Universal Link / App Link / 小程序承接配置在实施时核验。手输/相机/相册/深链最终都解析成同一个 groupNo，走相同 preview 与 join API，不另建二维码邀请 token、过期或用量机制。
- App 扫描器只解析受支持版本与白名单域名路径，不自动打开任意二维码 URL。识别无效码提示重新扫描或输入号码；识别成功关闭扫描器，去重连续识别，再获取服务端预览，**不自动加入**。
- 组改名后的旧码仍定位相同号码并读取最新资料；关闭加入/满员/归档/解散在扫码时同样生效。二维码不是绕过审批的另一条路径。
- 未安装 App 时由 Web 落地页显示最小资料与打开/下载入口；微信扫码的 H5/小程序承接需独立配置与真机验证，不能假设普通二维码天然就是小程序码。
- 本轮 HTML 生成可解码的真实二维码，payload 仅为示例数字小组号，用于视觉评审；“扫一扫”和“相册识别”使用显式模拟，不申请设备权限。正式版替换为上述 HTTPS payload，不把纯文本示例码当已上线跨端能力。

### 范围分层（建议，待用户评审）

| 阶段 | 能力 | 准入条件 |
|---|---|---|
| 当前设计阶段 | HTML 闭环与前后端契约 | 不改业务代码 |
| Phase 0 | 身份/权限、项目能力目录、结果契约、持久队列与缓存设计 | API/迁移与异常用例评审完成 |
| Phase 1 | 固定项目小组、按号加入/审批、成员/临时认领、约球、自由计分、结果确认、战绩 | 首批羽毛球/乒乓球/网球/匹克球的单/双打（同为 A 档结果形状）；各端按能力开关接入 |
| Phase 2 | 轮转、签到、场地分配、主控租约 | 轮转专项算法与离线策略确认 |
| Phase 3 | 固定参赛单位联赛、赛程、积分榜 | 规则版本/赛程/结果修正评审 |

暂不承诺公开发现、俱乐部、聊天、收费门槛、推送必达、赛事导出、手表管理。用户不登录仍可原样使用个人计分。未登录点小组入口可看说明/小组最小预览，创建和加入需现有登录流程。

## 2. 当前代码核验（本地工作区，非线上部署核验）

iOS 根目录 `/Users/yangyang/Desktop/jifenqi/jifen-ios`；后端根目录 `/Users/yangyang/Desktop/jifenqi/jifenqi-backend`。

| 位置 | 已有事实 | 设计影响 |
|---|---|---|
| iOS `Features/Home/HomeTab.swift` 的 `buildScheduleSection()` | 首页已有本机约球、创建 sheet、导航和开始计分回调 | 在该区块前插横向入口，复用现有导航栈，不套第二个栈 |
| `Features/MainTabView.swift` | 首页/记录/计分/计时/我的 5 Tab | 不加第六个 Tab，不把小组战绩冒充全局记录 |
| `Features/Schedule/LocalBooking.swift`、`LocalBookingManager.swift` | 本机约球，有项目/赛制、名字、提醒、日历字段；名字归一化去重 | 账号身份不能用名字关联；小组活动另设缓存模型，不能直接改成本机约球云同步 |
| `BookingStartPersistence.swift` | 先持久化初始计分状态，返回续打 ID；支持多个项目 | 加小组启动上下文，保留单活跃会话保护与可靠续打 |
| `Features/Records/ScoreboardRecord.swift` | **currentSchemaVersion=5**，有 winnerIdentity、setResults、配置/快照、备注/语音 | 不能照搬旧文档的 v4 假设；分享成绩使用白名单 DTO，不上传整条私人记录 |
| `ScoreboardRecordManager.swift` | 正式记录先可靠落盘，再清理续打快照 | 小组网络失败不得回滚个人记录 |
| `Core/Link/RecordSyncOutbox.swift` | 已有匿名 identity、时间戳 revision、稳定散列 ID 的本地队列 | 存在 outbox 不等于存在账号小组服务端同步；不能直接复用其身份和冲突语义 |
| `Core/Network/APIClient.swift`、`Features/Account/SessionStore.swift` | JWT/刷新、actor 网络层；错误解析使用 `error/message` | 新接口对齐错误字段；网络层需支持自定义幂等/版本头及读取冲突信息 |
| `Core/Theme/Theme.swift` | 系统语义背景、卡片、浅/深绿、iPad 宽度规则 | 原生实现沿用现有主题；HTML 是交互稿，不是替换原生设计系统 |
| 后端 `api-server/package.json`、`src/index.ts`、`prisma/schema.prisma` | Express + TypeScript + Zod + Prisma + PostgreSQL | 增加模块化路由/服务/迁移，不另起第二套账号服务 |
| 后端 `User`、`Identity`、`middleware/auth.ts`、`lib/userResolver.ts` | 内部 `User.id` 是 CUID，另有数字 `uid`；身份与账号映射存在 | 小组外键使用内部 `User.id`；`uid/openid/unionid` 都不能代替成员主键 |
| 后端 `routes/events.ts`、`routes/matches.ts`、`Match/MatchParticipant` | 公开组局和实时房间；房间有显示端/控制端角色 | 不给小组成员自动授予房间控制权限；小组号和投屏码完全独立 |
| 后端 schema 与路由文件检索 | 未发现正式小组域或通用个人完赛记录归档模块 | Phase 1 新增独立 `GroupResult`，不假设只传 recordId 后端就能读取本机文件 |
| 后端 `routes/accountDeletion.ts` | 已有注销、审计、匿名化流程 | 加小组所有权检查/清理，不能创建新的无法处理的账号依赖 |

项目能力开关应扩展现有 `lib/scoreboardCatalog.ts` / `routes/clientConfig.ts` 的服务端目录思路。现有实时房间 `allowCreateMatch` 不能当作“允许小组统计”的标志。未核验的账号合并能力不视为已完成，合并接入属于上线前必查项。

## 3. 客户端与服务端职责

| 业务 | 客户端 | 服务端 |
|---|---|---|
| 小组与成员 | 表单、缓存、状态提示、隐藏无权动作 | 唯一权威、鉴权、配额、审批、审计 |
| 按小组号加入 | 数字输入/二维码识别、精确查找、保留登录前号码、明确加入 | 号码唯一性、加入方式、限流、名额、重复加入/审批 |
| 约球 | 表单草稿、报名 UI、个人本机提醒 | 活动版本、容量、截止时间、参加资格 |
| 计分过程 | 现有本机引擎、单活跃会话、续打、个人记录落盘 | 不参与每个加分动作；实时房间沿用独立协议 |
| 比赛结果 | 显式席位成员 ID、快照、白名单结果、可靠 outbox | 校验规则、去重、确认/争议/作废与结果版本 |
| 战绩 | 展示统计版本及来源比赛，不永久自行累计 | 从已确认有效结果派生，可重算 |
| 通知 | 前台刷新、本地提醒、通知权限由用户控制 | 域事件与投递任务；推送是可选加速，不是正确性依赖 |

一致性边界：正式个人记录与“待共享小组结果”在同一设备持久化；是否计入小组战绩由服务端结果状态决定。清除个人记录不等于撤销已分享结果，必须走明确的结果作废/更正流程。

## 4. 页面与权限契约

页面列表：首页横条、小组列表/空态、创建、小组号查找/预览/登录恢复、详情四页签、约球编辑/详情、席位选择、提交状态/结果详情、成员管理/认领审批、设置/转让/退出/归档。

角色与身份正交：`OWNER / ADMIN / MEMBER`；`ACCOUNT / TEMPORARY`。临时成员没有登录权限，也不能当所有者/管理员。初版设置默认普通成员可约球和自由计分；所有账号成员都可分享小组号；审批和临时成员管理仅所有者/管理员，加入方式仅所有者修改。

| 动作 | 所有者 | 管理员 | 普通账号成员 |
|---|---|---|---|
| 浏览、自己的报名、允许范围内计分/提交 | ✓ | ✓ | ✓ |
| 修改/取消活动 | ✓ | ✓ | 自己创建且未开始的活动 |
| 分享小组号 | ✓ | ✓ | ✓ |
| 修改小组简介（description，选填、≤200、可清空） | ✓ | ✓ | — |
| 审批、临时成员认领核对 | ✓ | ✓ | — |
| 修改加入方式 | ✓ | — | — |
| 移除普通成员 | ✓ | ✓ | — |
| 任命/撤销管理员 | ✓ | — | — |
| 转让、归档/恢复、解散 | ✓ | — | — |
| 确认结果 | ✓，留审计 | ✓，留审计 | 非提交者且属于对方参赛席位 |
| 作废/裁定冲突 | ✓，必填原因 | ✓，必填原因 | 只能发起争议 |

任何写入均由服务端重新检查：当前账号是否有效、是否为有效成员、小组是否可写、对象是否属于该组、实体版本是否匹配。请求体不接受用户自报 role / submitterUserId / confirmedBy。

归档只读，所有者可以恢复；成员仍可在线退出。移除/退出立刻失去访问权并取消未开始活动报名，历史成员逻辑保留。所有者不得直接退出；新所有者必须为有效账号成员且不是自己，转让事务内更新唯一 owner 及双方角色。

## 5. 数据模型（新增建议）

新表名用 `ScoreGroup` 等避免 SQL 关键字 `GROUP`。新 ID 使用服务端不透明字符串，客户端离线命令用 UUID；不要要求现有 CUID User.id 改格式。每张业务表至少含 id、createdAt、updatedAt，可编辑对象含 bigint revision（API 输出十进制字符串，避免 JS 精度问题）。

| 实体 | 核心字段 / 约束 |
|---|---|
| ScoreGroup | groupNo（唯一且不可改）、name(2–24 Unicode scalar)、description(≤200)、gameType、timezone(IANA)、status、joinPolicy、ownerMemberId、memberLimit、settings、revision、changeSeq。gameType 创建后锁定 |
| GroupMember | groupId、userId?、kind、displayName、role、status(ACTIVE/LEFT/REMOVED/MERGED)、mergedIntoMemberId?。对非空 userId 保证 `(groupId,userId)` 唯一，重返恢复原成员关系并留审计 |
| GroupJoinRequest | groupId、userId、status、message、reviewerId、reviewedAt；同一用户最多一条 PENDING |
| GroupClaimRequest | groupId、temporaryMemberId、claimantUserId、status、reviewerId；可选单次认领凭证摘要、有效期、消费状态；凭证只用于指定临时成员，不复用公开小组号 |
| GroupActivity | groupId、creatorMemberId、type(CASUAL，预留 ROTATION)、formatId、ruleSnapshot、startsAt、timezone、durationMinutes、placeSnapshot、capacity、registrationClosesAt、status、revision |
| ActivityParticipant | activityId、memberId、status(REGISTERED/CANCELLED)、joinedAt；唯一 `(activityId,memberId)`；临时成员由管理员代报名 |
| GroupGame | groupId、clientSessionId(UUID)、creatorMemberId、activityId?、formatId、ruleSnapshot、participantSnapshots、state(STARTED/SUBMITTED/ABANDONED)、revision；保留开局身份/规则，不作为成绩事实 |
| GroupResult | groupId、gameId、clientRecordId、recordSchemaVersion、submitterUserId、source(SCOREBOARD/MANUAL)、playedAt、finishedAt、formatId、ruleVersion、resultPayload、canonicalHash、status、revision。唯一 gameId；唯一 `(submitterUserId,clientRecordId,groupId)` |
| ResultParticipant | resultId、memberId、side(A/B)、seat、displayNameSnapshot；唯一 `(resultId,memberId)`，成员必须同组且开赛时有资格 |
| ResultRevision | resultId、revision、immutablePayload、status、reason、actorId；确认/更正/作废保留旧版本 |
| GroupChange | groupId、changeSeq、entityType、entityId、operation(UPSERT/DELETE)、payload、committedAt；用于可靠增量 |
| GroupAudit / DomainEventOutbox | 敏感操作记录与事务内待投递事件；不给普通成员暴露完整内部审计数据 |
| IdempotencyReceipt | actorUserId、operation、key、requestHash、statusCode、response、expiresAt；唯一三元组 |

数据库约束：`kind=ACCOUNT` 时必须有 userId，TEMPORARY 时无 userId 且 role=MEMBER；ownerMemberId 必须引用本组 ACTIVE ACCOUNT；用同组组合键/事务验证避免跨组外键。活跃 owner 唯一可用部分唯一索引加事务约束维护，迁移中显式定义 Prisma 无法表达的约束。所有者创建与首个成员原子提交。

索引：`GroupMember(userId,status,groupId)`、`GroupActivity(groupId,status,startsAt,id)`、`GroupResult(groupId,formatId,status,finishedAt,id)`、`GroupChange(groupId,changeSeq)`、待审批/待确认索引。分页排序末尾始终加 ID。

### 小组号分配与生命周期

服务端使用随机分配（建议 8 位、首位非零）+ 数据库唯一索引，冲突后在有界次数内重试；创建组与分配号在同一事务。客户端不得自行生成正式号码。用独立 `GroupNumberRegistry(groupNo UNIQUE, groupId?, allocatedAt, retiredAt?)` 或永久保留的组 tombstone 确保解散/删除后不回收旧号，旧二维码不会误导到新小组；编号池高水位时规划扩位并通过能力目录下发长度，禁止无限重试。

组更名、转让、归档/恢复及加入方式变化均不改号。精确查找使用 groupNo 唯一索引，只返回明确白名单字段；号码公开也不能批量导出内部数据，查找接口按 IP/登录账号限流。不存在和已解散统一“未找到”，关闭加入/已归档可展示最小卡片但不能加入。管理员移除且标记禁止重返的成员不能凭同一公开号重新自动加入，须先由管理员解除限制。

无需创建 `GroupInvite` 表及普通邀请 token 验证服务。`GroupNumberRegistry` 是公开标识账本，不存账号认证信息。

### 临时成员认领与账号合并

1. 管理员发仅对应一个临时成员的认领邀请；账号用户先确认本人，再由管理员确认。
2. 用户未在组内：原 temporary member 转为 ACCOUNT，保留 memberId 及历史。用户已在组内：临时 member 标为 MERGED 并指向已有 member，不按姓名自动合并。
3. 原始历史快照不改写。统计解析 canonical memberId；若一次比赛合并后同一账号落在双方席位，标记待人工核验并暂不入榜，禁止重复计场。
4. 同时锁定两个成员，检查并发认领；迁移未来报名、取消重复报名、重算结果归属、revision/change log/audit 一并提交。
5. 不同登录提供方仅在确认为同一内部 User.id 时自然跨端互通；真正账号合并须接现有身份归并流程并处理重复成员、owner、幂等回执、待提交映射，不能承诺相同昵称自动互通。

## 6. 状态机与核心事务

### 加入

`输入号码 → 精确查找 → 确认加入 → 必要时登录 → 已加入 / 待审批 / 不可加入`。待审批是**按账号**可查的状态，不依赖 groupId（见 §4 的 `pendingJoinRequests` 与 `/groups/join-requests/mine`），否则非成员没有任何入口知道自己的申请还在等。

加入请求按 groupNo 解析到内部 groupId，先检查账号状态和是否已有有效成员关系；已加入返回同一成员关系，不重复插入，也不因当前满员/关闭加入而阻止已有成员正常进入。

新加入时锁小组行，重新检查当前加入方式、小组状态、账号资格/移除限制、实时容量。OPEN：同事务插入或恢复成员、更新 revision/change log；APPROVAL：同一账号最多一条 PENDING，申请不占名额。通过时锁组和请求、重新检查容量/资格/小组状态/加入是否关闭，插入成员与审批状态原子提交。避免多人抢最后一个名额。

组主切换 CLOSED 后暂停新的加入与旧申请通过，待审批申请保留；重新开放后管理员可继续处理。APPROVAL 切换 OPEN 不自动把所有待审用户加入，用户再次点击加入或管理员批准才消耗名额；成功加入后同账号旧 PENDING 一并收口为 APPROVED，避免悬挂申请。拒绝/撤回保留历史，允许重新申请时受冷却/限流控制。

建议默认成员数 30，硬上限 50，临时成员也占名额；这些是旧 PRD 延续的待确认配置，由服务端返回，不再存在邀请使用次数限制。

### 活动与开赛

持久状态 `RECRUITING → IN_PROGRESS → COMPLETED`，开始前可 CANCELLED；草稿在客户端，`FULL` 是报名数达到 capacity 的派生显示，不作为第二个可变事实。时间戳 UTC，显示使用活动 IANA 时区并向跨时区用户标注。

报名事务校验截止、容量、成员资格、归档状态；不提供“本机报名成功、稍后再说”的离线假成功。修改活动带 revision，降低容量不得低于有效报名数，开始后锁定赛制/参与席位。

首期普通约球建议“一次活动对应一场正式比赛”，capacity 可大于席位数，但开始时选定实际对阵。对同一 activity 只允许一个未放弃/未作废的 game。重复开局返回现有 game 或 409，不能多端各自建立两场。

在线开始：服务端创建 GroupGame / 占用 activity → 本机写入启动上下文与初始会话 → 进入现有计分板。若本机启动失败，补偿 abandon；超时不自动重开，查询 clientSessionId 恢复原事务。

离线：允许缓存小组的**自由比赛**本机继续/开局；约球尚未取得服务端 gameId 时不允许离线占用。已在线开始的约球可离线续打。服务端收到过期成员/归档期间结果时不盲目计入榜单，返回明确错误或管理员复核状态，个人记录仍保留。恢复后不得另组提交。

### 结果

本机 `SAVED → PENDING_UPLOAD → SUBMITTED`；失败区分可重试、需登录、永久业务拒绝和冲突。

服务端 `PENDING_CONFIRMATION → CONFIRMED / DISPUTED`；争议由管理员核对后确认，已确认结果通过新 revision 更正或 VOIDED。更正重新进入待确认，原已确认版本是否继续统计必须固定：**建议更正审核期间继续统计旧确认版本，裁定成功原子切换；正式争议触发暂停统计。** 不允许客户端写 CONFIRMED 或直接改积分。

普通计分和手工补录均先待确认；管理员可再执行确认（强制填写审计动作），或对方非提交者确认。同账号不能代表双方自证。临时成员无确认入口，若只有临时对手则由管理员核对。确认权限基于提交时角色快照与当前权限共同判定，不按 UI 角色开关信任。

结果重复：同 gameId、同 canonicalHash 返回原结果；不同 hash 返回 RESULT_CONFLICT 与现有版本，要求走更正申请。疑似同时间/同席位/同比分只能提示，不能把可能真实发生的复赛静默去重。

本地删除/改备注不影响已共享结果；共享比分更正走单独确认流程。小组记录不包含私人 note、voiceNote、音频路径、定位历史或完整 stateSnapshot。

### 补记比赛：整场局分必填，每局比分选填（2026-09-26 修正）

用户指出羽毛球补记应先记录整场局分（例如 2:1），按需展开记录每一局分数。本稿采用此交互，替代初版把补记直接当作一局 21 分终局录入的错误。

流程：选择单/双打与成员、比赛日期 → 选择比赛局制 → 填 A/B 胜局数 → 可选展开“每局比分” → 保存为待确认结果。比赛列表主比分显示“局分 2:1”，详情先显示整场局分，再列每局小分。未填写每局时明确显示“未录入每局比分”，不虚构 21:0 或 0:0。

- 单/双打与比赛局制是两个维度。demo 默认三局两胜，并提供一局定胜负/五局三胜作现有可配置局制的示例；正式可选范围由项目规则/活动快照决定，不把 demo 列表当作官方规则声明。
- 整场局分按胜局制校验：三局两胜允许 2:0、2:1、0:2、1:2；一局制允许 1:0/0:1；未完赛、平局、负数、非整数不能当作已完成比赛补记。活动/联赛已锁定的局制不可随意改选。
- 每局比分**整组可选**，展开本身不要求填写；全部留空代表缺失明细。填写任何一格后，首期要求补全所有已赛局的双方小分；局数必须等于 A 胜局+B 胜局。暂不引入“只知道其中几局”的半完整明细。
- 先校验每局终局合法性，再按顺序推导胜局：数量、胜方及累计局分必须与 summary 相符；任一方已达到获胜局数后不得继续有下一局。每局小分按选定 ruleVersion 校验，不能把 demo 的 21 分封顶 30 固化到所有项目。
- 折叠只是视觉操作，不丢弃或忽略已填数据；需要只保留局分时清空每局输入。切换局分导致局数变化时，正式实现应保留草稿并确认是否移除多出的已填局，不能静默丢掉手动录入内容。
- 缺少逐局明细不降低到“无比赛结果”：仍可由对方/管理员确认，并统计场次、胜负、胜率、胜局/负局/净胜局；不参与净胜小分、每局平均得分等需要逐局数据的指标。
- 弃权、退赛、超时裁定属于独立 resultType（后续评审），本轮不通过伪造 2:0 或 21:0 支持；不能强制用户为这些情况编造正常完赛结果。

服务端结果 payload 统一保留：`setScore:{a,b}`（整场胜局数）、`sets:null | [{a,b},…]`、`detailLevel:SUMMARY_ONLY|PER_SET`、`winnerSide`。MANUAL 允许 SUMMARY_ONLY；SCOREBOARD 正常输出引擎保存的完整局比分。缺失用 null，不用空数组或全 0 冒充真实数据。

```json
{
  "source": "MANUAL",
  "formatId": "badminton.singles",
  "ruleVersion": "badminton-21-v1",
  "rules": { "maxSets": 3, "pointsToWinSet": 21, "winByTwo": true, "pointCap": 30 },
  "result": {
    "setScore": { "a": 2, "b": 1 },
    "sets": null,
    "detailLevel": "SUMMARY_ONLY",
    "winnerSide": "A"
  }
}
```

上例是完整成绩提交 DTO 的结果相关字段，仍需按下节完整协议携带比赛标识、日期和参赛人。若补充逐局数据，改为 `sets:[{a:21,b:18},{a:17,b:21},{a:21,b:19}]`、`detailLevel:PER_SET`，整场仍为 2:1。服务端对 SUMMARY_ONLY 从 setScore 校验/推导胜方，对 PER_SET 从每局推导后与 setScore/winnerSide 三方核对，不能一律要求有 sets。

完整性和逐局字段进入 canonicalHash。已提交的仅局分结果日后补全小分走同一 resultId 的 corrections + revision/确认，不新建第二场，也不能使用旧幂等 key 修改正文；统计是否纳入小分随确认版本原子更新。

## 7. API 契约草案

所有以下路径均为**拟新增**。前缀 `/api`，默认 JWT，只有按小组号查找的最小预览匿名可读。沿用现有 `{error,message}` 错误形状；新增 `details/currentRevision/retryable/requestId` 为可选字段。成功使用具体资源或 `{items,nextCursor}`，不再新包一层通用 success。

所有写操作带 `Idempotency-Key: <UUID>`。修改操作带 `If-Match: "<revision>"`，revision 为字符串；missing 返回 428，冲突统一 409 REVISION_CONFLICT。幂等判断在相同账号/操作范围内，检查请求 hash；重复 key 不同正文返回 409 IDEMPOTENCY_KEY_REUSED。读写响应都返回当前 revision。

| 方法与路径 | 请求要点 / 返回 | 权限与冲突 |
|---|---|---|
| GET `/groups/capabilities` | 支持 gameType/formatId、规则版本、允许动作、limits、最小客户端版本 | 登录；先于 `/:groupId` 路由注册 |
| GET `/groups` | cursor、limit≤50 → items（含 myMember/摘要） | 只返回自己的有效/可见归档组 |
| POST `/groups` | name、gameType、timezone、joinPolicy（仅 OPEN/APPROVAL）→ group（含 groupNo）+owner | 原子创建；CLOSED 返回 422 INVALID_INITIAL_JOIN_POLICY |
| GET/PATCH `/groups/:g` | 详情 / name、description、settings、joinPolicy（OPEN/APPROVAL/CLOSED） | PATCH 管理权限；joinPolicy 仅 owner；禁止改 gameType/groupNo |
| POST `/groups/:g/archive`、`/restore` | expected revision → group | owner |
| POST `/groups/:g/ownership-transfer` | targetMemberId → group+myMember | owner；同组在线账号 |
| POST `/groups/:g/leave` | 当前 member revision | owner 返回 OWNER_TRANSFER_REQUIRED |
| GET `/groups/by-number/:groupNo/preview` | 完整数字号码 → groupNo、name、gameType、description（公开简介，供加入前判断）、memberCount、joinPolicy、availability | 匿名、限流、白名单最小预览；不存在统一 404 |
| POST `/groups/by-number/:groupNo/join` | 空正文（message 可选）→ membership 或 joinRequest | JWT，显式确认；按最新 policy 执行；已加入返回同关系 |
| GET `/groups/join-requests/mine` | 当前账号跨组的 PENDING 申请（groupId、groupNo、name、gameType、requestedAt）→ `items` | JWT；非成员也须可读，否则空状态无法显示待审批 |
| GET `/groups/:g/join-requests` | 管理员看全部，成员仅自己的请求 | 分页 |
| POST `/groups/join-requests/:r/withdraw` | revision | 本人；按 requestId 定位，**不要求 groupId**（预览不下发内部 groupId，非成员无从拥有） |
| POST `/groups/:g/join-requests/:r/approve\|reject` | revision、reason? | approve/reject 管理员 |
| GET `/groups/:g/members` | 稳定 memberId、显示名、kind、role、status | 仅成员，无 email/openid 等 |
| POST `/groups/:g/members/temporary` | displayName | 管理员，计入配额 |
| PATCH `/groups/:g/members/:m` | displayName 或 role | 角色只有 owner 可改 |
| POST `/groups/:g/members/:m/remove` | revision、reason | 管理员只可移除普通成员 |
| POST `/groups/:g/members/:m/claim-invites` | 有效期 → claimCode | 管理员 |
| POST `/group-claims` | claimCode → 待核对请求 | 本人认证，不能直接合并 |
| POST `/groups/:g/claims/:c/approve\|reject` | revision | 管理员；事务合并 |
| GET/POST `/groups/:g/activities` | 过滤/分页 / 时间、赛制、容量、地点 | 创建者受 settings 控制 |
| GET/PATCH `/groups/:g/activities/:a` | activity / 可修改字段 | 编辑者权限和 revision |
| POST `/groups/:g/activities/:a/register\|unregister` | 自己报名；管理员可指定临时 memberId | 原子容量校验，不能替普通账号随意报名 |
| POST `/groups/:g/activities/:a/cancel` | reason、revision | 创建者/管理 |
| POST `/groups/:g/games` | clientSessionId、activityId?、formatId、ruleSnapshot、席位 | 服务端返回 gameId；活动唯一占用 |
| POST `/groups/:g/games/:game/abandon` | reason、revision | 创建者/管理员；有结果则不能放弃 |
| POST `/groups/:g/results` | result DTO（见下） | 离线自由局可随 DTO 原子补建 game |
| GET `/groups/:g/results`、`/:r` | format/date/member/status 筛选；详情带 revisions | 仅组成员 |
| POST `/groups/:g/results/:r/confirm\|dispute\|void` | revision、reason（争议/作废必填） | 校验角色、对方席位、提交者 |
| POST `/groups/:g/results/:r/corrections` | proposedResult、reason、baseRevision | 生成新版本审核，不覆盖旧事实 |
| GET `/groups/:g/rankings` | formatId、from/to → rows、statsRevision、criteria | 仅 CONFIRMED 有效版本；禁止混赛制 |
| GET `/groups/:g/snapshot` | 全量初始快照及 cursor | 事务一致 watermark |
| GET `/groups/:g/changes?cursor=…` | changes、nextCursor、hasMore | 过期返回 410 SYNC_CURSOR_EXPIRED |

`/groups/by-number/...`、`/groups/capabilities` 与 `/groups/join-requests/...` 路由注册在通用 `/:groupId` 之前；groupNo 仅用于查找/加入，内部业务接口继续使用原有不透明 groupId。

个人报名状态可在活动响应中返回；`GET /groups` 每次前台刷新也核对访问撤销，不能只依赖已经失去权限的 group changes 通道。

### 成绩提交示例

```json
{
  "gameId": "opaque-server-game-id",
  "clientSessionId": "7d1b5689-cc73-4a51-a08a-e311d2c5a111",
  "clientRecordId": "existing-local-record-string-id",
  "recordSchemaVersion": 5,
  "source": "SCOREBOARD",
  "formatId": "badminton.doubles",
  "ruleVersion": "badminton-21-v1",
  "rules": { "maxSets": 3, "pointsToWinSet": 21, "winByTwo": true, "pointCap": 30 },
  "startedAt": "2026-09-26T06:00:00Z",
  "finishedAt": "2026-09-26T06:35:00Z",
  "participants": [
    { "memberId": "m1", "side": "A", "seat": 0, "displayNameSnapshot": "杨扬" },
    { "memberId": "m3", "side": "A", "seat": 1, "displayNameSnapshot": "林启" },
    { "memberId": "m2", "side": "B", "seat": 0, "displayNameSnapshot": "陈鹏" },
    { "memberId": "m4", "side": "B", "seat": 1, "displayNameSnapshot": "小北" }
  ],
  "result": { "setScore": { "a": 2, "b": 0 }, "sets": [{ "a": 21, "b": 17 }, { "a": 21, "b": 19 }], "detailLevel": "PER_SET", "winnerSide": "A" }
}
```

服务端按 format/ruleVersion 校验席位数量、成员不重复、同组关系、合法终局、时间顺序、按 detailLevel 从整场局分或逐局比分推导 winner 并核对。不能直接信任客户端最终 winner 字符串。全局最大请求体、比赛局数、字符串长度、时间范围须配置上限；拒绝未知 schema/未支持规则版本，返回升级/不支持提示。自定义规则需在 catalog 明确注册校验器后开放小组上传。

```json
{
  "id": "result_opaque_id",
  "status": "PENDING_CONFIRMATION",
  "revision": "1",
  "groupChangeSeq": "128",
  "allowedActions": ["dispute"],
  "statsRevision": "127"
}
```

错误例：`{ "error":"REVISION_CONFLICT", "message":"内容已被其他成员修改", "currentRevision":"8", "retryable":false }`。

| 错误 | 客户端动作 |
|---|---|
| 401 SESSION_EXPIRED | 使用现有刷新链，失败后暂停账号队列；登录原账号再恢复 |
| 403 ROLE_FORBIDDEN / GROUP_ACCESS_REVOKED | 刷新权限，清除组缓存/提醒，个人记录保留 |
| 409 GROUP_FULL / ACTIVITY_FULL | 显示最新容量，不假装报名成功 |
| 404 GROUP_NOT_FOUND | 检查小组号或向朋友确认号码 |
| 403 GROUP_JOIN_CLOSED / GROUP_ARCHIVED | 显示当前状态；号码不变，不能靠再次分享绕过 |
| 422 INVALID_INITIAL_JOIN_POLICY | 创建时只能选择直接加入或需要审批；不得静默改成其他方式 |
| 422 INVALID_GROUP_NUMBER | 输入纯数字并满足 capabilities 下发的长度规则 |
| 409 REVISION_CONFLICT / RESULT_CONFLICT | 保留用户草稿，拉新版本，要求明确解决 |
| 422 INVALID_RESULT / UNSUPPORTED_FORMAT | 保留本机记录，停止无效自动重试 |
| 429 RATE_LIMITED | 按 Retry-After 重试，不立即循环 |
| 5xx / 网络失败 | 按原幂等 key 退避重试；允许用户手动触发 |

## 8. 幂等、同步与离线恢复

幂等回执建议保留 30 天；业务唯一键长期保留，超过幂等窗口的旧 outbox 也不能重复计场。只有确定业务输入更改才生成新 commandId；一次请求刷新 token 或 HTTP 重试始终沿用原 key。

不要使用客户端时间戳作为服务端 revision。每个组内事务锁 group 行、递增 changeSeq，并在同一事务写 changes/tombstone；这样 cursor 不能越过尚未提交的较小序号。全量快照与 cursor 必须同一一致性视图生成；大型分页快照用固定 watermark，不能每页重取“现在”。增量游标携带 groupId、水位、固定分页上界并做签名，授权与查询条件不能靠游标绕过。

删除/合并/权限撤销也发 changes。游标过期全量重拉前保留本机未上传结果，不能用服务器快照覆盖 outbox。缓存命名空间至少包含环境、User.id、groupId。退出登录清掉可浏览缓存和提醒，未上传队列隔离保存，另一个账号不能读取/代发；原账号重新认证后继续。账号注销涉及的未上传内容明确告知并按注销语义清理。

新建 `GroupResultOutbox`（建议独立于现有匿名跨设备 outbox）：

- 字段：commandId、accountId、groupId、clientSessionId、localRecordId、immutablePayload、payloadHash、attempts、nextAttemptAt、state、lastError。
- 本机正式记录保存成功后再建立任务；启动上下文已提前持久化，崩溃恢复扫描“有正式记录及组上下文但无提交回执”的记录补任务，保证落盘与入队间崩溃不丢共享结果。
- 指数退避加随机抖动；同组/同比赛命令有序，其他组可独立推进；永久拒绝可见且停止重试。
- 接收成功响应但本地还没存回执就崩溃：重试原 key，返回同 resultId，不重复入榜。
- 前台进入小组/手动刷新/网络恢复/登录恢复触发；首期不依赖后台常驻、WebSocket 或远程推送。

排名查询首期直接从有效确认版本聚合，避免双写累计字段；规模增长再异步物化并返回 statsRevision/recomputing。单打、双打分别排名，双打本期每名参与者记一次出场/胜场；首期按胜场、净胜局排序，相同指标显示同名次，最后用 memberId 保证分页稳定。每局小分可缺失，因此净胜小分仅作为有明细记录的附加统计，同时返回覆盖场数/总场数；首期不拿部分明细的净胜小分作为排名决胜项。缺失明细不得补零。胜率满 5 场才显示；作废与重复结果不计。时间过滤按 finishedAt，from 含/to 不含。

## 9. iOS 接入设计（后续实施，当前不写代码）

建议新增：`Features/Groups/{GroupEntryView,GroupListView,GroupDetailView,GroupActivityView,GroupMembersView,GroupRecordsView}`，`GroupStore` 负责 @MainActor UI 状态，`GroupRepository` actor 管缓存/网络与 DTO，`GroupAPI` 复用 APIClient，`GroupResultOutbox` 管可靠提交。

1. `HomeTab` 对应手机/iPad布局在 `buildScheduleSection()` 前插 `GroupEntryView`；沿用 NavigationDestination/NavigationStack，入口失败不拖慢首页个人功能。
2. 新 `GroupActivity` DTO 与本机 `LocalBooking` 分开，地点/名字可借常用数据填充，但成员身份必须用 memberId；不修改常用姓名库以冒充账号成员。
3. `GroupScoreLaunchContext` 保存 accountId、groupId、gameId?、clientSessionId、activityId?、formatId、ruleSnapshot、memberId/side/seat/displayName 快照；在现有启动持久化流程旁以稳定 sessionId 关联存储，续打/换边不能丢失席位身份。
4. 使用适配器将成员映射到现有 `SportsSetupResult` / `BookingStartRequest`；字符串名字只用于显示。服务端 side A/B 对应稳定 TeamID，不随 UI 换边交换成员身份。
5. 先经过全局单活跃会话检查；本机新建失败不会把活动永久占住；继续已有计分必须恢复其原组上下文。
6. 完赛继续走 `ScoreboardRecordManager`。新增白名单 result encoder；`winnerIdentity` 到 side 的映射按稳定参赛身份核对，禁止从显示名/最终屏幕左右位置猜胜者。
7. 初期可用独立 sidecar 保存小组上下文，无需立即改变现有 v5 格式。若以后选择内嵌字段，必须升级/兼容 Codable 与本机迁移，不能向已持久化记录随意增加必填字段。
8. 全局记录列表可显示小组提交状态徽标并跳详情，但私人记录仍归个人；小组页只读服务端共享结果。退出/移除清缓存后仍能看自己的本地记录。
9. 小组活动提醒单独命名空间，用服务端 revision 重建，本机个人约球提醒原样保留；权限拒绝不阻止报名，改时/取消主动更新提醒。
10. 全部 UI 文案走当前多语言机制，不在本轮已有多语言改动中插实现；iPad 宽度/Dynamic Type/深浅色遵循 Theme，图标沿用系统样式。

旧本地约球不自动上传。后续若提供显式关联：用户选择组、映射真实成员、检查项目赛制、确认共享范围，回填稳定关联 ID 后幂等创建；之前已分享过的结果不能换组静默复制。

## 10. 后端接入与跨端边界

拟新增 `routes/groups.ts`、`routes/groupInvites.ts`、`lib/groups/*`（服务/权限/结果校验/同步），Prisma 迁移只增表/约束；入口注册 JWT/限流/Zod 校验。数据库事务内不得调用外部分享、审核或推送 API，使用 DomainEventOutbox。

复用现有账号 JWT、账号状态检查、审计与内容审核组件，但实际字段/枚举扩展需逐项完成。小组名称、简介和昵称可举报；隐私范围默认仅成员。JWT、临时认领凭证、完整成绩正文不进访问日志。groupNo 是公开标识，不当作 token；分享页不附带内部资料、成员账号或地点，埋点只记录必要操作。

注销：先检查所有权；存在其他账号成员则要求转让，只有本人及临时成员可先归档并处置后再继续。其他成员状态和昵称按现有注销原则处理。保留原始不可变比分与匿名审计，展示层匿名化敏感姓名；保留期限沿用实际隐私方案，本文不虚构法定天数。

跨端统一使用本契约，不能创建 iOS 专属群。Android/HarmonyOS/小程序逐步开功能时先协商 capability/minVersion。微信小程序分享路径和 HTTPS Universal Link 均只携带同一个固定 groupNo（例如拟议 `/groups/join?groupNo=82603158`）；二维码编码同一落地链接，不创建额外入组凭证。跨端账号是否相同取决于已验证的身份绑定，不由分享页自动合并。关联域、查找落地页、小程序路径属于未来配置，当前 HTML 提供真实编码的数字示例二维码及模拟识别；不生成假装可用的生产链接，不发送系统分享。

Phase 1 组数据走 REST。现有实时 Match/显示屏/短码/控制权继续独立；以后可用 GroupGame 可选关联 realtimeMatchId，但不得因为属于同一小组就能接管其他人的计分板。

## 11. 轮转与联赛扩展预留

轮转：Activity.type=ROTATION，增加 Round、Assignment、ControlLease。Round 发布前满足人数/场地硬约束，12 人双打最多 3 场，候场人数为 12−4×场地数。公平目标应优先安排**休息多/出场少**的人，而不是旧稿“休息轮次少”的反向规则。未完场须完成/明确作废后才发布下一轮；轮转算法另行确认。

租约带 ownerDeviceId、epoch、expiresAt；续租/接管 CAS。建议离线可记已发布场次结果，**不离线发布新的全局轮次**；这修正旧原型“离线随意下一轮”的风险。接管后旧 epoch 结果进入逐场核对，不能覆盖新排阵。正式协议、暂停/迟到/早退策略需专项评审。

联赛：League、Competitor、Fixture、RuleVersion，个人/固定搭档/固定队伍开赛后锁定。赛程场次唯一关联 GroupResult，确认后同一事实进入长期战绩和赛季积分榜。重复提交、作废、更正一次驱动两榜重算，禁止两份独立胜负记录。单循环 n 人的场次数为 n(n−1)/2，demo 4 人对应 6 场。后续联赛接口应复用 result 的确认/冲突约定。

## 12. 待原型评审确定

- ~~首批项目是否按羽毛球单/双打先做~~ → 2026-09-26 收敛为 A 档四项目（羽毛球/乒乓球/网球/匹克球）同批，见 [PRD §4](PRD.md)；其余项目按能力目录逐个放开。**网球"每盘局分"明细是否进首批仍待定**。
- 普通约球首期一场结果，还是立即需要同一次约球多场对局；若多场，应拆 Game 与活动完成动作，不能每个完赛就结束整个活动。
- 成绩默认双方确认、管理员可确认的门槛是否合适；是否需要自动确认超时机制（本稿不自动确认）。
- 小组号建议 8 位；默认审批还是直接加入、免费成员额度、归档/解散流程。普通成员分享公开小组号不再需要单独授权，添加临时成员仍属于管理能力。
- 轮转算法与联赛首版范围另行评审，不阻塞基础小组设计。

首页入口的位置与横向样式已由用户明确，不列为待定项。

## 13. 实施后的验收门槛

以下是未来实现的验收要求，不表示本轮已跑后端/原生测试：

- 相机扫描、相册识别、手输号码、已安装/未安装/微信内深链均回到相同预览；拒绝相机授权可手输，重复识别不重复申请，二维码不能绕过 CLOSED 或审批。
- 同一 groupNo 在各端精确定位同组；更名/转让/归档恢复不变号，解散后不回收；重复分配碰撞可重试，旧号不指向新组。
- 双端不同 provider 但同一 User.id 登录，同一组与记录一致；重复加入/最后一个名额并发只成功一次。
- 创建表单仅 OPEN/APPROVAL；绕过前端直接 POST CLOSED 也拒绝。创建后组主 PATCH CLOSED 成功，现有成员仍能访问/计分，重开恢复加入，号码不变；非组主不得修改。
- 已登录加入无需重复登录；未登录能恢复号码；OPEN/APPROVAL/CLOSED、待审时切 policy、满员、重复申请/撤回、被移除禁止重返均按服务端最新状态处理。
- 任意跨组 ID、越权审批/确认/移除/转让均拒绝，按号预览无内部地点、完整名单或战绩。
- 同一 command 重试、超时后重试、提交成功后崩溃都只有一条结果；相同比赛不同比分进入冲突。
- 真机杀进程覆盖“正式记录成功但入队前”“请求成功但回执前”，恢复不丢、不重复、不换账号发送。
- 归档、移除、登出/切账号后缓存和通知隔离；私人备注音频不出现在抓包结果。
- 满员/过截止报名、并发开同一约球、旧 revision 修改均正确拒绝，草稿仍在。
- 结果待确认不入榜，确认/作废/认领/更正后统计可追溯且可重算；同名两个人不混淆。
- 补记 2:1 可不填逐局；填写完整 21:18、17:21、21:19 能通过。逐局胜方相反、缺一局、前两局已赢仍录第三局、非法终局、负数/平局均拒绝；仅局分与含明细两种结果均正确统计，不把缺失小分当 0。
- 首页原有计分、约球、续打、通知、5 Tab、多语言与 iPad 布局回归通过。
- 后端迁移在 staging 验证旧客户端兼容、回滚功能开关与新域数据保留，再分端灰度；本轮不部署、不提审。
