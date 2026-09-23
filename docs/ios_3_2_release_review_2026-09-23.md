# iOS 3.2 提审前核对（2026-09-23）

## 基线与当前判断

- 中国区 App Store 查询到的公开版本为 **3.0**（2026-09-22 上架；公开更新说明为页面改版、多个项目、投屏和跨设备同步）。本仓库 `HEAD` 同为 **3.0 / build 40**；当前工作区工程配置为 **3.2 / build 46**。版本跨过 3.1，提审前确认这是预期版本序列。
- 2026-09-23 最终决定：本次 iOS 版本**不包含 Apple Watch App，也不包含手机与手表联动的 UI 和运行逻辑**。相关实现已保存在独立 Git stash 中，当前工程只保留 iPhone/iPad 主应用与测试目标。
- **今晚不提审**。最终仍需以固定提交重新归档，并完成手机、iPad、跨端显示和会员链路的实机验收。

## 3.0 → 当前 3.2 工作区的主要变化

| 模块 | 实际改动 | 提审关注点 |
|---|---|---|
| Apple Watch | 本版不包含 Watch target、Watch App、Watch 测试目标、WatchConnectivity 服务、手机联动入口或计分板联动逻辑。 | 归档前确认目标列表、Embed 阶段和最终 App 包中均无 Watch 内容。 |
| 计分与恢复 | 保留与手表无关的计分板、编辑态、短屏布局、菜单及本地恢复改动。 | 旧版升级后记录与草稿不能丢失；编辑态与菜单不能误加分或挡住按钮。 |
| 投屏与跨设备显示 | 结束比分按项目选择分/局/盘/等级；补发球方、无占先、补时、九球及 UNO 等协议字段。未发现投屏设备的插图改为向外渐隐实心圆。 | iOS ↔ Android/鸿蒙实机逐步记分、换边、结束、重连；尤其投篮训练六格、六人毽球、四人斗地主、软式网球与掼蛋/升级等级。 |
| 会员、账号与分享 | 会员权益使用对应 SF Symbols；未登录购买的协议行补用户协议；登录后扫 StoreKit 当前权益，补验先购买或兑换后登录的永久会员；分享应用文案扩展为具体场景。 | 沙盒购买/恢复/兑换、不同账号与网络状态、协议链接与会员状态；不要在 Release Note 宣称尚未真机验证的购买可靠性。 |
| 依赖与隐私 | 新增 FirebaseCore 并在启动时 `FirebaseApp.configure()`。当前仓库只见 Firebase 初始化，未见其他 Firebase 产品调用；不再引入仅用于 Watch 的 TelemetryDeck。 | 确认 FirebaseCore 是否确实需要；核对最终包内配置、第三方 SDK 声明及 App Store Connect 隐私回答。此项不写入用户更新说明。 |

## 已完成的本轮只读/低干扰验证

- `swift test --package-path Packages/JifenCore`：**227 个 Swift Testing 用例 + 2 个 XCTest 用例通过**。
- 主应用模拟器单测：**471 项通过，0 失败**；`ScoreboardDisplayTests` 46 项均通过。定向 UI 回归已覆盖四种双打样式元素、拳击加回合与足球补时、斯诺克抬头及样式编辑，相关用例均通过。
- `node scripts/localization/gen_zh_hant.mjs --check`：通过；1426 键、`suspects=0`、`hardErrors=0`。
- `git diff --check` 通过；主应用 plist、Xcode 工程文件与 Firebase 配置均通过 `plutil -lint`。
- Firebase 12.19.2 包已解析完成；移除 Watch 后的当前工作区已通过 `generic/platform=iOS`、`Release`、`CODE_SIGNING_ALLOWED=NO` 构建。构建产物为 **3.2 / build 46**，未发现 Watch 内容，也未链接 WatchConnectivity 或 TelemetryDeck。正式签名 Archive 与实机安装仍待完成。

## 提审门槛与测试顺序

