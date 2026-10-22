# 小组独立复查 R1–R5 二次确认与修复（2026-10-17）

独立复查报告中的 5 项问题均再次核实并完成修复。变更涉及 iOS 和 Android；鸿蒙对应实现已满足本轮要求，仅运行定向回归。熟人组范围、默认 30 人及正式和临时成员合并计数规则均未调整。

## 逐项结果

| 问题 | 二次确认 | 修复后行为 |
| --- | --- | --- |
| R1 · iOS 未确认创建请求丢失重试标识 | 建组、创建报名活动仍使用表单内 UUID；服务端按幂等键返回回执 | 发送前按账号、接口和请求内容保存键与原始请求体；关闭页面、重建仓库或应用重启后，相同未确认请求复用原键。成功确认或明确拒绝只清理该请求；成功后的新建使用新键 |
| R2 · iOS 活动刷新失败误删提醒 | 再次运行生产方法探针，活动读取失败被转为空数组，已存提醒被删除 | 失败保留提醒；成功取得空列表、取消活动、退报名时正常移除。已经确认组为归档或解散状态时，即使活动或成员分区读取失败也清理提醒 |
| R3 · Android 只读小组仍发送提醒 | 正确 DTO 的修复前 5 项回归中，4 项失败：归档/解散仍可发送，读取状态和成功变更状态均不清理提醒 | 成功归档、发起解散、列表或详情读到非 active 状态时清理提醒；通知发送前重新要求组为 active。正常活动提醒保留，归档失败不会误删提醒 |
| R4 · iOS 持久失败提示不随语言变化 | 再次运行持久层探针，旧本地化句子被直接读回；界面直接显示该字段 | 新失败保存稳定错误码，展示时按当前语言解析；已有“错误码 + 旧句子”和仅旧句子的记录均兼容，保留人工修复状态；临时限流等可重试行继续自动重试 |
| R5 · iOS 旧账号请求提前解锁当前账号 | 再次运行生产 `perform` 探针，A 请求结束导致 B 尚在执行的操作被解锁 | 只有与当前身份代次匹配的操作才可递减当前计数；A→B、A→B→A 两种情况均保持当前操作锁，当前操作结束后再解锁 |

R1 保留网络结果不确定、畸形成功响应和会话失效取消时的请求记录；无法落盘或记录损坏时停止发送，避免生成无法安全重试的创建操作。账号注销会清理该账号的记录，不影响其他账号。直接排赛沿用原有持久请求实现。

R4 的兼容显示不直接输出旧语言句子：已有稳定错误码优先；旧代码字符串继续识别；仅有句子的记录按本地比分有效性使用“结果需要检查”或通用保存失败提示。新本地规则失败也写入 `INVALID_RESULT`。

## 主要源码

- R1：[创建请求](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:63)、[持久请求登记](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupLocalPersistence.swift:83)。建组和报名活动表单已调用持久创建入口，删除页面内重试键及其重置逻辑。
- R2：[提醒同步接受失败状态](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupActivityReminder.swift:57)、[只读组独立清理](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:304)。
- R3：[Android 状态清理](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/data/repository/GroupRepository.kt:221)、[发送前校验](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/managers/group/GroupActivityReminder.kt:91)、[详情同步守卫](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/group/GroupDetailViewModel.kt:866)。
- R4：[旧失败记录兼容解析](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupLocalPersistence.swift:18)、[当前语言展示](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupDetailView.swift:426)。
- R5：[操作计数的身份守卫](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Groups/GroupRepository.swift:389)。

## 验证

| 检查 | 结果 |
| --- | --- |
| iOS 原生模拟器编译及小组测试 | **118/118 通过**：GroupContractTests 20、GroupPortParityTests 92、GroupPreviewDecodingTests 6 |
| iOS 新增回归 | 15 项；涵盖创建丢响应/畸形成功、重启、交错请求、内容变化、账号隔离、成功后新请求、明确拒绝、损坏登记、落盘失败不发送、请求中换账号；提醒成功/失败与只读状态；旧失败记录 47 语言显示；A→B 和 A→B→A 并发操作锁 |
| Android 定向测试 | **32 项唯一测试通过**：新 GroupReminderLifecycleReviewTest 7，既有 GroupRepositoryReviewTest 4、GroupDetailSessionIsolationTest 1、GroupAuditV2RemediationTest 13、GroupDataScenarioRemediationTest 7 |
| Android 修复前后对照 | 初始测试 DTO 缺少 `isCoach` 使两个用例先触发响应校验；补全 DTO 后再次运行，确认 5 项中 4 项因报告所述行为失败。修复后原 5 项及后来补的列表清理、拒绝归档不清理两项均通过 |
| iOS 多语言资源 | `group_copy_20261017.py --check`：47 语言 × 382 个小组键 + 2 个共用计数键，0 文件需要写回；`test_group_localization.py` 7 项通过 |
| 鸿蒙 | 活动报名/提醒/开局 16 场景、持久请求与账号缓存边界、二维码分享生命周期三个脚本全部通过；未修改鸿蒙源码，跳过 hvigor |
| 残留和差异检查 | 旧的活动失败转空数组、直接显示持久失败句子、跨身份无条件扣减计数、两个创建表单内重试键已清除；相关文件 `git diff --check` 通过 |

iOS 使用 iPhone 17 Pro / iOS 26.5 模拟器及 ad hoc 测试签名。最终结果包：`/tmp/group-independent-fixes-20261017/ios-verified-tests.xcresult`。iOS 118 项测试同时保留已有 **720×920 海报**断言；鸿蒙二维码生命周期回归仍检查实际导出宽高。

Android 先运行包含 30 项测试的五组定向回归，再为新增列表和失败归档边界运行最终 7 项提醒回归；两轮重叠 5 项，因此按唯一测试计为 32 项。没有将修复前用于证明缺陷的失败断言计入最终通过数。

新回归位于 [GroupPortParityTests.swift](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifenTests/GroupPortParityTests.swift:227) 与 [GroupReminderLifecycleReviewTest.kt](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/test/java/com/douhua/jifen/group/GroupReminderLifecycleReviewTest.kt)。网络返回和系统通知依赖使用隔离测试替身，没有向真实服务端重复建组或发送真实通知。

## 构建告警与边界

按项目验证策略使用增量编译及定向单元测试，未执行 clean、商店发布包构建或真机通知冒烟。iOS 修复过程中一并消除了提醒更新捕获可变变量的既有告警，并消除了新增测试的同类告警；最终测试日志仍有其他文件中既有的可变变量捕获和 AppIntents 元数据告警。首次重编译持久层也报告了既有 AnyCodable 的 actor 隔离告警，其对应表达式与改前备份一致。本轮没有建立全仓 clean 告警基线，也没有修改这些无关代码。Android 有既有 JVM CDS/Gradle 弃用提示。

三端真机完整链路、真实通知弹出、47 语言逐页视觉验收仍未执行。本轮完成的是上述 5 项代码修复、编译和针对性回归；未提交 Git、部署服务端或发布 App。

改动前 13 份相关文件的原样备份保存在 `/tmp/group-independent-fixes-20261017/before/`，测试及编译日志在同级目录。原有未提交修改保留。
