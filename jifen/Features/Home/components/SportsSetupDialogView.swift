import SwiftUI

// MARK: - CommonNameSelectorDialog
// Sheet to pick a common team/player name (aligned with HarmonyOS common-name picker)

struct CommonNameSelectorDialog: View {
    @Environment(\.dismiss) var dismiss
    var nameType: NameType
    var onSelect: (String) -> Void

    private let commonNamesManager = CommonNamesManager.shared

    private var names: [String] {
        commonNamesManager.getNames(type: nameType)
    }

    var body: some View {
        NavigationView {
            Group {
                if names.isEmpty {
                    VStack(spacing: Theme.sm) {
                        EmptyStateCourtIcon(size: 44)
                        Text(NSLocalizedString("common_names_empty", value: "暂无常用名称", comment: ""))
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(names, id: \.self) { name in
                        Button(action: {
                            onSelect(name)
                            dismiss()
                        }) {
                            HStack {
                                Text(name)
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("common_names_title", value: "常用名称", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(Theme.primary)
                }
            }
        }
    }
}

struct InlineCommonNameTextField: View {
    let placeholder: String
    @Binding var text: String
    var onChevronTap: () -> Void
    var font: Font = .system(size: 16)
    var textColor: Color = Theme.textPrimary
    var iconColor: Color = Theme.textSecondary
    var backgroundColor: Color = Theme.homeCardDark
    var height: CGFloat = 44
    var cornerRadius: CGFloat = Theme.sm

    var body: some View {
        HStack(spacing: Theme.xs) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundColor(textColor)

            Button(action: onChevronTap) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Theme.sm)
        .padding(.trailing, Theme.xs)
        .frame(height: height)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
    }
}

// MARK: - SportsSetupDialogView

struct SportsSetupDialogView: View {
    @Environment(\.dismiss) var dismiss

    var gameType: GameType
    var defaultTeam1Name: String
    var defaultTeam2Name: String
    var initialMaxSets: Int?
    var initialPointsPerSet: Int?
    var initialTieBreakPoints: Int?
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    private enum NameInputTarget: String, Identifiable {
        case team1
        case team2
        case team1Player1
        case team1Player2
        case team2Player1
        case team2Player2

        var id: String { rawValue }
    }

    @State private var team1Name: String = ""
    @State private var team2Name: String = ""
    @State private var activeNameInputTarget: NameInputTarget? = nil
    @State private var recentGames: [RecentGameDisplay] = []
    @State private var selectedMaxSets: Int = 0
    @State private var selectedPointsPerSet: Int = 0
    @State private var selectedTieBreakPoints: Int = 0
    @State private var autoChangeSides: Bool = true // 默认开启自动换边
    @State private var isSingles: Bool = true // 乒乓球/羽毛球/网球：单打/双打
    @State private var team1Player1Name: String = ""
    @State private var team1Player2Name: String = ""
    @State private var team2Player1Name: String = ""
    @State private var team2Player2Name: String = ""

    // Managers
    private let scoreboardRecordManager = ScoreboardRecordManager.shared
    private let commonNamesManager = CommonNamesManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(getEmoji())
                    .font(.system(size: 20))
                Text(getTitle())
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.lg)
            .padding(.top, Theme.sm)
            .padding(.vertical, Theme.md)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.md) {
                    if shouldShowSinglesDoublesAtTop() {
                        buildSinglesDoublesSection()
                    }

                    if shouldUseDoublesPlayerInputs() {
                        buildDoublesNameInputs()
                    } else {
                        buildPrimaryNameInput()
                        buildSecondaryNameInput()
                    }

                    buildSettingsSection()

                    if !recentGames.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            HStack {
                                Text(NSLocalizedString("recent_records", comment: "Recent Records"))
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textSecondary)
                                Spacer()
                                Text(NSLocalizedString("tap_to_quick_use", comment: "Tap to quick use"))
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary.opacity(0.6))
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.sm) {
                                    ForEach(recentGames) { game in
                                        buildRecentGameCard(game: game)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.lg)
                .padding(.vertical, Theme.md)
            }

            HStack(spacing: Theme.md) {
                Button(action: {
                    onCancel?()
                    dismiss()
                }) {
                    Text(NSLocalizedString("cancel", comment: "Cancel button"))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 100, height: 44)
                        .background(Theme.homeCardDark)
                        .cornerRadius(.infinity)
                }
                .buttonStyle(.plain)

                Button(action: {
                    Task {
                        await confirmSetup()
                    }
                }) {
                    Text(NSLocalizedString("start_game", comment: "Start Game button"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.primary)
                        .cornerRadius(.infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.lg)
            .padding(.top, Theme.sm)
            .padding(.bottom, Theme.md)
        }
        .background(Theme.homeDialogBackground.ignoresSafeArea())
        .onAppear {
            initializeView()
        }
        .onChange(of: isSingles) { _, newValue in
            guard shouldShowSinglesDoublesAtTop() else { return }
            if newValue {
                let firstLeft = team1Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                let firstRight = team2Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !firstLeft.isEmpty { team1Name = firstLeft }
                if !firstRight.isEmpty { team2Name = firstRight }
            } else {
                syncDoublesPlayerNamesFromTeamNames()
            }
        }
        .sheet(item: $activeNameInputTarget) { target in
            CommonNameSelectorDialog(nameType: nameType(for: target)) { name in
                applySelectedName(name, to: target)
                activeNameInputTarget = nil
            }
        }
    }

    private func initializeView() {
        team1Name = defaultTeam1Name
        team2Name = defaultTeam2Name
        syncDoublesPlayerNamesFromTeamNames()

        selectedMaxSets = initialMaxSets ?? getDefaultMaxSets() ?? 0
        selectedPointsPerSet = initialPointsPerSet ?? getDefaultPointsPerSet() ?? 0
        selectedTieBreakPoints = initialTieBreakPoints ?? getDefaultTieBreakPoints() ?? 0

        Task {
            // await scoreboardRecordManager.init() // Managers should be initialized at app launch
            await loadRecentRecords()
        }
    }

    private func getDefaultMaxSets() -> Int? {
        switch gameType {
        case .pingpong: return 5
        case .tennis: return 3
        default: return nil
        }
    }

    private func getDefaultPointsPerSet() -> Int? {
        switch gameType {
        case .pingpong: return 11
        default: return nil
        }
    }

    private func getDefaultTieBreakPoints() -> Int? {
        return gameType == .tennis ? 7 : nil
    }

    private func getTeamNameLabel(isTeam1 _: Bool) -> String {
        if shouldShowSinglesDoublesAtTop() {
            return isSingles
                ? NSLocalizedString("setup_player_name", value: "选手名称", comment: "Player name in setup")
                : NSLocalizedString("setup_team_name", value: "队伍名称", comment: "Team name in setup")
        }
        if isConfirmedPlayerSetupGame() {
            return NSLocalizedString("setup_player_name", value: "选手名称", comment: "Player name in setup")
        }
        if isConfirmedTeamSetupGame() {
            return NSLocalizedString("setup_team_name", value: "队伍名称", comment: "Team name in setup")
        }
        return NSLocalizedString("team_or_player_name", comment: "")
    }

    private func isConfirmedPlayerSetupGame() -> Bool {
        return gameType == .boxing || gameType == .archery
    }

    private func isConfirmedTeamSetupGame() -> Bool {
        return gameType == .football || gameType == .volleyball || gameType == .basketball
    }

    private func getTitle() -> String {
        switch gameType {
        case .football: return NSLocalizedString("football_setup_title", comment: "")
        case .basketball: return NSLocalizedString("basketball_setup_title", comment: "")
        case .volleyball: return NSLocalizedString("volleyball_setup_title", comment: "")
        case .pingpong: return NSLocalizedString("pingpong_setup_title", comment: "")
        case .badminton: return NSLocalizedString("badminton_setup_title", comment: "")
        case .tennis: return NSLocalizedString("tennis_setup_title", comment: "")
        default: return gameType.displayName + NSLocalizedString("setup_suffix", value: " 设置", comment: "")
        }
    }

    private func getEmoji() -> String {
        return gameType.icon // Using GameType.icon which is defined
    }

    private func getChipBackgroundColor(selected: Bool) -> Color {
        return selected ? Theme.primary : Theme.homeCardDark // Using homeCardDark as rgba(255,255,255,0.12)
    }

    private func getChipTextColor(selected: Bool) -> Color {
        return selected ? .white : Theme.textPrimary // Using Theme.textPrimary for dialog text color
    }
    
    private func shouldShowSettings() -> Bool {
        return gameType == .pingpong ||
               gameType == .tennis ||
               gameType == .badminton ||
               gameType == .volleyball
    }

    private func shouldShowSinglesDoublesAtTop() -> Bool {
        return gameType == .pingpong || gameType == .badminton || gameType == .tennis
    }

    private func shouldUseDoublesPlayerInputs() -> Bool {
        shouldShowSinglesDoublesAtTop() && !isSingles
    }

    @ViewBuilder
    private func buildPrimaryNameInput() -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(getTeamNameLabel(isTeam1: true))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            InlineCommonNameTextField(
                placeholder: defaultTeam1Name,
                text: $team1Name,
                onChevronTap: { activeNameInputTarget = .team1 }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func buildSecondaryNameInput() -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(getTeamNameLabel(isTeam1: false))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            InlineCommonNameTextField(
                placeholder: defaultTeam2Name,
                text: $team2Name,
                onChevronTap: { activeNameInputTarget = .team2 }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func buildDoublesNameInputs() -> some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            VStack(alignment: .leading, spacing: Theme.sm) {
                Text(NSLocalizedString("team1_name", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("player1_name", value: "选手1", comment: ""),
                    text: $team1Player1Name,
                    onChevronTap: { activeNameInputTarget = .team1Player1 }
                )
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("player2_name", value: "选手2", comment: ""),
                    text: $team1Player2Name,
                    onChevronTap: { activeNameInputTarget = .team1Player2 }
                )
            }

            VStack(alignment: .leading, spacing: Theme.sm) {
                Text(NSLocalizedString("team2_name", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("player1_name", value: "选手1", comment: ""),
                    text: $team2Player1Name,
                    onChevronTap: { activeNameInputTarget = .team2Player1 }
                )
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("player2_name", value: "选手2", comment: ""),
                    text: $team2Player2Name,
                    onChevronTap: { activeNameInputTarget = .team2Player2 }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func buildSinglesDoublesSection() -> some View {
        Picker("", selection: $isSingles) {
            Text(NSLocalizedString("singles", value: "单打", comment: ""))
                .tag(true)
            Text(NSLocalizedString("doubles", value: "双打", comment: ""))
                .tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(Theme.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func buildSettingsSection() -> some View {
        if shouldShowSettings() {
            VStack(alignment: .leading, spacing: Theme.sm) {
                if gameType == .pingpong {
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text(NSLocalizedString("pingpong_set_count_label", comment: "Pingpong set count label"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: Theme.sm) {
                            ForEach([3, 5, 7], id: \.self) { sets in
                                Button(action: { selectedMaxSets = sets }) {
                                    Text(NSLocalizedString("pingpong_set_option_best_of_\(sets)", comment: ""))
                                        .font(.system(size: 14, weight: selectedMaxSets == sets ? .medium : .regular))
                                        .foregroundColor(getChipTextColor(selected: selectedMaxSets == sets))
                                        .padding(.horizontal, Theme.sm)
                                        .padding(.vertical, Theme.xs)
                                        .background(getChipBackgroundColor(selected: selectedMaxSets == sets))
                                        .cornerRadius(Theme.sm) // Adjust for 16
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle(isOn: $autoChangeSides) {
                            Text(NSLocalizedString("pingpong_auto_change_sides", comment: "Auto change sides"))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textPrimary)
                        }
                        .tint(Theme.primary) // selectedColor
                        .padding(.top, Theme.sm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if gameType == .tennis {
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text(NSLocalizedString("tennis_set_count_label", comment: "Tennis set count label"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: Theme.sm) {
                            ForEach([3, 5], id: \.self) { sets in
                                Button(action: { selectedMaxSets = sets }) {
                                    Text(NSLocalizedString("tennis_set_option_best_of_\(sets)", comment: ""))
                                        .font(.system(size: 14, weight: selectedMaxSets == sets ? .medium : .regular))
                                        .foregroundColor(getChipTextColor(selected: selectedMaxSets == sets))
                                        .padding(.horizontal, Theme.sm)
                                        .padding(.vertical, Theme.xs)
                                        .background(getChipBackgroundColor(selected: selectedMaxSets == sets))
                                        .cornerRadius(Theme.sm)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(NSLocalizedString("tennis_tiebreak_label", comment: "Tennis tiebreak label"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: Theme.sm) {
                            ForEach([7, 10], id: \.self) { points in
                                Button(action: { selectedTieBreakPoints = points }) {
                                    Text(NSLocalizedString("tennis_tiebreak_option_\(points)", comment: ""))
                                        .font(.system(size: 14, weight: selectedTieBreakPoints == points ? .medium : .regular))
                                        .foregroundColor(getChipTextColor(selected: selectedTieBreakPoints == points))
                                        .padding(.horizontal, Theme.sm)
                                        .padding(.vertical, Theme.xs)
                                        .background(getChipBackgroundColor(selected: selectedTieBreakPoints == points))
                                        .cornerRadius(Theme.sm)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle(isOn: $autoChangeSides) {
                            Text(NSLocalizedString("tennis_auto_change_sides", comment: "Auto change sides"))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textPrimary)
                        }
                        .tint(Theme.primary)
                        .padding(.top, Theme.sm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if gameType == .badminton {
                    Toggle(isOn: $autoChangeSides) {
                        Text(NSLocalizedString("badminton_auto_change_sides", comment: "Auto change sides"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textPrimary)
                    }
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.sm)
                } else if gameType == .volleyball {
                    Toggle(isOn: $autoChangeSides) {
                        Text(NSLocalizedString("volleyball_auto_change_sides", comment: "Auto change sides"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textPrimary)
                    }
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Recent Game Card
    @ViewBuilder
    private func buildRecentGameCard(game: RecentGameDisplay) -> some View {
        Button(action: {
            Task {
                await loadFromRecord(game: game)
            }
        }) {
            HStack(spacing: Theme.xs) {
                Text(game.team1Name)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(game.score)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                
                Text(game.team2Name)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let setsInfo = game.setsInfo {
                    Text(setsInfo)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.primary)
                        .padding(.horizontal, Theme.xs)
                        .padding(.vertical, 2)
                        .background(Theme.homeCardDark.opacity(0.5)) // getSetsInfoBackgroundColor
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, Theme.sm)
            .padding(.vertical, Theme.xs)
            .background(Theme.homeCardDark.opacity(0.3)) // getRecordCardBackgroundColor
            .cornerRadius(6)
        }
        .buttonStyle(CardButtonStyle()) // Using existing CardButtonStyle for pressed state
    }

    private func formatTime(timestamp: TimeInterval) -> String {
        let now = Date().timeIntervalSince1970
        let diff = now - timestamp
        
        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)
        let days = Int(diff / 86400)

        if minutes < 60 {
            return String.localizedStringWithFormat(NSLocalizedString("minutes_ago", comment: ""), minutes)
        } else if hours < 24 {
            return String.localizedStringWithFormat(NSLocalizedString("hours_ago", comment: ""), hours)
        } else if days < 7 {
            return String.localizedStringWithFormat(NSLocalizedString("days_ago", comment: ""), days)
        }

        let date = Date(timeIntervalSince1970: timestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd"
        return dateFormatter.string(from: date)
    }

    private func loadRecentRecords() async {
        let allRecords: [ScoreboardRecordSummary] = scoreboardRecordManager.getAllRecordSummaries()
        recentGames = allRecords
            .filter { $0.gameType == gameType }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(3)
            .map { record in
                let setsInfo = formatSetsInfo(record)
                return RecentGameDisplay(
                    id: record.id,
                    team1Name: record.team1Name,
                    team2Name: record.team2Name,
                    score: "\(record.team1FinalScore)-\(record.team2FinalScore)",
                    time: formatTime(timestamp: record.timestamp),
                    recordId: record.id,
                    setsInfo: setsInfo
                )
            }
    }

    private func formatSetsInfo(_ record: ScoreboardRecordSummary) -> String? {
        if gameType == .pingpong {
            var maxSets: Int? = nil
            if let extraData = record.extraData, let ms = extraData["maxSets"]?.value as? Int {
                maxSets = ms
            }
            
            if maxSets == nil {
                let team1Sets = record.team1SetScore ?? 0
                let team2Sets = record.team2SetScore ?? 0
                let completedSets = team1Sets + team2Sets

                if completedSets >= 5 { maxSets = completedSets <= 5 ? 5 : 7 }
                else if completedSets >= 3 { maxSets = completedSets <= 3 ? 3 : 5 }
                else if completedSets >= 2 { maxSets = 3 }
                else { maxSets = 5 } // Default 5 sets
            }

            return maxSets != nil && maxSets! > 0 ? "\(maxSets!)" : nil
        } else if gameType == .tennis {
            var maxSets: Int? = nil
            var tieBreakPoints: Int? = nil

            if let extraData = record.extraData {
                if let ms = extraData["maxSets"]?.value as? Int { maxSets = ms }
                if let tbp = extraData["tieBreakPoints"]?.value as? Int { tieBreakPoints = tbp }
            }

            if maxSets == nil { maxSets = 3 } // Default 3 sets
            if tieBreakPoints == nil { tieBreakPoints = 7 } // Default tiebreak 7

            if let tbp = tieBreakPoints, (tbp == 7 || tbp == 10) {
                return "\(maxSets ?? 0) | \(tbp)"
            } else {
                return "\(maxSets ?? 0)"
            }
        }
        return nil
    }

    private func loadFromRecord(game: RecentGameDisplay) async {
        team1Name = game.team1Name
        team2Name = game.team2Name

        if gameType == .pingpong || gameType == .tennis || gameType == .badminton {
            let record: ScoreboardRecord? = scoreboardRecordManager.getRecordById(game.recordId)
            if let record = record, let extraData = record.extraData {
                if gameType == .pingpong {
                    if let ms = extraData["maxSets"]?.value as? Int, ms > 0 {
                        selectedMaxSets = ms
                    }
                } else if gameType == .tennis {
                    if let ms = extraData["maxSets"]?.value as? Int, ms > 0 {
                        selectedMaxSets = ms
                    }
                    if let tbp = extraData["tieBreakPoints"]?.value as? Int, tbp > 0 {
                        selectedTieBreakPoints = tbp
                    }
                }
                if let singles = extraData["isSingles"]?.value as? Bool {
                    isSingles = singles
                }
            }
        }
        syncDoublesPlayerNamesFromTeamNames()

        #if DEBUG
        print(NSLocalizedString("load_recent_game", comment: "Loaded recent game"))
        #endif
    }

    private func syncDoublesPlayerNamesFromTeamNames() {
        let left = splitDoublesTeamName(team1Name)
        let right = splitDoublesTeamName(team2Name)
        team1Player1Name = left.first
        team1Player2Name = left.second
        team2Player1Name = right.first
        team2Player2Name = right.second
    }

    private func splitDoublesTeamName(_ value: String) -> (first: String, second: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", "") }
        let parts = trimmed
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (parts[0], parts[1])
        }
        return (trimmed, "")
    }

    private func buildDoublesTeamName(_ player1: String, _ player2: String) -> String {
        let first = player1.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = player2.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty && !second.isEmpty {
            return "\(first) / \(second)"
        }
        return first.isEmpty ? second : first
    }

    private func nameType(for target: NameInputTarget) -> NameType {
        switch target {
        case .team1, .team2:
            return shouldShowSinglesDoublesAtTop() ? .player : .team
        case .team1Player1, .team1Player2, .team2Player1, .team2Player2:
            return .player
        }
    }

    private func applySelectedName(_ value: String, to target: NameInputTarget) {
        switch target {
        case .team1:
            team1Name = value
        case .team2:
            team2Name = value
        case .team1Player1:
            team1Player1Name = value
        case .team1Player2:
            team1Player2Name = value
        case .team2Player1:
            team2Player1Name = value
        case .team2Player2:
            team2Player2Name = value
        }
    }
    
    private func confirmSetup() async {
        let resolvedTeam1Name = shouldUseDoublesPlayerInputs()
            ? buildDoublesTeamName(team1Player1Name, team1Player2Name)
            : team1Name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTeam2Name = shouldUseDoublesPlayerInputs()
            ? buildDoublesTeamName(team2Player1Name, team2Player2Name)
            : team2Name.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = SportsSetupResult(
            team1Name: resolvedTeam1Name,
            team2Name: resolvedTeam2Name
        )

        if config.team1Name == config.team2Name && !config.team1Name.isEmpty {
            // promptAction.showToast
            #if DEBUG
            print(NSLocalizedString("duplicate_names_warning", comment: "Duplicate names warning"))
            #endif
            return
        }
        
        var finalConfig = config

        if gameType == .pingpong {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 5
            finalConfig.pointsPerSet = 11 // Fixed for pingpong
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.isSingles = isSingles
        } else if gameType == .tennis {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            finalConfig.tieBreakPoints = selectedTieBreakPoints > 0 ? selectedTieBreakPoints : 7
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.isSingles = isSingles
        } else if gameType == .badminton {
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.isSingles = isSingles
        } else if gameType == .volleyball {
            finalConfig.autoChangeSides = autoChangeSides
        }
        
        if shouldUseDoublesPlayerInputs() {
            let playerNames = [
                team1Player1Name,
                team1Player2Name,
                team2Player1Name,
                team2Player2Name,
            ]
            for name in playerNames {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    await commonNamesManager.recordUsage(trimmed, .player)
                }
            }
        } else if shouldShowSinglesDoublesAtTop() {
            if !finalConfig.team1Name.isEmpty && finalConfig.team1Name != defaultTeam1Name {
                await commonNamesManager.recordUsage(finalConfig.team1Name, .player)
            }
            if !finalConfig.team2Name.isEmpty && finalConfig.team2Name != defaultTeam2Name {
                await commonNamesManager.recordUsage(finalConfig.team2Name, .player)
            }
        } else {
            if !finalConfig.team1Name.isEmpty && finalConfig.team1Name != defaultTeam1Name {
                await commonNamesManager.recordUsage(finalConfig.team1Name, .team)
            }
            if !finalConfig.team2Name.isEmpty && finalConfig.team2Name != defaultTeam2Name {
                await commonNamesManager.recordUsage(finalConfig.team2Name, .team)
            }
        }

        onConfirm?(finalConfig)
        dismiss()
    }
}
