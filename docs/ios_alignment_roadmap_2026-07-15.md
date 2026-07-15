# iOS 以 Android Score Engine 为模板的重构总计划

日期：2026-07-15  
项目：`jifen-ios` / App Store bundleId `com.douhua.jifen.ios`  
目标：iOS 主应用与 Apple Watch 端按 Android 当前 `Score Engine` / `Score Core` 架构一起完全重建，先把手机和手表共用的本地计分内核、记录模型、Watch 独立计分和最小联动闭环打稳，再把账号服务端能力拆到后续阶段。

## 0. 当前决策

本轮 iOS 追版本先聚焦“本地可用、离线稳定、规则可信、手机和手表同核”。下列能力本版本明确不做：

- 账号体系：登录、会员权益、云端用户资料、跨设备账号数据。
- 用户反馈：服务端反馈列表、反馈状态、客服闭环。
- 依赖服务端的云端同步积分 / 显示端大屏：包括 WebSocket 房间、同步码、展示端协议、多人云房间。

账号、反馈、云端同步这些能力不是废弃，而是推迟到第 3 阶段以后，避免备案、证书、服务端、账号主体和 Apple 审核材料把 iOS 追本地能力的节奏拖乱。

本轮核心判断：

- iOS 不沿着现有页面小修小补，而是按 Android 的计分内核重构路线重来。
- Android 是架构真源；HarmonyOS 是产品覆盖、手表能力和跨端体验的重要参考。
- 当前 iOS 代码主要作为功能盘点、局部 UI、素材、文案和 App Store 配置来源。
- Apple Watch 端不再后置到单独重构阶段，Phase 1 必须一起完成手表底层重构。
- Watch 和 iPhone 必须共用同一套纯 Swift `ScoreCore` / `SessionCore` / record projection，不能后续再分开改。

架构优先级按 Android 重构文档执行：规则真源正确 -> session 模型稳定 -> record / audit / replay 完整 -> presentation 接线。也就是说，先有可测试的纯 Swift 规则内核，再让手机页面和手表页面接入，而不是让 SwiftUI 页面继续各写一套计分规则。

## 1. 模拟器联动结论

当前本机环境：

- Xcode：`26.6`
- 已存在 3 组 active 的 iPhone + Apple Watch 模拟器配对，可用于 Phase 1 开发和 smoke。
- 当前项目未发现 `WatchConnectivity` / `WCSession` 主链路，需要新建。

Apple 平台判断：

- `WatchConnectivity` 是 iOS companion app 与 watchOS app 通信的系统框架。
- `WCSession.sendMessage` / `sendMessageData` 面向 reachable counterpart 的即时通信，适合做手机发起、手表确认、比分状态更新、ACK 这类前台联动。
- Apple 官方文档明确 `transferFile` 等部分 WatchConnectivity API 在 Simulator 不支持；Apple Developer Forums 也有 DTS 说明部分后台传输 API 需要真机设备测试。

Phase 1 的联动策略：

- 先把手机手表联动放入 Phase 1，目标是用模拟器完成前台实时 smoke：手机发起 -> 手表确认 -> 手表计分 -> 手机同步 -> 手机接管 -> 完赛回传。
- 如果实际 smoke 发现模拟器无法稳定覆盖，则 Phase 1 仍完成共享 core、协议模型和前台消息骨架，Phase 2 再做真机联动收口。
- 无论模拟器是否覆盖完整链路，完赛记录回传、后台恢复、断连补包都要保留真机最终验收。

## 2. 阶段总览

| 阶段 | 名称 | 目标 | 不做 |
| --- | --- | --- | --- |
| Phase 1 | 手机 + 手表同核完全重构 | 以 Android `Score Engine` / `Score Core` 为模板重建 iOS 主 App 和 Watch App：共享纯 Swift 计分内核、Session、记录投影、手机页面、Watch 独立计分、手机手表最小联动闭环 | 账号、服务端、云同步、显示端大屏 |
| Phase 2 | 联动真机强化与全量手表覆盖 | 若模拟器无法完整验证联动，则在此阶段做真机联调、后台/断连恢复和更多项目联动；若 Phase 1 已跑通联动，则此阶段做全量项目、复杂双打和手表体验强化 | 账号、云端同步 |
| Phase 3 | 主应用服务端与账号对齐 | 在备案、证书、账号主体、隐私材料明确后接入登录、反馈、会员/权益、云端数据 | 重新设计本地规则内核 |
| Phase 4 | 跨端云同步与展示端对齐 | 在本地同核和账号体系稳定后，再接云端同步积分、显示端大屏、跨设备记录合并 | 重新发明规则内核 |

