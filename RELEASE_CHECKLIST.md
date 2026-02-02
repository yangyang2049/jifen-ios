# 发布前检查清单（除 App Icon 与 Launch Screen 外）

## 必做 / 已处理

### 1. 版本与构建号
- [x] `MARKETING_VERSION`（CFBundleShortVersionString）在 project.pbxproj 中为 1.0
- [x] `CURRENT_PROJECT_VERSION` 为 1；每次提交 App Store 前建议递增
- [ ] 发布前确认版本号与 App Store Connect 一致

### 2. 隐私与权限
- [x] **相册**：`NSPhotoLibraryAddUsageDescription` 已配置（中/英 InfoPlist.strings）
- [ ] **隐私政策**：App Store 要求提供 Privacy Policy URL；若应用涉及数据或权限，需在 App Store Connect 填写；可选在设置页增加「隐私政策」链接

### 3. 显示名称与本地化
- [x] 主应用：zh-Hans「全能计分器」、en「iScore」（InfoPlist.strings）
- [x] Watch：与主应用一致，通过 InfoPlist.strings 本地化（zh-Hans「全能计分器」、en「iScore」）；已移除 pbxproj 中 INFOPLIST_KEY_CFBundleDisplayName = jifenWatch

### 4. 调试与稳定性（已处理）
- [x] 将调试用 `print()` 包在 `#if DEBUG`，Release 构建不再输出
- [x] `QuickStartConfigManager.saveConfig` 中 `fatalError` 改为 `do/try/throw`，编码失败时由调用方处理
- [x] `SportsSetupDialogView` 中 CommonNameSelectorDialog 占位按钮去掉 `print`；`MenuDialog` 点击日志包在 `#if DEBUG`

---

## 建议 / 可选

### 5. 无障碍
- [ ] 为主要按钮、标签增加 `accessibilityLabel` / `accessibilityHint`（当前未使用）
- [ ] 计分、重要操作考虑 VoiceOver 可读性

### 6. 设置与关于（已加入口）
- [x] 设置页「关于」下已增加：**隐私政策**、**联系与支持**（点击在浏览器打开）。发布前请在 **SettingsView.swift** 顶部 `AppSupportURLs` 中替换为你的真实链接（`privacyPolicy`、`support`）；若暂不提供可改为空字符串 `""` 以隐藏对应行。

### 7. 功能与体验
- [ ] 截图功能：当前由 `ScoreboardTemplate` 实现；若某计分类型关闭了 `enableScreenshot`，菜单仍显示「截图」时需确认文案或行为是否符合预期
- [ ] 真机全流程测试：计分、记录、分享、截图、Watch 配对等

### 8. 商店与合规
- [ ] App Store Connect：截图、描述、关键词、分类、年龄分级
- [ ] 若使用第三方 SDK / 收集数据：隐私政策与 App Tracking Transparency（如需要）需完整

---

## 快速核对

| 项目           | 状态   |
|----------------|--------|
| 版本号/构建号  | 已配置，发布前核对 |
| 相册权限文案   | 已中英本地化       |
| 应用显示名     | 已中英本地化       |
| 调试 print     | 已包在 #if DEBUG  |
| fatalError     | 已改为安全处理     |
| 占位 print     | 已移除/无副作用    |
| 隐私政策 URL   | 需在商店填写；应用内已加「隐私政策」「联系与支持」入口，发布前替换 AppSupportURLs |
| 无障碍         | 可选增强           |
