# 友盟 iOS 集成说明

## 当前配置

- CocoaPods：`UMCommon 7.6.4`
- 间接依赖：`UMDevice 3.6.0`
- 渠道：`App Store`
- Bundle ID：`com.douhua.jifen.ios`
- iOS AppKey：已配置到 Debug 和 Release 的 `UMENG_APP_KEY` Build Setting
- 仅在用户接受当前版本的《用户协议》和《隐私政策》后初始化
- 已关闭当前版本不使用的 Apple Search Ads 与 SKAdNetwork 归因能力
- UI 自动化测试不会初始化友盟，避免污染正式统计数据

## 首次拉取工程

```bash
pod install
open jifen.xcworkspace
```

此后请使用 `jifen.xcworkspace`，不要再直接打开 `jifen.xcodeproj`。

## AppKey 配置位置

如需更换 AppKey，请同时修改 `jifen` Target 的 Debug 和 Release Build Settings：

```text
UMENG_APP_KEY = 你的 iOS AppKey
```
