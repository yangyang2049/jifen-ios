# Localization Review

This document tracks strings that are not localized in the project.

## Summary

The project has a significant number of hardcoded strings that need to be localized. The issues are present in both the iOS (SwiftUI) and HarmonyOS (ArkTS) parts of the codebase.

Common issues include:
- Hardcoded UI strings in Chinese (e.g., "获胜", "局数", "开始比赛"). Many of these already have corresponding keys in the localization files.
- Hardcoded date/time and currency formats (e.g., `"MM月dd日"`, `"¥"`). These should use the user's locale.
- Hardcoded separators in strings (e.g., " vs ", " - ").
- Use of hardcoded emojis for icons, which can lead to inconsistent appearance across platforms. Using SF Symbols or other icon assets is recommended.
- Hardcoded identifiers, prefixes, and values in logic (e.g., `"left"`, `"right"`, `"pingpong_"`).

A systematic effort is needed to go through the identified files and replace the hardcoded strings with localized versions.

## General

- **`GameType.icon`:** The `icon` property in the `GameType` enum (defined in `jifen/Features/Scoreboard/Shared/Types.swift`) returns hardcoded emoji strings for each game type (e.g., "🏓", "🏸", "象棋"). This is the source of the hardcoded icon issue found in multiple views. Replacing these with SF Symbols would provide a more consistent and professional appearance.

## ArkTS / HarmonyOS (.ets files)

The `.ets` files use the `$r('app.string.key')` syntax for localization, which is correct. However, similar to the Swift code, there are several instances of hardcoded strings.

- **`home/HomeTab.ets`:**
    - The locale is hardcoded for date formatting: `now.toLocaleDateString('zh-CN', ...)`.
    - Separators are hardcoded: `" vs "` and `" : "`.
    - Default player names are hardcoded: `['A', 'B', 'C']` and `['P1', 'P2', 'P3', 'P4']`.
    - The layout string `"横版"` ("Landscape") is hardcoded in multiple places.

## jifen/Features/Home/SettingsView.swift

- The `languages` dictionary contains hardcoded language names: `"zh-CN": "中文(简体)"` and `"en": "English"`.
- A hardcoded default value is used for the language display: `Text(languages[selectedLanguage] ?? "中文(简体)")`.
- The developer name is hardcoded: `value: "jifen Team"`.
- The `Toggle` in `ToggleRow` has an empty label `Toggle("", isOn: $isOn)`. While it is hidden with `.labelsHidden()`, providing a descriptive label is better for accessibility.

## jifen/Features/Home/HomeTab.swift

- The date format is hardcoded: `monthDayFormatter.dateFormat = "MM月dd日"`. This should be replaced with a localized date format template.
- The separator " vs " in `title: "\(record.team1Name) vs \(record.team2Name)"` is hardcoded. It should be localized.
- The weekday format is hardcoded: `weekdayFormatter.dateFormat = "EEEE"`.
- The debug message `print("Start timer game: \(selectedTimerGameType?.displayName ?? "Unknown")")` uses a hardcoded "Unknown" string, although a localized `"unknown"` key exists. This is minor as it's a debug message.

## jifen/Features/Home/components/QuickStartGridView.swift

- The icon for the "New Game" card is a hardcoded string: `icon: "➕"`. This should be a system image name (e.g., "plus") for better scalability and to avoid localization issues with the character itself.

## jifen/Features/Home/HomeUtils.swift

- The `getGameStats` function returns a hardcoded string: `return "开始比赛"`. This should be localized.

## jifen/Features/Activity/RecentActivityPage.swift

- The empty state displays a hardcoded emoji: `Text("🧘‍♂️")`.
- The separator " vs " in `Text("\(record.team1Name) vs \(record.team2Name)")` is hardcoded.
- The separator " - " in `Text("\(record.team1FinalScore) - \(record.team2FinalScore)")` is hardcoded.
- The string " wins" is hardcoded in `Text("\(winner == "left" ? record.team1Name : record.team2Name) wins")` and `Text("\(winner) wins")`. The logic also relies on the hardcoded string `"left"`.
- The date formats `"yyyy-MM-dd"` and `"MM-dd"` are hardcoded.
- The `RecordItem` identifiers have hardcoded prefixes: `"s-"` and `"t-"`. While not user-facing, it's a hardcoded string.
- The `Button` in the toolbar to toggle edit mode uses a system image, but has no text label for accessibility. An accessibility label should be added.
- The delete button in edit mode also has no accessibility label.

## jifen/Features/Tools/TenSecondChallengeView.swift

This view contains several hardcoded Chinese strings, even though corresponding keys exist in `Localizable.strings`.

- `Text("误差")`: "Error". Should use `NSLocalizedString("error_label", comment: "")`.
- `Text("秒")`: "Seconds". Should use `NSLocalizedString("seconds", comment: "")`.
- `Text(isRunning ? "停止" : "开始")`: "Stop" / "Start". Should use `NSLocalizedString("stop", comment: "")` and `NSLocalizedString("start", comment: "")`.
- `Text("最佳")`: "Best". Should use `NSLocalizedString("best", comment: "")`.
- `Text("尝试")`: "Attempts". Should use `NSLocalizedString("attempts", comment: "")`.
- `Text("清空")`: "Clear". Should use `NSLocalizedString("clear", comment: "")`.

## jifen/Features/Tools/DateTimeToolView.swift

- The locale for the weekday string is hardcoded to Chinese: `formatter.locale = Locale(identifier: "zh_CN")`. It should use the user's current locale.
- The date format for the weekday is hardcoded: `formatter.dateFormat = "EEEE"`. Using a date format template would be more robust for localization.

