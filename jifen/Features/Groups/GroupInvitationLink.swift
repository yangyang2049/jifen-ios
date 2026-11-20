import Foundation

nonisolated struct GroupInvitation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let groupNo: String
    let fromScan: Bool

    init(groupNo: String, fromScan: Bool = false) {
        self.groupNo = groupNo
        self.fromScan = fromScan
    }
}

/// Text and QR image sharing attach the same invitation, including the download fallback.
nonisolated enum GroupInvitationText {
    @MainActor static func message(group: ScoreGroup, regionCode: String? = Locale.current.region?.identifier,
                                   localization: String = Bundle.main.preferredLocalizations.first ?? "en", capabilities: GroupCapabilities? = nil) -> String {
        guard let url = GroupInvitationLink.joinURL(groupNo: group.groupNo, regionCode: regionCode, localization: localization, capabilities: capabilities) else { return "" }
        // 台球是「小组类别」，GroupSport.billiards 落到计分板上会变成「普通台球」这种玩法名；
        // 邀请文案面向组外的人，必须念小组名（台球小组），不能写成「普通台球小组」。
        let sportName = group.sport == .billiards
            ? groupText("sport_billiards", "Billiards")
            : group.sport.title
        let intro = String(format: groupText("invitation_intro_ball", "Join our %@ group to play and keep score together!"), sportName)
        return String(format: groupText("share_message", "%@\n\nGroup: %@\nGroup No.: %@\n\nJoin group: %@\n\nDownload iScoreboard and enter the group number to join:\n%@"),
                      intro, group.name, group.groupNo, url.absoluteString,
                      GroupInvitationLink.website(regionCode: regionCode, localization: localization) + "/download")
    }
}

/// Both domains accept every invitation; region only chooses the shared URL.
nonisolated enum GroupInvitationLink {
    static func website(regionCode: String?, localization: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
        let region = regionCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let domestic = region.flatMap { $0.isEmpty ? nil : $0 }.map { $0 == "CN" }
            ?? (Locale(identifier: localization).language.languageCode?.identifier == "zh")
        return domestic ? "https://jifenqi.com" : "https://iscoreboard.live"
    }

    static func validNumber(_ number: String, capabilities: GroupCapabilities? = nil) -> Bool {
        (capabilities?.groupNumberLengths ?? 6...8).contains(number.count) && number.first != "0"
            && number.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// 邀请链接带号进入才走「已在群聊直接进群」；扫码进入停留在加入页先看小组预览。
    static func usesInvitationLinkEntry(number: String, fromScan: Bool, capabilities: GroupCapabilities? = nil) -> Bool {
        !fromScan && validNumber(number, capabilities: capabilities)
    }

    static func joinURL(groupNo: String, regionCode: String? = Locale.current.region?.identifier, localization: String = Bundle.main.preferredLocalizations.first ?? "en", capabilities: GroupCapabilities? = nil) -> URL? {
        let number = groupNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validNumber(number, capabilities: capabilities) else { return nil }
        return URL(string: "\(website(regionCode: regionCode, localization: localization))/groups/join?groupNo=\(number)")
    }

    static func groupNumber(from url: URL, capabilities: GroupCapabilities? = nil) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil else { return nil }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()
        let path = components.path
        let webLink = scheme == "https"
            && ["jifenqi.com", "www.jifenqi.com", "api.jifenqi.com", "iscoreboard.live"].contains(host ?? "")
            && ["/groups/join", "/groups/join/"].contains(path)
        let legacyLink = scheme == "jifenqi" && host == "groups" && ["/join", "/join/"].contains(path)
        guard webLink || legacyLink else { return nil }
        let numbers = components.queryItems?.filter { $0.name == "groupNo" } ?? []
        guard numbers.count == 1, let number = numbers.first?.value, validNumber(number, capabilities: capabilities) else { return nil }
        return number
    }
}
