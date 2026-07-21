# iOS 架构评审逐项复核与修复（2026-07-20）

对照输入：2026-07-19 `jifen-ios` 架构评审，以及同仓 `jifen-android` 的 Tennis / LineScore / Boxing reducer、KernelRegistry 和 SessionFactory。

| ID | 复核结论 | 本次处理 | 当前状态 |
| --- | --- | --- | --- |
| F1 | 属实，遗留 Template 与 reducer/store 并存 | 足球、简单计分改由 `LineScoreReducer` 适配；拳击核心转移到 `BoxingMatchReducer`；补齐 Tennis reducer/session factory | 部分完成：Tennis UI 仍待从旧 VM 切到 session store |
| F2 | 属实 | 新增 `TennisMatchReducer`、`LineScoreReducer`、`BoxingMatchReducer`，并补 parity 测试 | Core 缺口已修；Tennis UI 切换待完成 |
| F3 | 属实 | 新增唯一 `SessionArchiveRepository`；Rally/Basketball dispatch/undo 自动写 v2；Rally 停止 v1 双写；Home 未完成局优先读 v2 index；旧 Rally 草稿成功迁移后删除 | 现代栈已单轨；其他遗留板仍是 v1，随 F1/F9 迁移 |
| F4 | 属实 | 删除 5 组无入口 VM/Controller、ComingSoon、Flexible，共 1,883 行；清掉 Template 死类型判断 | 完成 |
| F5 | 部分属实 | app `GameType` 明确作为 UI/计时包装；新增与 `ScoreCore.GameType` 的集中转换；编码和 prefs key 均使用 canonical ID | 完成；保留 UI-only 类型是有意边界，不再散落 alias |
| F6 | 属实 | 新增 `ScoreboardKernelRegistry`、descriptor、默认规则路由及 `ScoreboardSessionFactory` | 完成 |
| F7 | 属实但属于纯结构重排 | 本次仅因死代码让 Template 减少；未做 4k 行的大规模无行为拆文件 | 待办：应独立提交，避免与 reducer/持久化迁移混在一起 |
| F8 | 部分属实 | `PreferencesManager` 改为 Observation revision，所有计分板移除 NotificationCenter；主题层分别代表 App semantic token 与 scoreboard palette，职责并不重复 | API 收敛完成；String Catalog 属独立资源迁移 |
| F9 | 属实 | 斗地主、UNO、多人及专用 reducer 的每次有效操作已镜像写入 v4 结构化动作；详情支持按轮/排名复盘和旧字符串降级 | 部分完成：记录语义已补齐，UI 全量切到 S3/S4 SessionStore 仍应独立推进 |
| F10 | 原评审部分过时 | Watch Rally 原本已经直接依赖 `ScoreSessionCore<RallyMatchReducer>`；本次进一步统一到 `SessionArchiveRepository`，dispatch/undo 自动保存 | 完成 |
| F11 | 属实/部分已处理 | 删除根目录唯一 TS 残留；`UITestScreenshots/` 原本已在 `.gitignore`，无需重复修改 | 完成；旧报告刷新由本文替代 |
| F12 | 属实 | 两个计分记录 VM 改为 `@Observable`，相关页面由 `@State` 持有；删除无调用 listener 机制 | 完成（计时记录不在该问题证据范围） |

## 验证

- `swift test --filter 'sessionArchiveRepository|lineScoreReducer|boxingReducer|tennisReducer|kernelRegistry'`：5 项通过。
- iPhone 17 Pro（iOS 26.5）Simulator，`xcodebuild ... build CODE_SIGNING_ALLOWED=NO`：通过。
- 全量 `swift test`：83 项通过。

## 后续不可混做的两项

1. Tennis UI、斗地主/UNO/多人全部切到 SessionStore；v1 记录现已可读迁移到 v4，仍需完成 UI 状态源单轨化。
2. 纯文件拆分（Template / Specialized / Rally）与 String Catalog 迁移，分别单独提交，保持可审查性。
