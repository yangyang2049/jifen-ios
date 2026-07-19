import SwiftUI

/// 多人 / 卡牌 / 简单计分开局设置，对齐鸿蒙 CasualGameSetupDialog。
struct MultiScoreSetupDialogView: View {
    enum LayoutMode {
        case multiScore
        case doudizhu
        case uno
        case twoTeam
    }

    var gameType: GameType = .multiScoreboard
    var titleEmoji: String
    var titleKey: String
    var titleFallback: String
    var maxContentHeight: CGFloat = 520
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    @State private var selectedPlayerCount: Int
    @State private var playerNames: [String]
    @State private var team1Name: String
    @State private var team2Name: String
    @State private var unoTargetScore: Int
    @State private var activeCommonNameIndex: Int? = nil
    @State private var activeTeamNameTarget: TeamNameTarget? = nil

    private enum TeamNameTarget: String, Identifiable {
        case team1
        case team2
        var id: String { rawValue }
    }

    private let commonNamesManager = CommonNamesManager.shared

    private var layoutMode: LayoutMode {
        switch gameType {
        case .doudizhu: return .doudizhu
        case .uno: return .uno
        case .guandan, .shengji, .simpleScore: return .twoTeam
        default: return .multiScore
        }
    }

    private var playerCountRange: ClosedRange<Int> {
        switch layoutMode {
        case .uno: return 2...10
        case .multiScore: return 3...9
        case .doudizhu: return 3...3
        case .twoTeam: return 2...2
        }
    }

