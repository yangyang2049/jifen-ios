# iOS 以 Android Score Engine 为模板的重构总计划

日期：2026-07-15  
项目：`jifen-ios` / App Store bundleId `com.douhua.jifen.ios`  
目标：iOS 主应用按 Android 当前 `Score Engine` / `Score Core` 架构完全重建，先追上本地计分、计时、记录和工具能力，再把 Apple Watch、账号服务端、手机手表联动拆成清晰的后续阶段。

## 0. 当前决策

本轮 iOS 追版本先聚焦“本地可用、离线稳定、规则可信”。下列能力本版本明确不做：

- 账号体系：登录、会员权益、云端用户资料、跨设备账号数据。
- 用户反馈：服务端反馈列表、反馈状态、客服闭环。
- 云端同步积分 / 显示端大屏：包括 WebSocket 房间、同步码、展示端协议。
- 手机与手表实时联动：包括手机发起、手表确认、状态 ACK / 重发、接管、记录回传。
- Apple Watch 端大重构：手表先单独列阶段，当前主线可暂不看。

这些能力不是废弃，而是推迟到第 3 / 第 4 阶段，避免备案、证书、服务端、账号主体和 Apple 审核材料把 iOS 追本地能力的节奏拖乱。

本轮核心判断：iOS 不沿着现有页面小修小补，而是按 Android 的计分内核重构路线重来。Android 是架构真源；HarmonyOS 是产品覆盖、手表能力和跨端体验的重要参考；当前 iOS 代码主要作为功能盘点、局部 UI、素材、文案和 App Store 配置来源。

架构优先级按 Android 重构文档执行：规则真源正确 -> session 模型稳定 -> record / audit / replay 完整 -> presentation 接线。也就是说，先有可测试的纯 Swift 规则内核，再让页面接入，而不是让每个 SwiftUI 页面继续各写一套计分规则。

## 1. 阶段总览

| 阶段 | 名称 | 目标 | 不做 |
| --- | --- | --- | --- |
| Phase 1 | 主应用完全重构 | 以 Android `Score Engine` / `Score Core` 为模板重建 iOS 主 App：纯 Swift 计分内核、Session、记录投影、页面接线、本地测试 | 账号、服务端、云同步、手机手表联动 |
| Phase 2 | 手表功能对齐 | Apple Watch 独立使用能力对标 HarmonyOS / 华为手表端：本地计分、计时、工具、记录、设置 | 手机手表实时联动、云同步 |
| Phase 3 | 主应用服务端与账号对齐 | 在备案、证书、账号主体、隐私材料明确后接入登录、反馈、会员/权益、云端数据 | 手表联动主协议 |
| Phase 4 | 手机手表联动对齐 | 用 WatchConnectivity 设计 iPhone / Apple Watch 联动协议，对齐 HarmonyOS V2 产品语义 | 重新发明规则内核、混入账号/云同步 |

建议实际推进顺序：Phase 1 先做到“Android 风格计分内核 + 代表项目页面 + 记录闭环”可发内部版本，再决定是否发 `1.1`；Phase 2 可与 Phase 1 后半并行评估，但不要阻塞主 App 重构主线；Phase 3 / Phase 4 分别等外部条件和本地规则稳定后再进。

## 2. 当前 iOS 现状

### 2.1 已有基础

iOS 主 App 当前已经具备一批本地功能：

- Tab：首页、记录、计分、计时、工具。
- 计分项目：足球、篮球、排球、乒乓球、羽毛球、网球、匹克球、拳击、台球、射箭、斗地主、掼蛋、简单计分、多人计分。
- 计时项目：围棋、象棋、国际象棋、魔方、正计时/秒表、暂停/超时、篮球 24 秒、篮球 12 秒。
- 工具：抛硬币、骰子、哨子、红黄牌、积分表、秒表、全屏时间、AA 计算器、十秒挑战。
- 本地数据：计分记录、计时记录、常用名称、预约球局、快速开始配置、振动设置。
- Apple Watch：已有独立 Watch App，包含本地计分、工具、记录、设置等雏形。

