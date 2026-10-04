import Foundation

nonisolated enum FeedbackLanguage {
    static var current: String { normalize(Bundle.main.preferredLocalizations.first ?? "en") }
    private static let supported: Set<String> = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "fr-CA", "es-MX", "es-ES", "pt-BR", "pt-PT", "ar", "he", "ur", "ru", "uk", "pl", "tr", "it", "nl", "id", "vi", "th", "hi", "bn", "gu", "kn", "ml", "mr", "or", "pa", "ta", "te", "ca", "hr", "cs", "da", "fi", "el", "hu", "ms", "nb", "ro", "sk", "sl", "sv"]

    static func normalize(_ localization: String) -> String {
        let tag = localization.replacingOccurrences(of: "_", with: "-").lowercased()
        if let exact = supported.first(where: { $0.lowercased() == tag }) { return exact }
        let parts = tag.split(separator: "-").map(String.init)
        guard let base = parts.first else { return "en" }
        switch base {
        case "zh": return parts.contains("hant") || parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
        case "es": return parts.contains("mx") ? "es-MX" : "es-ES"
        case "pt": return parts.contains("br") ? "pt-BR" : "pt-PT"
        case "fr": return parts.contains("ca") ? "fr-CA" : "fr"
        case "no", "nb": return "nb"
        case "iw": return "he"
        default: return supported.contains(base) ? base : "en"
        }
    }
}
