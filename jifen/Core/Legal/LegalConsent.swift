import Foundation

enum LegalDocuments {
    static let currentVersion = "2026-08-05"

    static var termsURL: URL {
        localizedURL(path: "terms")
    }

    static var privacyURL: URL {
        localizedURL(path: "privacy")
    }

    static var membershipAgreementURL: URL {
        localizedURL(path: "membership-agreement")
    }

    private static func localizedURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "jifenqi.com"
        components.path = "/\(path)"
        components.queryItems = [
            URLQueryItem(name: "lang", value: Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"),
            URLQueryItem(name: "source", value: "mobile_app")
        ]
        return components.url!
    }
}

enum LegalConsent {
    /// Exposed inside the app so the local-data reset can preserve the exact
    /// legal decision while removing every other app preference.
    static let acceptedVersionKey = "legal_documents_accepted_version"

    static func hasAcceptedCurrentDocuments(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: acceptedVersionKey) == LegalDocuments.currentVersion
    }

    static func acceptCurrentDocuments(defaults: UserDefaults = .standard) {
        defaults.set(LegalDocuments.currentVersion, forKey: acceptedVersionKey)
    }
}
