import Foundation

/// Pure board-timer voice helpers aligned with Harmony `soundManager` / `gameTimerViewModel`.
///
/// Wired clips (same as Harmony `SoundType`): start/pause/resume/stop/end,
/// start_seconds / last_seconds. Locale-aware names append `_en` where Harmony has an English asset.
///
/// Player switch cues intentionally do NOT announce colors ("红方/黑方/白方"):
/// the Android board timer has no color announcements, so both platforms play the
/// neutral `ding` clip (Android `res/raw/ding.mp3`, byte-identical on iOS).
///
/// Bundle also contains Harmony rawfile leftovers `one`…`ten` that are **not** in Harmony
/// `SoundType` / board-timer playback — keep for asset parity, do not announce from DualPlayer.
/// `timeout` is used by the standalone countdown tool (Harmony `CountdownPage`), not board timers.
public enum BoardTimerVoice {
    public enum ControlSound: String, Sendable {
        case start
        case pause
        case resume
        case stop
        case end
    }

    public enum ByoyomiPhrase: String, Sendable {
        case startSeconds = "start_seconds"
        case lastSeconds = "last_seconds"
    }

    /// Harmony countdown-end clip (`SoundType.TIMEOUT`).
    public static let timeoutSoundBaseName = "timeout"
    /// Neutral standalone countdown completion clip shared by all locales.
    public static let countdownCompletionSoundBaseName = "ding"

    /// Harmony `START_SOUND_DURATION_MS` / `START_SOUND_DURATION_MS_EN`
    public static let startDurationMsZh = 864
    public static let startDurationMsEn = 648
    /// Harmony `PLAYER_ANNOUNCEMENT_AFTER_START_EXTRA_DELAY_MS`
    public static let postStartExtraDelayMs = 600

    public static func isEnglishLocale(_ locale: Locale = .current) -> Bool {
        if let code = locale.language.languageCode?.identifier {
            return code.hasPrefix("en")
        }
        return locale.identifier.lowercased().hasPrefix("en")
    }

    public static func resolvedSoundName(_ baseName: String, isEnglish: Bool) -> String {
        isEnglish ? "\(baseName)_en" : baseName
    }

    public static func resolvedSoundName(_ baseName: String, locale: Locale = .current) -> String {
        resolvedSoundName(baseName, isEnglish: isEnglishLocale(locale))
    }

    public static func postStartPlayerAnnouncementDelayMs(isEnglish: Bool) -> Int {
        (isEnglish ? startDurationMsEn : startDurationMsZh) + postStartExtraDelayMs
    }

    public static func postStartPlayerAnnouncementDelayMs(locale: Locale = .current) -> Int {
        postStartPlayerAnnouncementDelayMs(isEnglish: isEnglishLocale(locale))
    }

    /// Go byoyomi period-start phrase. `periodsRemaining == 1` → last period.
    public static func byoyomiPhrase(periodsRemaining: Int) -> ByoyomiPhrase {
        periodsRemaining == 1 ? .lastSeconds : .startSeconds
    }
}
