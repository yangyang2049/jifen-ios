import Foundation
import Testing
import TimerCore

@Suite struct BoardTimerVoiceTests {
    @Test func playerColorMappingMatchesHarmony() {
        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "go", playerID: 1) == .black)
        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "go", playerID: 2) == .white)

        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "xiangqi", playerID: 1) == .red)
        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "xiangqi", playerID: 2) == .black)

        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "chess", playerID: 1) == .white)
        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "chess", playerID: 2) == .black)

        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "checkers", playerID: 1) == .red)
        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "checkers", playerID: 2) == .black)

        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "go", playerID: 3) == nil)
        #expect(BoardTimerVoice.playerColorSound(gameTypeRawValue: "football", playerID: 1) == nil)
    }

    @Test func resolvedSoundNameUsesEnSuffix() {
        #expect(BoardTimerVoice.resolvedSoundName("start", isEnglish: false) == "start")
        #expect(BoardTimerVoice.resolvedSoundName("start", isEnglish: true) == "start_en")
        #expect(BoardTimerVoice.resolvedSoundName("last_seconds", isEnglish: true) == "last_seconds_en")
        #expect(BoardTimerVoice.resolvedSoundName("black", isEnglish: false) == "black")
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

    @Test func timeoutSoundResolvesLikeOtherControlClips() {
        #expect(BoardTimerVoice.resolvedSoundName(BoardTimerVoice.timeoutSoundBaseName, isEnglish: false) == "timeout")
        #expect(BoardTimerVoice.resolvedSoundName(BoardTimerVoice.timeoutSoundBaseName, isEnglish: true) == "timeout_en")
    }
}
