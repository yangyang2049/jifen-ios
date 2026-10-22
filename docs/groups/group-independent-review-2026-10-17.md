# 小组功能三端独立复查（2026-10-17）

本轮从用户操作中断、网络不确定结果、账号切换和本地通知出发，复查 Android、HarmonyOS、iOS 当前工作区，并核对本地服务端实现。范围仍是熟人组；不新增训练组，不调整默认 30 人及正式、临时成员合并计数规则。

独立复查新增确认 **5 项问题：iOS 4 项、Android 1 项**。用户随后授权修复，现已再次核实并全部修复，iOS 118 项小组测试、Android 32 项定向测试通过，见 [逐项修复与回归](group-independent-fixes-2026-10-17.md)。下文保留修复前的发现及实验记录，行号对应复查时源码。鸿蒙在本轮检查的对应链路中未发现新增可确认缺陷，这不等于全部页面和真机场景已验收。

## 发现

### R1 · P2 · iOS 关闭页面或重启后，无法延续结果未确认的建组请求

建组表单的请求幂等键仅存在于 `@State` 中。服务端已成功建组但响应在网络中丢失时，留在原页面直接重试可以复用旧键；关闭页面重新填写相同内容或重启应用后再试，会产生新键。服务端以“账号、操作、键”识别回执，没有按名称和内容去重，因此第二次请求可以再建一个组，额外占用创建配额和小组号。创建报名活动也有相同的页面内键生命周期。

证据：[建组键](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupViews.swift:273)、[建组提交](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupViews.swift:306)、[活动键](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupActivityViews.swift:19)、[iOS 通用写请求只透传键](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:35)、[服务端回执查找](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/api-server/src/lib/groups/idempotency.ts:71)、[服务端建组](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/api-server/src/lib/groups/service.ts:145)。

Android 会将未确认请求按账号和内容登记，鸿蒙也会在发送前落盘并在重启后复用。iOS 的直接排赛已经使用了持久请求记录，因此这一缺口主要在通用表单写入路径，并非所有小组写入都缺少幂等保护。

建议：把建组、创建活动等未确认写入纳入持久请求登记，保存原始请求体与键；成功确认后只清理对应项。已确认成功后的再次新建必须能获得新键。

验证：源码链路确认；未向真实服务端发送重复建组请求。

### R2 · P2 · iOS 活动刷新失败会永久删除已设置的提醒

已经报名并开启活动提醒后，若成员接口成功、活动接口超时或返回临时错误，`try?` 将活动结果转为 `nil`。详情页继续展示旧活动缓存，却向提醒同步传入 `a ?? []`。同步方法把空数组解释为活动已不存在，删除本地记录并取消系统提醒。后续网络恢复不会自动恢复这条提醒，用户需要手动重新打开。

证据：[失败结果被当作空活动集](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:277)、[找不到活动即删除提醒](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupActivityReminder.swift:58)。

Android 仅在活动刷新成功时同步；鸿蒙也有 `activitiesLoaded` 成功标记：[Android](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/group/GroupDetailViewModel.kt:355)、[HarmonyOS](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/group/GroupDetailPage.ets:419)。

建议：活动读取失败时保留提醒，只有读取成功的活动快照才用于判断取消、退报名或不存在；已经确认归档、解散、失去成员资格时仍应独立清理。

验证：提取当前生产 `synchronize` 方法及调用处的空值表达式，用替代通知平台运行 Swift 探针。正常活动快照保留提醒；随后模拟读取失败，提醒记录被删除。未验证真机通知弹出。

### R3 · P2 · Android 已归档、解散冷静期的小组仍能触发活动提醒

用户开启提醒后，小组被归档或进入解散冷静期，服务端只更新小组状态，并不会把报名活动改为取消。Android 的归档、解散写入与详情提醒同步没有清理该组提醒；提醒触发时虽重新读取小组，校验仅检查活动状态、时间和报名资格，忽略 `group.status`，因此仍会放行并显示“活动即将开始”的通知。

证据：[Android 触发前校验](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/managers/group/GroupActivityReminder.kt:89)、[归档写入](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/data/repository/GroupRepository.kt:569)、[详情状态发布](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/group/GroupDetailViewModel.kt:825)、[服务端归档只更新组状态](/Users/yangyang/Desktop/jifenqi/jifenqi-backend/api-server/src/lib/groups/service.ts:330)。

iOS 的提醒同步要求 `group.isActive`；鸿蒙在详情刷新及提醒刷新中明确清理只读小组：[HarmonyOS](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/group/GroupDetailPage.ets:418)。

建议：Android 在归档、发起解散及读到非 active 状态时取消该组提醒，并在通知实际触发前再次要求小组为 active，覆盖其他设备变更小组状态的情况。

验证：通过临时 Gradle source set 调用实际生产 `GroupActivityReminder.validate`，只替代仓库、账号与平台调度依赖。`archived`、`dissolving` 两种输入都返回了可发送提醒的记录，复现 2 项。诊断探针通过表示缺陷被复现，并非此场景符合预期。未发送真实通知。