### 2.2 关键现状判断

- 主 App 现在更像“多页面 SwiftUI 功能集合”，不应作为后续主架构基础；后续应重建为 Android 当前那种“统一计分内核 + session + 记录投影 + 契约测试 + 项目规则注册”的架构。
- `HttpClient`、`WebSocketManager` 目前是 placeholder，说明服务端能力没有真实接入；这与本轮裁剪账号/反馈/同步积分一致。
- 代码中未发现 `WatchConnectivity` / `WCSession` 主链路，手机手表联动应作为 Phase 4 重新设计，而不是在现有 Watch 页面上临时补消息。
- 旧文档和 CHANGELOG 记录了不少“对齐鸿蒙”的局部改造，但缺少一个能指导后续重构的阶段化路线图。

## 3. 架构基线

### 3.1 Android 是主应用架构模板

Phase 1 直接以 Android 计分内核重构文档为蓝本，在 iOS 侧实现对应的纯 Swift 模块：

| Android 模块语义 | iOS 建议模块 | 责任 |
| --- | --- | --- |
| `score-core` | `ScoreCore` | state、intent、event、reducer/state machine、invariant |
| `session-core` | `SessionCore` | `ScoreSession`、版本、撤销/历史、能力检查、replay |
| `persistence` | `Persistence` | session snapshot、event log、`ScoreboardRecord` projection |
| `presentation` | `Presentation` | ViewModel、UiState、共享组件、项目页面 |

原则：

- 单一规则真源：比分、局分、胜负、封顶、发球轮转、撤销等只能存在于 reducer / state machine / invariant validator。
- Session 与 Score 解耦：项目规则不直接知道页面、存储、账号、手表或云端。
- UI 只消费 projection：SwiftUI 页面不直接修改规则状态，只发送 intent 并渲染 UiState。
- Audit / Replay 先行：每个关键动作可记录、可撤销、可回放，后续云同步和手表联动才有稳定基础。
- 测试优先级高于页面迁移：核心引擎 fixture 通过后，再批量接项目页面。

建议目录草案：

```text
jifen/
  ScoreCore/
    Common/
    S1/
    S2/
    S3/
    S4/
  SessionCore/
  Persistence/
  Presentation/
    Shared/
    Scoreboards/
jifenTests/
  ScoreCore/
  SessionCore/
contracts/
  score-core/
    s1/
    s2/
    s3/
    s4/
```

### 3.2 Android / HarmonyOS 主应用产品基线

后续 iOS Phase 1 应优先对齐以下基线：

- 项目范围：S1 双边比分、S2 事件型台球/拳击、S3 多人积分、S4 牌类状态机。
- 通用旅程：进入设置、计分、撤销、编辑、换边、退出草稿、恢复、结束、查看记录。
- 记录模型：`ScoreboardRecord`、`ScoreAction`、`extraData` 的语义要能和 Android / HarmonyOS 对齐。
- 本地体验：横竖屏、平板布局、常用名称、快速开始、记录详情分享、清除数据、主题/字号/振动。
- 测试方式：从少量手测转向规则夹具、记录模型测试、关键 UI smoke。

### 3.3 HarmonyOS 手表和联动基线

后续 Phase 2 / Phase 4 的参考基线：

- 手表独立能力：计分首页、计时、工具、记录、设置、小屏适配、布局切换、撤销、重置、完赛记录。
- 手机手表联动 V2 产品语义：手机发起、手表确认、主控/跟随、完整快照覆盖、ACK/重发、接管、断线恢复、完赛记录回传。
- 双打专项：乒乓球/羽毛球/网球双打后续应支持四人顺序、发球/接发槽位、场区顺序 revision。

Apple 平台实现不能复用 Wear Engine；Phase 4 需要用 WatchConnectivity 重新建协议，但产品状态机应尽量对齐。

## 4. Phase 1：主应用完全重构

### 4.1 目标