建议实际推进顺序：Phase 1 先做到“Android 风格共享计分内核 + 主 App 代表项目页面 + Watch 代表项目页面 + 记录闭环 + 联动 smoke”可发内部版本，再决定是否发 `1.1`。Phase 2 只承接模拟器无法可靠覆盖的真机联动与复杂手表项目。Phase 3 / Phase 4 分别等外部条件和本地规则稳定后再进。

## 3. 当前 iOS 现状

### 3.1 已有基础

iOS 主 App 当前已经具备一批本地功能：

- Tab：首页、记录、计分、计时、工具。
- 计分项目：足球、篮球、排球、乒乓球、羽毛球、网球、匹克球、拳击、台球、射箭、斗地主、掼蛋、简单计分、多人计分。
- 计时项目：围棋、象棋、国际象棋、魔方、正计时/秒表、暂停/超时、篮球 24 秒、篮球 12 秒。
- 工具：抛硬币、骰子、哨子、红黄牌、积分表、秒表、全屏时间、AA 计算器、十秒挑战。
- 本地数据：计分记录、计时记录、常用名称、预约球局、快速开始配置、振动设置。
- Apple Watch：已有独立 Watch App，包含本地计分、工具、记录、设置等雏形。

### 3.2 关键现状判断

- 主 App 现在更像“多页面 SwiftUI 功能集合”，不应作为后续主架构基础。
- Watch App 已有不少本地功能，但如果继续独立扩展，会形成第二套规则债务。
- `HttpClient`、`WebSocketManager` 目前是 placeholder，说明服务端能力没有真实接入；这与本轮裁剪账号/反馈/同步积分一致。
- 代码中未发现 `WatchConnectivity` / `WCSession` 主链路，手机手表联动应作为 Phase 1 的新协议重新设计，而不是在现有 Watch 页面上临时补消息。
- 旧文档和 CHANGELOG 记录了不少“对齐鸿蒙”的局部改造，但缺少一个能指导后续同核重构的阶段化路线图。

## 4. 架构基线

### 4.1 Android 是主应用和 Watch 架构模板

Phase 1 直接以 Android 计分内核重构文档为蓝本，在 iOS 侧实现对应的纯 Swift 模块，并将这些模块同时挂到 iPhone App 与 Watch App：

| Android 模块语义 | iOS 建议模块 | 责任 |
| --- | --- | --- |
| `score-core` | `ScoreCore` | state、intent、event、reducer/state machine、invariant |
| `session-core` | `SessionCore` | `ScoreSession`、版本、撤销/历史、能力检查、replay |
| `persistence` | `Persistence` | session snapshot、event log、`ScoreboardRecord` projection |
| `presentation` | `Presentation` | ViewModel、UiState、共享组件、手机页面、手表页面 |
| connectivity model | `Connectivity` | message envelope、sessionId、seq/revision、ACK/NACK、snapshot |

原则：

- 单一规则真源：比分、局分、胜负、封顶、发球轮转、撤销等只能存在于 reducer / state machine / invariant validator。
- Session 与 Score 解耦：项目规则不直接知道页面、存储、账号、手表或云端。
- UI 只消费 projection：SwiftUI 页面不直接修改规则状态，只发送 intent 并渲染 UiState。
- Audit / Replay 先行：每个关键动作可记录、可撤销、可回放，后续云同步和手表联动才有稳定基础。
- 手机和手表同核：Watch 不复制规则，只复用纯 Swift core，并拥有自己的小屏 Presentation。
- 测试优先级高于页面迁移：核心引擎 fixture 通过后，再批量接手机和手表页面。

建议目录草案：

```text
jifenShared/
  ScoreCore/
    Common/
    S1/
    S2/
    S3/
    S4/
  SessionCore/
  Persistence/
  Connectivity/
jifen/
  Presentation/
    Shared/
    Scoreboards/
  Connectivity/
jifenWatch Watch App/
  Presentation/
    WatchScoreboards/
  Connectivity/
jifenTests/
  ScoreCore/
  SessionCore/
  WatchConnectivitySmoke/
contracts/
  score-core/
    s1/
    s2/
    s3/
    s4/
```

