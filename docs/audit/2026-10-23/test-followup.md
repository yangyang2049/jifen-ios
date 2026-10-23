# 测试与本地化复核收尾（2026-10-23）

复核起点：当前分支 `3.4`，HEAD `844f6f63`，已包含 `8023b40f` 及后续中文微信登录提交。起点已有 `Info.plist` 格式调整和工程版本号 `3.4 (78)` 等改动，本轮保持原样，不纳入提交。

## 二次确认与修复

- **局数输入取帧过早**：原用例现场失败，输入框/预设中心分别为 375.33 / 354.67pt。诊断轮询的首次帧差为 21pt，0.5 秒后同时位于 y=303、尺寸高 44pt，后续采样保持一致。保留原有 1pt 中心对齐、64×44pt 输入尺寸和可见性要求，在键盘缩放与自动滚动结束、帧连续稳定 0.75 秒后比较同一轮采样。
- **分数编辑自动滚动**：稳定取帧后继续暴露输入框底部 466.67pt 超出滚动区域底部 454pt 的问题。自动滚动任务同时跟随焦点和可用视口高度；键盘收缩晚于初次聚焦时重新定位，保留输入框可见性断言及首次聚焦、清空、切换预设行为。
- **截图工作流悬空引用**：原样执行 `python3 -m unittest discover -s scripts`，46 项登记、1 个导入错误，缺失 `capture_localized.py`。历史工作流目录未入库；目录缺失时在导入可选依赖前明确 `SkipTest`，目录存在但文件缺失/损坏时继续报错。保留全部测试，未虚构或恢复未知脚本。
- **已读状态与动作混用**：`group_read_notices` 用于已读徽章、历史分组及 `seen` 状态，不应映射至 `group_copy_mark_seen` 动作。删除运行时和 copy-pack 的动作别名，英文状态恢复为 `Read`，保留已有 47 语言状态文案并同步 catalog/source snapshot。`Mark as Read` 动作不变，新增独立语义回归。
- **微信 catalog 缺项**：`844f6f63` 增加了 7 个资源键，却未登记 44 份 catalog，导致本地化 48 项出现 1 失败、2 错误。本轮仅登记已有英文 fallback 和真实源哈希。按用户确认，微信登录仅支持简繁体中文；未新增其他语言翻译。每份 catalog 的差异限定为 7 条 fallback 新增和 1 条已读状态修正。

## 历史证据校正

此前“恢复的两份日志与 pre-submission-manifest 哈希一致”不成立。当前两文件均与 Git `474d0c61` 版本逐字节一致、在起点保持干净，但历史清单保存的是另一份工作区状态。保留原始清单和日志，不改写历史证据：

| 文件 | 当前/474d0c61 SHA256 | 历史清单 SHA256 |
| --- | --- | --- |
| `ios-initial-status.txt` | `4ac239ac4c5d107e2d36fe1eb21bb94bdb092c57343e4158a5d3385cc49d415f` | `6847b743bcb9407fd2f3330469d2b6e64b7d76e2aad9386283fbffa22c6c1fba` |
| `ios-xcode-unit-tests.log` | `4b0305381388e51a676f8bed44161d14357c4ea9617737ac9c768c27a56bede4` | `5005465f581884775b209b9175fbd17fcd39f43e803d315259f2c80a2c9075ac` |

本轮输出统一写入 `/tmp/jifen-review-*20261023*`，不追加到历史日志。最终原生回归使用独立 DerivedData `/tmp/jifen-review-derived-20261023`；默认输出目录的一次运行出现了旧诊断语句，未将其作为最终验证证据。

## 验证范围

| 验证 | 最终结果 |
| --- | --- |
| 独立 Debug 编译/测试产品构建 | `TEST BUILD SUCCEEDED` |
| Release / generic iOS / 无签名 / 空输出目录 | `BUILD SUCCEEDED`；35 类 Swift 告警与 2026-10-22 clean Release 基线一致，无新增；另有既有 AppIntents 元数据提示 |
| `jifenTests` | 719 项登记，718 通过、1 项 APNs 探针按原设置跳过，0 失败 |
| iPhone 最终 UI | 3/3：内联局数/分数、分数清空后输入、拳击预设与自定义切换；内联完整用例在最终修复后独立通过两次 |
| iPad 最终 UI | 2/2：内联局数/分数与拳击自定义切换 |
| `swift test --package-path Packages/JifenCore` | 251 项通过 |
| `python3 -m unittest discover -s scripts` | 46 项登记，45 通过、1 个缺失的可选工作流模块明确跳过，0 失败；包含 WS 真实握手间隔 1/2/4/8/16 秒回归 |
| `python3 -m unittest discover -s scripts/localization` | 49/49 通过，含新增状态/动作分离回归 |
| 44 catalog 严格审核验证 | 44/44 通过，0 blocker；微信已有英文 fallback 的 source-equality 提示保留，不声称其他语言翻译完成 |
| copy pack / English heading / audit copy `--check` | 全部通过、0 待写文件 |
| 可选截图包边界 | 目录缺失触发 SkipTest；模拟目录存在但文件缺失仍触发 FileNotFoundError |
| `git diff --check` / 原有配置差异核对 | 通过；两个原有配置文件的 diff 与起点逐字节一致 |

最终应用单测使用独立产品目录中的 `jifen-review-zh-Hans.xctestrun`，明确写入宿主 `-AppleLanguages (zh-Hans) -AppleLocale zh_CN`。此前仅传 `-testLanguage/-testRegion` 的两轮宿主仍用英文启动，导致 **1 个中文专用用例、24 条断言失败**；这些失败日志保留，没有计入最终通过结果，也没有放宽中文文案断言。

[验证摘要](evidence/validation.json)保存最终配置、源码与受测产品哈希。[修复前截图](evidence/custom-points-clipped-before.png)与[修复后截图](evidence/custom-points-visible-after.png)均来自真实原生 UI 测试附件，显示输入框从裁切变为完整可见。

最终日志：`/tmp/jifen-review-final-unit-zh-20261023.log`、`/tmp/jifen-review-final-iphone-20261023.log`（仅 UI 3 项通过，单测部分的语言失败不采用）、`/tmp/jifen-review-final-ipad-20261023.log`、`/tmp/jifen-review-release-20261023.log`、`/tmp/jifen-review-scripts-after-20261023.log`、`/tmp/jifen-review-localization-v3-20261023.log`、`/tmp/jifen-review-core-20261023.log`。模拟器不能证明真机的单侧摄像头安全区、静音开关或微信跨应用授权链路，发布前仍须完成对应设备验收。固定白色主按钮文案的跨端产品规则未改动。
