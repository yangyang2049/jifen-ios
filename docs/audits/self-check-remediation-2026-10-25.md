# 未提交修改二次复核与修复 · 2026-10-25

范围：用户提供的四项 P1、P2/P3 清单，以及关联的服务端与投屏接收端。保留各仓已有工作；本次没有提交、部署、生产迁移或真机安装。

## UI 冒烟新增发现：开局卡死

原报告“无 P0”的判断不成立。真实开局 UI 回归发现：`RallyScoreboardView.init` 在 SwiftUI 重建时为未安装的临时 State ID 注册身份；账本更新触发父视图再次计算，再生成临时 ID 并写账本，形成主线程循环。表现为点“开始”后按钮禁用、无法进入计分板、CPU 接近 100%。[主线程采样](../verification/audit-remediation-2026-10-25/scoreboard-start-main-thread.sample.txt) 和[卡住画面](../verification/audit-remediation-2026-10-25/scoreboard-start-hang.png) 已保存。

已全量扫描并移除计分板构造函数中的身份写入，包括 Rally、Tennis、四类台球、多人、射箭、拳击、斗地主及非个人计分板；篮球 store 构造同样不再登记。初始 selections 只以 State 值捕获，统一在首次 onAppear 后以实际安装的记录 ID 注册；恢复会话跳过，后续返回不会用初始配置覆盖已编辑绑定。局内续局继续在实际成功后复制或登记新 ID。预约持久化的身份登记也统一在明确的成功边界处理。

本轮新增构造/宿主回归与真实开局 UI 检查，最终结果见验证节。首次 UI 失败中还发现两项测试适配问题：旧用例等待语音气泡自动关闭，与本轮常驻需求不符；筛选用例依赖完整按钮 label 并大幅滚动越过目标，已改稳定标识及表单内短滚动。没有通过恢复自动消失行为来迁就旧断言。

## 测试宿主云同步副作用：已隔离，用户确认专用测试账号

终轮收尾读日志发现，测试宿主曾沿用模拟器正常 Keychain 的已有登录态，默认共享云同步在快照测试/fixture 运行期间发送了真实私有记录请求。这应在运行测试前隔离，不能把这些成功响应当作 mock 验证。

现已增加 `AppTestRuntime`：DEBUG 单测使用每进程独立 Keychain/defaults/存储目录，明确 UI fixture 使用独立稳定空间；共享身份、云缓存、计分/计时历史和语音文件也按此分开。默认私人云同步在测试宿主中无法激活；显式注入 mock 的传输测试仍完整执行。Release 及普通运行路径保持原 service 和目录。新增回归实际验证共享管理器写入隔离目录，不读取正常凭据。

修复后 878 项全量单测、iPhone 三项 UI 和 iPad 一项 UI 均通过；日志逐行复核没有注入式 `PersonalRecordsTransportTests` 以外的身份/私库/附件请求。隔离专项 25 项通过，[日志](../verification/audit-remediation-2026-10-25/ios-test-isolation.log)。

隔离后又只读核对了本机文件：正常身份与云缓存的哈希、大小、mtime 均未变化（仍为 11:23:34）；新 UI 空间只有 29 条 fixture、未登录账本，云缓存和 outbox 为 0。见[存储隔离复核](../verification/audit-remediation-2026-10-25/post-isolation-storage-summary.json)。这证明后续隔离生效，不代表此前副作用已撤销。

用户随后明确确认：该模拟器此前登录的是**专用测试账号**。本机缓存中的 29 条明确 `ui-fixture-*` 样例及 30 条来源未定的 UUID 记录按该测试账号范围保留；30 条记录的逐条来源仍未认定，24 条 `RECORD_NOT_FOUND` 也不计为删除成功。用户没有要求清理，因此没有对云端或原缓存执行补偿删除。精确样例键、时间、版本、队列状态与归因边界见[本地只读核对报告](../verification/audit-remediation-2026-10-25/test-cloud-side-effect-review.md)。

## 四项 P1

