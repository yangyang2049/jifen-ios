import XCTest

/// Single source for UI-test launch locales. zh-Hant here is the same
/// (language, locale) pair the app resolves to Traditional Chinese.
enum UITestLocale {
    typealias Configuration = (language: String, locale: String)

    static let en = Configuration(language: "en", locale: "en_US")
    static let zhHans = Configuration(language: "zh-Hans", locale: "zh_CN")
    static let zhHant = Configuration(language: "zh-Hant", locale: "zh_TW")

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