### R4 · P2 · iOS 上传失败记录保存了当时的语言，切换语言后仍显示旧文案

例如在中文环境上传赛果被拒，队列同时保存稳定的 `failureCode` 和已经翻译好的中文 `failure`。用户切到英文并重新启动后，界面直接显示磁盘里的 `upload.failure`，未按当前语言解析错误码。无效本地比分也直接保存本地化句子，并且没有设置对应错误码。

因此，47 语言资源完整、错误映射覆盖完整，并不能保证这些已持久保存的失败记录随语言切换。这是本轮新发现的运行时多语言遗漏。

证据：[同步时保存本地化错误](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:415)、[错误码与文案一同持久化](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupLocalPersistence.swift:168)、[界面直接显示旧文案](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupDetailView.swift:426)、[本地规则失败只保存句子](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupLocalPersistence.swift:140)。Android 和鸿蒙队列显示路径均优先使用稳定错误码。

建议：统一保存稳定错误码，在展示时解析当前语言；对已有失败记录和本地规则错误补兼容处理，保留“需要人工处理”的状态语义。

验证：提取生产上传行结构、读写、重试更新及读取方法，写入 `GROUP_ARCHIVED` 和中文失败文案，重新实例化持久层后旧文案仍原样返回；另核对界面确实直接使用该字段。未做实际应用语言切换 UI 自动化。

### R5 · P2 · iOS 旧账号请求结束会提前解锁新账号的管理菜单

账号 A 的写操作尚未返回时切换到 B，`sessionDidChange` 会把写操作计数清零。B 发起新写操作后，A 的请求返回，其 `defer` 仍无条件对同一个全局计数减一，导致 B 的请求还在执行时 `mutating` 已变为 false。详情顶栏管理菜单依赖这个值禁用，会提前恢复可点，允许并行发起原本应被阻止的管理操作。

证据：[账号切换清零计数](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:184)、[旧请求无条件递减](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:365)、[菜单禁用依赖此状态](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupDetailView.swift:151)。

请求本身还有账号与认证代次守卫，本轮没有据此认定旧请求会把数据写入 B。确认的问题是新账号界面的并发操作保护被旧请求解除。

建议：让写操作计数绑定身份代次，旧身份操作结束时不得更改新身份计数，或以当前身份的在途操作集合派生忙碌状态。

验证：提取生产 `perform` 方法及账号切换的计数重置语句，受控暂停 A、B 两次写操作，先释放 A。实验确认 B 尚未结束时 `mutating == false`。

## 复查通过的对应行为

- 三端邀请海报的当前导出尺寸仍为 **720×920**；鸿蒙额外检查实际 PixelMap 宽高。鸿蒙二维码导出生命周期脚本通过。
- iOS **47 语言 × 382 个小组键 + 2 个共用计数键**的资源、格式参数、复数、catalog 检查通过，写回器 `--check` 为 0 个文件需要变化；这与 R4 的持久化显示缺口是两个不同层次。
- Android、鸿蒙未确认创建请求的持久重试标识，以及账号切换后拒绝旧响应的相关定向回归通过。
- 非成员、已移除成员访问详情，当前服务端统一返回未找到；没有把 iOS “只对 404 清缓存”单独列为新权限缺陷。
- 直接排赛的 iOS 持久请求实现、三端正式与临时成员合并计数，以及训练组不新增的本期范围均保留。

## 本轮验证及边界

| 项目 | 结果 |
| --- | --- |
| iOS 生产方法 Swift 探针 | 3 个诊断场景复现 R2、R4、R5；使用生产方法文本及替代依赖，不等同于整 App 模拟器测试 |
| Android OfficialDebug 定向单元测试 | 既有 GroupRepositoryReviewTest 4 项、GroupDetailSessionIsolationTest 1 项通过；另 2 项临时诊断探针复现 R3 |
| HarmonyOS 定向脚本 | `test_group_activity_actions.mjs`、`test_group_review_followup.mjs`、`test_group_session_isolation.mjs`、`test_group_personal_result_tasks.mjs`、`test_group_share_qr_lifecycle.mjs` 全部通过；其中报名、提醒、开局脚本含 16 项场景，会话脚本另联跑其依赖的认证隔离检查 |
| iOS 语言 | 写回器只读检查通过；`test_group_localization.py` 7 项通过 |

临时实验、源码生成器、诊断 Kotlin 测试、Gradle source set 注入脚本和日志位于 `/tmp/group-independent-review-20261017/`。Android 首次诊断编译因探针将 suspend 账号读取误用普通 MockK `every` 失败，改为 `coEvery` 后最终 7 项全部通过；该错误只在临时探针中。

未修改业务代码，未做完整 App 打包、三端真机交互、47 语言逐页截图或生产服务写入。本轮跳过完整构建，因为任务是源码复查，现有定向测试和隔离实验已覆盖报告中的论据。三端现有未提交修改均保留。

建议先处理 R1 的重复创建风险与 R2/R3 的提醒生命周期，再收尾 R4 的语言切换和 R5 的并发状态隔离。