| 报告项 | 复核及处理 |
| --- | --- |
| 八球/斯诺克局内“再来一局”丢身份 | 确认。两板在新局持久化成功后复制旧记录的身份选择。 |
| “我的记录”逐摘要全库解码 | 确认。后台生成摘要时加入有效参赛位置/名称、小组场次 ID；页面直接结合实时身份账本筛选，不打开完整记录。历史 claim 与 outbox 均建立按记录索引，避免逐行扫描整表。详情及注释更新改为单文件定位读取。 |
| 删除全部的跨设备范围未告知 | 确认。保留记录删除向账号其他设备同步的既有语义，登录时确认明确涵盖其他设备同步记录、不可撤销；批量删除也提示同步。限制为可读记录库，批量墓碑一次持久化，并去重原生管理器的后续回调。 |
| 详情 replay 不回填人员身份 | 确认。`setup(from:identity:)` 按权限、有效席位、名称快照恢复显式选择；唯一有效历史 claim 可延续。排除小组原始归属、陈旧改名及歧义 claim。 |

## P2/P3 逐项结论

| 报告项 | 复核及处理 |
| --- | --- |
| 民间九球转账允许负分 | 产品预期，既有九球规则预设说明已写明；不钳制转账分数，赛事继续非负。 |
| 单条 ≥9MiB 卡住全部同步 | 确认。超大项与明确拒绝项持久化隔离，后续批次继续；内容变化后生成新 mutation；现有同步页提供手动重试，先捕获本机最新内容。保留本机原记录。 |
| 音频 uploadUrl/downloadUrl | 服务端现有契约明确返回相对路径，因此绝对 URL 不是当前服务端缺陷。客户端增加同源绝对/相对地址解析、保留查询参数，拒绝异源等错误地址；下载使用返回的 downloadUrl。 |
| 同步主线程、重复编码和搜索 | 全库读盘、同步状态编码写盘、SHA256、批次尺寸编码、音频读盘/摘要移到后台。状态写入统一 FIFO，恢复时验证 generation/取消；每次最多处理 50 个候选，逐条生成 envelope；搜索增加可取消的 300ms 防抖。原生单条 Codable 转码仍遵循 MainActor 隔离，详见下方性能边界。 |
| 本地保留上限移除、计时整表 UserDefaults | 不恢复会删除用户历史的条数上限；去掉两个死常量。计时历史迁到逐条原子文件并缓存读取；旧聚合迁移后才删除源，写盘失败保留源，损坏源先备份再允许新保存。服务端没有按条数自动清除历史的策略，不将“永久保留”误解释成服务端会自动淘汰。 |
| 清除本地数据后云端恢复 | 与既有“不登出、不删云端”设计一致。登录时确认新增“云端记录在下次同步后重新显示”的说明。 |
| 九球规则页其他规则族显示默认 | 计分板只持久化当前规则族，另一族没有可恢复的比赛配置。当前族保留实际自定义值，另一族标明“预设示例，不是当前比赛配置”。 |
| 九球数字键盘定位 | 复用焦点和视口高度变化后重新滚动定位的模式；物理设备键盘验收尚未完成。 |
| 证据只在 /tmp | 本轮文本日志、机器可读摘要及 UI 截图存到仓库内 verification 目录；旧交付文档的历史 /tmp 路径不冒充本轮验证。 |
| 四个九球死键 | 已确认无调用后删除；47 个主表键集保持一致。 |
| 繁体“占先” | 改为“佔先”，同步资源、catalog、短语源及分语言断言。 |
| 身份字符串表未覆盖 | 新增三语键集、占位符及编译 bundle 一致性回归；其余语言英文回退维持既定范围。 |
| 旧记录金九 8 被推测迁移为 4 | 移除不能区分默认与自定义的猜测，重开保留原值。 |
| 重置首局开球人 | 新增向后兼容的 initialBreakerPlayer；新局重置恢复最初选择，旧快照缺字段保持原默认 0。 |
| applyingRemote / participantRecordID / tabChips | 复核为无效字段/代码后删除相关实现。 |
| 不同真人同名 | 保留允许同名的设计，设置页增加非阻断提示，建议增加区分称呼以方便显示和播报。 |
| Android/鸿蒙投屏漏新九球字段 | 确认。国内 Android、Google Android、鸿蒙补全 13 个字段白名单及 v3 民间/赛事分类、开球标记。 |

