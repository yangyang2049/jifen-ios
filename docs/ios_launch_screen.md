# Launch Screen 说明

## 当前配置

- **背景色**：Asset Catalog 中 `LaunchScreenBackground`（#1a1a1a）。
- **Logo**：Asset Catalog 中 `LaunchScreenLogo`（1x/2x/3x）。
- **Info.plist**：项目根目录 **Info.plist**（与 jifen.xcodeproj 同级）中配置了 `UILaunchScreen`（UIColorName + UIImageName）。主 target 使用 `INFOPLIST_FILE = Info.plist`，与 `GENERATE_INFOPLIST_FILE = YES` 合并，仅生成一份 Info.plist（该文件不在 jifen 目录下，不会被 Copy Resources 重复复制）。

## 如何修改 Logo

1. 替换 **jifen/Assets.xcassets/LaunchScreenLogo.imageset** 中的图片。
2. 或新建 Image Set，在 **Info.plist** 的 `UILaunchScreen.UIImageName` 中改为新名称。

## 使用 Storyboard 方式（可选）

若需要更复杂的布局（多图、多文字），可改用 Launch Screen Storyboard：

1. **File → New → File → Launch Screen**，保存为 `LaunchScreen.storyboard`，放入 jifen 目录。
2. 在 Storyboard 中设计界面（背景、Logo、文字等）。
3. 在 **Target → Info** 中设置 **Launch Screen File** 为 `LaunchScreen.storyboard`（对应 key `UILaunchStoryboardName`）。
4. 需移除 Build Settings 中的 `INFOPLIST_KEY_UILaunchScreen_UIColorName`，避免与 Storyboard 冲突。

当前项目使用 **Build Settings + 颜色资源** 的方式，无需 Storyboard 即可显示纯色启动屏。
