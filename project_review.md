# Project Review: Bugs and Incompleteness

This document summarizes potential bugs, inconsistencies, and incomplete features found during a review of the project.

## Summary

The project is a functional score-keeping application with a variety of tools. However, there are several areas that need attention to improve code quality, user experience, and feature completeness. The main issues are:

- **Incomplete Features**: Some scoreboards are not fully functional due to build errors in their view models.
- **Error Handling**: Many errors are either silently ignored (empty `catch` blocks) or just printed to the console, which is not ideal for a production application.
- **Potential Crashes**: There are a few instances of force unwrapping optionals that could lead to crashes.
- **UI/UX Inconsistencies**: The UI has some inconsistencies in styling and uses emojis for icons, which can look unprofessional and render differently on various platforms. (IGNORE BY NOW, REVIEW LATER)
- **Code Quality**: There is some code duplication and hardcoded values that could be refactored for better maintainability.

## Bugs and Potential Crashes

### 1. Force Unwrapping Optionals

There are a few places where force unwrapping is used, which could lead to a crash if the optional is `nil`.

-   **`jifen/Features/Scoreboard/Records/ScoreboardRecordsViewModel.swift`**:
    -   `groups[date]!.sorted(...)`: A dictionary value is force-unwrapped. While it seems to be safe within the current logic, it is a potential crash point if the logic changes.
-   **`jifen/Features/Tools/RandomTeamView.swift`**:
    -   `animationColors.randomElement()!`: Force-unwrapping the result of `randomElement()`. This will crash if the `animationColors` array is empty.
    -   `teamColors[team]!`: A dictionary value is force-unwrapped.
-   **`jifen/Features/Activity/RecentActivityPage.swift`**:
    -   `Calendar.current.date(byAdding: .day, value: -1, to: Date())!`: This force unwraps the result of a date calculation, which could fail in theory.

### 2. Error Handling

The project has a significant number of empty `catch` blocks, which means errors are silently ignored. This can lead to unexpected behavior and makes debugging difficult.

-   **Empty `catch` blocks are found in:**
    -   `jifenWatch Watch App/Managers/WatchSoundManager.swift`
    -   `jifenWatch Watch App/Managers/WatchRecordManager.swift`
    -   `jifen/Features/Scoreboard/Shared/BaseScoreboardController.swift`
    -   `jifen/Features/Scoreboard/Records/ScoreboardRecordManager.swift`
    -   `jifen/Core/Managers/SoundManager.swift`
-   **Console Logging for Errors**: In many `.ets` files, errors are simply logged to the console (e.g., `console.error(...)`). For a production app, user-facing error messages should be shown.

## Incomplete Features

-   **Basketball and Football Scoreboards**: The `BasketballViewModel.swift` and `FootballViewModel.swift` files had build errors that I have now fixed. However, the fact that they were broken suggests that the basketball and football scoreboards may not have been fully tested and might contain other bugs.
-   **Unimplemented Sports**: In `ScoreboardTab.swift`, `Basketball`, `Football`, and `Volleyball` were previously pointing to a "not implemented" view. While they now point to their respective scoreboard views, the prior state indicates they might be less mature than the other sports features.
-   **Missing Toast Message**: In `AACalculatorView.swift`, there is a commented-out `// Show toast: "请输入有效金额"` which indicates a missing user-facing message for invalid input.

## UI/UX Inconsistencies and Issues

-   **Iconography**: The project heavily relies on hardcoded emojis for icons (e.g., "🏓", "🏸", "🔊", "🪙", "🎲").
    -   This leads to an inconsistent visual style.
    -   The rendering of emojis can vary significantly across platforms and OS versions.
    -   Using a consistent icon set like SF Symbols would provide a more professional and uniform user experience.
    -   There's an inconsistency with the whistle icon: `ProToolsSectionView` uses "🔊", while `ToolDefinitions.swift` uses "🔔".
-   **Card Style**: The "New Game" card in the quick start grid had a different style from the other cards. I have fixed this for the `.ets` version, but the issue still exists in the SwiftUI version (`jifen/Features/Home/components/QuickStartGridView.swift`).
-   **Hardcoded Formats**: Date and currency formats are hardcoded in several places (e.g., `"MM月dd日"`, `"¥"`). These should be based on the user's locale to provide a native experience.
-   **Accessibility**: Some buttons with system images lack accessibility labels, making them difficult to use for users who rely on screen readers.

## Code Quality

-   **Code Duplication**: As seen in the fix for `BasketballViewModel.swift` and `FootballViewModel.swift`, the inability to override methods in the base view model led to code duplication. The base classes could be designed to be more extensible.
-   **Hardcoded Values**: Beyond localization strings, there are other hardcoded values like team names for previews, record ID prefixes, and logical values like `"left"` and `"right"` for the winner. These should be defined as constants or enums.
-   **Mixed Languages in Code**: Some files contain a mix of English and Chinese in comments and string literals, which can make maintenance harder.
