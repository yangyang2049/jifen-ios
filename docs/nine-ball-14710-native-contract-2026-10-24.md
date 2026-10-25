# 九球追分 14710 原生契约

本次授权范围为 iOS、鸿蒙手机、Android 手机（含独立 Google 仓库）。沿用已确认的 HTML Demo；不是全国统一比赛规则。

## 新局（ruleVersion = 2）

默认收益表（小金仅开球人赔付）：

| 类型 | 单家赔付 | 2 人赢家净拿 | 3 人赢家净拿 | 4 人赢家净拿 |
| --- | ---: | ---: | ---: | ---: |
| 普胜 | 4 | 4 | 4 | 4 |
| 黄金9 | 4 | 4 | 8 | 12 |
| 小金 | 7 | 7 | 7 | 7 |
| 大金 | 10 | 10 | 20 | 30 |

- 默认单家分值：犯规 1、普胜 4、小金 7、大金 10、黄金9 4。
- 普胜仅向一位付分人收 4；预选座位上家，实际上一位失败者不同时由用户更正。
- 小金默认仅本局开球人付 7；`smallGoldAllPay = true` 才是其余每人付 7。
- 大金/黄金9其余每人分别付 10/4；赢家收到各家付款总和。
- 犯规本人扣分、座位下家等额加分，不另收自由球分；让杆选择继续人，不计分、不换局。
- 普胜/小金后由赢家的座位下家开下一局。大金/黄金9默认赢家续开；`goldRetainsBreak = false` 时也改为赢家下家。
- 双人所有六项直接执行。多人保留付分人/继续击球人的确认，犯规直接执行。
- 开球人用姓名左侧现有球杆图标；每位玩家保留相同图标位置。首次说明只出现一次，仅“知道了”。

## 模型与兼容

状态新增 `ruleVersion`、`roundNumber`、`breakerPlayer`、`currentShooter`；新局为 2/1/所选开球人/空。**解码缺失版本为 1**，绝不升级旧对局或重算分数。

`currentShooter` 仅是犯规/让杆后的继续人，不声称逐杆跟踪实际上手者；标记始终只表示本局开球人。

保留旧六个统计位置：big_gold、small_gold、golden_nine、normal_win、ball_in_hand、foul；`handoff` 追加第七格。新局仅展示大金/小金/黄金9/普胜/让杆/犯规；旧局继续显示旧六项。

旧 `chase_event` 只接受版本 1；新 `chase_transfer`（player、kind、payer?、continuePlayer?）只接受版本 2。另有版本 2 的 `set_breaker`。事件包含一次完整的全员 deltas、付分人/继续人、原局号/开球人、下一局开球人，一次用户操作只生成一个可撤销状态快照。

旧记录只显示“旧版规则”，旧进行中会话继续旧 reducer；新局默认黄金9=4，旧已存的8分不修改。手动管理分数保留现有能力，正常计分事件必须转分守恒。

跨端记录 extra 统一 `chaseRuleVersion`、`chaseRoundNumber`、`chaseBreakerPlayer`、`chaseCurrentShooter`、`chasePlayerPoints`、`chaseSmallGoldAllPay`、`chaseGoldRetainsBreak`。iOS 的 setup/projectConfiguration 仍沿用 `nineBall…` 设置键。

鸿蒙手机/手表控制权交接传输完整状态，并非各端同时重放意图。旧表接管 v2 会错误计算，因此新局在未确认新能力前不允许交给旧表；旧 v1 联动不改变。独立手表 UI 此轮不扩展。

## 验收

共同分值样例位于 `contracts/nine-ball-14710-v2-fixtures.json`。每端验证 2/3/4 人收益、负分、守恒、开球轮换、单家与全员小金、付分人更正、一次撤销恢复所有状态、缺版本旧数据/旧事件不变，以及新旧意图隔离。

2026-10-24 实际验证：

- iOS：JifenCore 全量 261 测试通过；应用定向两轮分别 104/98 测试通过（有重复覆盖，不相加）。第二轮包含真实异步队列中跨局小金拒绝、同局犯规/让杆可连续提交。模拟器构建成功。
- Android 主仓与独立 Google 仓：各 63 定向 JUnit 测试通过、Kotlin 编译成功。最后双人横屏布局复用原 `NineBallHalfContent` 后，两仓再次编译通过。
- 鸿蒙：73 项九球与兼容回归、90 项既有手表共享回归通过；手机与 wearable 最终整包构建成功。双人换边采用纯展示映射，逻辑身份不迁移；独立撤销换边不会删除前一笔得分记录。
- iOS 47 种资源的 21 个新键无重复，格式参数一致，`plutil` 语法检查通过。
- iPhone 17 Pro 模拟器手动检查：三人小金预选开球人 −7、赢家 +7，第三人不变；确认后下一局标记移动到赢家下家；一次撤销同时恢复余额、统计和开球人。首次球杆说明只有“知道了”。截图在 `demos/nine-ball-14710-2026-10-24/native-ios-*.png`。
- 最终只读复核确认：三端缺版本记录保持 v1；Android/Google 的 reducer 与 codec 一致。现有后端实时 metadata/配置支持新增字段与负数，无需后端部署。
- 2026-10-24 晚补充：投屏与跨设备同步显示面（iOS ScoreboardExternalLiveView、Android DisplaySurfaceHost、鸿蒙 TwoSideScoreboardView/MultiGridScoreboardView）统一加上"本局开球"球杆标记——v2 每侧/每格预留同一图标位（透明占位），仅开球人一侧/一格显示，v1 与其他项目不受影响；数据源为线上已有的 chaseRuleVersion/chaseBreakerPlayer。Android/鸿蒙投屏统计带同步改为 v2 展示序（第 5 格"让杆"取存储第 7 格），iOS 投屏此前已换序。新增字符串：Android 复用既有 chase_chalk_handoff；鸿蒙补 base/en_US=P、zh_CN=让。验证：iOS ScoreboardDisplayTests 51 项通过（新增投屏标记/换序断言）；Android 双仓九球+显示定向单测通过；鸿蒙 test_display_surface_model_paths（新增断言）+ test_nine_ball_14710 共 74 项通过、entry HAP 编译成功。

本轮未安装到真机、未做折叠屏回归、未提交或发布。
