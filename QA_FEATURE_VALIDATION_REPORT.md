# iOS 功能用例与修复报告（对齐鸿蒙）

日期：2026-02-24  
范围：计分、计时、工具、我的球局（预约）、常用名称、设置清理流程

## 1. 用例设计（普通 + 极端）

### 1.1 我的球局（预约）
- 普通：
  - 新增预约后可查询到，状态筛选正确。
  - 取消预约后状态变更为 `cancelled`。
  - 删除预约后数据消失，再次删除返回失败。
- 极端：
  - `getUpcomingPendingBookings(limit: 0)` 返回空。
  - `getUpcomingPendingBookings(limit: -1)` 不崩溃且返回空。

### 1.2 常用名称
- 普通：
  - 单个添加自动去首尾空格。
  - 编辑名称成功，读取顺序正确。
  - 批量添加支持中英文逗号/分号/换行分隔。
- 极端：
  - 大小写重复名去重。
  - 空字符串被跳过。
  - 总量上限 50 生效。
  - 使用记录会将名称置顶。

### 1.3 计分（记录）
- 普通：
  - 保存 finished 记录后可读取 summary。
  - 草稿（unfinished）ID 正确维护。
- 极端：
  - 新草稿覆盖旧草稿（旧草稿删除）。
  - 丢弃 unfinished 后 ID 清空。
  - 记录总量上限 1000 生效并保持时间倒序。

### 1.4 计时（记录）
- 普通：
  - 新增记录后可读取。
  - 同 ID 新记录可覆盖并置顶。
- 极端：
  - 记录上限 500 生效。
  - 删除不存在 ID 返回 `false`。

### 1.5 工具（积分表）
- 普通：
  - standings 积分排序正确。
  - 持久化 save/load 一致。
- 极端：
  - 同分时按名称升序稳定排序。

### 1.6 设置清理流程
- 普通：
  - 清理后计分记录、计时记录、预约、常用名称均为空。
- 极端：
  - 清理前后多模块混合数据，执行一次可全部清空。

## 2. 自动化仿真

仿真入口：
- `qa/FeatureCaseSimulator.swift`
- `qa/SimulationStubs.swift`

执行命令：

```bash
swiftc -o /tmp/feature_case_sim \
  qa/SimulationStubs.swift \
  jifen/Core/Utils.swift \
  jifen/Core/Managers/CommonNamesManager.swift \
  jifen/Core/Managers/CommonNamesBatchParser.swift \
  jifen/Features/Home/Models/HomeModels.swift \
  jifen/Features/Activity/Models/TimerRecord.swift \
  jifen/Features/Activity/Models/TimerRecordManager.swift \
  jifen/Features/Scoreboard/Records/ScoreboardRecord.swift \
  jifen/Features/Scoreboard/Records/ScoreboardRecordManager.swift \
  jifen/Features/Tools/PointsTable/PointsTableModels.swift \
  jifen/Features/Tools/PointsTable/PointsTableStorage.swift \
  jifen/Features/Schedule/LocalBooking.swift \
  jifen/Features/Schedule/BookingNotificationManager.swift \
  jifen/Features/Schedule/LocalBookingManager.swift \
  qa/FeatureCaseSimulator.swift && /tmp/feature_case_sim
```

结果：
- Passed: 7
- Failed: 0

## 3. 发现的问题与优化点

### 问题 1：预约查询极端参数可导致崩溃
- 现象：`prefix(-1)` 会触发运行时崩溃。
- 位置：`LocalBookingManager.getUpcomingPendingBookings(limit:)`
- 修复：增加 `guard limit > 0 else { return [] }`。

### 问题 2：预约提醒触发时间精度不足
- 现象：仅使用 `year/month/day/hour/minute` 组装触发时间，秒级场景可能提前或错过触发。
- 位置：`BookingNotificationManager.scheduleReminder`
- 修复：`dateComponents` 增加 `second`。

### 问题 3：批量常用名称在中文环境会错误拆分带空格英文名
- 现象：如 `Real Madrid` 可能被拆成两个名称。
- 位置：`CommonNamesManagementView.parseBatchInput`
- 修复：
  - 新增统一解析器 `CommonNamesBatchParser`。
  - 批量输入只按逗号/分号/顿号/换行分割，不再按空格拆分整条名称。

### 优化 1：通知管理在无 App Bundle 场景可安全降级
- 背景：CLI 仿真环境下 `UNUserNotificationCenter.current()` 会异常。
- 位置：`BookingNotificationManager`
- 优化：无 bundle 时通知逻辑 no-op，并保证 completion 回调仍执行，不影响 App 内行为。

### 优化 2：单人添加名称键盘约束冲突风险
- 背景：此前出现键盘约束冲突日志，影响系统键盘弹出稳定性。
- 位置：`CommonNamesManagementView` 名称编辑 sheet。
- 优化：移除 `.toolbar(placement: .keyboard)` 自定义键盘工具条，保留自动聚焦。

## 4. 本轮代码变更清单

- `jifen/Features/Schedule/LocalBookingManager.swift`
- `jifen/Features/Schedule/BookingNotificationManager.swift`
- `jifen/Core/Managers/CommonNamesBatchParser.swift`（新增）
- `jifen/Features/Home/SettingsView.swift`
- `qa/SimulationStubs.swift`（新增）
- `qa/FeatureCaseSimulator.swift`（新增）

## 5. 编译验证

- 命令：
  - `xcodebuild -project jifen.xcodeproj -scheme jifen -configuration Debug -destination 'generic/platform=iOS Simulator' build`
- 结果：
  - `BUILD SUCCEEDED`
