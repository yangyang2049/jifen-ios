# 小组三端审计二次复核与修复

日期：2026-10-15。服务端依据为 `jifenqi-backend/api-server/src/routes/groups.ts`、`lib/groups/service.ts`、`reports.ts`。本轮只修改三个客户端及相关回归测试，没有修改服务端行为。

## 复核结论

| 项目 | 二次复核 | 本轮处理 |
| --- | --- | --- |
| F1–F5 | 上轮修复仍存在，未发现回退 | 保留既有实现，由相关测试继续覆盖 |
| F6 | iOS 举报状态动态拼接的四个键确实缺失 | 显式状态映射；47 个 locale 补齐四态文案；兼容 processing；未知状态使用本地化兜底 |
| F7 | iOS 三处确实使用 scalar 计数，但训练取消原因上限的描述不准确 | 按实际接口分别使用 UTF-16 200 / 500 / 300；同时补扫简介、排期备注与地点、场地名、成员页举报详情、请假留言、作废原因 |
| F8 | iOS 能力模型缺少号码范围，校验固定 6–8 | 解码可选 min/max；传入手输、URL、扫码、相册及分享；旧响应、无能力数据或非法区间兜底 6–8 |
| F9 | 小组、活动、赛果、举报等状态直接回显字符串确实存在 | 统一显式白名单映射，补齐 active / dissolved 文案，取消原始状态字符串兜底 |
| F10 | 安卓和鸿蒙部分列表调用方已有教练限制，但共享决策和赛果详情路径不完整 | 将训练组权限纳入共享确认决策，接入各调用方；训练组禁止 peer 的 owner_authority；鸿蒙提交动作再次检查权限 |
| 小组号分组 | iOS 对 7 位号也插入空格 | 仅 6 位和 8 位分组，其他长度原样显示 |

F8 属于能力契约收敛，当前服务端允许的范围仍为 6–8。测试中使用的 9 位能力报文用于验证客户端确实消费区间，不表示服务端已经允许 9 位号。

## 必须保留的计长差异

不能把所有 `unicodeScalars.count` 机械替换为 UTF-16。服务端小组名称、活动标题使用 `Array.from(value).length` 的标量规则，应保留 iOS 对应规则。客户端成员名仍收紧至 24 个标量，最坏 48 个 UTF-16 码元，未超过服务端 64 的限制。

服务端 `z.string().max(n)` 字段使用 UTF-16。截断时保留完整字素，避免拆开 emoji、组合字符或代理对。训练取消接口实际允许 300 个 UTF-16 码元，本轮纠正旧页面 200 的限制。

## 验证证据

改动前：iOS 97 项定向测试通过；安卓赛果确认与等待名单测试通过；鸿蒙 41/41 小组脚本通过。开始前的工作区差异保存在 `/tmp/group-audit-20261015-before/`。

修复后：

- iOS：105 项单测与资源完整性测试通过；47 个 locale 的 1808 个 Localizable 键集合一致；所有状态映射键存在。
- iOS 模拟器：邀请链接冷/热启动、举报页、训练学生与归档只读三个界面用例通过。归档用例首次失败于旧辅助方法从普通列表直接查找归档小组；修正为先进入归档列表后，单独复跑通过。
- 安卓：`:app:testOfficialDebugUnitTest --tests '*GroupResultConfirmationTest' --tests '*GroupResultWaitingNamesTest'` 通过，13 项测试，0 失败；包含正式组、训练学生、显式非教练、教练、自提交、只读及终态回归。
- 鸿蒙：`scripts/test_group_*.mjs|.cjs|.py` 共 42/42 通过，包含执行生产方法的训练权限回归。原弹窗生命周期脚本补齐真实成员、赛果和组类型数据，保留原有请求版本与弹窗隔离断言。
- 鸿蒙：使用 DevEco SDK 根目录和 bundled hvigor，`--mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon` 成功。
- 三端相关文件 `git diff --check` 通过。iOS 残留扫描只保留名称、活动标题的有意 scalar 计数；未发现 `groupText(status, status)` 类原始状态回退。

日志：`/tmp/group-audit-20261015-ios-final.log`、`/tmp/group-audit-20261015-ios-ui-recheck.log`、`/tmp/group-audit-20261015-android-final.log`、`/tmp/group-audit-20261015-hos-final.json`、`/tmp/group-audit-20261015-hos-build.log`。iOS 编译仍报告未修改文件的既有并发告警，本轮不宣称全仓零告警。

未进行安卓、鸿蒙真机冒烟或折叠屏发布回归，也未执行提交、上传或发布。
