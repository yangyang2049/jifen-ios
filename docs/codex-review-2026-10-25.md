# Codex 新功能收尾审查 · 2026-10-25

> 后续二次复核更新：以[二次复核与修复报告](audits/self-check-remediation-2026-10-25.md)为最新结论。后续 UI 冒烟发现并修复了本报告遗漏的开局卡死，也补上测试凭证/存储隔离；用户已确认此前自动同步涉及专用测试账号，相关数据保留。本文件保留初始审查快照。

审查对象：jifen-ios 工作区全部未提交修改（**120 个已改 + 32 个新增**，`b8255085` 之后无新提交）
Codex 收工时间：**2026-10-25 01:17**（此后 8 小时零改动，确认已停手）

后端结论复核：**2026-10-25 10:11（Asia/Shanghai）**。下文已更正测试执行历史、正式 API 域名和生产部署状态；本次仅只读查询，没有部署、重启或修改生产库。

后续更新：用户随后授权二次复核、部署验证，后端已于 **2026-10-25 10:35** 增量上线。下文第 3 项保留 10:11 的部署前快照；最新状态见其末尾及 [实施记录](implementation/participant-identity-2026-10-24.md)。客户端发布与真机联调尚未完成。

---

## 一、两个新功能是什么

### 功能 1：本人身份 / 名称绑定 / 我的记录

| 模块 | 内容 |
|---|---|
| `Packages/JifenCore/Sources/ScoreCore/ParticipantIdentity.swift` | 领域模型：`ParticipantPersonRef`、`ParticipantAlias`、`ParticipantIdentityLedger`、`ParticipantSelection`、重复占位规则 |
| `jifen/Features/Identity/`（8 文件 / 1881 行） | 本地身份账本、云同步、个人记录适配、小组记录、视图 |
| `jifen/Core/Managers/NameTransliteration.swift` | 中文姓名转拼音（含多音字姓氏表） |
| `jifen/Resources/*/ParticipantIdentity.strings` | 独立字符串表（en / zh-Hans / zh-Hant，各 56 键，**键集完全一致**） |

**产品行为**：登录后本人名字置顶选人列表并标「我」；历史用过的名字可随时关联归户；「我的记录」= 我恰好占一个座位的记录（帮别人记的不算）；多端同改同一条记录保留冲突版本供用户选择。

### 功能 2：九球规则版本3（民间追分 + 赛事积分）

| 模块 | 内容 |
|---|---|
| `NineBallTournament.swift` | 赛事计分：累计制、同局三犯判负、总局数、提前结束 |
| `NineBallChaseTransfers.swift` | 民间转移制计分（v2/v3 共用），从原 reducer 抽出 |
| `NineBallRulesView.swift` | 三段式规则说明页（民间 / 赛事 / 差异对照） |
| `NineBallSetupDialogView.swift` | 设置页重做：赛制切换、分值可编辑、局数预设+自定义 |
| `NineBallChaseScoreboardView.swift` | 计分板：开球人标记、转移确认弹窗、三犯提示、投屏字段 |
| 语音 | `LocalizedVoiceAnnouncement` + 三语 voice catalog |

---

## 二、【已修复】我改的 2 处

### 1. 「再来一局」丢身份绑定（真 bug，功能 1 的核心）

- **文件**：`jifen/Features/Scoreboard/Sports/Billiards/NineBallChaseScoreboardView.swift:1563`、`1603`
- **现象**：九球打完点「再来一局」，新记录不会被归到「我」名下 → **「我的记录」里看不到这一场**。
- **根因**：`startNewMatch()` 取了 `previousIdentityRecord` 却从未使用（死变量），漏了 `copySelections`。其他 6 个计分板（台球 / 斗地主 / 射箭 / 拳击 / 多人计分 / 追分）都有这一步。
- **修复**：补上 `ParticipantIdentityStore.shared.copySelections(from: previousIdentityRecord, to: newRecordID)`。

### 2. 反馈标签硬编码中文（i18n）