回归期间另修复：清空/删除发生于后台加载时，丢弃过期列表快照，等待新一轮加载完成后再发布及迁移身份；超大记录隔离分支的 Swift 独占访问冲突；账号预热取消后旧错误覆盖清理/新会话状态；手动重试先发旧内容的边界。均增加真实路径回归。

## 服务端结论

本次修复不需要新增服务端源码或 API。已逐项核对本地 `jifenqi-backend/api-server/src/lib/participantIdentity/{contracts,service}.ts` 和现有接口文档：支持逐项 applied/conflict/rejected、分页、记录库权限、墓碑、相对音频地址与现有请求大小限制。

发布流程仍须核对原实施 API 与新增数据库迁移的部署状态，并完成原生多端联调。本次没有执行服务端部署或迁移；测试期间的真实响应说明相关接口可达，但不能据此认领完整发布验收。旧报告中的生产快照属于历史记录。

后端本轮 contract 测试 1 通过；真实隔离 Postgres suite 因本地专用 env 已不存在而跳过，未加载生产配置。此前“54 项通过”属于旧实施记录，本轮不重复认领。

## 验证证据

统一目录：[audit-remediation-2026-10-25](../verification/audit-remediation-2026-10-25/)。构建命令直接记录退出码，未通过 `tail` 管道推断成功；Xcode 使用正常签名及独立测试输出路径。

- JifenCore：277 项通过，[日志](../verification/audit-remediation-2026-10-25/swift-test.log)。
- 最终 iOS 全量单元：878 项，877 通过、1 跳过、0 失败。跳过项是需单独启用的真实 APNs 探针；[分类摘要](../verification/audit-remediation-2026-10-25/validation-summary.json)、[原始结果摘要](../verification/audit-remediation-2026-10-25/ios-isolated-final-summary.json)、[日志](../verification/audit-remediation-2026-10-25/ios-isolated-final.log)。同步专项 17 项也包含在全量中，不重复累加。
- 最终 iPhone UI：3 项通过，覆盖实际开局、语音气泡保持展开/手动收起、不挤压布局、筛选清除及个人页隐藏 Tab；同一结果包的总数为 881（878 单测 + 3 UI），[截图](../verification/audit-remediation-2026-10-25/ui-phone-isolated-final/manifest.json)。
- 最终 iPad UI：个人记录筛选与页面层级回归 1 项通过；[摘要](../verification/audit-remediation-2026-10-25/ios-ui-ipad-isolated-summary.json)、[截图](../verification/audit-remediation-2026-10-25/ui-ipad-isolated-final/manifest.json)。两端 XXXL 字号筛选行与个人页截图已直接目视复核。
- 本地化 Python：12 项通过，[日志](../verification/audit-remediation-2026-10-25/voice-localization.log)。
- 九球 demo 契约：23 项通过，[日志](../verification/audit-remediation-2026-10-25/nine-ball-demo.log)。
- 国内 Android：133 项通过，[摘要](../verification/audit-remediation-2026-10-25/nineball-android-test-summary.txt)。
- Google Android：133 项通过，[摘要](../verification/audit-remediation-2026-10-25/nineball-google-test-summary.txt)。
- 鸿蒙 entry Debug HAP 构建通过；生产显示函数 v3 回归、两个既有显示脚本及九球 73 项检查通过；同目录保留构建和脚本日志。
- 后端：[本轮 contract 日志](../verification/audit-remediation-2026-10-25/backend-contract.log)。
- 干净编译：0 errors，[构建摘要](../verification/audit-remediation-2026-10-25/ios-clean-build-summary.json)。工程仍有 actor isolation、旧 API 弃用、optional coercion、Sendable capture 等告警；[分类对照](../verification/audit-remediation-2026-10-25/build-warning-categories.json) 未出现新增告警类别。本报告不宣称整个工程零告警。

## 验证与性能边界

实体电视/AirPlay、九球键盘真机、实际多端登录和云端联调尚未验收，模拟器及契约测试不能替代这些结果。

本轮消除了逐行全库磁盘解码、无防抖查询、主线程同步循环中的全状态 JSON 写入及多份整批 envelope 中间数组。记录列表/云缓存目前仍保存完整历史；原生单条 Codable 转码仍在 MainActor。大库场景仍需调整原生值模型隔离及云缓存/列表分页，这一架构性能项尚未完全关闭。
