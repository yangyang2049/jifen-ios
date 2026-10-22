# iOS 未提交修改提审前复核（2026-10-22）

> **修复更新（2026-10-22）：下列 3 项问题已二次确认并修复。最终 714 项应用单测、9 项 UI 回归、3 项脚本回归全部通过，另有 1 项 APNs 探针按原设置跳过；真实采集和 Release 构建通过。当前实现与完整证据见 [修复记录](pre-submission-fixes.md)。下文保留修复前的审计快照。**

**结论：暂不建议提审。确认 3 项 P2，其中 1 项为原生 UI 实测复现的 UNO 选值回归，另外 2 项影响测试门禁与验证证据。未发现确认的新增 P0/P1 缺陷。**

本轮只检查与运行验证，未修业务代码、未改测试断言、未提交或上传。此前审计报告作为线索，以下结果均以本轮磁盘代码和实际执行为准。

## 确认发现

### 1. P2：UNO 自定义目标分切回预设后丢失所选值

- 位置：[MultiScoreSetupDialogView.swift:475](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/MultiScoreSetupDialogView.swift:475)。
- 复现：打开 UNO 设置 → 选 500 → 点自定义输入 600 → 点预设 1000 → 再点自定义。应回填 1000，实际回填 **500**。
- 本轮 `MainFlowUITests.testSetupUnoCustomTargetFocusesOnFirstTap` 在首轮和单独复跑中均失败于同一断言（测试第 1594 行）；首次自定义输入 600 的断言通过。不是仅等待输入框或键盘失败。
- 代码原因：新逻辑在选择预设时清空文本并移除 TextField，但它的 Binding setter 没有隔离退出编辑后的回写。该 setter 仍会根据空文本覆盖 `unoTargetScore` 为 0；再次打开自定义时 `normalized` 将无效值回退为 500。这一回写路径与实测结果一致。同轮 `SportsSetupSettingsSection` 已有 `requestedCustomField` 门禁，UNO 未采用同等保护。
- 除选值丢失外，代码中的 `canConfirmSetup` 依赖有效范围，目标被写成 0 时也会禁用开始；这一影响由代码推导，本轮没有追加点击开始的专门断言。
- 建议：给自定义编辑绑定增加明确的编辑会话/退出保护，防止移除输入框时的旧回调覆盖新预设；保留现有失败测试，增加“选择预设后可以直接开始且实际目标分为预设值”的验证。
- 证据：[首轮 UI 日志](/tmp/jifen-preflight-ui-20261022.log)、[复跑日志](/tmp/jifen-preflight-ui-followup-20261022.log)。

### 2. P2：颜色测试直接比较不同色彩空间，导致全量单测失败

- 位置：[GroupPortParityTests.swift:1577](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifenTests/GroupPortParityTests.swift:1577)。
- `Theme.textOnPrimary` 改为 `Color.white` 后，`UIColor(Theme.textOnPrimary)` 返回 `UIExtendedSRGBColorSpace 1 1 1 1`；直接与 `UIColor.white` 的 `UIExtendedGrayColorSpace 1 1` 做对象相等比较会失败。
- 完整应用测试登记 715 项：**713 通过、1 失败、1 跳过**。失败的是这一个测试中的浅/深色两次断言，不能把“2 failures”误写为两个失败测试。跳过项是需要真实 APNs 的显式 opt-in 探针。
- 这是本次改动引入的测试门禁问题；两个输出都代表白色，没有据此认定产品出现错误颜色。
- 建议：将颜色转成相同色彩空间后比较 RGBA 分量及容差，保留浅/深色与白色预期，不要删除测试或改回产品颜色来规避。
- 证据：[应用完整单测日志](/tmp/jifen-preflight-unit-20261022.log)、[结果包](/tmp/jifen-preflight-unit-20261022.xcresult)。

### 3. P2：自定义 xctestrun 与记录的二进制哈希不对应

- 位置：[capture_duo_layout.py:88](/Users/yangyang/Desktop/jifenqi/jifen-ios/scripts/capture_duo_layout.py:88)，关联该文件第 100–106 行。
- 新增 `--xctestrun` 会改变实际测试所用的构建，但 `binary_sha256` 仍固定读取 `build/duo/DerivedData/Build/Products/Debug-iphonesimulator`。
- 当调用者指定另一个 DerivedData 的 xctestrun 时，`session.json` 会把默认目录的旧包哈希写成此次测试证据；默认目录不存在时则允许空哈希。这会破坏截图/录像与实际受测包的对应关系。
- 本机对照：默认目录 `jifen.debug.dylib` 的 SHA256 为 `0067cefbf94c99b4c525497f36f19a854502ceaedf230ec5ffa9343236c1f387`；本轮应用测试使用的 DerivedData 对应文件为 `ebfee4bed39fe1b342c95b3bdc57a78f20229a4e4c42463798c988bd14cb6d5c`。两份 xctestrun 的 UI target 都通过 `__TESTROOT__` 解析各自产品目录，确实可以指向不同二进制。
- 建议：从选定 xctestrun 的 `UITargetAppPath`、`TestHostPath`、`TestBundlePath` 解析真实文件后计算哈希，并记录所选 xctestrun 本身；缺少必需文件时失败退出。
- 这是验证脚本缺陷，没有证据表明 App Store 包因此发生运行故障。本轮 UI 直接通过 xcodebuild 执行，没有用这个脚本的哈希证明测试版本。

