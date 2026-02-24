import SwiftUI

struct MultiScoreSetupDialogView: View {
    @Environment(\.dismiss) private var dismiss

    var titleEmoji: String
    var titleKey: String
    var titleFallback: String
    var fixedPlayerCount: Int?
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    @State private var selectedPlayerCount: Int
    @State private var playerNames: [String]
    @State private var activeCommonNameIndex: Int? = nil

    private let commonNamesManager = CommonNamesManager.shared

    init(
        defaultPlayerCount: Int = 4,
        initialPlayerNames: [String] = [],
        titleEmoji: String = "👥",
        titleKey: String = "game_multi_scoreboard",
        titleFallback: String = "多人计分",
        fixedPlayerCount: Int? = nil,
        onConfirm: ((SportsSetupResult) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.titleEmoji = titleEmoji
        self.titleKey = titleKey
        self.titleFallback = titleFallback
        self.fixedPlayerCount = {
            guard let fixedPlayerCount else { return nil }
            return (3...9).contains(fixedPlayerCount) ? fixedPlayerCount : nil
        }()
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let safeCount = (3...9).contains(defaultPlayerCount) ? defaultPlayerCount : 4
        _selectedPlayerCount = State(initialValue: self.fixedPlayerCount ?? safeCount)
        _playerNames = State(initialValue: Self.normalizePlayerNames(initialPlayerNames))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(titleEmoji)
                    .font(.system(size: 20))
                Text(NSLocalizedString(titleKey, value: titleFallback, comment: "") + NSLocalizedString("setup_suffix", value: " 设置", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.lg)
            .padding(.top, Theme.sm)
            .padding(.vertical, Theme.md)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.md) {
                    if fixedPlayerCount == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.sm) {
                                ForEach(Array(3...9), id: \.self) { count in
                                    Button(action: {
                                        selectedPlayerCount = count
                                    }) {
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
                    confirmSetup()
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
            if let fixedPlayerCount {
                selectedPlayerCount = fixedPlayerCount
            }
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
    }

    private static func normalizePlayerNames(_ names: [String]) -> [String] {
        let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
        var result = names
        if result.count < 9 {
            for i in result.count..<9 {
                result.append("\(base) \(i + 1)")
            }
        }
        if result.count > 9 {
            result = Array(result.prefix(9))
        }
        return result
    }

    private func playerCountText(_ count: Int) -> String {
        if count == 4 {
            return NSLocalizedString("players_4", value: "4人", comment: "")
        }
        if count == 6 {
            return NSLocalizedString("players_6", value: "6人", comment: "")
        }
        if count == 8 {
            return NSLocalizedString("players_8", value: "8人", comment: "")
        }
        return String.localizedStringWithFormat(
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
        let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
        let finalNames = Array(playerNames.prefix(selectedPlayerCount)).enumerated().map { idx, raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "\(base) \(idx + 1)" : value
        }
        let team1 = finalNames.first ?? "\(base) 1"
        let team2 = finalNames.count > 1 ? finalNames[1] : ""
        let result = SportsSetupResult(
            team1Name: team1,
            team2Name: team2,
            playerCount: selectedPlayerCount,
            playerNames: finalNames
        )
        Task {
            for name in finalNames {
                await commonNamesManager.recordUsage(name, .player)
            }
        }
        onConfirm?(result)
        dismiss()
    }
}

#Preview {
    MultiScoreSetupDialogView()
}
