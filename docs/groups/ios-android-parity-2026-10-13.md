# iOS 小组与国内安卓逐页对照（2026-10-13）

本轮只修改 iOS。功能依据是国内安卓项目的当前工作区源码，包含尚未提交的最新修改；旧 PRD、原型和先前截图不作为行为判断依据。安卓参考仓库为 `../jifen-android`，参考提交为 `4a418f65f342a23cc9e1fa0d0d2d135edc7ad488`。本次读取的逐文件 SHA-256 保存在 `build/groups-port-20261013/android-source-snapshot.json`，可区分该提交和实际参考的工作区版本。

UI 保留 SwiftUI 的导航、List/Form、选择器、sheet、确认弹窗和系统分享。下表的“对齐”指流程、数据、权限和状态处理；平台控件与布局按 iOS 实现。训练组继续支持已有小组；当前服务端能力目录只开放熟人组创建，iOS 按目录提供创建选项。轮转、联赛不在本轮范围内。

用户已明确由本人执行真实联调。本轮验收分开记录自动测试、真实联调、真机域名关联，模拟器 URL 打开测试不视为 Universal Links 真机关联通过。没有修改国内安卓、独立 Google Play 项目、网站或后端，没有提交商店或部署。

## 逐页面、逐组件对照

安卓路径下文均相对于 `app/src/main/java/com/douhua/jifen/screen/group/`，iOS 路径均相对于 `jifen/Features/Groups/`。

