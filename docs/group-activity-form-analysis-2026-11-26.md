# 小组「发起活动」表单字段语言：三端差异分析与结论

日期：2026-11-26 · 结论针对 iOS 3.4.4 与 `jifen-android` 3.5 / `jifen-hos` 3.2 的当前工作区

---

## 一、问题陈述

分组场景里「发起活动 / 编辑活动」是一个表单。安卓与鸿蒙在 2026-11-19～20 把四个球类（乒乓、羽毛球、网球、匹克球）的表单改成了**台球那套字段语言**，并抽成共用组件。iOS 没跟，而且 iOS **自己内部还有两套**。

## 二、三端现状（逐字段）

| 字段 | 安卓（`GroupActivityForm.kt`） | 鸿蒙（`GroupActivityPage.ets`） | iOS（`GroupActivityViews.swift`） |
| --- | --- | --- | --- |
| 字段名呈现 | 不单独占行，写在 placeholder 里 | 同安卓 | **标签独占一行在输入框上方** |
| 输入框外观 | 48dp 填充块（`groupControlBackground`），无描边 | `app_dialog_field` 填充块 | 系统 `Form` 行 / `GroupAlignedField` 描边输入框 |
| 说明文字 | 行尾「?」气泡（`HelpPopupButton`） | `HelpHint` 气泡 | **常驻小字占一行**（名称自动命名说明 `:44-45`、多人/单场说明 `:86-87`） |
| 日期 / 时间 | 整行块 + 日历/时钟图标 + 行尾箭头 | 同安卓 | 半宽并排两个系统日期字段（`ViewThatFits` 窄屏转竖排） |
| 报名截止 | 整行块 + 时钟图标 + 值右对齐 + 箭头；「用开始时间」内联文字按钮 | 同安卓 | 系统日期字段 + 「用开始时间」文字按钮 |
| 地点 | 整行块 + 地点图标 + 箭头（进常用地点） | 同安卓 | 标签在上的输入框 + 行尾 chevron |
| 玩法（单/双打） | chips 紧贴名称下方、横滑 | 同安卓 | `GroupActivityChoices` chip 行，位置在日期之后 |
| 报名人数 | 一行，含问号气泡 | 同安卓 | 标签 + `Stepper` |
| 备注 | 填充块 + placeholder | 同安卓 | 标签在上的多行输入框 |

证据：
- 安卓 `app/src/main/java/com/douhua/jifen/ui/components/group/GroupActivityForm.kt:111-208`（①名称 ②chips ③日期/时间 ④报名截止 ⑤地点）；类注释 `:55-61` 明确写「台球与其它项目用同一套行…别再各写一套」
- 鸿蒙 `entry/src/main/ets/pages/group/GroupActivityPage.ets:780-903`（`buildCreateForm`：`TextInput` + `placeholder` + `HelpHint` + `app_dialog_field`）
- iOS `jifen/Features/Groups/GroupActivityViews.swift:38-127`

## 三、iOS 内部也不统一（这条比三端差异更要紧）

| 入口 | 实现 | 外观 |
| --- | --- | --- |
| 乒乓 / 羽毛球 / 网球 / 匹克球 发起活动 | `GroupActivityCreateView`（`GroupActivityViews.swift:4`） | `GroupAlignedField`：标签在上、描边输入框 |
| **台球** 发起活动 / 直接排赛 | `GroupBilliardsActivityEditor`（`GroupBilliardsViews.swift:1406`） | **系统 `Form` + `Section` + `TextField` + `Stepper`**（`:1436-1454`） |

同一个小组里，用户在「台球」和「乒乓」两个活动表单看到的是两种完全不同的表单。安卓与鸿蒙都不存在这个问题（两边都是一个共用组件、一套行）。

## 四、差异的实际影响

