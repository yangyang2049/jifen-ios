# 未提交改动全量复核报告（2026-11-06 01:10）

> 本报告取代 `docs/audits/uncommitted-review-2026-11-05.md`（该版基于 11-05 19:43 快照，5 个阻断项现已全部修复）。
> 复核方式：对上一版每条结论在当前工作树上重新取证；不采信第三方修复报告的结论，只采信代码、测试文件与日志证据。
> 全程只读，未修改任何业务文件。

---

## 一、结论

| 判断 | 说明 |
|---|---|
| 🔴 → ✅ **5 个阻断项全部已修复** | 逐条在当前代码验证，并都有针对性回归测试（见第三节） |
| ⚠️ **但当前快照的验证已过期，且工作区仍在变动** | 最终一次全量测试在 **00:54:34 / 指纹 `f844dfc1…`**（1006 通过 / 0 失败 / 1 跳过）；此后 **4 个文件被修改**，其中 `ScoreboardLayoutMetrics.swift` 是业务代码（01:06:09），01:04–01:08 内指纹又变了 3 次 → **1006 通过不代表当前代码** |
| ⚠️ **3 个交付决策 + 1 笔翻译债** | 公开仓库暴露 GA4 内部链接、VIP 入口 fail-open、照片主题可编辑范围、handoff 逃生口；44 语言 115 条英文占位 |
| ✅ 当前可进入「重跑验证 → 决策 → 分组提交」阶段 | 不再有需要改代码的已知阻断项 |

---

## 二、快照对比

| 项 | 11-05 版报告 | 最终测试（00:54） | **当前（01:07）** |
|---|---|---|---|
| 已跟踪变更 | 89 文件 `+6512/-209` | — | **96 文件 `+8663/-967`**（含 1 个 staged rename） |
| 新增未跟踪 | 47 | — | **51**（含本报告） |
| status 条目 | 136 | — | **147**（95 M + 51 ?? + 1 R） |
| diff 指纹 | `da85474e…` | `f844dfc1…` | **`114f6b9f1a38deb9`** |
| 暂存区 | 空 | — | **1 项**：`jifen/Features/Groups/Fixtures/rules-v1.json → jifenTests/Fixtures/rules-v1.json`（R100） |
| 最后一次写入 | — | 00:54:34 | **01:06:09**（`ScoreboardLayoutMetrics.swift`） |

**⚠️ 审查期间工作区仍在被并发写入**（不是本报告所为，本报告只新增/修改 `docs/audits` 下的 md）：

| 采样 | 指纹 | 规模 |
|---|---|---|
| 01:04 | `fcbda431…` | 95 文件 `+8653/-965` |
| 01:06:52 | `1f9bdd28…` | 146 项 |
| 01:08:09 / 01:08:21 | `edc59c44…` | 95 文件 `+8640/-957` |
| 01:08:33 / 01:08:53 | **`114f6b9f…`** | **96 文件 `+8663/-967`** |

反复变动的文件是 `ScoreboardLayoutMetrics.swift`、`ScoreboardStyleEditorControllerTests.swift`、`FullAppScreenshotUITests.swift`——正是第五节 5.1 指出的「测试后改动」。因此本报告的**代码结论（阻断项已修）可信，验证结论（测试是否覆盖当前代码）不成立**，必须在写入停止后重跑。

---

## 三、5 个阻断项复核

