import Foundation

/// Traditional-channel support for the Chinese announcer.
///
/// The builders emit simplified literals (single code path, aligned with
/// HarmonyOS / Android). For `zh-TW` we post-convert with a curated map of
/// simplified-only glyphs, so Traditional user/team names pass through
/// unchanged. Deliberate exclusions: 台 (measure word stays 台 in Traditional)
/// and 云/系 (context-dependent or identical in Traditional).
public enum VoiceChinesePhrases {
    /// Word-level corrections applied before the character map so the
    /// announcement matches the UI vocabulary in zh-Hant Localizable.strings.
    static let wordOverrides: [(String, String)] = [
        ("间歇", "休息"),
    ]

    /// Simplified-only codepoints present in the announcer vocabulary.
    static let characterMap: [Character: Character] = [
        "两": "兩", "决": "決", "占": "佔", "发": "發", "号": "號", "场": "場",
        "并": "並", "开": "開", "抢": "搶", "择": "擇", "换": "換",
        "时": "時", "暂": "暫", "点": "點", "盘": "盤", "结": "結",
        "继": "繼", "续": "續", "胜": "勝", "获": "獲", "赛": "賽",
        "赢": "贏", "过": "過", "选": "選", "钟": "鍾", "间": "間",
        "须": "須", "领": "領", "黄": "黃",
    ]

    public static func toTraditional(_ text: String) -> String {
        var result = text
        for (from, to) in wordOverrides {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return String(result.map { characterMap[$0] ?? $0 })
    }
}