## jifen/Features/Tools/AACalculatorView.swift

- The currency symbol "¥" is hardcoded in multiple places. This should be retrieved from the user's locale.
- The stepper buttons use hardcoded `Text("-")` and `Text("+")`. Using system images like "minus" and "plus" would be better for accessibility and consistency.
- A comment `// Show toast: "请输入有效金额"` indicates an unimplemented user-facing message for invalid input. The key `enter_valid_amount` exists and should be used to show an alert or toast to the user.

## jifen/Features/Tools/RandomTeamView.swift

Similar to `TenSecondChallengeView`, this view has many hardcoded Chinese strings with existing localization keys.

- The player selection buttons have hardcoded labels: `"4人"`, `"6人"`, `"8人"`. These should use `NSLocalizedString("players_4", comment: "")`, etc.
- The person emoji `👤` is hardcoded.
- The "Simulate" and "Try Again" buttons use hardcoded text: `"模拟"` and `"再来一次"`. Keys `simulate` and `try_again` exist.
- The status text is updated with several hardcoded strings:
    - `"请将手指放在方块上 (\(touchedIndices.count)/\(numPlayers))"` should use `place_fingers_on_blocks`.
    - `"正在分组..."` should use `grouping_in_progress`.
    - `"分组完成！"` should use `grouping_complete`.
- Team names "A" and "B" are hardcoded.

## jifen/Features/Tools/WhistleToolView.swift

- The long whistle card uses a hardcoded emoji: `Text("📯")`.

## jifen/Features/Tools/FlipCoinView.swift

- The text on the coin faces is hardcoded and includes cultural-specific references: `Text(isEnglish ? "8" : "666")` and `Text("❀")`. These should be configurable or use symbols that are more universally understood.
- The "Recent Flips" title is hardcoded: `Text("Recent Flips")`. This string is currently not visible in the UI.

## jifen/Features/Home/components/ProToolsSectionView.swift

- The icons for the tools are hardcoded emojis: `"🔊"`, `"🪙"`, `"🎲"`, `"👥"`, `"🟨"`. Using SF Symbols would provide a more consistent and professional look.

## jifen/Features/Tools/ToolDefinitions.swift

- This file defines the emojis for the tool icons. As noted in other files, these are hardcoded.
- There is an inconsistency in the whistle icon. `ProToolsSectionView` uses `"🔊"`, while `ToolDefinitions.swift` uses `"🔔"`.
- The list of hardcoded emojis: `"🪙"`, `"🎲"`, `"🔔"`, `"👥"`, `"🟨"`, `"🕐"`, `"💰"`, `"⏱️"`.

## jifen/Features/Scoreboard/Sports/PingPong/PingPongScoreboardView.swift

- Toast messages are hardcoded:
    - `"已撤销"` ("Cancelled"). Should use `NSLocalizedString("undone", comment: "")`.
    - A complex string for set end results: `"第\(data.setNumber)局结束，\(data.winnerName)获胜，比分 \(data.finalLeftScore)-\(data.finalRightScore)"`. Should use `NSLocalizedString("set_ended_winner", comment: "")` with format specifiers.
    - `"换边"` ("Change Sides"). Should use `NSLocalizedString("change_sides", comment: "")`.
    - `"请手动换边"` ("Please change sides manually"). Should use `NSLocalizedString("please_change_sides_manually", comment: "")`.
- Rest countdown message is hardcoded: `"局间休息"` ("Set Break"). Should use `NSLocalizedString("set_break", comment: "")`.
- The record ID has a hardcoded prefix: `"pingpong_"`.
- The `winner` property is set to hardcoded strings `"left"` or `"right"`.

## jifen/Features/Scoreboard/ScoreboardTab.swift

- The emojis for the sports icons are hardcoded: `"🏓"`, `"🏸"`, `"🎾"`, `"🏀"`, `"⚽"`, `"🏐"`.
- The placeholder views for unimplemented sports (`Basketball`, `Football`, `Volleyball`) contain hardcoded text combined with a localized key, e.g., `Text("\(GameType.basketball.displayName) \(NSLocalizedString("not_implemented", comment: "Not implemented"))")`. The combination should be done within a localized string format for better grammar and flexibility.

## jifen/Features/Scoreboard/Shared/GameFinishedOverlay.swift

- The "wins" string is hardcoded: `Text("\(winnerName) 获胜")`. It should use the `winner_wins` localized key.
- The preview uses a hardcoded Chinese team name: `"红队"`.

## jifen/Features/Scoreboard/Sports/Badminton/BadmintonScoreboardView.swift

This view has many of the same hardcoded string issues as `PingPongScoreboardView`.

- **Main View:**
    - The navigation title is hardcoded: `.navigationTitle("羽毛球")`.
    - Toast messages are hardcoded: `"已撤销"`, `"第...局结束..."`, `"换边"`, `"请手动换边"`.
    - Rest countdown messages are hardcoded: `"局间休息"` and `"中场休息"`.
    - Record ID has a hardcoded prefix: `"badminton_"`.
    - `winner` is set to hardcoded strings `"left"` or `"right"`.
- **Settings Sheet:**
    - The navigation title is hardcoded: `"羽毛球设置"`.
    - `Text("局数")`, `Picker("局数", ...)`
    - `Text("3局2胜")`, `Text("5局3胜")`
    - `Text("每局分数")`, `Picker("每局分数", ...)`
    - `Text("21分")`, `Text("11分")`
    - `Text("自动换边")`
    - `Text("开始比赛")`
    - All of these have corresponding keys in `Localizable.strings` that should be used.
