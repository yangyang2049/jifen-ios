import ScoreCore
import SwiftUI

struct SportsSetupParticipantSection: View {
    let gameType: GameType
    let defaultTeam1Name: String
    let defaultTeam2Name: String
    @Binding var draft: SportsSetupDraft

    @State private var activeNameInputTarget: NameInputTarget?

    private enum NameInputTarget: String, Identifiable {
        case team1
        case team2
        case team1Player1
        case team1Player2
        case team2Player1
        case team2Player2

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 20) {
            if supportsSinglesDoubles {
                singlesDoublesSection
            }

            if usesDoublesPlayerInputs {
                doublesNameInputs
            } else {
                primaryNameInput
            }

            if showsServingSideSelector {
                servingSideSection
            }
        }
        .sheet(item: $activeNameInputTarget) { target in
            CommonNameSelectorDialog(nameType: nameType(for: target)) { name in
                applySelectedName(name, to: target)
                activeNameInputTarget = nil
            }
        }
    }

    private var supportsSinglesDoubles: Bool {
        [.pingpong, .badminton, .tennis, .pickleball, .foosball].contains(gameType)
    }

    private var usesDoublesPlayerInputs: Bool {
        supportsSinglesDoubles && !draft.isSingles
    }

    private var showsServingSideSelector: Bool {
        [
            .pingpong, .badminton, .tennis, .pickleball, .volleyball,
            .beachVolleyball, .airVolleyball, .foosball, .snooker, .archery
        ].contains(gameType)
    }

    private var singlesDoublesSection: some View {
        Picker("", selection: $draft.isSingles) {
            Text(singlesModeLabel)
                .tag(true)
                .accessibilityIdentifier("singles_option")
            Text(doublesModeLabel)
                .tag(false)
                .accessibilityIdentifier("doubles_option")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("singles_doubles_picker")
        .accessibilityValue(draft.isSingles ? singlesModeLabel : doublesModeLabel)
    }

    private var primaryNameInput: some View {
        HStack(spacing: Theme.sm) {
            InlineCommonNameTextField(
                placeholder: defaultTeam1Name,
                text: $draft.team1Name,
                onChevronTap: { activeNameInputTarget = .team1 }
            )
            .frame(maxWidth: .infinity)

            Text(NSLocalizedString("vs_separator", value: " vs ", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            InlineCommonNameTextField(
                placeholder: defaultTeam2Name,
                text: $draft.team2Name,
                onChevronTap: { activeNameInputTarget = .team2 }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var doublesNameInputs: some View {
        let placeholders = DefaultParticipantNames.doublesMembers
        return HStack(spacing: Theme.sm) {
            VStack(spacing: Theme.sm) {
                InlineCommonNameTextField(
                    placeholder: placeholders[0],
                    text: $draft.team1Player1Name,
                    onChevronTap: { activeNameInputTarget = .team1Player1 }
                )
                InlineCommonNameTextField(
                    placeholder: placeholders[1],
                    text: $draft.team1Player2Name,
                    onChevronTap: { activeNameInputTarget = .team1Player2 }
                )
            }
            .frame(maxWidth: .infinity)

            Text(NSLocalizedString("vs_separator", value: " vs ", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            VStack(spacing: Theme.sm) {
                InlineCommonNameTextField(
                    placeholder: placeholders[2],
                    text: $draft.team2Player1Name,
                    onChevronTap: { activeNameInputTarget = .team2Player1 }
                )
                InlineCommonNameTextField(
                    placeholder: placeholders[3],
                    text: $draft.team2Player2Name,
                    onChevronTap: { activeNameInputTarget = .team2Player2 }
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var servingSideSection: some View {
        HStack {
            servingSideButton(.left)
            Text(servingSideTitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
            servingSideButton(.right)
        }
        .padding(.vertical, 4)
    }

    private var servingSideTitle: String {
        switch gameType {
        case .snooker:
            return NSLocalizedString("setup_opening_break_side", value: "首局开球方", comment: "First-frame breaker")
        case .archery:
            return NSLocalizedString("setup_first_shooter", value: "首发选手", comment: "First archer")
        case .foosball:
            return NSLocalizedString("setup_foosball_kickoff_side", value: "开球方", comment: "Opening foosball side")
        default:
            return NSLocalizedString("setup_serving_side", value: "发球方", comment: "Opening serving side")
        }
    }

    private func servingSideButton(_ side: MatchSide) -> some View {
        let isSelected = side == draft.servingSide
        return Button {
            draft.servingSide = side
        } label: {
            Group {
                if gameType == .archery {
                    Image(systemName: "scope")
                        .font(.system(size: 22, weight: .medium))
                } else if gameType == .foosball {
                    Image(systemName: "soccerball")
                        .font(.system(size: 22, weight: .medium))
                } else {
                    Image(servingIconAssetName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
            }
            .foregroundStyle(isSelected ? Theme.primary : Theme.textSecondary.opacity(0.72))
            .frame(width: 26, height: 26)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(servingSideAccessibilityLabel(side))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func servingSideAccessibilityLabel(_ side: MatchSide) -> String {
        switch gameType {
        case .foosball:
            return side == .left
                ? NSLocalizedString("setup_foosball_kickoff_left", value: "左侧开球", comment: "")
                : NSLocalizedString("setup_foosball_kickoff_right", value: "右侧开球", comment: "")
        case .snooker:
            return side == .left
                ? NSLocalizedString("setup_snooker_break_left", value: "左侧首局开球", comment: "")
                : NSLocalizedString("setup_snooker_break_right", value: "右侧首局开球", comment: "")
        case .archery:
            return side == .left
                ? NSLocalizedString("setup_archery_shooter_left", value: "左侧选手先射", comment: "")
                : NSLocalizedString("setup_archery_shooter_right", value: "右侧选手先射", comment: "")
        default:
            return side == .left
                ? NSLocalizedString("setup_serving_left", value: "左侧发球", comment: "")
                : NSLocalizedString("setup_serving_right", value: "右侧发球", comment: "")
        }
    }

    private var servingIconAssetName: String {
        switch gameType {
        case .pingpong: return "ic_pingpong_serve"
        case .pickleball: return "ic_pickleball_serve"
        case .badminton: return "ic_badminton_serve"
        case .tennis: return "ic_tennis_serve"
        case .volleyball, .beachVolleyball, .airVolleyball: return "ic_volleyball_serve"
        case .snooker: return "ic_snooker_cue"
        default: return "ic_pingpong_serve"
        }
    }

    private var singlesModeLabel: String {
        gameType == .foosball
            ? NSLocalizedString("foosball_mode_1v1", value: "1V1", comment: "")
            : NSLocalizedString("singles", value: "单打", comment: "")
    }

    private var doublesModeLabel: String {
        gameType == .foosball
            ? NSLocalizedString("foosball_mode_2v2", value: "2V2", comment: "")
            : NSLocalizedString("doubles", value: "双打", comment: "")
    }

    private func nameType(for target: NameInputTarget) -> NameType {
        switch target {
        case .team1, .team2:
            return supportsSinglesDoubles || ScoreboardCommonNamePolicy.nameType(for: gameType) == .player
                ? .player
                : .team
        case .team1Player1, .team1Player2, .team2Player1, .team2Player2:
            return .player
        }
    }

    private func applySelectedName(_ value: String, to target: NameInputTarget) {
        switch target {
        case .team1: draft.team1Name = value
        case .team2: draft.team2Name = value
        case .team1Player1: draft.team1Player1Name = value
        case .team1Player2: draft.team1Player2Name = value
        case .team2Player1: draft.team2Player1Name = value
        case .team2Player2: draft.team2Player2Name = value
        }
    }
}