### 4.2 Android / HarmonyOS 主应用产品基线

后续 iOS Phase 1 应优先对齐以下基线：

- 项目范围：S1 双边比分、S2 事件型台球/拳击、S3 多人积分、S4 牌类状态机。
- 通用旅程：进入设置、计分、撤销、编辑、换边、退出草稿、恢复、结束、查看记录。
- 记录模型：`ScoreboardRecord`、`ScoreAction`、`extraData` 的语义要能和 Android / HarmonyOS 对齐。
- 本地体验：横竖屏、平板布局、常用名称、快速开始、记录详情分享、清除数据、主题/字号/振动。
- 测试方式：从少量手测转向规则夹具、记录模型测试、关键 UI smoke。

### 4.3 HarmonyOS 手表和联动基线

Phase 1 / Phase 2 的参考基线：

- 手表独立能力：计分首页、计时、工具、记录、设置、小屏适配、布局切换、撤销、重置、完赛记录。
- 手机手表联动 V2 产品语义：手机发起、手表确认、主控/跟随、完整快照覆盖、ACK/重发、接管、断线恢复、完赛记录回传。
- 双打专项：乒乓球/羽毛球/网球双打后续应支持四人顺序、发球/接发槽位、场区顺序 revision。

Apple 平台实现不能复用 Wear Engine；Phase 1 需要用 WatchConnectivity 重新建协议，但产品状态机应尽量对齐。

## 5. Phase 1：手机 + 手表同核完全重构

### 5.1 目标

以 Android `Score Engine` / `Score Core` 为模板同时重建 iOS 主 App 和 Apple Watch App，在不依赖账号和服务端的情况下，达到“规则可信、记录可追溯、手机手表同核、页面可批量接入、新用户本地功能不明显落后”的状态。

### 5.2 重点工作包

1. Swift ScoreCore 骨架
   - 建立 iOS 统一纯 Swift 计分内核，避免手机和手表各自写规则。
   - 按 S1 / S2 / S3 / S4 分类定义规则、状态、意图、动作日志和记录输出。
   - 先覆盖 S1 单打/线分/局分项目，再处理 S2 台球/拳击、S3 多人、S4 牌类。
   - 与 Android 的 reducer/state machine/invariant 思路保持同构，便于跨端 fixture 对照。

2. SessionCore 与 replay
   - 定义 `ScoreSession`、session version、project id、participant、settings、history、capabilities。
   - 所有计分动作进入 event log，支持 undo、redo 或 replay，避免页面状态成为事实来源。
   - 草稿 / 未完赛恢复以 session snapshot + event log 为基础。
   - Session 结构必须同时服务 iPhone 和 Watch，不能出现 Watch 私有规则状态。

3. 计分项目补齐与规则校验
   - 以 Android / HarmonyOS 当前项目表为准，补齐缺口：黑八、九球、斯诺克、升级等需要单独确认是否进入 iOS 本轮。
   - 乒乓球、羽毛球、网球需要明确单打/双打策略；若双打本轮不完整，底层模型也要提前支持。
   - 统一每个项目的胜局、封顶、领先 2 分、抢七、回合、局分/盘分显示。

4. 记录模型与详情页
   - 统一 `ScoreboardRecord` 字段语义：final score、set score、action timeline、extraData。
   - 记录详情需能解释各项目动作，特别是网球、射箭、台球、拳击、牌类。
   - 记录投影从 session / event log 生成，不由手机页面或手表页面手动拼字段。

5. 主 App Presentation 接线
   - 先做共享 Scoreboard ViewModel / UiState，再让项目页面消费统一状态。
   - 旧 SwiftUI 页面只保留能复用的布局、组件和文案，规则逻辑逐步下线。
   - 选择 3 个代表项目打样：羽毛球或乒乓球（S1）、网球（复杂 S1）、黑八/九球/拳击或多人计分（S2/S3）。

6. Watch Presentation 接线
   - Watch App 与主 App 共享 `ScoreCore` / `SessionCore` / record projection。
   - Watch 只保留小屏交互、布局、触觉/音效、表端本地存储适配，不复制计分规则。
   - 第一批 Watch 代表项目建议覆盖羽毛球或乒乓球、网球、匹克球或射箭；篮球训练是否进 Phase 1 需单独拍板。