| # | 上一版问题 | 当前证据 | 状态 |
|---|---|---|---|
| 1 | 照片主题跨端 wire 丢失 | `DisplayStateWireCodec.swift:104-112`：`style` 为权威来源，不再执行 `style.themeCode = appearance.theme`；扁平字段改为 `map["theme"] = style.themeCode`；backdrop 仅在主题确实非照片主题时清空。`:449-455` 把 `appearance.style/theme/font/倍率` **移出 `panels` 门控**。新增 `ScoreboardStyleV2ModelTests.swift:373` 用 `ScoreboardDisplayState(compactState:)` 真实链路，断言扁平 theme、`style.themeCode`、`backdrop.imageData`、dim、panelOpacity 五项存活 | ✅ |
| 2 | 「恢复默认」不自洽 | `ScoreboardStyleEditorController.swift:37-49`：`canResetDraft` 改为比较字体 + **解析后的元素倍率**，无 session 直接 false；`resetDraft()` 收敛到 `typographySession?.resetPreview(preferences:)` 单一路径，清除陈旧预览、保存时删除持久化键。`ScoreboardStyleEditorControllerTests.swift:216` 新增真实 `ScoreboardTypographySession` 用例，断言重置后置灰且不残留倍率 | ✅ |
| 3 | 台球结果解码契约 | `GroupBilliardsModels.swift:166-197`：`format`/`participants` 下沉到分支；台球走 `GroupBilliardsRow(from:)`，`format` 用 `decodeIfPresent` + `participantMode` 兜底，座位由 `groupSeat(individual:)` 合成；球拍分支也改 `decodeIfPresent`。新增 `GroupBilliardsTests.swift:94` 直接读磁盘真实 fixture 6 条，断言 format/seat/side/往返 + 网球行回归 | ✅ |
| 4 | 持久化故障扩散 | `GroupBilliardsPersistence.swift:11-24`：`read` 不抛错，解码失败 `quarantine` 改名后返回 fallback；`:35-40` `annotate` 不抛错；`ScoreboardRecordManager.swift:597` 主路径去掉 `try`。新增 `GroupBilliardsTests.swift:123` 破坏三个 JSON，断言回落、隔离一次、随后可自愈 | ✅ |
| 5 | 44 语言缺 33 个 key | 47 个 `.lproj` × 2391 key **集合零差异**（脚本复算）；`plutil -lint` 全部通过；无重复 key。新增 `LocalizationIntegrityTests.testLocalizedResourcePairsStayInSync` 钉住 key 集合与占位符一致性 | ✅（缺 key 已消除） |
| 5b | 同一项的翻译质量 | 44 语言中 **115 条**（hi 为 116）新增 key 的值仍与英文原文逐字相同，属英文占位；`billiards_group_*` 等旧占位共 97 条被继承 | ⚠️ 翻译债，非阻断 |

---

## 四、上一版 23 项风险的处理情况

| 类别 | 数量 | 明细 |
|---|---|---|
| ✅ 已修复 | 14 | WireCodec 解码造值（Optional 保持 nil）、`panels` 门控、死代码删除（Overlay **2283 → 1596 行**）、`.id()` 硬切移除、台球绿钮白字（`GroupBilliardsViews.swift:84,115` 已加 `Theme.textOnPrimary`，并顺带修 `WechatBindingView.swift:518`）、`GroupFormat.title` 按用例分文案、版本号文案改 `%@` 占位（`LocalizationIntegrityTests.swift:256` 覆盖 47 语言）、fixture 移出 app 源码树（旧目录已不存在）、`GroupContract.version` 单一来源（`GroupModels.swift:178`，`GroupRepository.swift:50,75,465` 引用）、`GroupPortParityTests` 改为 v2 可写 / v3 禁写、照片 base64 校验改无分配字符集检查 + `Task.detached` 解码、CC BY 常量 URL 去强制解包、发球指示器改条件移除、篮球面板白字改用自动对比 |
| ⚠️ 判定为误报（未改） | 6 | `GroupBetaSportTags` 含台球（依赖安卓 `GroupSports.ALL` 证据，**未独立跨仓核实**）；outbox `done` 墓碑（仓库内已有反向断言，我复核到 `finish(discard:true); add(row)` 后仍为空，同意）；「更正」重复提交 / 规则白名单过严 / tournament 缺字段（三者均依赖后端契约，**未独立核实**）；验证文档跨仓链接（仓库既有约定，同意） |
| 🔶 待你决策 | 3 | `docs/analytics` 入库范围、VIP `enabled` fail-open、照片主题可编辑范围 + handoff 逃生口（详见第六节） |

---

## 五、本次复核新发现（上一版没有的）

### 5.1 🔴 当前快照缺少有效验证（最重要）