以 Android `Score Engine` / `Score Core` 为模板重建 iOS 主 App，在不依赖账号和服务端的情况下，达到“规则可信、记录可追溯、页面可批量接入、新用户本地功能不明显落后”的状态。

### 4.2 重点工作包

1. Swift ScoreCore 骨架
   - 建立 iOS 统一纯 Swift 计分内核，避免每个 SwiftUI 页面各自写规则。
   - 按 S1 / S2 / S3 / S4 分类定义规则、状态、意图、动作日志和记录输出。
   - 先覆盖 S1 单打/线分/局分项目，再处理 S2 台球/拳击、S3 多人、S4 牌类。
   - 与 Android 的 reducer/state machine/invariant 思路保持同构，便于跨端 fixture 对照。

2. SessionCore 与 replay
   - 定义 `ScoreSession`、session version、project id、participant、settings、history、capabilities。
   - 所有计分动作进入 event log，支持 undo、redo 或 replay，避免页面状态成为事实来源。
   - 草稿 / 未完赛恢复以 session snapshot + event log 为基础。

3. 计分项目补齐与规则校验
   - 以 Android / HarmonyOS 当前项目表为准，补齐缺口：黑八、九球、斯诺克、升级等需要单独确认是否进入 iOS 本轮。
   - 乒乓球、羽毛球、网球需要明确单打/双打策略；若双打本轮不完整，入口和文案不能过度承诺。
   - 统一每个项目的胜局、封顶、领先 2 分、抢七、回合、局分/盘分显示。

4. 记录模型与详情页
   - 统一 `ScoreboardRecord` 字段语义：final score、set score、action timeline、extraData。
   - 记录详情需能解释各项目动作，特别是网球、射箭、台球、拳击、牌类。
   - 记录投影从 session / event log 生成，不由页面手动拼字段。

5. Presentation 接线
   - 先做共享 Scoreboard ViewModel / UiState，再让项目页面消费统一状态。
   - 旧 SwiftUI 页面只保留能复用的布局、组件和文案，规则逻辑逐步下线。
   - 选择 3 个代表项目打样：羽毛球或乒乓球（S1）、网球（复杂 S1）、黑八/九球/拳击或多人计分（S2/S3）。

6. 计时与工具
   - 计时项目要对齐 Android / HarmonyOS 的入口、默认值、暂停/恢复、保存记录、详情展示。
   - 工具页先保留本地工具，不做服务端或活动运营能力。
   - 积分表、AA 计算器、时间、红黄牌等要走稳定的本地持久化或无状态策略。

7. 设置、常用名称、预约
   - 常用名称继续作为本地能力，过滤默认名、批量导入、使用频次排序要稳定。
   - 预约球局先保留本地提醒，不接城市/活动/云端组局。
   - 设置页明确“本地数据清除”的范围：计分记录、计时记录、预约、常用名称、快速开始配置是否一并清。

8. 自动化与验收
   - 为规则内核建立 fixture 测试，而不是只靠 UI 点测。
   - 每个项目至少覆盖：进入、计分、撤销、编辑、结束、记录详情、恢复。
   - 补 `xcodebuild` 主 App 构建、核心 Swift 单测、关键 QA 脚本。

### 4.3 当前问题

- 规则散在多个 ViewModel / View 中，后续扩展和跨端对齐成本高；这些页面不能继续当作规则基础。
- 记录字段含义需要重新统一，否则后续云同步会很痛。
- 牌类、台球类、双打类还没有像 Android 那样形成清晰的 S1-S4 契约。
- `checkers` 枚举存在但当前计时/计分定位不清，需要决定保留、隐藏还是改名。
- 主 App 里已有 `HttpClient` / `WebSocketManager` placeholder，容易让人误以为服务端功能可用；Phase 1 应保持隐藏或隔离。

### 4.4 Phase 1 完成标准