- **文件**：`jifen/Features/Home/Components/NineBallRulesView.swift:50`
- **现象**：英文环境下，规则页点「反馈」，标题仍是中文 `#九球追分# `。
- **根因**：字面量写死，未走本地化。既有正确写法在 `GroupViews.swift:91`。
- **修复**：改用已有键 `nine_ball_rules_title`（三语齐备）：`"#\(nineBallText("nine_ball_rules_title", "Nine-ball chase"))# "`。

---

## 三、【验证通过】我跑过的检查

| 检查 | 结果 |
|---|---|
| `swift build`（JifenCore） | ✅ 通过 |
| `swift test`（JifenCore） | ✅ **275 项全过**（含新增 8 项 v3 规则测试） |
| `xcodebuild` 模拟器构建 | ✅ **BUILD SUCCEEDED** |
| `LocalizationIntegrityTests` + `ScoreboardDisplayTests` | ✅ **89 项全过** |
| **iOS 全量单元测试（846 项，正常签名）** | ✅ **846 项 0 失败**（1 项跳过） |
| 47 个 `.lproj` 键集合一致性 | ✅ **完全一致**（各 2211 键） |
| `nine_ball_*` 占位符格式校验 | ✅ **0 处不匹配** |
| `ParticipantIdentity.strings` 三语键集 | ✅ **完全一致**（各 56 键），且**已正确打包进 app bundle** |
| 新增 13 个 `.swift` 是否进工程 | ✅ 项目用 `PBXFileSystemSynchronizedRootGroup` 自动包含；测试文件已显式登记进 pbxproj |
| 调试残留（print/TODO/FIXME/强制解包） | ✅ 新增模块**零命中** |
| 赛事提前结束公式 | ✅ 手工复算边界正确（大于才结束、等于仍可追平、打满平分加局） |
| 隐私：他人记录是否被上传 | ✅ 上传按 `identity.canRead` 过滤，不会泄露 |
| 微信合并是否影响登录 | ✅ 合并失败被 catch，不回滚已提交的登录态 |
| 清空本地数据是否覆盖新数据 | ✅ 已加 `clearLocalCache` + `clearLocalState`，UserDefaults 全清 |

---

## 四、【待你决策】不建议我擅自改的

### 0. 跨仓范围：iOS 加另外 7 个仓库

按 `docs/implementation/participant-identity-2026-10-24.md`，本轮身份功能涉及 **8 个仓库（包含 iOS）**。以下为另外 7 个仓库的原审查快照；未提交数量包含既有工作，不能全部归为本轮功能改动：

| 仓库 | 未提交 | 身份相关文件 | 昨夜后改动 |
|---|---|---|---|
| jifenqi-backend | 205 | 16 | 20 |
| jifen-android | 240 | 12 | **453** |
| jifen-android-google | 725 | 13 | — |
| jifen-hos（鸿蒙） | 162 | 6 | **137** |
| jifenqi-website | 110 | 4 | **401** |
| iscoreboard-website | 87 | 4 | — |
| jifen-wechat | 85 | 4 | 34 |

**本份审查逐行检查了 iOS；另外 7 个仓库在原审查中只做了存在性核查。跨端实施与既有验证另见实施记录，不代表本份报告重新逐行审查了各端。**

### 1. 后端接口契约：已核对通过 ✅

- 本地源码已在 `api-server/src/index.ts:349-351` 挂载三个路由族：`/api/self-identity`、`/api/private-records`、`/api/private-record-assets` 及其子路径。此处是源码注册状态，不代表这些路由已部署到生产。
- 字段级 contrat 一致：后端 `identityMutationSchema`（`.strict()`）与 iOS `PersonalIdentityMutation` 字段吻合，历史 claim 严格六字段也一致。
- 后端 contract 单测通过（`npx tsx --test src/lib/participantIdentity.integration.test.ts` → 1 pass）。

### 2. 真实数据库集成测试此前已执行：54 项通过、0 跳过