| 页面 / 组件 | 安卓最新处理及源码依据 | iOS 对应实现 / 本轮修正 | 自动验证 |
| --- | --- | --- | --- |
| 首页小组入口 | `home/HomeGroupSection.kt`，首页可进入小组列表 | `HomeTab.swift` 保留原首页位置及原导航，连接 `GroupListView` | 首页入口进入详情 UI |
| 列表排序与组卡 | `home/GroupSummaryOrder.kt`：活动组在前，同类按 updatedAt 降序 | `GroupStore.refresh` 同口径排序；组号、人数、运动、生命周期标签 | 列表 → 详情 UI |
| 待审 / 拒绝申请 | `list/GroupJoinRequestCard.kt`：刷新、撤回；开放加入时可继续加入；拒绝后可重新预览 | `GroupListView` 区分 pending/rejected，保留目标组号，阻止满员、关闭、归档等不可加入状态 | 状态模型单测；真实提交由用户验证 |
| 空态、测试版与反馈 | `list/GroupListScreen.kt`：创建、加入、测试说明、反馈 | 原生 List 空态和创建/加入入口；反馈复用原生 Feedback 页面，登录后继续 | 空态 / 管理表单 UI |
| 创建基础信息 | `create/GroupCreateScreen.kt`、`GroupCreateValidation.kt`：名称、简介、运动、加入策略，失败留在表单 | `GroupCreateView` 按能力目录类型与长度校验，一次请求；成功替换为详情，首次打开分享 | Unicode / 能力目录单测 |
| 输入组号 / 预览 | `join/GroupJoinScreen.kt`：目标变化废弃旧预览；确认后才加入 | `GroupJoinView` 按输入及请求代次拒绝过期响应；结果始终对应当前目标 | 乱序代次 / 预览解码单测 |
| 预览生命周期 / 容量 | `join/GroupJoinAvailability.kt`：生命周期、加入策略、容量优先；已有成员仍可打开 | `GroupPreview.effectiveAvailability` 相同优先级；待审遇开放策略重新允许加入 | closed、dissolving、open+pending、already_member 单测 |
| 申请留言 / 撤回 | 仅审批加入显示留言；待审保留撤回，包括加入策略变化后 | `GroupJoinView` 仅 approval 显示留言；独立保留 pending request 撤回 | 状态推导单测；真实审批由用户验证 |
| 登录后继续 | `GroupJoinScreen.kt` 保留原目标，登录后重新预览 | 确认过的目标保存在 loginTarget；登录后加载新预览再继续；改号取消旧目标 | 双域名冷 / 再次打开 UI |
| 相机 / 相册二维码 | `join/GroupJoinScanEntry.kt`、`GroupJoinScanEntry` | 原生 DataScanner、PhotosPicker；后台 Vision 识别，CPU QR 回退；新输入或会话变化使旧识别失效 | 真实二维码像素解码 + 旧格式单测；相机由用户实测 |
| 邀请 / 分享 | `share/GroupInvitePolicy.kt`：生命周期、策略与容量限制邀请；组号唯一 | `GroupShareView` 请求新预览后决定可分享；文字和图片使用同一 URL | QR 与文字 URL 相等、双域名接收单测 |
| 概览信息卡 | `detail/GroupDetailOverviewTab.kt`：运动、名称、组号复制、二维码；邀请为次要入口 | 原生信息卡保留二维码；名字最多两行；仅底部不显示邀请时在卡内提供次要邀请 | 概览 / QR / 横屏 UI |
| 概览底部主操作 | `GroupOverviewProgress.kt`：少于 2 人仅邀请；达到 2 人后计分/训练；有历史再加补记；仅教练可补记训练 | `GroupOverviewActions` 集中判断；safeAreaInset 固定底部；1 或 2 个按钮；归档 / 解散中隐藏 | 全状态单测、位置不随滚动变化、页签切换 UI |
| 概览统计 / 最新赛果 | 确认数 >0 才展示统计；真实赛果或确认数 >0 才展示最新赛果 | `overview` 相同显示条件，待确认独立入口；不在空态重复增加主按钮 | 有历史 / 无历史 UI，规则单测 |
| 即将开始 / 进行中 / 已过时间 | 活动进行中优先；训练当前场和未来场分开；不伪造空活动；过时未结束另列 | 依据实际起止时间、状态、本人席位选择场次；取消计划保留已开局场次 | 普通 / 训练概览 UI |
| 成员正式 / 临时与搜索 | `detail/GroupDetailMembersTab.kt`：搜索、角色、VIP、临时身份、审核信息 | `members` 保留正式/临时分段、搜索、审核中的称呼、VIP 和移除时间 | 搜索 UI、权限单测 |
| 批量临时姓名解析 | `GroupTemporaryMemberBatch.kt`：分隔、空白归一、大小写去重；失败仅重试未成功项 | `temporaryNames` 对齐；保留成功集合及各姓名幂等键，失败保留输入 | Unicode、空白、大小写、分隔符单测 |
| 常用姓名导入 | `GroupCommonNameImportDialog.kt`：独立搜索、多选、确定导入 | 原生独立 List 搜索和多选，确认后填入批量表单；不把整份姓名库展开在主表单 | 原生批量表单 UI；提交由用户验证 |
| 成员操作权限 | `GroupMemberActionPolicy.kt`：经理可改临时称呼；组长才可设管理员；训练组不设管理员；禁止自己/组长移除 | `GroupPermissions` 与 `GroupManagementView` 同权限；角色调整、改称呼、移除原生表单及确认 | 管理员/组长/本人/临时成员权限单测 |
| 历史成员 | `GroupRemovedMembersSection.kt`：历史独立加载和折叠 | removed 查询独立分页，保留历史姓名、移除时间、搜索与 DisclosureGroup | 旧成员模型兼容 / 搜索 UI |
| 资料与加入策略 | `GroupDetailScreen.kt`：资料及策略一起保存；审核中的信息与拒绝原因展示 | 单次 PATCH；采用 pending 内容作为编辑初值；展示两类审核原因 | 版本头 / 冲突单测、资料表单 UI |
| 归档 / 恢复 / 转让 / 退出 | `GroupDetailScreen.kt`：归档可转让；解散中禁止转让；退出清本组同步关联但留个人记录 | 原生 Menu/Form；生命周期检查；forgetGroup 仅清当前账号当前组上传、关联及活动提醒 | 账号 / 组隔离、终态去重单测 |
| 解散冷静期 / 撤销 | 只读冷静期及取消解散，由服务端返回时间 / 状态 | dissolve 与 dissolve/cancel 版本化接口；只读组不显示底栏；保留冷静期说明 | 归档 / 解散权限单测 |
| 举报 / 本人状态 | `GroupReportForm.kt`：原因、说明、本人举报状态；成员及预览均可举报 | `GroupReportView`、`GroupPreviewReportView`，加载本人状态，待审禁重复提交 | 报文模型检查；真实提交由用户验证 |
| 活动列表 | `GroupDetailActivitiesTab.kt`：进行中优先，历史后置；创建只有一处，只读无创建 | 两段原生卡片；创建固定底部，概览空态无重复创建按钮 | 活动页签 UI |
| 活动创建 / 编辑 | `GroupActivityFormPolicy.kt`：未来开始、有效截止时间；编辑保留已过去的原截止时间；开局后禁止改基础资料 | 原生日期、地点、人数、赛制表单；deadline 与 starts 同步初值；动态刷新动作边界 | 原生表单检查、规则 / 协议单测 |
| 本人报名 / 代报名 | 截止时间内本人报名/撤销；经理为临时成员操作；满员阻止新增 | `registrationOpen(at:)` 支持 recruiting/in_progress；满员保留撤销、禁新增；经理代报 | 状态 / 权限代码对照；真实写入由用户验证 |
| 单场 / 多场对阵 | `activity/GroupActivityLineupScreen.kt`、`GroupActivitySessionActions.kt`：独立场次、固定席位、终态与补记权限 | `GroupActivityView`、`GroupScheduleEditor`，session ID 全流程保留；只按 canCorrectResult 开放终态修正 | 多场 → 原生编排 → 复核 UI；报文单测 |
| 本机继续 / 其他设备 | 检查本机上下文及云端 state；无本机草稿时提示原设备继续 | `GroupGameOperations.resumeID` 查云端 started 后匹配当前账号本机恢复项；保留其他设备提示 | 上下文 / 会话隔离单测；跨设备由用户验证 |
| 放弃占位 | 组长 / 管理员或比赛创建者释放，确认后清关联 | 原生确认弹窗；abandon 成功后为相关上传建立终态标记 | abandon 终态 / 去重单测 |
| 取消 / 结束活动 | 已开局保护；多场全部完成 / 取消后才结束 | canCancel 检查开局状态；结束检查每个 session；版本头、原因与失败留页 | 活动取消状态单测、编排 UI |
| 独立席位选择器 | `GroupResultEntryScreen.kt`：搜索、替换、清空；重复席位禁止；已冻结不能改 | `GroupSeatPicker` / `GroupMemberSelector`：原生可搜索 List，独立清空、排除已占席位 | 固定双打 / 单场席位选择 UI，冻结快照校验单测 |
| 规则目录与原生引擎 | `result/GroupResultCapabilities.kt`：schema 1、能力默认值与选项、操作白名单 | 按目录渲染选项；不支持定制时固定默认规则；完整 groupMatchRules 传入本机引擎，普通计分默认行为不变 | 四项目规则 fixture、单双打引擎规则往返单测 |
| 快捷局分 / 逐局明细 / 日期 | `GroupResultScoreControls.kt`：合法整场局分；明细选填且校验一致；实际比赛日期 | 合法快捷分数、结构化每局比分；无明细不补零；输入不合法禁提交；日期不得晚于现在 | 17 组规则 fixture、原生补记表单 UI |
| 比赛确认 | `GroupResultPermissions.kt`：参与者、代记、经理、组长权威；同队/提交者等待 | `GroupPermissions.confirmation` 共用列表和详情；权威确认携带 authority；等待姓名排除临时/已移除成员 | 对手、同队、代记、本人、权威、临时身份单测 |
| 作废 / 详情 | `GroupResultReviewActions.kt`、结果详情：原因、版本保护、保留原历史 | 原生详情 Form、作废原因、If-Match；失败不丢原因，支持刷新最新结果 | 版本冲突单测；真实作废由用户验证 |
| 待确认 / 筛选 / 分页 | `GroupResultPermissions.kt`：待确认独立，不受历史赛制筛选影响 | pending 单独 allPages；历史按 format 服务端分页；代次保护；重复 cursor 拒绝 | 状态模型 / 分页 / cursor / 乱序会话单测；赛制筛选 UI |
| 排行榜 / 个人战绩 | `GroupDetailRecordsTab.kt`、`GroupMemberResultsViewModel.kt`：独立赛制、确认口径、分页 | 排行榜独立请求；个人记录服务端 memberId/format 查询；服务端统计口径不自行重算 | 赛制切换 UI；请求检查 |
| 排期草稿 / 发布 | `training/TrainingDraftRecovery.kt`、`GroupTrainingPlanScreen.kt`：草稿按账号与计划；旧版本草稿显式选择；发布前预检 | 账号/组/计划持久草稿，旧 revision 不静默覆盖；原生复核后提交 | 草稿账号隔离 / 稳定 ID 单测；复核 UI |
| 改期 / 后续顺延 | 安卓顺延从锚定场按时长接续，冻结场不变，先预览确认 | `shifted` 同逻辑；改日期仅由用户的 DatePicker Binding 触发，初始化不会二次平移 | 顺延冻结时间及 ID 单测 |
| 排期冲突 | 同时占用同场 / 同成员禁止；同组其他计划预检；场次数与每人次数限额 | 本排期及已加载本组计划冲突预览；能力目录限额；服务器仍作最终校验 | 跨计划时间 / 成员冲突、顺延单测 |
| 冻结席位 / 场馆 / 历史 | 已开局/赛果固定 ID、时间、席位；场馆锁定；说明可改；取消留历史 | 合法固定行不删除、不重建；草稿恢复使用服务器冻结行；metadata-only PATCH 省略未改 sessions；取消保留原成绩 | 冻结快照 / 稳定 ID / 编码单测，固定席位 UI |
| 教练 / 学员 | `GroupTrainingTab.kt`：教练编排计分，学员只读本人场次，可请假 | 只有 coach 开编辑和计分；学员只显示自己的席位场；当前安排在前，历史在后 | 教练固定席位 UI、学员底栏只读 UI |
| 请假 / 原因修改 / 已读 | `GroupTrainingTab.kt`：未读独立，已读及失效历史折叠；快照保留 | 快照姓名/时间/场地、原原因回填；教练标已读；失效历史不删除 | 请假卡及原因 UI；写入由用户验证 |
| 训练变更通知 | unread 优先、历史折叠，发布/改期/取消快照 | `GroupTrainingNoticesView`、全局通知跳转训练页 | 通知模型检查、训练 UI |
| 全局通知 | `notice/GroupNoticeInbox.kt`：未读数、分页、已读覆盖晚返回；拒绝/移除不打开无权限组 | 原生通知 List；seen 代次及覆盖；重复 cursor 检查；分页不增加旧快照未读数；活动/训练/结果跳转 | 通知入口 / 快照 UI；会话及分页单测 |
| 活动提前 15 分钟提醒 | 安卓本地提醒，报名/退出/取消/改期同步 | 原生 UserNotifications；提醒按账号/组/活动持久；改期更新，退出/注销清理；异步授权后拒绝旧会话 | 时间及账号保护源码核对；通知授权/送达由用户实测 |
| 上传重试 / 修正 | `GroupResultEntryViewModel.kt`：持久上传、幂等标识、冻结规则修正、已有结果检查 | GroupStore 持久重试队列；冻结比赛重新读取规则/席位；自由比赛可修规则/席位；同记录替换保持原幂等键 | 修正/去重/账号隔离/迁移单测 |
| 放弃上传 / 个人记录 | 上传终态只留去重标记，个人记录独立保留 | tombstones 仅保留身份/组/结果 ID；清队列正文；放弃后修复队列不会再入队 | tombstone、迁移、组隔离单测 |
| 前台 / 联网 / 会话隔离 | 请求/缓存/草稿/上传绑定账号及登录 revision | APIClient revision、GroupStore 代次、TaskLocal 写入身份；前台和联网继续处理队列；账号切换取消旧请求 | 15 项 APIClient 隔离 + 小组分页同账号重登单测 |

