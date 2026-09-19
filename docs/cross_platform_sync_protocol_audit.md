# 跨设备同步协议三端对齐专项检查（iOS / Android / HarmonyOS）

检查日期：2026-09-19
对照范围：REST 契约、WebSocket 消息、DisplayState wire JSON（顶层 + team/player/result/keyPoint/clock/rest/appearance/style 每个字段）、每个记分板项目的 sportState 字段白名单、支持同步的游戏类型清单。
基准：后端 `jifenqi-backend`（协议仲裁方）+ 安卓 `DisplayState.kt`（wire 格式定义方）。

| 代码位置 | iOS | Android | HarmonyOS |
|---|---|---|---|
| 协议编解码 | `jifen/Core/CloudSync/DisplayStateWireCodec.swift` | `app/.../display/model/DisplayState.kt` | `entry/src/main/ets/scoreboard/display/DisplayState.ts` |

## 结论

**总体对齐度高**：REST 契约、WS 消息、DisplayState 顶层结构、team/player/result/keyPoint/appearance/style 的全部字段均已对齐，网球点数协议编码（0/15/30/40/AD→0/1/2/3/4）也一致。游戏类型清单的差异（iOS 多 `basketball_training`、安卓/鸿蒙多 `mahjong`）与后端 scoreboardCatalog 分平台放行完全一致，属设计如此。

**发现 2 个真实功能缺口（P1）、3 个信息丢失风险（P2）**，全部集中在 sportState 白名单、足球时钟、局间休息三处，详见下节。

---

## 🔴 未对齐项（重点）

### P1-1 鸿蒙局间休息 `rest.sport` 白名单只收 4 个项目（iOS/安卓为 8 个）

- iOS 发送白名单：badminton, pingpong, tennis, pickleball, **squash, shuttlecock, soft_tennis, padel**（`DisplayStateWireCodec.swift:287`）
- Android：同 8 个（`OfficialBreak.kt:305-314`）
- 鸿蒙：类型声明 8 个，但 `sanitizeDisplayState` 的显示端清洗白名单只接受 **badminton, pingpong, tennis, pickleball**（`DisplayState.ts:332`）

**影响**：壁球、毽球、软式网球、板式网球 4 个项目的休息/暂停倒计时帧，鸿蒙端发送前就会被剥掉、接收时也会被丢弃 —— 鸿蒙参与的这 4 个项目同步没有休息显示。iOS/安卓之间正常。
**建议**：鸿蒙 `DisplayState.ts:332` 白名单补齐为 8 项（与 `officialBreak.ts:1-3` 类型定义对齐）。

### P1-2 足球时钟 `clock.injuryTimeText` iOS 缺失

- Android wire 含 `injuryTimeText`（`ScoreboardModels.kt:499`，构建于 `ScoreboardTemplate.kt:160-178`）；鸿蒙含（`DisplayState.ts:285`）
- iOS `ScoreboardDisplayClock` 无此字段，编解码均不处理（`DisplayStateWireCodec.swift:140-161, 262-283`）

**影响**：双向丢字段 —— 安卓/鸿蒙分享足球给 iOS 显示端时伤停补时文本被 iOS 丢弃；iOS 分享足球给安卓/鸿蒙时该字段根本不在帧里，显示端无法渲染伤停文本。其余 clock 字段（version/mode/visible/running/startedAt/elapsedMs/footballHalf 1..4/footballHalfLengthMs/footballInjuryTargetMs/halfLabel）三端完全对齐。
**建议**：iOS `ScoreboardDisplayClock` 增加 `injuryTimeText: String?` 并在 codec 两侧透传。

## 🟠 信息丢失风险（P2）

### P2-1 sportState 公共白名单：iOS 多 6 个键，安卓/鸿蒙解码时丢弃

`projectDisplaySportState` 的 common 键集合：

| 端 | common 键 |
|---|---|
| iOS（16） | currentSet, servingTeam, **servingSide, leftDisplayScore, rightDisplayScore, leftDetail, rightDetail, resultScoreLevel**, serverSlotIndex, team0ScreenSide, multiGrid×5 |
| Android（10） | currentSet, servingTeam, serverSlotIndex, team0ScreenSide, multiGrid×5 |
| 鸿蒙（13） | currentSet, servingTeam, serverSlotIndex, team0ScreenSide, **competitionFormat, teamCourtPlayers, ruleProfileVersion**, multiGrid×5 |

