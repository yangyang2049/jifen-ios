# 未提交变更审查的二次核实与修复（2026-10-17）

本轮针对用户提供的 7 项发现复核当前工作区。起点为分支 `3.3`、提交 `66c2cc55`，192 项未提交变更（183 修改、9 新增），没有暂存内容。原有修改全部保留。

## 逐项结论

| 发现 | 复核结论 | 本轮处理 |
| --- | --- | --- |
| 解散、退出、举报丢失红字 | 确认。枚举的 `isDestructive` 正确，但实际菜单创建按钮时没有传入 role | 恢复按钮的 `.destructive` 角色；增加实际菜单截图的红色像素回归，分别覆盖组主与普通成员 |
| 小组名应统一按 UTF-16 计数 | **误报，保留现有逻辑**。后端创建及编辑名称使用 `Array.from(value).length`；描述使用 Zod 的字符串 `.max(...)`，两者有意采用不同口径 | 增加名称 2–24 scalar、emoji、组合字符及描述 200 UTF-16 单元的边界测试；修正临时成员名称的过时注释 |
| `pending-writes.json` 无清理期限 | 确认。内容变化会追加记录，未确认的旧记录没有到期清理 | 增加 `lastUsedAt`，每次准备请求时清理 30 天未使用的其他记录；当前匹配请求始终保留原键并更新时间。旧格式首次迁移给予完整 30 天窗口；损坏文件仍失败关闭 |
| 非 NEED_LOGIN 的 401 会删除键 | 仓库的状态列表确实含 401，但**当前鉴权传输路径不可达该分支**：业务 401 转为 `unauthorized`，刷新失败转为 `sessionExpired`，本来就保留键 | 防御性移除终态列表中的 401；增加真实 APIClient 替身回归，验证非 NEED_LOGIN 的 401、刷新过期、重建持久层、重新登录后仍发送原键 |
| 入组申请回显原始状态 | 确认存在原始 fallback。当前列表只显示 pending/rejected，47 语言也都有对应键，正常资源下不会直接显示原值 | 改用 `GroupStatusText.joinRequest` 显式白名单；未知值统一显示本地化 Unknown，并检查 47 语言的申请状态键 |
| 小组 toast 继承计分板布局和动画禁用 | 确认。原组件占满可用高度、内置 56pt 底距，外部又添加 24pt，并禁止动画 | 增加独立 `GroupToast`，只占消息所需空间，由父视图设置一次底距；overlay 放在底部 safeAreaInset 的内侧，自然避开主操作栏；支持进出动画并尊重“减弱动态效果”设置 |
| 空行及 beta 小条 28pt | 确认 | 删除残留空行；收起条最小高度改为 44pt；展开态收起按钮保留 28pt 图形，点击区扩为 44×44pt |

## 契约依据

- 后端 `api-server/src/routes/groups.ts` 的 `createGroupSchema` / `updateGroupSchema` 对名称使用 `Array.from(value)`，描述单独使用 `.max(GROUP_DESCRIPTION_MAX)`。
- 后端 `api-server/src/lib/groups/capabilities.ts` 的 `groupNameLength` 及 `capabilities.test.ts` 明确按 Unicode scalar 计算名称。24 个普通 emoji 在客户端和后端均合法，改成 UTF-16 会错误收紧输入。
- 后端 `api-server/src/lib/groups/idempotency.ts` 将回执保存 30 天。本地清理对齐这一期限；对仍在主动重试的同一内容，不主动换键。超出后端回执保留期后的服务端去重能力仍受后端契约约束。
- `jifen/Core/Network/APIClient.swift` 在鉴权请求上将 401 转为 `unauthorized`，刷新时再次遇到 401 则清除过期会话并抛出 `sessionExpired`。

## 验证

- 原生编译和小组定向单元测试：**123/123 通过**，包括 GroupContractTests 20、GroupPortParityTests 97、GroupPreviewDecodingTests 6；本轮新增 4 项单元回归，并扩展状态白名单测试。
- 47 语言检查：`group_copy_20261017.py --check` 通过，47 × 387 个小组键及 2 个共用计数键均无需重写；本地化回归 7/7 通过。
- 界面回归：**4 项唯一测试通过**。第一轮 3 项覆盖组主/成员菜单实际红字、beta 卡在空/非空列表中的展开收起及 44pt 点击区、战绩页 toast；补充概览页 toast 与主操作栏不重叠的断言后，调整 overlay 顺序，再运行概览和战绩两项均通过。3 + 2 次执行中有 1 项重叠，按 4 项唯一测试统计。
- 重新从 clean 构建：**0 编译错误**。修复前全新 DerivedData 构建与修复后 clean 构建均有 40 类既有编译告警，差集为 0；随后仅调整 toast overlay 的修饰顺序，并真实重编译及回归验证。既有告警包括 actor 隔离、弃用 API、测试捕获等，本轮没有扩大修复范围。
- 最终 `git diff --check` 和相关旧模式残留扫描通过；本轮没有改动翻译资源或 catalog。

验证使用 iPhone 17 Pro / iOS 26.5 模拟器。单元测试结果包为 `/tmp/jifen-group-review-fixed.xcresult`，首轮界面回归为 `/tmp/jifen-group-review-ui.xcresult`，toast 最终两项回归为 `/tmp/jifen-group-review-toast-fixed.xcresult`。告警分类对比见 `/tmp/jifen-group-review-warning-comparison.json`。

首次基线在 `CODE_SIGNING_ALLOWED=NO` 下编译成功，但有 16 项既有测试因 Keychain 权限失败（`-34018`，部分被清理不存在文件的错误覆盖）；直接给该产物补签也未能启动。之后由 Xcode 使用本地 ad hoc 签名构建，123 项全部通过。没有为这些环境问题修改业务或鉴权代码。

本轮原样备份：`/var/folders/jh/cxw2j0jx1px6hxvs90c33vtr0000gn/T/jifen-review-original-20261017-e2f1lhyi/`。测试、构建日志和结果包使用 `/tmp/jifen-group-review-*` 前缀。未进行 Git 提交、商店提交或真机完整回归。