### P0：包、启动、旧数据

1. 以固定提交构建 **Release Archive**；确认只有 iPhone/iPad 主 App，且 target 列表、Embed 阶段、归档内容中均无 Watch App；同时核对 build/version、签名、`GoogleService-Info.plist`、隐私清单及必要资源。安装归档/TestFlight 构建验证，不能以 Debug 模拟器代替。
2. 从 App Store 3.0 覆盖升级至 3.2，再做一次全新安装：启动、协议、登录/退出、首页、记录、设置、计时和主要工具；旧记录、未完赛草稿、常用名称及外观偏好均保留。
3. 跑主应用单测与定向 UI 测试：`ScoreboardDisplayTests`、`LocalScoreboardDisplayStateTests`、`StoreKitPurchaseManager` 相关测试；UI 至少覆盖 `MainFlowUITests` 的 iPad 旋转、菜单再次打开、未完赛条，及 `FullAppScreenshotUITests` 的菜单和编辑态。记录测试设备、系统版本与通过数。

### P0：手机、iPad 实机

4. **iPhone SE2 或同等窄屏真机**：竖屏首页/会员/设置、横屏各类计分板；浅色和深色；编辑态局/盘与两侧数字同行、加减按钮可点；菜单在横竖屏高度正确，打开使用说明、关闭后再次打开仍可点击；滑动撤销与样式编辑不误加分。
5. **iPad 真机**：横屏、竖屏及分屏/Stage Manager 小窗口；上述菜单、编辑态、投屏和会员页均不裁切。特别检查带 4 项操作的比赛菜单、投篮训练菜单，以及“关于我们”弹窗等不同高度内容。
6. **无手表残留检查**：iPhone/iPad 设置、开局弹窗、计分板菜单和恢复入口中均不出现“在手表开始”、手表连接、接管或同步状态；运行期间不加载 `WatchConnectivity.framework`。

### P0：会员与跨设备

7. StoreKit 沙盒/TestFlight：未登录购买月/年/永久、登录后恢复；先在系统兑换优惠码或先购买永久会员再登录，确认后台绑定；取消、失败、网络中断与重试后没有重复权益或假成功。协议勾选、用户协议/自动续费条款/会员协议跳转正确。
8. iOS 控制 → Android/鸿蒙观看，以及反向控制 → iOS 观看：至少覆盖换边后发球和胜者、局/盘/等级结束比分、投篮训练固定/自由六格、四人斗地主、六人毽球、九球、软式网球；每例包含操作中、撤销、手动结束与断线重连。真实 AirPlay/HDMI 另测未检测到设备、连接、投屏中及断开状态。
9. 按既定全能计分器发布门槛，用 **华为 Pura X 或同等折叠屏**检查受影响的 Android/鸿蒙观看页：投篮训练和四人斗地主入口、控制/观看/结束页在内外屏切换及折叠/展开后不裁切；后台恢复与重连保留比分、计时、模式和结束态。跨平台版本提审前记录这项 P0 实机结果。

### 提审材料

10. 核对 App Store Connect 的 iPhone/iPad 截图、版本 3.2 与 build 46、审核账号/购买说明、第三方 SDK 与隐私标签；不要提交 Watch 截图，也不要在元数据中宣称手表或手机手表联动能力。

## App Store「此版本新功能」草稿

以下为**不包含 Apple Watch 功能**的保守版本：

**简体中文**

> 优化球类比赛的计分、计时与跨设备显示，改进 iPad 弹窗、编辑布局和投屏状态；同时完善会员恢复与多语言体验，修复若干问题。

**繁體中文**

> 優化球類比賽的計分、計時與跨裝置顯示，改善 iPad 對話框、編輯版面和投放狀態；同時完善會員恢復與多語言體驗，修正多項問題。

**English**

> This update improves scoring, timers, and cross-device display for sports, refines iPad dialogs and editing layouts, and fixes issues with membership restoration and localization.
