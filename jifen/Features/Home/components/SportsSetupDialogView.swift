import SwiftUI


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

    @State private var team1Name: String = ""
    @State private var team2Name: String = ""
    @State private var recentGames: [RecentGameDisplay] = []
    @State private var selectedMaxSets: Int = 0
    @State private var selectedPointsPerSet: Int = 0
    @State private var selectedTieBreakPoints: Int = 0
    @State private var autoChangeSides: Bool = true // 默认开启自动换边

    // Managers
    private let scoreboardRecordManager = ScoreboardRecordManager.shared
    private let commonNamesManager = CommonNamesManager.shared

    var body: some View {
        ZStack {
            // Background to dim content behind
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) { // Row()
                    HStack(spacing: 4) {
                        Text(getEmoji())
                            .font(.system(size: 20))
                        Text(getTitle())
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.homeDialogBackground)
                .cornerRadius(Theme.lg) // Top corners only
                .padding(.horizontal, Theme.md)

                // Content Area
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Theme.md) {
                        // Team 1 Name Input
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            Text(getTeamNameLabel(isTeam1: true))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                TextField(defaultTeam1Name, text: $team1Name)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.textPrimary)
                                    .padding(.horizontal, Theme.sm)
                                    .frame(height: 44)
                                    .background(Theme.homeCardDark) // Use a suitable background
                                    .cornerRadius(Theme.sm)

                                Button(action: {
                                    // TODO: Open CommonNameSelectorDialog for Team 1
                                    print("Open CommonNameSelectorDialog for Team 1")
                                }) {
                                    Image(systemName: "chevron.right")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .frame(width: 40, height: 40)
                                .background(Color.clear)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Team 2 Name Input
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            Text(getTeamNameLabel(isTeam1: false))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                TextField(defaultTeam2Name, text: $team2Name)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.textPrimary)
                                    .padding(.horizontal, Theme.sm)
                                    .frame(height: 44)
                                    .background(Theme.homeCardDark) // Use a suitable background
                                    .cornerRadius(Theme.sm)

                                Button(action: {
                                    // TODO: Open CommonNameSelectorDialog for Team 2
                                    print("Open CommonNameSelectorDialog for Team 2")
                                }) {
                                    Image(systemName: "chevron.right")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .frame(width: 40, height: 40)
                                .background(Color.clear)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Settings Section
                        buildSettingsSection()
                    }
                    .padding(.horizontal, Theme.lg)
                    .padding(.vertical, Theme.md)

                    // Recent Games Records
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
                            .frame(maxWidth: .infinity)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.sm) {
                                    ForEach(recentGames) { game in
                                        buildRecentGameCard(game: game)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.lg)
                        .padding(.bottom, Theme.md)
                    }

                    // Buttons
                    HStack(spacing: Theme.md) {
                        Button(action: {
                            dismiss()
                            onCancel?()
                        }) {
                            Text(NSLocalizedString("cancel", comment: "Cancel button"))
                                .font(.system(size: 16))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 100, height: 44)
                                .background(Theme.homeCardDark)
                                .cornerRadius(.infinity)
                        }

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
                    }
                    .padding(.horizontal, Theme.lg)
                    .padding(.vertical, Theme.md)
                }
                .background(Theme.homeDialogBackground)
                .cornerRadius(Theme.lg) // Corner radius for the whole content view
                .frame(width: 340) // Fixed width for the dialog content
            }
            .onAppear {
                initializeView()
            }
        }
    }

    private func initializeView() {
        team1Name = defaultTeam1Name
        team2Name = defaultTeam2Name

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

    private func getTeamNameLabel(isTeam1: Bool) -> String {
        // Only for football, volleyball, basketball use "主队名称"/"客队名称"
        if gameType == .football || gameType == .volleyball || gameType == .basketball {
            return NSLocalizedString(isTeam1 ? "team1_name" : "team2_name", comment: "")
        }
        // Other sports use "队伍/运动员名称"
        return NSLocalizedString("team_or_player_name", comment: "")
    }

    private func getTitle() -> String {
        switch gameType {
        case .football: return NSLocalizedString("football_setup_title", comment: "")
        case .basketball: return NSLocalizedString("basketball_setup_title", comment: "")
        case .volleyball: return NSLocalizedString("volleyball_setup_title", comment: "")
        case .pingpong: return NSLocalizedString("pingpong_setup_title", comment: "")
        case .badminton: return NSLocalizedString("badminton_setup_title", comment: "")
        case .tennis: return NSLocalizedString("tennis_setup_title", comment: "")
        // Removed billiards, boxing, pickleball
        default: return NSLocalizedString("setup", comment: "")
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
        do {
            let allRecords: [ScoreboardRecordSummary] = await scoreboardRecordManager.getAllRecordSummaries() // Assuming async getAllRecordSummaries
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
        } catch {
            print("Error loading recent records: \(error)")
            recentGames = []
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
        do {
            team1Name = game.team1Name
            team2Name = game.team2Name

            if gameType == .pingpong || gameType == .tennis {
                let record: ScoreboardRecord? = await scoreboardRecordManager.getRecordById(game.recordId)
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
                }
            }

            // promptAction.showToast - simulate with print for now
            print(NSLocalizedString("load_recent_game", comment: "Loaded recent game"))
        } catch {
            print("Error loading from record: \(error)")
            print(NSLocalizedString("load_recent_game", comment: "Loaded recent game (error)"))
        }
    }
    
    private func confirmSetup() async {
        let config = SportsSetupResult(
            team1Name: team1Name.trimmingCharacters(in: .whitespacesAndNewlines),
            team2Name: team2Name.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if config.team1Name == config.team2Name && !config.team1Name.isEmpty {
            // promptAction.showToast
            print(NSLocalizedString("duplicate_names_warning", comment: "Duplicate names warning"))
            return
        }
        
        var finalConfig = config

        if gameType == .pingpong {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 5
            finalConfig.pointsPerSet = 11 // Fixed for pingpong
            finalConfig.autoChangeSides = autoChangeSides
        } else if gameType == .tennis {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            finalConfig.tieBreakPoints = selectedTieBreakPoints > 0 ? selectedTieBreakPoints : 7
            finalConfig.autoChangeSides = autoChangeSides
        } else if gameType == .badminton || gameType == .volleyball {
            finalConfig.autoChangeSides = autoChangeSides
        }
        
        // Auto save team names
        if !finalConfig.team1Name.isEmpty && finalConfig.team1Name != defaultTeam1Name {
            await commonNamesManager.recordUsage(finalConfig.team1Name, .team)
        }
        if !finalConfig.team2Name.isEmpty && finalConfig.team2Name != defaultTeam2Name {
            await commonNamesManager.recordUsage(finalConfig.team2Name, .team)
        }

        onConfirm?(finalConfig)
        dismiss()
    }
}


