# iOS 审计修复记录（2026-10-22）

本端 3 项确认缺陷及 2 项补充事项已处理。用户已决定：**自动重试等待期间隐藏原因**。代码和自动回归闭环，发布前真机验收尚未完成。

| 原编号 | 总表编号 | 修复后行为 |
| --- | --- | --- |
| IOS-01 | X01 | 未读取成功不能编辑/提交；重试必须载入原举报说明、图片和版本；新建带版本 0，明确旧接口不发送证据替换字段。 |
| IOS-02 | X04 | 真正 WebSocket 握手后才标记连接并重置计数；旧 socket 回调不污染新连接；持续握手失败按指数退避、最多 5 次重试。 |
| IOS-03 | G01 | 44 个目录补齐包内已有译文，核对硬币源文后更新 hash；现有 final/审核状态保持不变，严格审核门禁无阻断。 |
| QA-IOS-01 | 等待文案 | 等待期间隐藏原因，保留内部错误码；停止自动等待后恢复失败原因显示。实现和测试与用户选择一致。 |
| QA-IOS-02 | 测试/错误码 | 动态检查实际源键与 locale plural 清单，保留唯一性/格式等约束；新举报错误码映射至已有本地化提示。 |
| 共享同步 | G03 | 同步器采纳已审核英文标题及 alias 选择，翻译和标题校验与共享检查同时通过。 |

定向应用 XCTest 152/152 通过；最终原生举报 UI 1/1 通过（首次读取失败、提交禁用、重试恢复旧内容、补充编辑）；生产 WebSocket 管理器的本地服务回归 2/2 通过。最终本地化测试 48/48，44 个目录 0 blocker；162 个英文标题、238 个 key 无漂移。Xcode 最终构建成功。

[应用单测](/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/audit/2026-10-22/remediation/ios-unit-v4.log) · [最终构建和 UI 回归](/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/audit/2026-10-22/remediation/ios-report-ui-v5.log) · [WebSocket 回归](/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/audit/2026-10-22/remediation/ios-websocket-lifecycle.log) · [本地化测试](/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/audit/2026-10-22/remediation/ios-localization-final.log) · [目录验证](/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/audit/2026-10-22/remediation/ios-catalog-validation.json) · [总报告](/Users/yangyang/Desktop/jifenqi/jifen-hos/docs/audit/2026-10-22/remediation.md)

早期模拟器目标失效、测试宿主启动失败及 UI 等待谓词失败日志保留，未计作通过。最终使用本任务新建的独立 iPhone 模拟器，完成后已清理；未操作用户其他模拟器或真机。没有重跑原审计全部 Core/全应用测试；最后文档整理未重复构建。其他任务的已有修改、提交及审核文案保留，本任务未提交或发布。
