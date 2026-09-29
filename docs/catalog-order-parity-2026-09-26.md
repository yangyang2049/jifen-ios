# 台球命名与棋类排序跨端调整

按用户确认，台球保留四项，顺序统一为：普通台球 → 斯诺克 → 黑八追分 → 九球追分。

- 普通台球使用独立的通用名称（中文“普通台球／普通檯球”，英文 `Billiards`），不标成八球、黑八或九球。
- 追分入口明确区分 8 球和 9 球，英文为 `8-Ball Chase`、`9-Ball Chase`；重点语言同步使用对应的积分玩法名称。
- 棋类：简中、繁中、日语、韩语保留各端原有顺序；其他语言按国际象棋 → 围棋 → 跳棋 → 象棋排列。

## 修改范围

- iOS：统一目录的台球顺序，17 个现有界面语言资源及 14 个外语审核目录同步；沿用上一轮的按语言排列棋类规则。计分目录、新比赛弹窗和记录筛选使用统一目录。
- 安卓国内工程、安卓 Google 工程：计分目录、计时目录、新比赛／快速开始选择器、记录筛选应用相同规则；界面与 shared-model 的名称一致（资源目录本身共享）。Google 工程补齐本次涉及的重点语言台球名称，其余原有未完整翻译的语言继续回退到英文。
- 鸿蒙：计分、计时、新比赛、记录筛选同步；补上新比赛弹窗原先缺少的普通台球入口。
- 比赛类型标识、历史记录格式和实际玩法规则未改动。已有其他工作区修改保留。

iOS 未上线的翻译草稿没有被冒充审核完成；英语追分名称更新后，这些草稿的旧源哈希会要求后续重新审核。已上线资源的审核门禁全部通过。

## 验证

- iOS：编译及 21 项目录／本地化检查通过；西语和葡语四个地区的 UI 流程通过，生成 28 张截图。目视确认西语计时目录为国际象棋、围棋、跳棋、象棋。截图流程没有覆盖所有玩法状态，也不等同于所有页面逐张验收。
- 安卓 Google：`:app:testDebugUnitTest --tests com.douhua.jifen.helpers.CatalogGameOrderTest` 通过，3 项测试。
- 安卓国内：`:app:testOfficialDebugUnitTest --tests com.douhua.jifen.helpers.CatalogGameOrderTest` 通过，3 项测试。
- 鸿蒙：`node scripts/test_catalog_game_order.mjs` 通过；`hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon` 通过。
- 排序专项检查涵盖地区语言标签、中日韩保留规则、部分列表、重复项、非棋类位置保留以及四项台球顺序。
- 41 个修改的字符串／XML／JSON 资源文件完成语法或键唯一性检查。
- 本轮未做安卓、鸿蒙真机视觉验收，也未发布或提交商店。

本轮修改前备份、日志、截图和 iOS xcresult 位于 `build/localization/catalog-parity/`。
