import Foundation

/// Single source of truth for Simplified/Traditional detection, shared by
/// legal-document URLs, Accept-Language headers, and voice announcement resolve.
enum ChineseScript {
    static var isChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    static func isTraditional(locale: Locale = .current) -> Bool {
        // Foundation normalizes scripts (zh-HK → Hant, bare zh → Hans);
        // the region fallback only applies when no script is present.
        switch locale.language.script?.identifier {
        case "Hant": return true
        case "Hans": return false
        default:
            switch locale.region?.identifier {
            case "TW", "HK", "MO": return true
            default: return false
            }
        }
    }
}
