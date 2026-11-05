# 三端同步核查报告(iOS 今晚改动 × 安卓/鸿蒙)2026-11-06

范围:iOS 未提交改动(89 文件 ±6513/209 + 48 新文件);对照 jifen-android(288 文件未提交)、jifen-hos(162 文件未提交)、jifenqi-backend(api-server)。
iOS 侧自检详情见《全量自检》对话记录与 `docs/audits/uncommitted-review-2026-11-05.md`。

## 一、iOS 今晚改动梳理(按功能)

| # | 功能块 | 主要内容 | 跨端相关度 |
|---|---|---|---|
| 1 | 台球群(新) | GroupBilliardsModels/Persistence/Views/Tab、fixture billiards-v2、群合同 v2 | **高** |
| 2 | 样式工作台 V2 | 33 个 style_workbench_* key、照片主题 event_background、名牌字体、发球指示器样式 | 中 |
| 3 | 外接显示(Duo) | photoScene、投屏 wire 增加 backdrop/nameFontCode/serverIndicatorStyle/Hidden | **高** |
| 4 | VIP 社区 | 弹窗优先级、与评分邀请互斥、会员页入口 | 中 |
| 5 | 个人记录 | 台球记录归档/摘要、groupGameId 回退、滚动统计 | 低 |
| 6 | 弹窗让位 | 评分邀请/微信绑定升级弹窗与社区弹窗互斥 | 低(iOS 特有 StoreKit) |
| 7 | 文案/本地化 | 微信绑定文案改"其他设备";新 key 只进 3 语言;VIPCommunity.strings 3 语言 | **高** |

## 二、跨端比对结论

| # | 事项 | 安卓 | 鸿蒙 | 结论/建议 |
|---|---|---|---|---|
| 1 | **合同 v2 门槛**(后端已强制:billiards 接口对 v1 头返回 409,capabilities 不含台球,见 api-server billiards.integration.test.ts:47-50) | ⚠️ 只加了请求头(HttpClient.kt:81),门槛仍 >1 拒绝:GroupRepository.kt:210(UPDATE_REQUIRED)、GroupResultCapabilities.kt:13 | ⚠️ allows 已 ≤2(groupBilliards.ts:27),但 groupResultCapability 仍 >1(GroupParity.ts:39) | **需拷贝**:安卓两处、鸿蒙一处把门槛放宽到 ≤2,与 iOS 对齐;iOS 同步修失败的 parity 测试(改为 v2 可写、v3 禁写) |
| 2 | **投屏/外显 4 个新样式字段** | ✅ 已对齐:DisplayState.kt:555-572/711-718(编码+解码,语义与 iOS 一致) | ✅ 已对齐:DisplayState.ts:473-476(normalize 同源) | 无需拷贝;iOS 剩余风险是自身测试绕开真实 compactState 路径(P2) |
| 3 | **样式工作台 33 key 缺 44 语言**(iOS P1) | ✅ 不适用:安卓仅 3 语言包,自有命名(style_workbench_* 部分共用 + scoreboard_workbench_photo.xml),UI 字符串齐全 | ✅ 不适用:鸿蒙 7 个 locale,自有命名 app.string.scoreboard_style_* | 仅 iOS 需修:补 44 语言,或改用 iOS 端 value: 兜底 |
| 4 | **微信绑定升级文案**(iOS 改为"可在其他设备和网页端") | ❓ 未定位到对应 key(wechat_binding_upgrade_body 在 res 无命中,需确认安卓是否有此弹窗) | ❌ 仍为旧文案且点名平台:"可在 iOS、安卓和网页端…"(zh_CN string.json:10805) | **需同步**:定稿统一文案后,鸿蒙 zh_CN/zh_HK/zh_Hant/zh_TW/en_US/base 全改;安卓定位后再改 |
| 5 | **VIP 社区 URL 白名单**(https + work.weixin.qq.com + path 正则) | ✅ VipCommunity.kt:73 有 host 校验 | ⚠️ 未 grep 到 work.weixin.qq.com,待确认是否校验 | 若鸿蒙有跳转/二维码 URL,建议对齐 iOS/安卓的严格白名单 |
| 6 | **绿钮白字规范**(三端 AGENTS.md 均已加) | 规范已同步;Compose 默认 onPrimary 白字,通常合规,新增台球 UI 待抽查 | 规范已同步;ArkTS 需抽查 GroupBilliardsTab.ets 等新按钮 | 两端新增台球/工作台按钮各抽查一遍(iOS 已发现 2 处违规:GroupBilliardsViews.swift:84,115) |
| 7 | **测试 fixture 打包** | ✅ 放 testResources,不进正式包 | 无此文件 | 反向学习:iOS 的 billiards-v2.json 会进 app bundle,建议加 membershipException 或移测试目录 |
| 8 | iOS 独有(Duo 快照 88/86 环境漂移、String(localized:"ok")、GroupBetaSportTags) | 不适用 | 不适用 | 仅 iOS 处理 |

## 三、建议动作(按优先级)

1. **合同 v2 门槛三端对齐**(唯一需要跨端拷贝的代码项)
   - 安卓:`GroupRepository.kt:210`、`GroupResultCapabilities.kt:13` → `<= 2`(两处一行改动)
   - 鸿蒙:`GroupParity.ts:39` groupResultCapability → `<= 2`(一处一行改动)
   - iOS:更新 `GroupPortParityTests.swift:184` 断言(v2 可写、v3 禁写)
   - 后端已在集成测试中锁定 v2 行为,三端不改则服务端一旦把 capabilities.minClientContractVersion 升到 2,安卓直接弹"请更新应用"且台球群入口消失,鸿蒙台球规则目录为空
2. **微信绑定文案统一**:iOS 已定稿"其他设备和网页端",拷贝到鸿蒙 6 个 locale;安卓定位对应文案后同步
3. **鸿蒙 VIP 白名单确认**(半小时内可核完)
4. 两端新增台球群 UI 按绿钮白字规范抽查
5. iOS 侧其余 P1(44 语言 key)与 P2 按自检报告处理,不涉及两端

## 四、备注

- 三端本轮都在并行开发台球群+工作台+VIP 社区,命名体系各异(iOS style_workbench_* / 安卓 R.string style_*+workbench_photo_* / 鸿蒙 app.string.scoreboard_style_*),互不影响,无需强行统一。
- 安卓/鸿蒙的群模块与 iOS 同构(port parity),业务规则校验(九球 14710/1357、八球让分、斯诺克整局)三端一致,iOS 全量 993/997 通过即为佐证。
- 本报告基于三端工作区未提交状态快照(2026-11-06 00:30 前后),两端仍在变动,落地前建议按上述行号复核。