- 复核仍在的 `/tmp/jifen-participant-root-regression.log`：真实 Postgres suite 包含身份、记录、WAV 上传下载、微信 merge/keep、会话撤销和隔离；末尾为 `tests 54 / pass 54 / fail 0 / skipped 0`。日志修改时间为 2026-10-25 00:28:09，测试源文件为当日 00:25:09。
- 默认执行要求 `RUN_LOCAL_DB_TESTS=true` 和隔离库保护条件；未启用时会跳过。这只说明该次运行未执行 DB 测试，不能推出历史「从未跑过」。原结论撤回。
- 原审查尝试空库初始化遇到旧迁移及 `user_uid_seq` 障碍，这不等于新功能迁移失败。此前采用当前基线 schema → 本次纯新增 migration 的隔离验证方式，已记录于 [后端交付核验](../../jifenqi-backend/doc/participant-identity-private-records-verification-2026-10-24.md)。不可对生产库使用 `db push` 绕过迁移。
- `user_uid_seq` 是数据库 sequence，由既有 `20260612113000_add_user_uid` 迁移创建，不需要 Prisma model；既有 `scripts/test-feedback-languages.sh` 也先创建它再初始化隔离库。原报告关于「未定义模型」的解释不准确。
- 该文件使用 `node:test`，应通过 `node --import tsx --test ...` 或 `npx tsx --test ...` 执行，不用 Vitest。完整隔离配置和命令见上述交接。
- 本次复核读取既有日志，没有重新运行 DB 测试；此前 54 项通过不等同于生产或原生客户端真机联调验收。

### 3. 现有生产后端正常；本次身份与私人记录功能尚未部署

- iOS 正式 API 域名是 `https://api.jifenqi.com`（`APIEnvironment.swift`），不是网站域名 `https://jifenqi.com`。2026-10-25 10:11 实测正式 `/api/health` 返回 HTTP 200、`status: ok`；服务器内网 `127.0.0.1:3031/api/health` 同样 200，PM2 `jifenqi-api` 为 online。健康检查实际执行数据库 `SELECT 1`。
- 正式及内网 `/api/self-identity`、`/api/private-records` 均为 HTTP 404。只读核对运行产物：`dist/index.js` 没有这两个路由挂载，`dist/routes/participantIdentity.js` 及新迁移文件均不存在。
- 生产库只读元数据查询：`_prisma_migrations` 没有 `20261024230000_participant_identity_private_records`，新身份和私人记录表也不存在。确认本功能代码与数据库迁移均尚未上线。
- 因此现有后端并非未部署或故障；**本轮新增身份云同步暂时保持本地降级，发版前须发布对应代码与迁移，再完成客户端联调**。网站域名 health 404、本机 3000 未启动均不足以判断生产 API 状态。
- 本次未部署、重启、执行迁移或读写生产用户记录。

**后续部署结果（10:35 起）：** 二次静态复核无阻断；源码与最终部署文件组合各 54 项真实 Postgres/HTTP 回归通过、0 跳过；生产纯结构副本演练确认 78 张旧表定义不变。限定增量代码与本次 migration 已上线，生产健康 200、PM2 online、48 条迁移无 failed。公网专用临时账号验证身份承接、历史 claim、记录同步/筛选/隔离/冲突/删除及语音往返通过，临时数据已清理。60 秒 AAC 实测 494,756 字节并通过；Nginx 仍为 3 MiB，大于该值的 WAV 公网仍返回 413，10 MiB 契约兼容须取得 sudo 后调整并复测。完整证据见 [后端交付核验](../../jifenqi-backend/doc/participant-identity-private-records-verification-2026-10-24.md)。

### 4. 其余 22 种语言用英文占位（已知取舍）

- **现状**：ar / de / ja / ko 等 22 个语言里，九球新增 91 个键全是英文原文。
- **评估**：Codex 在 `docs/nine-ball-rule-presets-ios-2026-10-24.md:48` 已明确记录这是本轮决策。**不崩、不报错**，只是非中英用户会看到英文。
- **建议**：① 若这版要发海外，走既有 `scripts/localization/` 流程补译；② 若先发国内，可接受。**要我补译的话说一声，我可以批量走现有工具链。**

