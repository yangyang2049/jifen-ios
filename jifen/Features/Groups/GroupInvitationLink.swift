import Foundation

nonisolated struct GroupInvitation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let groupNo: String
}

/// Both domains accept every invitation; region only chooses the shared URL.
nonisolated enum GroupInvitationLink {
    static func website(regionCode: String?, localization: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
        let region = regionCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let domestic = region.flatMap { $0.isEmpty ? nil : $0 }.map { $0 == "CN" }
            ?? (Locale(identifier: localization).language.languageCode?.identifier == "zh")
        return domestic ? "https://jifenqi.com" : "https://iscoreboard.live"
    }

    static func validNumber(_ number: String) -> Bool {
        (6...8).contains(number.count) && number.first != "0"
            && number.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func joinURL(groupNo: String, regionCode: String? = Locale.current.region?.identifier, localization: String = Bundle.main.preferredLocalizations.first ?? "en") -> URL? {
        let number = groupNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validNumber(number) else { return nil }
        return URL(string: "\(website(regionCode: regionCode, localization: localization))/groups/join?groupNo=\(number)")
    }

    static func groupNumber(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil else { return nil }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()
        let path = components.path
        let webLink = scheme == "https" && ["jifenqi.com", "iscoreboard.live"].contains(host ?? "")
            && ["/groups/join", "/groups/join/"].contains(path)
        guard webLink else { return nil }
        let numbers = components.queryItems?.filter { $0.name == "groupNo" } ?? []
        guard numbers.count == 1, let number = numbers.first?.value, validNumber(number) else { return nil }
        return number
    }
}
