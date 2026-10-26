# ITMS-90208：微信框架最低系统版本修复

日期：2026-10-25。目标版本：iOS 3.4，构建号由 78 增至 79。

## 根因

用户提供的 Apple 错误指向 `jifen.app/Frameworks/WechatOpenSDK.framework`。已检查实际失败归档：

`/Users/yangyang/Library/Developer/Xcode/Archives/2026-10-25/jifen 2026-10-25, 20.13.xcarchive`

| 对象 | Info.plist MinimumOSVersion | Mach-O 最低版本 |
| --- | --- | --- |
| jifen.app | 26.0 | 26.0 |
| WechatOpenSDK.framework | **12.0** | **26.0** |

SPM 锁定的 WechatOpenSDK 2.0.7 原始文件是静态 archive。Xcode 27.1 的复制任务使用 `-remove-static-executable`，为嵌入包生成 `__text` 大小为 0 的动态占位文件；该占位文件按 App 的 iOS 26 构建，却保留了原 SDK 的 iOS 12 声明。版本声明低于实际二进制要求，符合此次 ITMS-90208 的具体错误。

原失败归档及 SPM 缓存均保留原样，旧 78 不能作为本次修复包继续上传。

## 修复

- 新增 `scripts/normalize_wechat_framework_metadata.py`，读取嵌入框架各架构 Mach-O 的实际最低版本；仅在声明低于二进制要求时校正 `MinimumOSVersion`，不硬编码 iOS 26。
- App 的 Debug／Release 增加末尾构建阶段 `Normalize WeChat Framework Metadata`，依赖已复制的微信框架；App 最终签名前完成校正，并用 Xcode 当前签名身份重新签名、验证框架。
- 仅 App target 的构建脚本沙箱设为 NO，供可信仓库脚本更新构建产物并重签；运行时 App Sandbox、其他 entitlement 与依赖版本保持原配置。
- 脚本带 `--check-only` 只读校验模式；不能解析 Mach-O 或缺少必要签名身份时让构建失败，不猜测最低版本。
- 构建号升级到 79，市场版本保持 3.4。

## 验证

| 项目 | 结果 |
| --- | --- |
| 原失败归档只读检查 | 正确报出 plist 12.0／Mach-O 26.0，不修改原包 |
| 原框架临时副本集成验证 | 校正为 26.0、重新签名、严格签名检查通过 |
| 脚本回归 | 6/6，通过多架构最大版本、幂等、原字段保留、只读拒绝、签名要求与未知身份保护 |
| 新 Release Archive | `ARCHIVE SUCCEEDED`，3.4（79） |
| 分发导出 | `EXPORT SUCCEEDED`，Apple Distribution 签名 |
| 新归档与导出 IPA | 微信框架声明／Mach-O 均为 26.0；App 与全部嵌套签名严格检查通过 |
| 发布权限 | `get-task-allow=false`，APNs production、Apple 登录、Universal Link 均保留 |
| 微信代码 | App 二进制仍含 WXApi，SPM 原始声明仍为 12.0，未修改 SDK 缓存 |
| 微信相关 iOS 单测 | 56/56，0 跳过、0 失败；包含 URL 回调、授权、绑定、账号关联会话与登录 |

Apple 分发包验证接口已通过（退出码 0）：`No errors validating archive`。见 [Apple 验证回执](apple-validation.json) 与 [完整摘要](summary.json)。新包尚未重新上传，未提交 App Review 或发布。

## 产物与证据

- 新归档：`/Users/yangyang/Library/Developer/Xcode/Archives/2026-10-25/jifen 3.4 (79) WeChat fixed.xcarchive`
- 新 IPA：`build/itms-90208-2026-10-25/app-store/jifen.ipa`
- IPA SHA-256：`f9ef0625575f4f75601eb4c91e9a5baafbb6b4ada51a35f5c3418dc2be3b67de`
- 本地包校验：`build/itms-90208-2026-10-25/local-verification.json`
- 归档日志：`/tmp/jifen-itms90208-archive-20261025.log`
- 导出日志：`/tmp/jifen-itms90208-export-20261025.log`
- 单测结果：`/tmp/jifen-itms90208-wechat-20261025.xcresult`
- Apple 包验证日志：`/tmp/jifen-itms90208-apple-validation-20261025.log`

复跑命令：

```bash
python3 -m unittest discover -s scripts -p 'test_normalize_wechat_framework_metadata.py' -v
python3 scripts/normalize_wechat_framework_metadata.py /path/to/jifen.app/Frameworks/WechatOpenSDK.framework --check-only
```

背景：[Apple MinimumOSVersion 说明](https://developer.apple.com/documentation/bundleresources/information-property-list/minimumosversion)。本次针对已确认的 SDK 包声明修正，未变更 App 的最低 iOS 支持版本。