iOS 解码不做白名单（全量保留），安卓/鸿蒙解码会按各自白名单重投影。**iOS 作为分享端时，`leftDisplayScore/rightDisplayScore`（显示分覆盖串）、`leftDetail/rightDetail`（副分细节文案）、`resultScoreLevel`（结果卡片层级）、`servingSide` 这 6 个键在安卓/鸿蒙显示端丢失**，具体表现取决于显示端本地兜底（主分有 `team.score` 兜底，不受影响）。
**建议**：确认安卓/鸿蒙显示端是否需要这些键；需要则把 6 键加进两端 common 白名单（改动小、向后兼容）。

### P2-2 sportState `layoutKind`（羽毛球家族）：鸿蒙白名单缺

羽毛球/毽球分支 iOS 与安卓都放行 `layoutKind`（`DisplayStateWireCodec.swift:437-439`、`DisplayState.kt:325-327`），鸿蒙分支只有 `badmintonServerSide` + common 三键，没有 `layoutKind`（`DisplayState.ts:606`）。**安卓/iOS 分享羽毛球时，鸿蒙显示端丢 `sportState.layoutKind`**（顶层 `layoutKind` 字段不受影响）。

### P2-3 麻将 sportState：鸿蒙比安卓多 2 键

鸿蒙分支多 `mahjongCurrentHandDeltas`、`mahjongLastEventText`（`DisplayState.ts:652-657`），安卓白名单没有（`DisplayState.kt:359-364`）→ **鸿蒙分享麻将时，安卓显示端丢这 2 个键**（当前局分差、最近事件文案）。iOS 不支持麻将同步（与后端 catalog 一致：mahjong 仅 android 可控、harmony 只读、iOS 无能力行）。

## 🟡 差异但无害 / 低风险（P3，建议顺手收敛）

1. **eight_ball / archery_dual：鸿蒙多发内部键** `localProjectionEightBall*`（3 个）、`localProjectionArcheryCurrentShooter` —— 安卓解码丢弃，无功能影响，建议鸿蒙发送前剥离。
2. **style V2 解码容错不对称**：iOS 要求 `serverIndicatorColor`、`styleRevision` 同时在场才接受整个 style（`DisplayStateWireCodec.swift:357-363`），安卓/鸿蒙缺省可回退（安卓回退 `#30D158`/0）。现网两端都恒写这些字段，互通无碍；iOS 偏严。iOS 另外兼容读取 `backgroundHex/foregroundHex`（仅旧帧，发送端三端都不发，一致）。
3. **short-code 请求的 `role` 字段**：三端都发 `role:"DISPLAY"`，但后端 schema（`matches.ts:123-132`）只有 `ttlSec/maxUses`，`role` 被静默剥离 —— 无害，属三端共同冗余。
4. **REST DTO 小差异**：iOS 的 rt-token 响应模型少 `expiresAt/expiresIn`、join-by-code 响应少 `role`（安卓有）—— iOS 不使用，无影响。
5. **layoutKind 取值集合**：iOS 独有 `shot_training_grid`（篮球训练，iOS-only 同步，安卓/鸿蒙收到会回退默认布局）；鸿蒙枚举声明了 `team_court` 但从不产出。不影响现网互通。
6. **WS 消息覆盖面**：iOS 未实现 `DANMAKU`/`TIMER_COMMAND`/`TIMER_PATCH`（弹幕、计时器比赛），安卓定义了 DANMAKU 但不发送，鸿蒙全量支持。计分板同步主链路不受影响。
7. ** sportState 解码方向不对称**：iOS 收帧全量保留未知键，安卓/鸿蒙收帧按白名单重投影丢弃未知键。宽松方向在 iOS，安全（最多多显示，不会崩）。

---

## ✅ 已对齐明细（逐字段核对通过）

### 1. REST 契约（对齐后端 `matches.ts`）

