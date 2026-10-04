import AVFoundation
import Foundation
import ScoreCore

/// Application language, rather than the device's region, determines spoken content.
enum SportsVoiceSupport {
    static var localization: String { Bundle.main.preferredLocalizations.first ?? "en" }
    static var language: SportsVoiceLanguage? {
        SportsVoiceLanguage.resolve(localization: localization, iosMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
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
        let message = LocalizedVoiceAnnouncementBuilder.buildReviewed(payload, localization: language.localization)
        guard let line = message.render(
            locale: Locale(identifier: language.speechLocale),
            template: { template($0, language: language) }
        ) else { return nil }
        guard announceServer, [.pingpong, .pingpongDoubles].contains(payload.gameType),
              [.opening, .scoreChange, .breakResume].contains(payload.phase),
              let side = payload.serverSide, !line.isEmpty else { return line }
        let name = payload.serverName.flatMap { $0.isEmpty ? nil : $0 }
            ?? (side == .left ? payload.leftTeamName : payload.rightTeamName)
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