- `ScoreCore` / `SessionCore` / `Persistence` / `Presentation` 基础链路跑通，并至少完成代表项目迁移。
- 本地可见入口与实际可用能力一致，没有“点进去是半成品”的主路径。
- 所有本地计分项目有规则说明、测试用例和记录语义。
- 无账号、无反馈、无云同步也不影响 App Store 文案自洽。
- 能提交一个“主 App 本地功能追版本”的 iOS 新包。

## 5. Phase 2：手表功能对齐

### 5.1 目标

Apple Watch 先作为独立计分工具，对标 HarmonyOS / 华为手表端的本地体验，而不是马上做手机手表联动。

### 5.2 重点工作包

- 手表项目范围确认：羽毛球、乒乓球、网球、匹克球、射箭、篮球训练是否作为第一批；台球/牌类是否排除。
- 手表规则与主 App 共用还是复制：建议尽量抽共享纯 Swift 规则层，避免主 App 和 Watch 各自漂移。
- 小屏布局：38/40/41/42/44/45/49mm、动态字体、圆角/边距、误触区域。
- 手表记录：本地记录列表、详情、删除、完赛后查看。
- 手表设置：布局偏好、声音/振动、使用说明、数据清理。
- 手表 QA：多尺寸截图、连续点击、撤销、重置、完赛、后台恢复。

### 5.3 当前问题

- Watch App 已有能力，但与主 App 规则是否一致需要系统复核。
- 手表双打和复杂项目不宜抢进 Phase 2，先做独立单机稳定。
- 如果主 App Phase 1 规则内核不先稳定，Watch 继续扩展会制造第二套规则债务。

### 5.4 Phase 2 完成标准

- Watch App 可以离线独立完成核心项目计分并保存本地记录。
- Watch 端规则与主 App 同项目一致，有最小自动化或脚本化验证。
- App Store 文案只写“支持 Apple Watch 独立计分/查看”，不承诺手机联动。

## 6. Phase 3：主应用服务端与账号相关功能对齐

### 6.1 进入条件

只有在以下事项明确后才进入：

- 中国区发行主体、ICP备案、隐私政策、App Store 元数据口径明确。
- Apple 登录、国内登录、会员/IAP、服务端域名与证书策略明确。
- 后端 API 版本与 iOS 数据 schema 兼容策略明确。

### 6.2 重点工作包

- 账号登录：Apple 登录优先，其它登录能力按中国区/海外区策略决定。
- 用户资料与权益：会员状态、购买恢复、权益缓存、离线兜底。
- 用户反馈：反馈提交、图片/日志、状态查看、客服回复。
- 云端记录：本地记录上传、冲突合并、分页拉取、删除同步。
- 服务端配置：API base、地区、隐私协议、功能开关。
- 审核材料：数据收集、隐私标签、登录/IAP 审核账号、客服说明。

### 6.3 当前问题

- iOS 当前网络层只是 placeholder，没有真实错误处理、鉴权、重试、日志和环境切换。
- 如果 Phase 1 记录模型未统一，Phase 3 云端记录会被迫兼容一堆历史字段。
- 国内区和海外区是否拆 App、是否同 bundleId 延续，需要结合 ICP 和主体长期策略再定。

### 6.4 Phase 3 完成标准

- 账号、反馈、权益、云端记录都有可测 API 契约。
- App Store 隐私标签与实际行为一致。
- 离线本地能力不因服务端失败而不可用。

## 7. Phase 4：手机手表联动功能对齐

### 7.1 目标

用 Apple 平台机制实现 iPhone / Apple Watch 联动计分，产品语义对齐 HarmonyOS V2。

### 7.2 重点工作包

- 技术选型：WatchConnectivity `WCSession`，确认前台/后台、可达性、延迟、消息大小。
- 协议设计：setup request、ready、state snapshot、finish、ACK、NACK、resync、takeover、left。
- 状态模型：主控/跟随、sessionId、seq/revision、pending snapshot、幂等去重。
- 项目范围：第一批建议只做羽毛球、乒乓球、网球单打；双打和台球后置。
- 完赛记录：手表完整记录回传手机，手机保存并展示来源。
- 异常恢复：断连、手机退出、手表退出、后台恢复、重复包、乱序包、ACK 丢失。