| 证据 | 说明 |
|---|---|
| `~/Library/.../runs/20261105T163902601170Z-.../logs/unit-tests-final.log` | `Executed 1006 tests, with 1 test skipped and 0 failures`，`** TEST SUCCEEDED **`，时间 **00:54:08** |
| 同目录 `logs/tree-final-after.txt` | 指纹 `f844dfc1695134b8…`，时间 `00:54:34` |
| `find -newermt '2026-11-06 00:54:30'` | **4 个文件**在该时刻之后被修改 |
| 当前指纹 | `114f6b9f…` ≠ `f844dfc1…`，且 01:04–01:08 内又变了 3 次 |

测试后改动的文件：

| 文件 | 修改时间 | 性质 |
|---|---|---|
| `jifen/Features/Scoreboard/Shared/ScoreboardLayoutMetrics.swift` | **01:06:09** | **业务代码**：字号倍率叠加顺序改变 |
| `jifenTests/ScoreboardStyleV2ModelTests.swift` | 00:58:50 | 测试 |
| `jifenTests/ScoreboardStyleEditorControllerTests.swift` | 01:01:15 | 测试（新增 resolver 倍率用例） |
| `jifenUITests/FullAppScreenshotUITests.swift` | 01:01:09 | UI 测试 |

**`ScoreboardLayoutMetrics.swift` 改动的影响**（`git diff HEAD` 可见）：
- 队名：`fitFontSizeByWidth(requested: 基础字号)` 之后再乘 `nameMultiplier`；
- 主分：`boundedBaseScore = min(fitBaseScore, verticalLimit)`，再乘 `scoreMultiplier`；
- 语义从「倍率参与约束」改为「约束只作用于基础字号，倍率在受限结果上叠加」。

这解决了「篮球面板把倍率整个吞掉、滑块看起来无效」的问题（注释有说明），但**倍率 > 1 时最终字号可能超出宽度/垂直约束**，存在裁切或与相邻元素重叠的风险。新增的 resolver 测试（`ScoreboardStyleEditorControllerTests.swift:281-314`）只断言「字号随倍率变大」，没有断言不越界；且该测试写于 01:01、代码改于 01:06，**两者都未进入 00:54 的最终测试**。

**必须做**：等该文件停止写入后，在当前快照重跑 `build-for-testing` + `jifenTests` 全量，重点看 `testAuditMultiScoreDuoSafeAreaSnapshots`、`testPhotoScoreHeightNativeSnapshots`、新增 resolver 用例；并人工确认 1.5x 倍率下队名/主分不裁切。

### 5.2 ⚠️ 仓库是公开的，分析报告含 GA4 内部链接

- `git remote -v` → `git@github.com:yangyang2049/jifen-ios.git`
- `curl https://github.com/yangyang2049/jifen-ios` → **HTTP 200**（可匿名访问）
- `docs/analytics/2026-10/source-manifest.json` 含 `propertyId 555327954` 与 `analytics.google.com/.../a254588017p555327954/...` 内部探索链接；`index.html` 内嵌同一链接。
- 无密钥/个人信息（已复扫）；但公开仓库会暴露 GA4 账号与媒体资源标识、内部探索入口。
- 建议：入库前剥离内部链接，或确认可接受；剥离会牺牲 `build_report.py` 的可复现性（`source-manifest.json` 由脚本生成）。

### 5.3 ⚠️ 提交时容易漏掉的三处

| 项 | 说明 |
|---|---|
| `billiards-v2.json` | 已移到 `jifenTests/Fixtures/`，但仍是 **untracked**；同目录 `rules-v1.json` 已是 **staged rename**。两者需一起 add，否则 `testFixtureRowsDecodeAsGroupResultsAndRacketRowsStillDecode` 在干净 clone 上找不到文件 |
| 两份新审计文档 | `docs/audits/self-check-remediation-2026-11-06.md`、`docs/audits/cross-platform-parity-2026-11-06.md` 均 untracked，需决定是否入库（后者引用了安卓/鸿蒙工作区，单独 clone 会断链） |
| 本报告 | `docs/audits/uncommitted-review-2026-11-06.md` 同样是新增文件，单独决定 |

### 5.4 ⚠️ 其余遗留（与上一版一致，未恶化）