7. 手机手表联动最小闭环
   - 建立 iPhone / Watch 双端 `Connectivity` 层，统一 message envelope、sessionId、seq、revision、ACK/NACK、snapshot。
   - Phase 1 优先使用 `WCSession.sendMessage` / reply 做前台实时联动 smoke。
   - 最小闭环：手机发起、手表确认、手表计分、手机同步、手机接管、完赛记录回传。
   - 对 `transferUserInfo` / `transferFile` 这类模拟器限制 API 不做 Phase 1 阻断，但要留真机验收项。

8. 计时与工具
   - 计时项目要对齐 Android / HarmonyOS 的入口、默认值、暂停/恢复、保存记录、详情展示。
   - 工具页先保留本地工具，不做服务端或活动运营能力。
   - 积分表、AA 计算器、时间、红黄牌等要走稳定的本地持久化或无状态策略。

9. 设置、常用名称、预约
   - 常用名称继续作为本地能力，过滤默认名、批量导入、使用频次排序要稳定。
   - 预约球局先保留本地提醒，不接城市/活动/云端组局。
   - 设置页明确“本地数据清除”的范围：计分记录、计时记录、预约、常用名称、快速开始配置是否一并清。

10. 自动化与验收
   - 为规则内核建立 fixture 测试，而不是只靠 UI 点测。
   - 每个项目至少覆盖：进入、计分、撤销、编辑、结束、记录详情、恢复。
   - 补 `xcodebuild` 主 App / Watch App 构建、核心 Swift 单测、联动 smoke 脚本、关键 QA 脚本。

### 5.3 当前问题

- 规则散在多个 ViewModel / View 中，后续扩展和跨端对齐成本高；这些页面不能继续当作规则基础。
- Watch App 当前已有能力，但规则与主 App 一致性需要系统复核，不能继续独立扩展。
- 记录字段含义需要重新统一，否则后续云同步会很痛。
- 牌类、台球类、双打类还没有像 Android 那样形成清晰的 S1-S4 契约。
- `checkers` 枚举存在但当前计时/计分定位不清，需要决定保留、隐藏还是改名。
- 主 App 里已有 `HttpClient` / `WebSocketManager` placeholder，容易让人误以为服务端功能可用；Phase 1 应保持隐藏或隔离。
- `WatchConnectivity` 当前未实现，联动协议需要从 Phase 1 开始设计，并明确模拟器 smoke 与真机验收边界。

### 5.4 Phase 1 完成标准

- `ScoreCore` / `SessionCore` / `Persistence` / 主 App `Presentation` / Watch `Presentation` 基础链路跑通，并至少完成代表项目迁移。
- Watch 端不再拥有独立规则实现，代表项目使用共享 core 完成离线计分和记录。
- 手机手表联动最小闭环在模拟器上完成 smoke；若模拟器受限，则完成协议骨架和真机验收清单。
- 本地可见入口与实际可用能力一致，没有“点进去是半成品”的主路径。
- 所有本地计分项目有规则说明、测试用例和记录语义。
- 无账号、无反馈、无云同步也不影响 App Store 文案自洽。
- 能提交一个“手机 + 手表本地同核追版本”的 iOS 新包。

## 6. Phase 2：联动真机强化与全量手表覆盖

### 6.1 目标

承接 Phase 1 无法被模拟器完整验证的部分，重点是真机联动稳定性、后台/断连恢复、更多项目 Watch 覆盖和复杂双打体验。如果 Phase 1 已能稳定完成联动闭环，则 Phase 2 变成全量项目和体验强化阶段。

### 6.2 重点工作包

- 真机联动：确认真实 iPhone + Apple Watch 上的 `isReachable`、前后台、锁屏、距离、低电量、重连语义。
- 后台与队列传输：完赛记录、断连补包、应用退出后的补偿同步是否需要 `updateApplicationContext` / `transferUserInfo`。
- 手表项目范围扩展：羽毛球、乒乓球、网球、匹克球、射箭、篮球训练是否作为第一批；台球/牌类是否排除。
- 共享 core 覆盖率：新增 Watch 项目必须走 Phase 1 建好的共享 core，不新增 Watch 私有规则。
- 小屏布局：38/40/41/42/44/45/49mm、动态字体、圆角/边距、误触区域。
- 手表记录：本地记录列表、详情、删除、完赛后查看。
- 手表设置：布局偏好、声音/振动、使用说明、数据清理。
- 手表 QA：多尺寸截图、连续点击、撤销、重置、完赛、后台恢复、断连恢复、手机接管。

