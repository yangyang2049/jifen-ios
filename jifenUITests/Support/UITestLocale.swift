import XCTest

/// Single source for UI-test launch locales. zh-Hant here is the same
/// (language, locale) pair the app resolves to Traditional Chinese.
enum UITestLocale {
    typealias Configuration = (language: String, locale: String)

    static let en = Configuration(language: "en", locale: "en_US")
    static let zhHans = Configuration(language: "zh-Hans", locale: "zh_CN")
    static let zhHant = Configuration(language: "zh-Hant", locale: "zh_TW")
    static let ja = Configuration(language: "ja", locale: "ja_JP")
    static let ko = Configuration(language: "ko", locale: "ko_KR")
    static let de = Configuration(language: "de", locale: "de_DE")
    static let it = Configuration(language: "it", locale: "it_IT")
    static let nl = Configuration(language: "nl", locale: "nl_NL")
    static let sv = Configuration(language: "sv", locale: "sv_SE")
    static let fr = Configuration(language: "fr", locale: "fr_FR")
    static let frCA = Configuration(language: "fr-CA", locale: "fr_CA")
    static let ru = Configuration(language: "ru", locale: "ru_RU")
    static let uk = Configuration(language: "uk", locale: "uk_UA")
    static let esMX = Configuration(language: "es-MX", locale: "es_MX")
    static let esES = Configuration(language: "es-ES", locale: "es_ES")
    static let ptBR = Configuration(language: "pt-BR", locale: "pt_BR")
    static let ptPT = Configuration(language: "pt-PT", locale: "pt_PT")
    static let ar = Configuration(language: "ar", locale: "ar_SA")
    static let he = Configuration(language: "he", locale: "he_IL")
    static let ur = Configuration(language: "ur", locale: "ur_PK")

    static func launchArguments(_ configuration: Configuration) -> [String] {
        [
            "-AppleLanguages", "(\(configuration.language))",
            "-AppleLocale", configuration.locale
        ]
    }

    static func languageValue(_ configuration: Configuration) -> String {
        "(\(configuration.language))"
    }
}
