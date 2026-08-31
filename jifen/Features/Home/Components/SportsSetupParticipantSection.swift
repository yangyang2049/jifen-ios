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
        case team1Player3
        case team2Player3

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 20) {
            if gameType == .shuttlecock {
                shuttlecockFormatSection
            }
            if supportsSinglesDoubles {
                singlesDoublesSection
            }

            if usesTeamPlayerInputs {
                shuttlecockTeamInputs
            } else if usesDoublesPlayerInputs {
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
        [.pingpong, .badminton, .tennis, .softTennis, .pickleball, .foosball].contains(gameType)
    }

    private var usesDoublesPlayerInputs: Bool {
        gameType == .padel
            || (supportsSinglesDoubles && !draft.isSingles)
            || (gameType == .shuttlecock && [.doubles, .mixedDoubles].contains(draft.competitionFormat))
    }

    private var usesTeamPlayerInputs: Bool {
        gameType == .shuttlecock && draft.competitionFormat == .team
    }

    private var shuttlecockFormatSection: some View {
        Picker("", selection: Binding(
            get: { draft.competitionFormat },
            set: {
                draft.competitionFormat = $0
                draft.isSingles = $0 == .singles
            }
        )) {
            Text(NSLocalizedString("competition_format_singles", value: "单打", comment: ""))
                .tag(CompetitionFormat.singles)
            Text(NSLocalizedString("competition_format_doubles", value: "双打", comment: ""))
                .tag(CompetitionFormat.doubles)
            Text(NSLocalizedString("competition_format_mixed_doubles", value: "混双", comment: ""))
                .tag(CompetitionFormat.mixedDoubles)
            Text(NSLocalizedString("competition_format_team", value: "团队赛", comment: ""))
                .tag(CompetitionFormat.team)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("competition_format_picker")
    }

    /// 对齐安卓 SportsSetupComponents.kt DoublesNameInputs：团队赛每边仅 3 名队员输入，
    /// 无单独队名输入，队名由 3 个队员名自动拼接（SportsSetupDraft.buildCompetitionTeamName）。
    private var shuttlecockTeamInputs: some View {
        let defaults = DefaultParticipantNames.shuttlecockTeamMembers
        return HStack(alignment: .top, spacing: Theme.sm) {
            VStack(spacing: Theme.sm) {
                InlineCommonNameTextField(placeholder: defaults[0], text: $draft.team1Player1Name, onChevronTap: { activeNameInputTarget = .team1Player1 })
                InlineCommonNameTextField(placeholder: defaults[1], text: $draft.team1Player2Name, onChevronTap: { activeNameInputTarget = .team1Player2 })
                InlineCommonNameTextField(placeholder: defaults[2], text: $draft.team1Player3Name, onChevronTap: { activeNameInputTarget = .team1Player3 })
            }
            .frame(maxWidth: .infinity)

            Text(NSLocalizedString("vs_separator", value: " vs ", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 12)

            VStack(spacing: Theme.sm) {
                InlineCommonNameTextField(placeholder: defaults[3], text: $draft.team2Player1Name, onChevronTap: { activeNameInputTarget = .team2Player1 })
                InlineCommonNameTextField(placeholder: defaults[4], text: $draft.team2Player2Name, onChevronTap: { activeNameInputTarget = .team2Player2 })
                InlineCommonNameTextField(placeholder: defaults[5], text: $draft.team2Player3Name, onChevronTap: { activeNameInputTarget = .team2Player3 })
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var showsServingSideSelector: Bool {
        [
            .pingpong, .badminton, .shuttlecock, .squash, .tennis, .softTennis, .padel, .pickleball, .volleyball,
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
                    ArcheryBowAndArrowPixelShape()
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
        case .badminton, .shuttlecock, .squash: return "ic_badminton_serve"
        case .tennis, .softTennis, .padel: return "ic_tennis_serve"
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
        case .team1Player1, .team1Player2, .team1Player3, .team2Player1, .team2Player2, .team2Player3:
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
        case .team1Player3: draft.team1Player3Name = value
        case .team2Player3: draft.team2Player3Name = value
        }
    }
}

/// 1:1 复刻安卓 ic_archery_bow_and_arrow.xml：72×72 视口内的像素风弓箭，
/// 由 162 条 1 单位高的横条组成，随前景色渲染（选中高亮 / 未选中置灰）。
private struct ArcheryBowAndArrowPixelShape: Shape {
    static let pixelRows: [(x: Int, y: Int, width: Int)] = [
        (4, 4, 4), (4, 5, 4), (4, 6, 6), (62, 6, 4), (4, 7, 10), (59, 7, 7),
        (5, 8, 21), (56, 8, 10), (6, 9, 25), (53, 9, 13), (8, 10, 26), (50, 10, 16),
        (9, 11, 27), (49, 11, 16), (11, 12, 27), (49, 12, 16), (11, 13, 28), (50, 13, 15),
        (11, 14, 29), (52, 14, 12), (11, 15, 6), (21, 15, 20), (52, 15, 12), (12, 16, 6),
        (24, 16, 18), (51, 16, 13), (12, 17, 6), (26, 17, 17), (50, 17, 13), (12, 18, 6),
        (28, 18, 15), (49, 18, 14), (12, 19, 6), (29, 19, 13), (48, 19, 9), (58, 19, 5),
        (12, 20, 6), (30, 20, 11), (47, 20, 9), (58, 20, 4), (12, 21, 7), (31, 21, 9),
        (46, 21, 9), (58, 21, 4), (13, 22, 6), (32, 22, 7), (45, 22, 9), (59, 22, 2),
        (13, 23, 6), (33, 23, 5), (44, 23, 9), (13, 24, 6), (33, 24, 4), (43, 24, 9),
        (13, 25, 6), (34, 25, 2), (42, 25, 9), (13, 26, 7), (34, 26, 1), (41, 26, 9),
        (14, 27, 6), (40, 27, 9), (14, 28, 6), (39, 28, 9), (14, 29, 6), (38, 29, 9),
        (53, 29, 2), (14, 30, 6), (37, 30, 9), (52, 30, 4), (14, 31, 6), (36, 31, 9),
        (51, 31, 6), (15, 32, 6), (35, 32, 9), (50, 32, 8), (15, 33, 6), (34, 33, 9),
        (49, 33, 10), (15, 34, 6), (33, 34, 9), (48, 34, 12), (15, 35, 6), (32, 35, 9),
        (47, 35, 13), (15, 36, 6), (31, 36, 9), (46, 36, 15), (15, 37, 7), (30, 37, 9),
        (45, 37, 16), (16, 38, 6), (29, 38, 9), (47, 38, 15), (16, 39, 6), (28, 39, 9),
        (49, 39, 13), (16, 40, 5), (27, 40, 9), (50, 40, 12), (16, 41, 4), (26, 41, 9),
        (51, 41, 12), (16, 42, 3), (25, 42, 9), (52, 42, 11), (17, 43, 1), (24, 43, 9),
        (53, 43, 10), (23, 44, 9), (54, 44, 9), (22, 45, 9), (54, 45, 9), (21, 46, 9),
        (55, 46, 9), (20, 47, 9), (55, 47, 9), (19, 48, 9), (56, 48, 8), (18, 49, 9),
        (56, 49, 8), (17, 50, 9), (32, 50, 3), (56, 50, 8), (10, 51, 15), (31, 51, 9),
        (57, 51, 7), (9, 52, 15), (30, 52, 15), (57, 52, 7), (8, 53, 15), (29, 53, 22),
        (57, 53, 7), (7, 54, 15), (28, 54, 28), (57, 54, 7), (6, 55, 15), (29, 55, 35),
        (5, 56, 16), (34, 56, 30), (4, 57, 17), (40, 57, 24), (5, 58, 16), (45, 58, 20),
        (13, 59, 8), (51, 59, 14), (13, 60, 8), (56, 60, 9), (13, 61, 8), (60, 61, 5),
        (13, 62, 7), (60, 62, 6), (13, 63, 6), (61, 63, 5), (13, 64, 5), (62, 64, 6),
        (13, 65, 4), (62, 65, 6), (13, 66, 3), (63, 66, 5), (14, 67, 1), (64, 67, 4)
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 72
        let scaleY = rect.height / 72
        for row in Self.pixelRows {
            path.addRect(CGRect(
                x: rect.minX + CGFloat(row.x) * scaleX,
                y: rect.minY + CGFloat(row.y) * scaleY,
                width: CGFloat(row.width) * scaleX,
                height: scaleY
            ))
        }
        return path
    }
}