### 6.3 当前问题

- Simulator 对部分 WatchConnectivity API 有限制，不能把模拟器 smoke 当成所有联动能力的最终验收。
- 手表双打和复杂项目不宜抢在 Phase 1 全部做完，但底层必须已经支持它们的状态模型。
- 真机联动可能暴露可达性、后台唤醒、消息乱序和延迟问题，需要独立 QA 时间。

### 6.4 Phase 2 完成标准

- 真实设备完成“手机发起 -> 手表确认 -> 手表计分 -> 手机同步 -> 手机接管 -> 完赛记录回传”闭环。
- 断连/重连/重复包/乱序包有测试。
- Watch 全量项目覆盖策略明确，新增项目都复用共享 core。
- App Store 文案按真实验收范围写，不泛化为所有项目联动。

## 7. Phase 3：主应用服务端与账号相关功能对齐

### 7.1 进入条件

只有在以下事项明确后才进入：

- 中国区发行主体、ICP备案、隐私政策、App Store 元数据口径明确。
- Apple 登录、国内登录、会员/IAP、服务端域名与证书策略明确。
- 后端 API 版本与 iOS 数据 schema 兼容策略明确。

### 7.2 重点工作包

- 账号登录：Apple 登录优先，其它登录能力按中国区/海外区策略决定。
- 用户资料与权益：会员状态、购买恢复、权益缓存、离线兜底。
- 用户反馈：反馈提交、图片/日志、状态查看、客服回复。
- 云端记录：本地记录上传、冲突合并、分页拉取、删除同步。
- 服务端配置：API base、地区、隐私协议、功能开关。
- 审核材料：数据收集、隐私标签、登录/IAP 审核账号、客服说明。

### 7.3 当前问题

- iOS 当前网络层只是 placeholder，没有真实错误处理、鉴权、重试、日志和环境切换。
- 如果 Phase 1 记录模型未统一，Phase 3 云端记录会被迫兼容一堆历史字段。
- 国内区和海外区是否拆 App、是否同 bundleId 延续，需要结合 ICP 和主体长期策略再定。

### 7.4 Phase 3 完成标准

- 账号、反馈、权益、云端记录都有可测 API 契约。
- App Store 隐私标签与实际行为一致。
- 离线本地能力不因服务端失败而不可用。

## 8. Phase 4：跨端云同步与展示端对齐

### 8.1 目标

在本地同核、Watch 联动和账号体系稳定后，再接云端同步积分、显示端大屏、跨设备记录合并等服务端相关能力。

### 8.2 重点工作包

- 云端同步积分：房间、短码、显示端、参与者状态、实时比分。
- 跨设备记录：本地记录上传、分页拉取、冲突合并、删除同步。
- 展示端大屏：扫码加入、显示端协议、断线恢复、主持端控制。
- 服务端事件模型：复用 Phase 1 的 session / event log / record projection，不重新定义计分事实。

### 8.3 当前问题

- 云同步会放大记录模型和事件模型的历史债务，所以必须等 Phase 1 同核稳定。
- 国内/海外服务端、备案、账号主体和隐私标签仍需单独决策。
- 显示端和 Watch 联动不能混成一套协议；它们可以共享 session 语义，但传输层不同。

### 8.4 Phase 4 完成标准

- 云端同步、显示端和记录合并都有可测 API 契约。
- 服务端失败不影响本地计分和 Watch 联动。
- App Store 隐私标签与实际数据行为一致。

## 9. 讨论点与需要拍板的问题

### 9.1 发版范围

- `1.1` 是否先发 Phase 1 的“新内核代表项目 + Watch 代表项目 + 联动 smoke + 旧项目可用保底”，还是等主要项目都迁完再发？
- iOS 内部版本号要继续 `1.1`，还是直接对齐 HarmonyOS / Android 的 `2.x` 口径？
- 本地功能补齐到什么程度可以发版：是“现有项目修稳”，还是必须补黑八/九球/斯诺克/升级？

### 9.2 产品范围

- 预约球局是否保留在 Phase 1？它现在是本地能力，但产品上可能容易让用户期待联网约球。
- 计时类棋类项目是否继续放在“计时”，还是要与计分项目的棋/牌类命名统一？
- `checkers` 当前枚举如何处理：隐藏、删除、改成跳棋/计时，还是留给后续？
- 篮球训练是否只属于 Watch，还是主 App 也要补？

