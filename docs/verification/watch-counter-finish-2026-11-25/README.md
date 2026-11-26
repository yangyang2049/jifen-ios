# 手表计数器：结束＝保存后归零（2026-11-25）

## 现象

工具 → 计数器点「结束」时，保存记录后直接退出到工具列表；和左上角返回重复，想连打几组还得重新进入。

## 改动

- `jifenWatch Watch App/Tools/WatchCounterView.swift`：`结束` 改为「保存本次计数 → 归零 → 留在本页开始下一次」；
  计数为 0 时不写空记录；退出仍由左上角返回（右滑返回手势保留）。
- 结束确认文案同步为「将结束并保存本次计数，然后从 0 重新开始。」（en / zh-Hans / zh-Hant 三语）。

## 验证

```
xcodebuild test -project jifen.xcodeproj -scheme jifenWatchUITests \
  -destination 'platform=watchOS Simulator,id=<Apple Watch SE 3 44mm>' \
  -only-testing:"jifenWatch Watch AppUITests/WatchCounterUITests"
```

`testFinishSavesAndResetsCountInPlace` 通过：点屏 3 次 → 结束 → 确认 → 数字归零、仍停留在「计数器」页
（未退回工具列表），再到「记录」页能看到这次计数器记录。

截图：`counter-3-before-finish.png`、`counter-reset-in-place.png`、`counter-record-saved.png`。
