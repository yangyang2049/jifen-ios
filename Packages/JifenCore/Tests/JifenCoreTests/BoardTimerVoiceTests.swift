import Foundation
import Testing
import TimerCore

@Suite struct BoardTimerVoiceTests {
    @Test func resolvedSoundNameUsesEnSuffix() {
        #expect(BoardTimerVoice.resolvedSoundName("start", isEnglish: false) == "start")
        #expect(BoardTimerVoice.resolvedSoundName("start", isEnglish: true) == "start_en")
        #expect(BoardTimerVoice.resolvedSoundName("last_seconds", isEnglish: true) == "last_seconds_en")
    }

    @Test func postStartDelayMatchesHarmony() {
        #expect(BoardTimerVoice.postStartPlayerAnnouncementDelayMs(isEnglish: false) == 864 + 600)
        #expect(BoardTimerVoice.postStartPlayerAnnouncementDelayMs(isEnglish: true) == 648 + 600)
    }

    @Test func byoyomiPhraseUsesLastOnlyOnFinalPeriod() {
        #expect(BoardTimerVoice.byoyomiPhrase(periodsRemaining: 3) == .startSeconds)
        #expect(BoardTimerVoice.byoyomiPhrase(periodsRemaining: 2) == .startSeconds)
        #expect(BoardTimerVoice.byoyomiPhrase(periodsRemaining: 1) == .lastSeconds)
    }

    @Test func englishLocaleDetection() {
        #expect(BoardTimerVoice.isEnglishLocale(Locale(identifier: "en_US")) == true)
        #expect(BoardTimerVoice.isEnglishLocale(Locale(identifier: "en-GB")) == true)
        #expect(BoardTimerVoice.isEnglishLocale(Locale(identifier: "zh_CN")) == false)
        #expect(BoardTimerVoice.isEnglishLocale(Locale(identifier: "zh-Hans")) == false)
    }

    /// Lock: zh-Hant keeps the Mandarin recordings (design decision, not a bug).
    @Test func traditionalChineseKeepsMandarinClips() {
        #expect(BoardTimerVoice.isEnglishLocale(Locale(identifier: "zh-Hant-TW")) == false)
        #expect(BoardTimerVoice.resolvedSoundName("start", locale: Locale(identifier: "zh-Hant-TW")) == "start")
        #expect(BoardTimerVoice.resolvedSoundName("last_seconds", locale: Locale(identifier: "zh-Hant-HK")) == "last_seconds")
    }

    @Test func timeoutSoundResolvesLikeOtherControlClips() {
        #expect(BoardTimerVoice.resolvedSoundName(BoardTimerVoice.timeoutSoundBaseName, isEnglish: false) == "timeout")
        #expect(BoardTimerVoice.resolvedSoundName(BoardTimerVoice.timeoutSoundBaseName, isEnglish: true) == "timeout_en")
    }

    @Test func standaloneCountdownUsesNeutralDingClip() {
        #expect(BoardTimerVoice.countdownCompletionSoundBaseName == "ding")
    }
}