## 覆盖范围

审阅基线 HEAD：`474d0c614a8f0d5eafd6c941d6a97f1a11a8c589`。无 staged 修改；全部 **150 个**未提交路径均纳入清点与差异审阅，包含未跟踪文件。见[文件哈希快照](evidence/pre-submission-manifest.json)。测试期间反复核对该快照，原有文件内容无变化。

| 文件簇 | 路径数 | 审阅方法与结论 |
| --- | ---: | --- |
| 生产 Swift | 28 | 网络/账户文案、举报读取与提交门禁、WebSocket 握手/重连/旧回调隔离、小组首页/头像、会员布局、计分设置/主题；确认 UNO 回归，其他修改未发现确定缺陷 |
| 本地化资源 | 47 | 全部修改键语义对比；英语 66 个键变化，其他语言仅增加补记赛果动作键，简/繁中文另缩短“其他”分类；无意外外语译文改写 |
| 翻译 catalog | 44 | 逐文件 JSONL 语义对比与严格验证；原有 final/status 保持，69 个旧键只改 note/hash，新增 `setup_auto_odd_sets` 与 `group_manual_result_action` 两键 |
| 单测 / UI 测试 | 2 / 3 | 全部测试差异审阅并执行完整应用单测与定向原生 UI；确认颜色测试断言问题 |
| 其余脚本 | 10 | 本地化审核/标题生成、测试及录像采集改动；确认自定义 xctestrun 的哈希来源问题 |
| 原有报告/证据 | 16 | 区分历史审计、修复记录与实际验证，检查 JSON/Python 语法、敏感凭据模式；历史失败日志不能替代本轮验证 |

大量 catalog diff 包含 JSON 字段格式重排，审阅以解析后的键和值为准。没有把 22,000 多行 diff 当作同等规模的翻译改写，也没有仅依据现有报告宣布修复通过。

## 本轮实际验证

| 验证 | 结果 |
| --- | --- |
| `git diff --check` | 通过 |
| `swift test --package-path Packages/JifenCore` | 251 项通过 |
| 本地化 `unittest discover` | 48 项通过 |
| 44 catalog `require_reviewed=True` | 44/44 通过，0 blocker；既有 source-equality/length-expansion 警告不作为逐屏翻译正确的证明 |
| 英文标题检查 | 163 个标题、239 个键，0 待写文件 |
| 小组共享文案/审核检查 | 47 语言 × 666 小组键及 2 个共享计数，0 待写文件；audit copy 检查通过 |
| 生产 WebSocket 管理器本地服务回归 | 2/2 通过；拒绝握手共 6 次尝试，间隔约 1.01/2.01/4.01/8.02/16.02 秒 |
| Group notice 脚本 | 8 个生产方法场景及通知目的地检查通过；unittest 登记数为 0，未冒充 XCTest 数量 |
| 完整 `jifenTests` | 715 登记，713 通过、1 失败、1 APNs 探针跳过；exit 65 |
| 定向原生 UI 首轮 | 9 项：8 通过、UNO 1 失败；举报读取失败/重试、首页入口/英文标题及其余自定义输入通过 |
| UI 补充 | 会员页 7 语言、14 张截图的 1 项测试通过；UNO 再跑仍失败 |
| Release / generic iOS / 不签名 | `BUILD SUCCEEDED`；exit 0 |

UI 使用本任务新建的 iPhone 17 Pro / iOS 26.5 模拟器（`1789CD68-A8E8-44F2-AE14-FF98E5CBC6D9`）。用户正在使用的 Duo 模拟器未操作。会员截图覆盖 it/nl/sv/fr/fr-CA/ru/ar，人工查看法语订阅、俄语终身、阿拉伯语订阅的截图，未发现新增遮挡或 RTL 错位。其余截图仅作为可复核证据，没有声称所有语言逐屏人工验收。

日志与结果包：`/tmp/jifen-preflight-{unit,ui,ui-followup,release,localization,core,ws}-20261022.*`。会员截图已在清理模拟器前导出至 `/tmp/jifen-preflight-screenshots-20261022/`。

关键命令：

```sh
xcodebuild test -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,id=1789CD68-A8E8-44F2-AE14-FF98E5CBC6D9' \
  -only-testing:jifenTests -testLanguage zh-Hans -testRegion CN \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/jifen-preflight-unit-20261022.xcresult CODE_SIGN_IDENTITY=-

xcodebuild build -project jifen.xcodeproj -scheme jifen \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

## 提审前仍需完成

上述 3 项代码/测试/采集问题现已修复，自动回归通过，详见修复记录。Release 编译通过不等于已完成签名 Archive、App Store 包校验或真实购买/恢复购买验证；本轮没有执行这些动作。

按此前保存的发布约束，Pura X/同等折叠屏真机回归仍是发布前 P0 门禁，本轮没有证明已完成。iOS 包不能运行在 Pura X 上，应由对应端/跨端联验承担该项，iOS 自身仍需 iPhone/iPad 真机确认。针对本轮差异，重点是：会员底部购买栏在小高度窗口中仍可操作；自定义分数输入在尺寸变化后保持数值/焦点且预设切换正确；举报草稿、旧附件和版本在窗口/前后台变化后不被清空；同步连接恢复后比分/计时/当前局与未关闭弹层仍保持。模拟器截图与本地 WS 测试不能替代这些真机结果。