### 5. 个人记录云同步的能力开关降级

- **现状**：`personalRecordsPrivateV1` 能力为 false 时自动退回纯本地（`PersonalRecordsCloudSync.swift:437`），这是好的降级设计。
- **最新确认（2026-10-25 10:35 后）**：新增接口及 migration 已上线，认证态 HTTP 冒烟成功。10:11 的「接口未上线」结论已由后续部署更新；真机客户端仍需验收。
- **建议**：发版前跑一次真机登录，确认 `phase` 能到 `synced`。

### 6. 九球「赛事」模式下残留 `goldenNine` 字段

- **现状**：赛事模式设置页不展示黄金9、reducer 也拒绝该意图（`SpecializedScoreboards.swift:414`），但 `config.goldenNine` 仍以默认值 4 存在，并被写进 `chasePoints` / `nineBallGoldenNine`。
- **影响**：**当前无用户可见影响**（展示顺序已按 `categoryCount` 过滤，测试 `testTournamentDisplayMetadataAndCategoriesRoundTrip` 覆盖）。
- **建议**：可留着做前向兼容；若想更干净，赛事写入时把该字段置空。**不影响发版，可不动。**

### 7. 实体电视 / AirPlay 未实测

- **现状**：投屏字段白名单、线缆数据往返、布局回归都有测试（`ScoreboardDisplayTests` 通过），但**没有连过真实电视或 AirPlay 接收端**。
- **建议**：发版前找台电视实测一次九球投屏，重点看开球人球杆标记和四项统计标签。

---

## 五、【仅提示】不需要动手的

- `jifen/Core/Managers/NameTransliteration.swift` 里的中文姓氏表是**数据**不是文案，i18n 扫描会命中但属正常。
- `docs/verification/` 新增 6.6M 截图：仓库既有惯例（已有 11 个同类文件被跟踪），不算误入产物。
- `jifen.xcodeproj/project.pbxproj` 改动仅为登记 4 个新测试文件，无副作用。
- `NineBallRulesView.playerCount` 参数当前未被使用（预留），无害。
- 新增 26 个测试覆盖：身份合并/冲突/隐私隔离/幽灵账号/墓碑记录/UI 筛选清除，覆盖度扎实。

---

## 六、机器整夜运行情况（你问的「会不会关掉」）

- **没关，也没休眠。** `pmset` 全程 `sleep 0`，`caffeinate` 从 00:04 起持有 PreventSystemSleep 直到早上审查结束。
- 看守脚本 **59 次快照，0 次断档**（相邻间隔均 < 15 分钟），覆盖 00:05 → 09:33。
- Codex 进程仍在（是 Codex Desktop 常驻，非任务），但**01:17 之后没有任何文件改动**。
- 磁盘剩余 19 GB，无异常。
- **审查结束后我已停掉看守循环和 `caffeinate`**，机器恢复正常休眠行为，不必再整夜通电。

---

## 七、你可以怎么继续

```bash
cd /Users/yangyang/Desktop/jifenqi/jifen-ios
git status                 # 152 项未提交
git diff                   # 逐块看
cd Packages/JifenCore && swift test    # 275 项
```

**我没有做任何 git commit**，所有改动（含我修的 2 处）都在工作区，你 review 后可自行决定如何分批提交。

### ⚠️ 跑测试时请注意签名

不要加 `CODE_SIGNING_ALLOWED=NO`。这样跑会出现 **76 项假失败**，错误码统一为 `status(-34018)`（Keychain entitlement 缺失），与业务代码无关。Codex 昨夜也踩过同一个坑（原话：「首轮测试遇到模拟器签名导致的 Keychain 环境错误，改用项目正常签名后已通过」）。

正确命令：

```bash
xcodebuild -project jifen.xcodeproj -scheme jifen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:jifenTests test        # → 846 项 0 失败
```