1. **观感**：iOS 是「表单（label + 输入框）」，两端是「设置列表（填充块 + 行内图标 + 箭头）」。并排看是三套设计。
2. **纵向高度**：iOS 每个字段多一行标签，另加两条常驻说明——比两端多约 6 行，iPhone SE / 小屏 + 键盘态下要多滚一屏。这也是安卓当初把说明挪进气泡的直接动机（`CHANGELOG.md:13`）。
3. **可读性反向风险**：改成 placeholder 当标签后，用户填了内容就看不到字段名。安卓是靠 `.semantics { contentDescription = ... }`（`GroupActivityForm.kt:133`）把标签补回无障碍层；鸿蒙靠 `HelpHint({ label: ... })`。iOS 若照抄，必须同样补 `accessibilityLabel`，否则 VoiceOver 会退步。
4. **维护成本**：安卓已经因为「两套表单」返工过一次（`CHANGELOG.md:13` 明确写「跟台球那页放一起看是两套观感」）。iOS 现在正处于那个状态。

## 五、结论（2026-11-26 已定：1:1 照抄安卓）

**产品决定**：iOS 按安卓 1:1 照抄，不做「半对齐」。理由：字段集合、校验、文案、接口本来就完全一致，差别只有「字段名放哪」和「行长什么样」两类纯视觉差异，改造不动业务逻辑；三端各自长得不一样，反而让人以为功能也不同。

**必做项 1（与照抄绑定）**：iOS 内部的台球活动编辑器（系统 `Form`+`Section`）必须一并并入同一套组件，否则照抄完还是两套。

**必做项 2（照抄的两条配套，否则净退步）**：
- 字段名不可见：填充块里只有 placeholder，用户填完就不知道这行是什么 → 每行补 `accessibilityLabel`（安卓靠 `.semantics { contentDescription }`，`GroupActivityForm.kt:133`）；
- 容器换血：从系统 `Form` 改成自绘 `ScrollView` 后，键盘避让（`scrollDismissesKeyboard`）、iPad 内容宽度上限（`Theme.focusedContentMaxWidth`）、返回手势都要自己接管。

**范围边界**：本次只改小组「发起活动 / 编辑活动 / 直接排赛」这一张表单，**不动** `CreateBookingPage`（预约球局）。若以后要让预约页也统一，另立一项。

**可视化对比**：`docs/demos/group-activity-form-compare-2026-11-26.html`（同时有同名 `.png`，可直接发群里看）。

## 六、实施计划（1:1 照抄）

| 阶段 | 内容 | 工作量 |
| --- | --- | --- |
| 1 | 抽 iOS 版共用骨架：`GroupFormRow`（48 填充块 + 行首图标 + 行尾箭头/问号）、`GroupFormChips`、`GroupFormFootnote`，对齐安卓 `GroupActivityFormFields` 的行序 | 1.5 人日 |
| 2 | 「发起活动 / 编辑活动」按行序重排：名称（含?）→ 玩法 chips → 日期 → 开始时间 → 报名截止（值右对齐 + 恢复按钮内联）→ 地点 → 报名人数（含?）→ 备注 | 1.5 人日 |
| 3 | 台球活动编辑器并入同一骨架（普通 / 直接排赛两个形态，direct 仍隐藏报名截止与人数） | 1 人日 |
| 4 | 无障碍与键盘：逐行 `accessibilityLabel`、`scrollDismissesKeyboard`、小屏 + 键盘态走查、iPad 宽度上限 | 1.5 人日 |
| 5 | UI 测试与截图基线：`group_activity_*` 标识符保持可用，补填充块版截图对比 | 1 人日 |
| **合计** | | **6.5 人日** |

**验收**：与安卓/鸿蒙并排截图一致（允许平台字体差异）；iPhone SE 小屏 + 键盘态不漏字段；VoiceOver 逐行读出「字段名 + 当前值」；台球与乒乓的活动表单外观完全相同；`direct` 形态仍不出现报名截止与人数。

## 七、待确认

- 鸿蒙侧本次表单改造尚未提交（`GroupActivityPage.ets` 在未提交工作区），落地前需先确认它是最终版；
- 台球「直接排赛」形态在 iOS 少了报名截止与人数（安卓 `direct` 分支同样隐藏这两行），合并时保留这个分支差异；
- 照抄后「报名人数」不再是 `Stepper`，需确认加号减号交互是否保留（安卓是数值输入）。