### 7.3 当前问题

- iOS 没有现成联动协议实现，不能把 HarmonyOS Wear Engine 代码逻辑机械搬过来。
- Apple Watch 后台能力和连接语义与华为手表不同，可能需要降级部分交互。
- 如果 Phase 2 手表规则和 Phase 1 主 App 规则不统一，联动会很难做正确。

### 7.4 Phase 4 完成标准

- 至少一个项目完成“手机发起 -> 手表确认 -> 手表计分 -> 手机同步 -> 手机接管 -> 完赛记录回传”闭环。
- 断连/重连/重复包/乱序包有测试。
- 文案和 App Store 更新说明明确支持范围，不泛化为所有项目联动。

## 8. 讨论点与需要拍板的问题

### 8.1 发版范围

- `1.1` 是否先发 Phase 1 的“新内核代表项目 + 旧项目可用保底”，还是等主要项目都迁完再发？
- iOS 内部版本号要继续 `1.1`，还是直接对齐 HarmonyOS / Android 的 `2.x` 口径？
- 本地功能补齐到什么程度可以发版：是“现有项目修稳”，还是必须补黑八/九球/斯诺克/升级？

### 8.2 产品范围

- 预约球局是否保留在 Phase 1？它现在是本地能力，但产品上可能容易让用户期待联网约球。
- 计时类棋类项目是否继续放在“计时”，还是要与计分项目的棋/牌类命名统一？
- `checkers` 当前枚举如何处理：隐藏、删除、改成跳棋/计时，还是留给后续？
- 篮球训练是否只属于 Watch，还是主 App 也要补？

### 8.3 架构取舍

- 是否确认 Android `Score Engine` / `Score Core` 为 iOS Phase 1 的唯一架构模板？
- 是否接受 Phase 1 做一次较大目录重组，把现有计分页拆成 `ScoreCore`、`SessionCore`、`Persistence`、`Presentation`？
- 是否允许代表项目迁移完成后删除或隐藏旧计分页，而不是长期双轨维护？
- Android fixture 是否作为跨端契约真源，iOS 只做 Swift 版实现和补充用例？
- Watch 是否也共享同一套纯 Swift core，避免主 App / Watch 两套规则漂移？
- 是否需要把记录模型先做 schema version，为 Phase 3 云同步预留迁移？

### 8.4 审核与合规

- 当前中国区 bundleId 是 `com.douhua.jifen.ios`，是否继续用朋友账号短期追版本？
- 如果账号/服务端功能后置，App Store 隐私标签是否继续保持“不收集数据”或最小化？
- 隐私协议、用户协议、ICP备案主体和 App Store 开发者主体是否需要在 `1.1` 前再核对一次？

### 8.5 手表策略

- Phase 2 是否必须进入本周范围，还是等主 App Phase 1 后再做？
- Apple Watch 第一批项目是否只保留当前已有项目，先不补双打和台球？
- App Store 文案是否只写“支持 Apple Watch 计分/查看”，不写“手机手表联动”？

## 9. 建议的近期执行顺序

1. 冻结 Phase 1 范围：列出本地项目白名单、隐藏项和首批代表项目。
2. 把 Android `score-core` / `session-core` / `persistence` / `presentation` 映射成 Swift 目录和协议草案。
3. 建立 Swift `ScoreCore` + `SessionCore` skeleton，并先让核心 fixture 跑通。
4. 从 Android 导入或翻译跨端契约 fixture，先覆盖 S1，再进入 S2 / S3 / S4。
5. 选 3 个代表项目打样：羽毛球或乒乓球（局分/封顶）、网球（game/set/tiebreak）、多人计分或台球/拳击（非 S1 简单局分）。
6. 打样通过后批量迁移其它项目，并逐步下线旧页面规则。
7. 补主 App 构建、规则 fixture、记录详情测试。
8. 最后处理 App Store 文案、截图、隐私/协议和版本号。

## 10. 参考文档

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