## 邀请域名

`GroupInvitationLink` 为唯一生成入口，二维码和文字分享复用同一个 HTTPS 地址及固定数字组号。

| 系统地区 | App 实际语言 | 生成域名 |
| --- | --- | --- |
| CN | 任意 | jifenqi.com |
| 明确其他地区，包括 HK/MO/TW | 任意，包括中文 | iscoreboard.live |
| 缺失/空白地区 | zh-Hans / zh-Hant / 中文变体 | jifenqi.com |
| 缺失/空白地区 | 其他 | iscoreboard.live |

地区来自 `Locale.current.region`，语言来自 `Bundle.main.preferredLocalizations`；不查定位或 IP。两域名始终接收，兼容旧 JSON 二维码及 6–8 位数字。现有 Associated Domains 同时保留两个域名。安卓国内项目和独立 Google Play 项目未补兼容。

## 验证与证据

自动结果与最终截图详见本节后续记录；所有原始日志、xcresult、源文件摘要及新增语言校验在 `build/groups-port-20261013/`。工作前备份位于 `before/`，`baseline-hashes.json` 记录原有改动；新增 HomeModels 接口另作修改前备份。

- 单元测试：GroupContractTests、GroupPreviewDecodingTests、GroupPortParityTests、APIClientSessionIsolationTests；包括最新目录/报文、四项规则、单双打原生规则、If-Match、版本冲突、同账号重登录、分页、旧二维码、草稿及终态队列。
- UI fixture：只使用合成账号和合成页面数据。可打开和编辑表单，测试不执行服务端提交；覆盖概览底栏、加入链接、资料、搜索、成员导入、活动编排、补记、训练和通知。
- 横屏：模拟器的传感器事件不可稳定投递，因此 `-UITestGroupsLandscape` 在 DEBUG fixture 中请求横屏 geometry，测试窗口、二维码和按钮的实际布局。真实设备旋转仍由用户验收；普通页面与计分板的方向拥有者互不覆盖。
- 本轮新增/复用 69 个本地化键，47 个语言资源同步；44 个非源语言目录按本项目规则校验。原目录已有的旧 hash / 审核阻塞单独记录，没有重写无关旧译文，也没有使用外部翻译服务。
- 无签名模拟器测试曾因 Keychain `-34018` 失败，随后使用本地 ad hoc 模拟器签名重新运行，验证真实 AuthTokenStore 会话逻辑；没有为测试削弱生产 Keychain。