### 9.3 架构取舍

- 是否确认 Android `Score Engine` / `Score Core` 为 iOS Phase 1 的唯一架构模板？
- Watch 共享 core 采用 shared target、Swift Package，还是 workspace 内共享 group？
- 是否接受 Phase 1 做一次较大目录重组，把现有计分页拆成 `ScoreCore`、`SessionCore`、`Persistence`、`Presentation`、`Connectivity`？
- 是否允许代表项目迁移完成后删除或隐藏旧计分页和 Watch 私有规则，而不是长期双轨维护？
- Android fixture 是否作为跨端契约真源，iOS 只做 Swift 版实现和补充用例？
- Connectivity 层是否也放进 shared target，还是 iPhone / Watch 各自实现 transport adapter、共享协议模型？
- 是否需要把记录模型先做 schema version，为 Phase 3 云同步预留迁移？

### 9.4 审核与合规

- 当前中国区 bundleId 是 `com.douhua.jifen.ios`，是否继续用朋友账号短期追版本？
- 如果账号/服务端功能后置，App Store 隐私标签是否继续保持“不收集数据”或最小化？
- 隐私协议、用户协议、ICP备案主体和 App Store 开发者主体是否需要在 `1.1` 前再核对一次？

### 9.5 手表与联动策略

- Phase 1 第一批 Watch 项目是否锁定羽毛球/乒乓球、网球、匹克球或射箭？
- 手机手表联动 Phase 1 是否只要求前台实时闭环，后台/断连补偿放 Phase 2 真机强化？
- 如果模拟器可以稳定跑 `sendMessage` 闭环，App Store 文案是否可以写“支持手机与 Apple Watch 联动计分”；如果只完成 smoke，是否先写“支持 Apple Watch 计分，联动能力逐步开放”？
- 双打联动是否 Phase 1 必须覆盖乒乓球/羽毛球/网球，还是先保证底层模型支持、页面后置？

## 10. 建议的近期执行顺序

1. 冻结 Phase 1 范围：列出主 App 白名单、Watch 白名单、隐藏项和首批代表项目。
2. 把 Android `score-core` / `session-core` / `persistence` / `presentation` 映射成 Swift 共享目录、target 和协议草案。
3. 建立 Swift `ScoreCore` + `SessionCore` skeleton，并同时接入 iPhone target 和 Watch target。
4. 从 Android 导入或翻译跨端契约 fixture，先覆盖 S1，再进入 S2 / S3 / S4。
5. 选 3 个主 App + Watch 代表项目打样：羽毛球或乒乓球（局分/封顶）、网球（game/set/tiebreak）、多人计分或台球/拳击（非 S1 简单局分）。
6. 建立 WatchConnectivity 前台联动 smoke：手机发起、手表确认、手表计分、手机同步、手机接管、完赛回传。
7. 打样通过后批量迁移其它项目，并逐步下线旧页面规则和 Watch 私有规则。
8. 补主 App / Watch App 构建、规则 fixture、记录详情测试、联动 smoke 脚本。
9. 最后处理 App Store 文案、截图、隐私/协议和版本号。

## 11. 参考文档

- Apple：`https://developer.apple.com/documentation/watchconnectivity/`
- Apple：`https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)`
- Apple：`https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)`
- Android：`/Users/yangyang/Desktop/jifenqi/jifen-android/docs/2026-03-main-app-global-alignment-report.md`
- Android：`/Users/yangyang/Desktop/jifenqi/jifen-android/docs/计分内核完全重构执行方案.md`
- Android：`/Users/yangyang/Desktop/jifenqi/jifen-android/docs/计分内核完全重构与协作架构设计稿.md`
- Android：`/Users/yangyang/Desktop/jifenqi/jifen-android/docs/scoreboard-all-game-types-test-cases.md`
- Android：`/Users/yangyang/Desktop/jifenqi/jifen-android/docs/计分项目双端对照与记录模型.md`
- HarmonyOS：`/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/scoreboard_sports_rules_and_records.md`
- HarmonyOS：`/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/watch_phone_protocol_v2.md`
- HarmonyOS：`/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/racket_doubles_watch_interaction_and_linking_plan_2026-07-11.md`
- iOS 当前：`CHANGELOG.md`
- iOS 当前：`QA_FEATURE_VALIDATION_REPORT.md`
- iOS 当前：`BUGS_AND_OPTIMIZATION_REPORT.md`
