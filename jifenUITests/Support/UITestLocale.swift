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

    static let ca = Configuration(language: "ca", locale: "ca_ES")
    static let pl = Configuration(language: "pl", locale: "pl_PL")
    static let ro = Configuration(language: "ro", locale: "ro_RO")
    static let cs = Configuration(language: "cs", locale: "cs_CZ")
    static let sk = Configuration(language: "sk", locale: "sk_SK")
    static let sl = Configuration(language: "sl", locale: "sl_SI")
    static let hr = Configuration(language: "hr", locale: "hr_HR")
    static let da = Configuration(language: "da", locale: "da_DK")
    static let nb = Configuration(language: "nb", locale: "nb_NO")
    static let fi = Configuration(language: "fi", locale: "fi_FI")
    static let hu = Configuration(language: "hu", locale: "hu_HU")
    static let el = Configuration(language: "el", locale: "el_GR")
    static let hi = Configuration(language: "hi", locale: "hi_IN")
    static let bn = Configuration(language: "bn", locale: "bn_IN")
    static let mr = Configuration(language: "mr", locale: "mr_IN")
    static let gu = Configuration(language: "gu", locale: "gu_IN")
    static let pa = Configuration(language: "pa", locale: "pa_IN")
    static let ta = Configuration(language: "ta", locale: "ta_IN")
    static let te = Configuration(language: "te", locale: "te_IN")
    static let kn = Configuration(language: "kn", locale: "kn_IN")
    static let ml = Configuration(language: "ml", locale: "ml_IN")
    static let or = Configuration(language: "or", locale: "or_IN")
    static let tr = Configuration(language: "tr", locale: "tr_TR")
    static let vi = Configuration(language: "vi", locale: "vi_VN")
    static let th = Configuration(language: "th", locale: "th_TH")
    static let id = Configuration(language: "id", locale: "id_ID")
    static let ms = Configuration(language: "ms", locale: "ms_MY")

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