真实联调、真机相机、双域名冷启动/再次唤起/未登录、系统扫码、实际通知送达及域名关联验收：按用户指示交由用户执行。本轮自动测试结果与这些项目分别记录，不合并宣称通过。

### 最终自动结果

| 验证 | 结果 | 原始证据 |
| --- | --- | --- |
| 本地签名模拟器 build-for-testing | 通过 | `build-final-handoff.log` |
| 小组规则、域名、报文、权限、草稿、队列及认证会话单元测试 | 69 / 69 通过 | `final-dissolving-iphone.xcresult`（含最新冲突 currentResultId 测试） |
| iPhone 17 Pro | 15 / 15 全量 UI 通过；冷静期补验通过 | `final-iphone.xcresult`、`final-dissolving-iphone.xcresult` |
| iPhone SE 2 | 15 / 15 全量 UI 通过；冷静期补验通过 | `completed-se.xcresult`、`final-dissolving-se.xcresult` |
| iPad Pro 13-inch | 15 / 15 全量 UI 通过；冷静期补验通过 | `completed-ipad.xcresult`、`final-dissolving-ipad.xcresult` |
| 最大辅助字号及深色模式，小屏 SE | 底部两按钮不重叠、完整可读；信息卡改为纵向信息，页签使用原生菜单 | `adaptive-large-se.xcresult`、`adaptive-large-screenshots/` |
| 47 种语言 / 69 个本轮键 | 资源语法与内容 0 问题；44 个译文目录的本轮键 0 阻塞 | `localization-final.json` |
| 工作区格式及安卓来源 | `git diff --check` 通过；参考安卓文件与逐文件摘要无漂移 | `android-source-snapshot.json`、`ios-final-source-hashes.json` |

UI 测试覆盖 16 个场景，三个模拟器分别完成 15 项全量和解散冷静期补验。普通字号保持双按钮横排；辅助字号使用纵向原生按钮。发现的表单虚拟化、导航栏遮挡、键盘输入与搜索导航过渡问题已修正并重新通过回归，失败日志保留作为过程证据，不列入最终通过结果。方向拥有者放在计分表单的 NavigationStack 生命周期，避免席位选择器进出时变更窗口方向。

普通 iPhone 最终概览截图：

![iOS 小组概览底部操作](../../build/groups-port-20261013/final-iphone-screenshots/9898F4CB-C429-4DE7-87C7-9D5BFA8584FF.png)

本轮没有填写真实账号联调或真机域名关联为“通过”。这两部分，以及真机旋转、相机与通知送达，按用户指示由用户验收。