| 项目 | 三端一致性 |
|---|---|
| `POST /api/matches` | 一致：`{type:"SCOREBOARD", name:"<gameType>_match_<ts>", config:{gameType}}` |
| `GET /api/matches/:id/rt-token` | 一致：响应 `rtToken/matchId/role/wsUrl`（后端另给 `expiresIn`，iOS 未用） |
| `POST /api/matches/:id/short-code` | 一致：`{ttlSec:3600, maxUses:10, role:"DISPLAY"}`；响应 `code/expiresAt(毫秒)/maxUses/usedCount/url` |
| `POST /api/matches/join-by-code` | 一致：请求 `{code}`（6 位数字）；响应 `matchId/wsToken/match/wsUrl` |
| `PUT /api/matches/:id` | 一致：`{config:{gameType}}` |
| join 错误码 | 一致：`CODE_EXPIRED / CODE_EXHAUSTED / INVALID_CODE / DISPLAY_SLOTS_EXHAUSTED / CONNECTION_LIMIT_REACHED` 五码映射文案三端对齐（后端还有 `RATE_LIMITED`，三端都走兜底文案） |

### 2. WebSocket（对齐后端 `validation.ts`）

- 信封 `{type, payload, timestamp}` 一致；DisplayState 经 `PARTICIPANT_UPDATE/PARTICIPANT_SYNC` 的 `participants[].metadata.displayState` 透传，三端 + 后端一致。
- 发送侧 payload 一致：`JOIN{matchId, displayInfo{name,platform,deviceType}}`（platform：IOS/ANDROID/HARMONYOS）、`PARTICIPANT_UPDATE{matchId, sessionPhase("active"/"set_break"/"idle"), replace, participants[]}`、`GAME_OVER{matchId, winner, finalScores, manualEnd}`（字段名 `winner` 三端一致）、`LEAVE{matchId, reason:"user_exit"}`、`CONTROLLER_AWAY/RESUME{matchId, reason}`、`MATCH_STARTED{matchId, gameType}`、`PING{}`。
- 接收侧监听集合一致（JOIN_SUCCESS/PARTICIPANT_SYNC/PARTICIPANT_UPDATE/GAME_OVER/MATCH_STARTED/控制器与显示端生命周期/ERROR，iOS 另处理 FORCE_RECONNECT）。

### 3. DisplayState 顶层（14 字段）

`schemaVersion=1`、`gameType`、`orientation("portrait"/"landscape")`、`layoutKind`、`teams`、`matchTitle`（trim+40 code point 截断，一致）、`players`、`sportState`（白名单投影、空则省略）、`appearance`、`result`、`updatedAt`、`keyPoint`、`clock`、`rest` —— 字段名、条件写入规则、`isDisplayState` 最小校验（gameType/schemaVersion==1/layoutKind/updatedAt/teams）三端一致。

### 4. 子对象字段

| 对象 | 字段 | 结论 |
|---|---|---|
| team | `id/name/score/sets?/games?/color?/order` | ✅ 完全一致（网球家族点数编码一致；`team_0/team_1` 逻辑身份 + `team0ScreenSide` 换边一致） |
| player | `id/name/score?/teamId/slot?/order/color?/isServer?` | ✅ 一致（字段名 `teamId` 小写三端统一；`rank` 三端都不上 wire，一致；pickleball 双打不写 isServer 一致） |
| result | `ended/manualEnd?/winnerId?/finalScores{id:{score,sets,games}}` | ✅ 一致（`winnerId` 取值映射 `team_0/team_1/draw` 一致，手动结束=draw 一致） |
| keyPoint | `kind("game"/"set"/"match")`、`side("left"/"right")` | ✅ 白名单一致（iOS 编码侧校验、安卓/鸿蒙解码侧校验） |
| clock | 见 P1-2，其余 10 字段 | ✅ 除 injuryTimeText 外一致（含 version==1、mode=="elapsed"、startedAt>0、elapsedMs>=0、footballHalf∈1..4 校验） |
| rest | `version=1/sport/kind(6 值)/phase("countdown"/"prepare")/startedAt/endsAt/remainingMs/prepareRemaining/revision/afterAction(4 值)/title?` | ✅ 字段、数值约束（countdown: prepareRemaining==0 且 remainingMs<=endsAt-startedAt；prepare: remainingMs==0 且 prepareRemaining>0）一致，**仅 sport 白名单见 P1-1** |

### 5. appearance / style V2（对齐安卓 `DisplayStyleSnapshotV2`）

