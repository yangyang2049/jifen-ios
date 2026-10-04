import Foundation

/// Product support and speech-region mapping; deliberately independent of installed voices.
public struct SportsVoiceLanguage: Equatable, Sendable {
    public let localization: String
    public let speechLocale: String
    public let minimumIOSMajorVersion: Int

    public static let all: [Self] = [
        .init(localization: "en", speechLocale: "en-US", minimumIOSMajorVersion: 26),
        .init(localization: "zh-Hans", speechLocale: "zh-CN", minimumIOSMajorVersion: 26),
        .init(localization: "zh-Hant", speechLocale: "zh-TW", minimumIOSMajorVersion: 26),
        .init(localization: "fr", speechLocale: "fr-FR", minimumIOSMajorVersion: 26),
        .init(localization: "fr-CA", speechLocale: "fr-CA", minimumIOSMajorVersion: 26),
        .init(localization: "es-ES", speechLocale: "es-ES", minimumIOSMajorVersion: 26),
        .init(localization: "es-MX", speechLocale: "es-MX", minimumIOSMajorVersion: 26),
        .init(localization: "pt-PT", speechLocale: "pt-PT", minimumIOSMajorVersion: 26),
        .init(localization: "pt-BR", speechLocale: "pt-BR", minimumIOSMajorVersion: 26),
    ] + [
        ("ar", "ar-SA"), ("bn", "bn-IN"), ("ca", "ca-ES"), ("cs", "cs-CZ"),
        ("da", "da-DK"), ("de", "de-DE"), ("el", "el-GR"), ("fi", "fi-FI"),
        ("he", "he-IL"), ("hi", "hi-IN"), ("hr", "hr-HR"), ("hu", "hu-HU"),
        ("id", "id-ID"), ("it", "it-IT"), ("ja", "ja-JP"), ("kn", "kn-IN"),
        ("ko", "ko-KR"), ("mr", "mr-IN"), ("ms", "ms-MY"), ("nb", "nb-NO"),
        ("nl", "nl-NL"), ("pl", "pl-PL"), ("ro", "ro-RO"), ("ru", "ru-RU"),
        ("sk", "sk-SK"), ("sl", "sl-SI"), ("sv", "sv-SE"), ("ta", "ta-IN"),
        ("te", "te-IN"), ("th", "th-TH"), ("tr", "tr-TR"), ("uk", "uk-UA"), ("vi", "vi-VN"),
    ].map { .init(localization: $0.0, speechLocale: $0.1, minimumIOSMajorVersion: 26) }
      + [("gu", "gu-IN"), ("ml", "ml-IN"), ("or", "or-IN"), ("pa", "pa-IN")]
        .map { .init(localization: $0.0, speechLocale: $0.1, minimumIOSMajorVersion: 27) }

    public static func resolve(localization: String, iosMajorVersion: Int) -> Self? {
        let normalized = localization.replacingOccurrences(of: "_", with: "-")
        let locale = Locale(identifier: normalized)
        let base = locale.language.languageCode?.identifier ?? normalized
        let key: String
        switch base {
        case "zh": key = locale.language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
        case "fr": key = locale.region?.identifier == "CA" ? "fr-CA" : "fr"
        case "es": key = locale.region?.identifier == "MX" ? "es-MX" : "es-ES"
        case "pt": key = locale.region?.identifier == "BR" ? "pt-BR" : "pt-PT"
        case "no": key = "nb"
        default: key = base
        }
        return all.first { $0.localization == key && iosMajorVersion >= $0.minimumIOSMajorVersion }
    }

    /// Never substitute another dialect for these individually localized product variants.
    public func matchedVoiceLanguage(in available: [String]) -> String? {
        if available.contains(speechLocale) { return speechLocale }
        if ["fr", "fr-CA", "es-ES", "es-MX", "pt-PT", "pt-BR", "zh-Hans", "zh-Hant"].contains(localization) { return nil }
        let base = speechLocale.split(separator: "-").first.map(String.init) ?? speechLocale
        return available.sorted().first { $0.split(separator: "-").first.map(String.init) == base }
    }
}

/// Runtime protection also applies to persisted voice-enabled matches.
/// Availability is supplied afresh, so installing a voice needs no app restart.
public struct SportsVoiceSessionGate: Sendable {
    public enum Decision: Equatable, Sendable {
        case unsupported
        case missingVoice(showDownloadGuide: Bool)
        case ready
    }
    private var sessionID = UUID()
    private var notifiedSessions: Set<UUID> = []
    public init() {}

    @discardableResult
    public mutating func beginSession(_ id: UUID) -> Bool {
        guard sessionID != id else { return false }
        sessionID = id
        return true
    }

    public mutating func evaluate(language: SportsVoiceLanguage?, voiceAvailable: Bool) -> Decision {
        guard language != nil else { return .unsupported }
        guard voiceAvailable else {
            let shouldNotify = notifiedSessions.insert(sessionID).inserted
            return .missingVoice(showDownloadGuide: shouldNotify)
        }
        return .ready
    }
}
