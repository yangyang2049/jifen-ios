# 全能计分器 · Apple Watch 竖屏宣传片（2026-11-26）

- 成片：`watch-promo-zh-Hans.mp4`（1080×1920，30 fps，15 秒，H.264 + AAC）
- 封面：`watch-promo-zh-Hans-poster.png`（第 6.2 秒，点按记分瞬间）
- 合成脚本：[`scripts/compose_watch_promo_video.py`](../../scripts/compose_watch_promo_video.py)
- 素材采集：[`WatchPromoVideoCaptureUITests`](../../jifenWatch%20Watch%20AppUITests/WatchPromoVideoCaptureUITests.swift)

## 分镜（120 BPM，镜头切换都落在拍点上）

| 时间 | 镜头 | 主标题 / 副标题 | 屏幕内容 |
| --- | --- | --- | --- |
| 0–2.5 s | 手表自下方升入、回正 | 比分，戴在手腕上 / 全能计分器 · Apple Watch 版 | 计分首页 |
| 2.5–5.0 s | 手表略退，8 个 3D 运动图标依次弹出环绕 | 多项运动，抬腕即开赛 / 羽毛球 · 网球 · 乒乓球 · 台球 · 射箭 · 足球 | 首页项目列表平滑滚动到「足球」 |
| 5.0–8.0 s | 推近到计分板 | 轻点一下，比分 +1 / 左右半屏各管一方，单手也能记 | 乒乓球 8:7 → 9:7 → 9:8 → 10:8 → 10:9，每拍一次点按涟漪 + 「+1」 |
| 8.0–9.0 s | 拿下首局 | 自动判局，专心比赛 / 拿下一局，自动进入局间休息 | 局间休息 01:00 浮层 |
| 9.0–11.0 s | 中景快剪，每 0.5 s 屏内横推 | 每项运动，专属计分板 | 羽毛球 9:7 · 网球 30:15 · 八球 3:2 · 足球 2:1（底部项目标签） |
| 11.0–13.0 s | 手表退场，手机 + 手表联动图升入 | 与 iPhone 实时同步 / 手腕上记分，手机上同步显示 | `WatchLinkIntroArtwork-zh-Hans` |
| 13.0–15.0 s | 片尾 | App 图标 · 全能计分器 · 现已支持 Apple Watch · App Store 搜索「全能计分器」 | — |

## 素材来源

- 手表画面全部来自真实 App：Apple Watch Ultra 4（49mm）模拟器，watchOS 27.2，简体中文。首页滚动镜头由 7 张逐步滚动的真实截图按逐行比对得出的精确偏移（175–177 px）拼接后平移生成；模拟器录屏在数码表冠滚动时只写入少量关键帧，不能直接使用。
- 机身：Apple Design Resources「AW Ultra 4 - Natural + Ocean Band Translucent Gray」，仅做合成，不重绘。
- 配乐与音效：脚本用 numpy 合成（C–G–Am–F 分解和弦、鼓组、点按音、转场音），无第三方版权音乐。整合响度约 -14 LUFS。

## 复现

```bash
python3 scripts/test_artifacts.py new-run watch-promo-video --active   # 记下批次路径 $B
xcrun simctl uninstall <Ultra4-UDID> com.douhua.jifen.ios.watchkitapp
xcodebuild test -project jifen.xcodeproj -scheme jifenWatchUITests \
  -destination "platform=watchOS Simulator,id=<Ultra4-UDID>" \
  -resultBundlePath "$B/promo.xcresult" \
  "-only-testing:jifenWatch Watch AppUITests/WatchPromoVideoCaptureUITests"
xcrun xcresulttool export attachments --path "$B/promo.xcresult" --output-path "$B/att"
# 按 manifest.json 把附件改名为 promo_XX_<name>.png 放入 $B/shots
python3 scripts/compose_watch_promo_video.py --shots-dir "$B/shots" \
  --output marketing/watch-promo-2026-11-26/watch-promo-zh-Hans.mp4 \
  --poster marketing/watch-promo-2026-11-26/watch-promo-zh-Hans-poster.png --poster-time 6.2
# 只看关键帧：追加 --preview 0.6 3.4 6.15 8.3 9.8 11.8 14.2
```

原始截图与 xcresult 存放在 `~/Library/Developer/jifen-ios-test-artifacts/runs/` 的临时批次中，会按保留策略过期清理。
