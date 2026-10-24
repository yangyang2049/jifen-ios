# 审计遗留与三端统一扫码复查 · 2026-10-24

## 审计遗留处理

- 原前三项问题（常用数据暂停归属、双订阅续费提示、掼蛋终局编辑）已修复，证据见 [二次复核与修复](uncommitted-review-2026-10-24.md#二次复核与修复)。旧审计标题及建议已明确标记为历史记录。
- 微信授权方向已经用户确认：继续尝试当前 SDK 接口，打不开时按实际安装状态显示“请先安装微信”或请求失败。当前待办是用户真机验收，不是重新决定授权 API。
- 修复英文登录方式显示为 `WeChat Login` 的文案问题：登录方式使用独立的 WeChat／微信名称，登录按钮原有文案保留。英简繁资源回归通过。
- 未跟踪截图、demo 和实现文档保留，没有删除、忽略或提交。

## 两个扫码入口的真实调用链

下列源码路径均相对各自仓库根目录。

| 平台 | 小组入口 | 我的入口 | 共用采集页 |
| --- | --- | --- | --- |
| iOS | 加群 Sheet | 设置／我的扫码 Sheet | `jifen/Features/Scan/QRScanSheet.swift` |
| Android | `GroupJoinScreen` → `QrScanContract(GROUP_JOIN)` | `QrLoginTopBarAction` → `QrScanContract` | `screen/scan/QrScannerActivity.kt` |
| HarmonyOS | `GroupJoinScreen` → `GroupRuntimeEffects.scanGroupCode` | `MeTab.scanWebQrLogin` | `components/QrScanSheet.ets`，经 `QrScanSheetController` 打开 |

安卓在本轮开始前已经共用相机、相册、返回、提示及权限恢复。本轮补齐相册多码识别和按入口优先选码，没有重复创建第二份扫码页。

鸿蒙此前分别调用 ScanKit 原生页面，小组开启相册、“我的”关闭相册且接受全部码型。本轮改为同一组件，统一二维码相机扫描、相册、关闭、提示和相机不可用时的占位；相机不可用仍可选择相册。

## 本轮跨端改动

- **安卓**：`QrImageDecoder` 读取相册中的多个二维码并兼容同图正反色；新增 `QrPhotoSelection`。小组优先邀请码，“我的”优先邀请码或登录码；没有认识的码仍返回首码，由既有业务层显示无效／过期提示。候选偏好不授权业务操作，小组入口仍不能处理登录码。
- **鸿蒙**：新增 `QrScanSheet`、`QrScanCameraSession`、`qrScanSelection`。相册多码采用同样的入口偏好及错误兜底。相机原生操作串行执行；相册、后台、尺寸变化时停止或重启，返回系统设置后重新检查权限。关闭时使回调失效、停止相机并释放组件；页面尚未打开就关闭、打开失败、关闭失败也有清理。
- **鸿蒙调用方**：重复点击只开启一次，页面离开取消扫描；等待扫描或登录 API 期间账号已变化时，旧结果不能继续导航或确认。业务解析仍留在小组与“我的”各自入口。fixture 保留隔离边界，不会因新增取消操作调用原生服务。
- **鸿蒙验收入口**：原有真机验收脚本从 ScanKit 旧页面定位切换到共用页的 `qr_scan_album`／`qr_scan_close` 控件标识，并识别当前应用的相机权限弹窗。七份语言资源各补五个共用扫码文案。
- 独立只读复核已检查真实调用链、权限、相册取消、重复交付及迟到结果。复核发现的早关竞态、组件清理和 fixture 取消接口问题均已修复。

## 本轮验证及边界

| 检查 | 实际结果 |
| --- | --- |
| iOS 账号关联契约与本地化定向测试 | 58 项、0 失败；独立 DerivedData，Xcode 原始退出码 0 |
| iOS 三份修改的 strings | plutil 全过 |
| Android 扫码解码／候选、登录解析／VM 单测 | 20 项全过；Gradle 原始退出码 0 |
| Android 主 app 与 UI 测试 Kotlin | 编译通过；未运行设备 UI 测试 |
| HarmonyOS 扫码相关行为回归 | 6 个脚本通过，覆盖原生边界 mock、实际生产事件方法和调用方时序 |
| HarmonyOS 真机验收脚本单测 | Python 5 项通过；未运行真机操作 |
| HarmonyOS 扫码隔离模块打包 | `entry:assembleHap` 编译、签名和打包通过；原始退出码 0 |
| 三仓库修改格式 | `git diff --check` 通过 |

日志与结果：

- iOS：`/tmp/jifen-scan-parity-ios-20261024.log`、`/tmp/jifen-scan-parity-ios-20261024.xcresult`。
- Android：`/tmp/jifen-android-unified-scan-20261024.log`。
- 鸿蒙回归：`/tmp/jifen-hos-unified-scan-regression.log`。脚本为 `test_unified_qr_scan.mjs`、`test_group_native_scan_cancel.mjs`、`test_me_group_scan.cjs`、`test_group_runtime_boundary.mjs`、`test_group_invitation_links.mjs`、`test_group_dialog_session_isolation.mjs` 及 Python `test_group_native_system_ui.py`。
- 鸿蒙共享树构建：`/tmp/jifen-hos-unified-scan-build.log`。该次构建失败，阻塞于扫码开工后由其他并行工作引入的 `media/nameTranslit.ts:51` 类型错误及语音资源引用，没有将它写为通过。
- 鸿蒙隔离打包：`/tmp/jifen-hos-unified-scan-isolated-build.log`。副本保留账号绑定及扫码修改，仅将开工时未改动的四个并行语音文件恢复到开工基线，并排除当时尚不存在的 `nameTranslit.ts`；当前资源键保留。详细边界记录在 `/tmp/jifen-hos-unified-scan-validation-20261024/SCAN_VALIDATION_PROVENANCE.txt`。原工作区未回退，隔离成功不代表共享树当前整包已通过。

成功打包命令：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon`。最终源码与成功打包副本仅差两个验收用 `.id` 属性，已按字节比较确认；两项标识加入后验收脚本单测通过。

本轮未重新安装任何设备、未发布。先前 iPhone 安装包为审计修复版 3.4（78），不包含本轮新增的英文方式名修复。真实微信往返和安卓／鸿蒙相机、系统权限、相册往返仍需设备验收；自动行为脚本不替代这些设备操作。所有源码修改仍未提交。