- appearance 顶层 8 个 wire 字段一致：`theme/fontCode/scoreColor(主分)/secondaryScoreColor(盘局分)/leftTeamColor/rightTeamColor/centerTeamColor/style`（`backgroundHex/foregroundHex` 仅 iOS 本地模型持有，不上 wire，一致）。
- style 子对象 8 字段完全一致：`version=2/themeCode/fontCode/fontSizeMultipliers/panels[{slotKey,participantId?,backgroundColor}]/elements[{elementKey,textColors[{slotKey,color}]}]/serverIndicatorColor/styleRevision`；hex 校验（# + 6/8 位）、slotKey/elementKey 去重、fontSizeMultipliers 过滤（`_` 前缀剔除、有限且>0）三端一致。elementKey 7 值（matchTitle/teamName/playerName/mainScore/setScore/gameScore/setGameScore）、slotKey（side_left/side_center/side_right/player_N）三端一致。

### 6. 各记分板项目 sportState 白名单（逐项目）

| 项目 | iOS | Android | HarmonyOS | 差异 |
|---|---|---|---|---|
| pingpong / pingpong_doubles | ✅ 6 键 tableTennis* | ✅ 同 | ✅ 同 | — |
| badminton / badminton_doubles / shuttlecock | ✅ 5 键 | ✅ 同 | ⚠️ 缺 `layoutKind` | P2-2 |
| squash | ✅ competitionFormat, ruleProfileVersion | ✅ 同 | ⚠️ 多 `badmintonServerSide` | 低风险（多余键被对端丢弃） |
| tennis / tennis_doubles / soft_tennis / padel | ✅ 10 键 | ✅ 同 | ✅ 同 10 键（competitionFormat/ruleProfileVersion 走 common，另多 teamCourtPlayers） | 低风险 |
| pickleball / pickleball_doubles | ✅ 2 键 | ✅ 同 | ✅ 同 | — |
| snooker | ✅ 3 键 | ✅ 同 | ✅ 同 | — |
| boxing | ✅ 2 键 | ✅ 同 | ✅ 同 | — |
| eight_ball | ✅ 3 键 | ✅ 同 | ⚠️ 多 3 个 localProjection* | P3-1 |
| nine_ball | ✅ 6 键 chase* | ✅ 同 | ✅ 同 | — |
| archery_dual | ✅ 1 键 | ✅ 同 | ⚠️ 多 1 个 localProjection* | P3-1 |
| basketball / three_basketball | ✅ 10 键（含时钟锚点 6 键） | ✅ 同（分支 4 + 锚点投影 6） | ✅ 同 10 键 | — |
| basketball_training | ✅ 8 键 training* | ❌ 无（else 分支） | ❌ 无（default 分支） | iOS-only，服务端仅放行 iOS，设计如此 |
| uno | ✅ 2 键 | ✅ 同 | ✅ 同 | — |
| guandan | ✅ 6 键 | ✅ 同 | ✅ 同 | — |
| shengji | ✅ 3 键 | ✅ 同 | ✅ 同 | — |
| mahjong | ➖ 不支持同步 | ✅ 12 键 | ⚠️ 14 键（多 2） | P2-3 |
| football / 排球三兄弟 / billiards / foosball / simple_score / doudizhu | 仅 common 键 | 仅 common 键 | 仅 common 键 | —（common 差异见 P2-1） |

### 7. 支持云端同步的游戏类型

- iOS 33 项（含 `basketball_training`，无 `mahjong`）；Android/HOS 34 项（含 `mahjong`，无 `basketball_training`）。
- 与后端 scoreboardCatalog 完全一致：`basketball_training` 仅 iOS（catalog 注释明确安卓/鸿蒙下版本跟进）；`mahjong` android 可控 + harmony 只读 + iOS 无能力行。**属分平台设计，不算未对齐。**

---

## 复核建议顺序

1. 鸿蒙补 `rest.sport` 4 项目白名单（P1-1，一行改动）。
2. iOS 补 `clock.injuryTimeText`（P1-2，模型 + codec 各一处）。
3. 三端 common 白名单收敛 6 个 iOS 附加键（P2-1，先确认安卓/鸿蒙显示端是否消费）。
4. 鸿蒙补羽毛球 `layoutKind`、收敛麻将/localProjection 差异键（P2-2/3、P3-1）。