- **CC BY-SA**：署名已含创作者 + 许可 + 链接，去掉了强制解包；**原始作品 URI、版权声明行、「是否修改」说明仍缺**，已登记 `TODO.md`。
- **多语言**：key 完整但 115 条英文占位；`VIPCommunity.strings` 仅 3 语言（有 `value:` 兜底，显示英文而非空白）。
- **产品决策**：VIP 入口 `enabled=true` fail-open；照片主题 tab 仅 theme/background，`.styleElementSelectable` 仍落在不渲染的 `templateBody`；`unfinished` 全局阻塞开新局。
- **`.ddzRetro` 名牌**：主分手动绿、其余走 AUTO 黑底白字，是否统一属设计确认项。

---

## 六、当前验证矩阵

| 检查 | 结果 |
|---|---|
| `git diff --check` | ✅ 0 错误 |
| `swiftc -frontend -parse`（全部 50 个变更/新增 Swift 文件） | ✅ 50/50 通过（语法层，非类型检查） |
| `plutil -lint`（全部变更/新增 `.strings`） | ✅ 0 失败 |
| 本地化 key 集合 47 × 2391 | ✅ 零差异、无重复 key |
| 本地化占位符一致性（测试） | ✅ `testLocalizedResourcePairsStayInSync` 通过（00:54 日志） |
| 主 target 编译 | ✅ `** BUILD SUCCEEDED **`（00:39–00:54 产物，绑定旧指纹） |
| 全量单测 | ✅ 1006 / 0 失败 / 1 跳过（00:54，绑定 `f844dfc1`） |
| **当前快照编译 + 单测** | 🔴 **未执行**：快照在测试后变更；本环境 `xcodebuild` 仍因 `sandbox-exec` 无法解析包依赖 |
| 打包产物 fixture 校验 | ✅ 旧产物 `find … -name '*.json'` 为空（但新位置的 `billiards-v2.json` 未跟踪，需提交后复验） |
| 敏感信息扫描 | ✅ 无密钥/个人信息；⚠️ 公开仓库 + GA4 内部链接 |

---

## 七、提交前清单

| # | 动作 | 验收 |
|---|---|---|
| 1 | 等 `ScoreboardLayoutMetrics.swift` 等文件停止写入，再取 `git status` / 指纹 | 连续两次采样一致，且差异已复核 |
| 2 | 当前快照重跑 `build-for-testing` + `jifenTests` 全量 | 全绿；重点 resolver 倍率用例与 3 个快照测试 |
| 3 | 人工确认 1.5x 倍率下篮球/网球/乒乓队名与主分不裁切、不重叠 | 截图或真机确认 |
| 4 | 决策：`docs/analytics` 入库范围（公开仓库） | 剥离内部链接或明确接受 |
| 5 | 决策：VIP fail-open / 照片主题可编辑范围 / handoff 逃生口 | 三项各一句话结论 |
| 6 | 补 115 条译文，或明确本版「非中英为英文兜底」 | 与发版市场一致 |
| 7 | `git add` 时一并纳入 `jifenTests/Fixtures/` 两个 JSON、决定三份审计文档 | `git status` 无遗漏 |
| 8 | 按主题拆 4 组提交（样式工作台+照片主题 / 台球小组 / VIP+记录 / 文档+本地化） | 每组可独立回滚 |

---

## 八、证据与限制

1. 单测与编译结论来自他人测试批次的日志与 xcresult（`~/Library/Developer/jifen-ios-test-artifacts/runs/20261105T163902601170Z-selfcheck-remediation-2026-11-06/`），**绑定指纹 `f844dfc1…`**，非本报告在当前快照产生。
2. 本环境无法执行 `xcodebuild`（`sandbox-exec: sandbox_apply: Operation not permitted`，免沙箱重试同样失败），因此类型检查、链接、运行时均未在当前快照验证。
3. 「误报」判定中涉及安卓/鸿蒙/后端的 3 条（`GroupBetaSportTags`、更正幂等、规则白名单/`chaseRoundNumber`）**未独立跨仓核实**，仅记录了他方证据。
4. 未纳入：忽略文件、3 条历史 stash、`/private/tmp/jifen-zhhant-check` worktree、其他仓库改动。
5. 本报告基于 `114f6b9f1a38deb9` 快照（01:08:53）；该快照前后 4 分钟内指纹变化 3 次，说明另一个会话仍在编辑字号逻辑与相关测试。**提交前必须重新采集并复核**。
