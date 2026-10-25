import AVFoundation
import Foundation
import ScoreCore

/// A popup needs an enabled voice control and at least one visible option.
enum SportsVoiceOptionsPolicy {
    static func canPresent(isVoiceControl: Bool, isVoiceEnabled: Bool, hasServeOption: Bool, appLanguage: String) -> Bool {
        isVoiceControl && isVoiceEnabled && (hasServeOption || appLanguage.hasPrefix("zh"))
    }
}

/// Application language, rather than the device's region, determines spoken content.
/// 播报语言偏好(voiceAnnouncementLanguage)显式选择 zh-CN/en-US 时覆盖 App 语言。
enum SportsVoiceSupport {
    static var localization: String { Bundle.main.preferredLocalizations.first ?? "en" }
    static var language: SportsVoiceLanguage? {
        if let override = UserDefaults.standard.string(forKey: "voiceAnnouncementLanguage"),
           override == "zh-CN" || override == "en-US" {
            let key = override == "zh-CN" ? "zh-Hans" : "en"
            if let match = SportsVoiceLanguage.resolve(localization: key, iosMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
                return match
            }
        }
        return SportsVoiceLanguage.resolve(localization: localization, iosMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    /// "zh-CN"/"en-US" 当前生效值:显式偏好优先,未手动选择时跟随 App 语言。
    static var effectiveAnnouncementLanguageCode: String {
        let override = UserDefaults.standard.string(forKey: "voiceAnnouncementLanguage") ?? "auto"
        if override == "zh-CN" || override == "en-US" { return override }
        return localization.hasPrefix("zh") ? "zh-CN" : "en-US"
    }
    static var isSupported: Bool { language != nil }

    static func voice(for language: SportsVoiceLanguage) -> AVSpeechSynthesisVoice? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestSportsVoiceMissing") { return nil }
        #endif
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard let matched = language.matchedVoiceLanguage(in: voices.map(\.language)) else { return nil }
        // Apple's locale initializer respects its selected/default voice. Verify its region.
        if let preferred = AVSpeechSynthesisVoice(language: matched), preferred.language == matched { return preferred }
        return voices.first { $0.language == matched }
    }

    static func template(_ key: String, language: SportsVoiceLanguage) -> String? {
        guard let path = Bundle.main.path(forResource: language.localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let missing = "__SPORTS_VOICE_MISSING__"
        let value = bundle.localizedString(forKey: key, value: missing, table: "ScoreVoice")
        return value == missing ? nil : value
    }

    static func message(_ payload: VoiceAnnouncementPayload, language: SportsVoiceLanguage, announceServer: Bool = false) -> String? {
        // 英文播报时名字罗马化,避免中文队名/选手名在英文语音里被跳过或乱读。
        let effectivePayload = language.speechLocale.hasPrefix("en") ? NameTransliteration.romanized(payload) : payload
        let message = LocalizedVoiceAnnouncementBuilder.buildReviewed(effectivePayload, localization: language.localization)
        guard let line = message.render(
            locale: Locale(identifier: language.speechLocale),
            template: { template($0, language: language) }
        ) else { return nil }
        guard announceServer, [.pingpong, .pingpongDoubles].contains(payload.gameType),
              [.opening, .scoreChange, .breakResume].contains(payload.phase),
              let side = payload.serverSide, !line.isEmpty else { return line }
        let name = effectivePayload.serverName.flatMap { $0.isEmpty ? nil : $0 }
            ?? (side == .left ? effectivePayload.leftTeamName : effectivePayload.rightTeamName)
        guard !name.isEmpty else { return line }
        return VoiceAnnouncementMessage.phrase("%1$@. %2$@ to serve", [.verbatim(line), .verbatim(name)]).render(
            locale: Locale(identifier: language.speechLocale),
            template: { template($0, language: language) }
        )
    }
}

extension Notification.Name {
    static let sportsVoiceNeedsDownload = Notification.Name("sportsVoiceNeedsDownload")
}