    init(
        gameType: GameType = .multiScoreboard,
        defaultPlayerCount: Int = 4,
        initialPlayerNames: [String] = [],
        defaultTeam1Name: String = "",
        defaultTeam2Name: String = "",
        initialTargetScore: Int = 500,
        titleEmoji: String = "👥",
        titleKey: String = "game_multi_scoreboard",
        titleFallback: String = "多人计分",
        maxContentHeight: CGFloat = 520,
        onConfirm: ((SportsSetupResult) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.gameType = gameType
        self.titleEmoji = titleEmoji
        self.titleKey = titleKey
        self.titleFallback = titleFallback
        self.maxContentHeight = maxContentHeight
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let mode: LayoutMode = {
            switch gameType {
            case .doudizhu: return .doudizhu
            case .uno: return .uno
            case .guandan, .shengji, .simpleScore: return .twoTeam
            default: return .multiScore
            }
        }()
        let range: ClosedRange<Int> = {
            switch mode {
            case .uno: return 2...10
            case .multiScore: return 3...9
            case .doudizhu: return 3...3
            case .twoTeam: return 2...2
            }
        }()
        let safeCount: Int = {
            switch mode {
            case .doudizhu: return 3
            case .twoTeam: return 2
            case .uno:
                return range.contains(defaultPlayerCount) ? defaultPlayerCount : 4
            case .multiScore:
                return range.contains(defaultPlayerCount) ? defaultPlayerCount : 4
            }
        }()

        _selectedPlayerCount = State(initialValue: safeCount)
        _playerNames = State(initialValue: Self.normalizePlayerNames(initialPlayerNames, capacity: 10))
        _team1Name = State(initialValue: defaultTeam1Name.isEmpty
            ? NSLocalizedString("red_team", value: "红方", comment: "")
            : defaultTeam1Name)
        _team2Name = State(initialValue: defaultTeam2Name.isEmpty
            ? NSLocalizedString("blue_team", value: "蓝方", comment: "")
            : defaultTeam2Name)
        let validTargets = [300, 500, 700, 1000]
        _unoTargetScore = State(initialValue: validTargets.contains(initialTargetScore) ? initialTargetScore : 500)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(titleEmoji)
                    .font(.system(size: 20))
                Text(NSLocalizedString(titleKey, value: titleFallback, comment: "")
                    + NSLocalizedString("setup_suffix", value: " 设置", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.lg)
            .padding(.top, Theme.sm)
            .padding(.vertical, Theme.md)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.md) {
                    switch layoutMode {
                    case .twoTeam:
                        twoTeamNameInputs
                    case .multiScore, .uno, .doudizhu:
                        if layoutMode != .doudizhu {
                            playerCountChips
                        }
                        playerNameFields
                        if layoutMode == .uno {
                            unoTargetScoreSection
                        }
                    }
                }
                .padding(.horizontal, Theme.lg)
                .padding(.vertical, Theme.md)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: maxContentHeight)

            HStack(spacing: Theme.md) {
                Button(action: { onCancel?() }) {
                    Text(NSLocalizedString("cancel", comment: "Cancel button"))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 100, height: 44)
                        .background(Theme.homeCardDark)
                        .cornerRadius(.infinity)
                }
                .buttonStyle(.plain)

                Button(action: confirmSetup) {
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
        .sheet(isPresented: Binding(
            get: { activeCommonNameIndex != nil },
            set: { if !$0 { activeCommonNameIndex = nil } }
        )) {
            CommonNameSelectorDialog(nameType: .player) { name in
                if let index = activeCommonNameIndex, playerNames.indices.contains(index) {
                    playerNames[index] = name
                }
                activeCommonNameIndex = nil
            }
        }
        .sheet(item: $activeTeamNameTarget) { target in
            CommonNameSelectorDialog(nameType: .team) { name in
                switch target {
                case .team1: team1Name = name
                case .team2: team2Name = name
                }
                activeTeamNameTarget = nil
            }
        }
    }

    private var playerCountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.sm) {
                ForEach(Array(playerCountRange), id: \.self) { count in
                    Button(action: { selectedPlayerCount = count }) {
                        Text(playerCountText(count))
                            .font(.system(size: 14, weight: selectedPlayerCount == count ? .medium : .regular))
                            .foregroundColor(selectedPlayerCount == count ? .white : Theme.textPrimary)
                            .padding(.horizontal, Theme.sm)
                            .padding(.vertical, Theme.xs)
                            .background(selectedPlayerCount == count ? Theme.primary : Theme.homeCardDark)
                            .cornerRadius(Theme.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var playerNameFields: some View {
        VStack(spacing: Theme.sm) {
            ForEach(0..<selectedPlayerCount, id: \.self) { index in
                InlineCommonNameTextField(
                    placeholder: playerLabel(index),
                    text: bindingForPlayerName(index),
                    onChevronTap: { activeCommonNameIndex = index }
                )
            }
        }
    }

    private var twoTeamNameInputs: some View {
        HStack(spacing: Theme.sm) {
            InlineCommonNameTextField(
                placeholder: NSLocalizedString("red_team", value: "红方", comment: ""),
                text: $team1Name,
                onChevronTap: { activeTeamNameTarget = .team1 }
            )
            .frame(maxWidth: .infinity)

            Text(NSLocalizedString("vs_separator", value: " vs ", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            InlineCommonNameTextField(
                placeholder: NSLocalizedString("blue_team", value: "蓝方", comment: ""),
                text: $team2Name,
                onChevronTap: { activeTeamNameTarget = .team2 }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var unoTargetScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("uno_target_score", value: "目标分", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 8) {
                ForEach([300, 500, 700, 1000], id: \.self) { score in
                    Button {
                        unoTargetScore = score
                    } label: {
                        Text("\(score)")
                            .font(.system(size: 14, weight: unoTargetScore == score ? .medium : .regular))
                            .foregroundStyle(unoTargetScore == score ? Color.white : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(unoTargetScore == score ? Theme.primary : Theme.homeCardDark)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static func normalizePlayerNames(_ names: [String], capacity: Int) -> [String] {
        let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
        var result = names
        if result.count < capacity {
            for i in result.count..<capacity {
                result.append("\(base) \(i + 1)")
            }
        }
        if result.count > capacity {
            result = Array(result.prefix(capacity))
        }
        return result
    }

    private func playerCountText(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("players_count_format", value: "%d人", comment: "Player count format"),
            count
        )
    }

    private func playerLabel(_ index: Int) -> String {
        let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
        return "\(base) \(index + 1)"
    }

    private func bindingForPlayerName(_ index: Int) -> Binding<String> {
        Binding(
            get: { playerNames.indices.contains(index) ? playerNames[index] : "" },
            set: { newValue in
                guard playerNames.indices.contains(index) else { return }
                playerNames[index] = newValue
            }
        )
    }

    private func confirmSetup() {
        switch layoutMode {
        case .twoTeam:
            let t1 = team1Name.trimmingCharacters(in: .whitespacesAndNewlines)
            let t2 = team2Name.trimmingCharacters(in: .whitespacesAndNewlines)
            let final1 = t1.isEmpty ? NSLocalizedString("red_team", value: "红方", comment: "") : t1
            let final2 = t2.isEmpty ? NSLocalizedString("blue_team", value: "蓝方", comment: "") : t2
            Task {
                await commonNamesManager.recordUsage(final1, .team)
                await commonNamesManager.recordUsage(final2, .team)
            }
            onConfirm?(SportsSetupResult(team1Name: final1, team2Name: final2))
        case .multiScore, .doudizhu, .uno:
            let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
            let finalNames = Array(playerNames.prefix(selectedPlayerCount)).enumerated().map { idx, raw in
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? "\(base) \(idx + 1)" : value
            }
            let team1 = finalNames.first ?? "\(base) 1"
            let team2 = finalNames.count > 1 ? finalNames[1] : ""
            var result = SportsSetupResult(
                team1Name: team1,
                team2Name: team2,
                playerCount: selectedPlayerCount,
                playerNames: finalNames
            )
            if layoutMode == .uno {
                result.targetScore = unoTargetScore
            }
            Task {
                for name in finalNames {
                    await commonNamesManager.recordUsage(name, .player)
                }
            }
            onConfirm?(result)
        }
    }
}

#Preview {
    MultiScoreSetupDialogView()
}
