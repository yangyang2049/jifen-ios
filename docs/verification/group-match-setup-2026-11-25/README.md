# 小组活动开赛 · 四球类定稿赛制（iOS 端）

日期：2026-11-25 · 分支 `3.4.3`（工作树未提交，含其它并行任务改动）

## 范围

手机端小组活动排阵后，对**未开赛**场次点「开始计分」时的赛制区。补记结果、历史记录、
本机 Setup 入口、已开赛的冻结规则都没有改动。

## 定稿对齐

| 项 | 落地方式 |
| --- | --- |
| 经典／打满 | 弱化为「局数（网球为盘数）· 经典 ▾」下拉，默认与回填都取实际规则 |
| 数字预设 | 圆角数字 chip；铅笔 chip 原位变数字输入，不再出现重复加减 |
| 摘要（第一行） | 赛制，例如「三局两胜」「打满 3 局」「抢七决胜局」 |
| 摘要（第二行，居中） | 计分方式 · 净胜两分 · 封顶，例如「每球得分 · 净胜两分 · 30 分封顶」；切换计分方式或封顶后即时改写 |
| 羽毛球 | 固定每球得分；封顶按本机规则推导：11→15、15→21、21→30，其它目标分不封顶 |
| 乒乓球 | 固定每球得分、无封顶；分数档沿用本机 Setup 的 5 / 7 / 9 / 11（+ 自定义） |
| 网球 | 常规：盘数、每盘局制、盘末抢分、占先／无占先各自独立；也可切到独立抢七／抢十决胜局（不显示封顶行） |
| 匹克球 | 计分方式按定稿用「发球方得分／每球得分」两枚选项；11 分时封顶「无／13／15」；其它目标分清空封顶，21 分可直接开赛 |
| 发球方 | 只保留「发球方」文字与两侧项目图标高亮，所选方写入计分板 |
| 席位名称 | 单打两行（A1 · B1）、双打四个位置（A1 · A2 · B1 · B2）；名称一律用主文本色（Theme.textPrimary），排阵冻结时只锁交互、不压暗 |
| 保留项 | 已排席位（A1/A2 · B1/B2）、开赛权限、已开赛规则快照、小组默认值与冻结规则 |

本机 Setup（首页开局弹窗）仍是原来的用法：比赛功能卡片保留、匹克球计分方式仍是开关。

## 三端共用文案

新增 3 个 group 文案键，47 个语种都写了键以保持键集一致；en / zh-Hans / zh-Hant 为人工译文，
其余语种先按英文兜底，等本地化流水线补齐：

| 键 | en | zh-Hans | zh-Hant |
| --- | --- | --- | --- |
| `group_side_out_scoring` | Server only | 发球方得分 | 發球方得分 |
| `group_score_cap_format` | %d-point cap | %d 分封顶 | %d 分封頂 |
| `group_no_score_cap` | No cap | 无封顶 | 無封頂 |

`group_side_out_scoring` 对位安卓 `group_audit_result_sideout`（仅发球方得分）。

## UI 夹具

`-UITestMatchSetupSport <sport>` 只切换小组项目，不动席位与排阵；四个项目各用自己的默认值
（与后台 capabilities 一致）：羽毛球 21 分 / 30 封顶、乒乓球 11 分 / 无封顶、网球 6 局 / 抢七、
匹克球 11 分 / 15 封顶 / 每球得分开启。真实配置仍以服务端为准。

## 验证

```
xcodebuild test -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/jifen-phone-check \
  -only-testing:jifenTests/GroupMatchSetupRulesTests \
  -only-testing:jifenTests/GroupPortParityTests \
  -only-testing:jifenUITests/GroupMatchSetupUITests \
  -only-testing:jifenUITests/GroupRedesignUITests/testScheduledBadmintonCanChangeToOneGameWithoutChangingSeats
```

结果：单元 124 项通过（新增 9 项赛制桥接/摘要）；UI 5 项通过：

- 四球类 × 单双打（8 个组合）都渲染定稿赛制区、居中摘要、发球方、可开赛；
- 「经典／打满」下拉与局数同排，切到打满后摘要改为「打满 3 局」；
- 匹克球摘要从「每球得分 · 净胜两分 · 15 分封顶」→ 选 13 →「13 分封顶」→ 切「发球方得分」后整行改写且不再出现「每球得分」；
- 匹克球 21 分仍可开赛；
- 单打排阵场次改成一局制后席位不变、摘要与提交都正确；
- 席位数量随赛制变化（单打 2 个、双打 4 个）。

席位名称配色用像素采样核对过（同一张双打截图、名称字形区域）：修复前该区域最暗像素亮度 124、无深色像素；
修复后最暗 0、近黑像素占 7.8%，即名称已回到 Theme.textPrimary。

截图（模拟器实拍，zh-Hans）：8 个球类/赛制组合 + 打满 + 匹克球 21 分 + 匹克球两种计分方式 + 单打默认/改一局制。

原始 xcresult 与录制在仓库外批次 `~/Library/Developer/jifen-ios-test-artifacts/runs/`（按保留策略过期）。

## 仍需验收

1. 44 个非中英语种的 3 个新键目前是英文兜底，需要本地化流水线出译文。
2. 摘要首行沿用既有本地化写法：网球是「每盘局数 6 · 抢七分数 7」，定稿写作「每盘 6 局 · 抢七」；
   匹克球首行是「目标分 11」，定稿示例是「每局 11 分」。
3. 小组能力返回的 `pointsToWinSet` 选项是 7/11/15/21，乒乓球定稿档位含 5 与 9；如服务端按该清单校验需后端放行。
4. 真机（iPhone SE）与小屏字号未覆盖：本轮在 iPhone 17（iOS 26.5）模拟器验证；iPhone SE 真机当前 `devicectl` 状态不可用（需解锁/信任后重试）。
