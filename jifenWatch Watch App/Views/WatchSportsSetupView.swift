import SwiftUI

/// Setup 选项尺寸：与鸿蒙手表（36×36 / r10）、iOS 手机（44×44 / r12）同属「圆角方块」语言，
/// 数字与文字选项共用同一高度，文字选项按内容加宽。
private enum SetupChipMetrics {
    static let side: CGFloat = 36
    static let minimumHitSide: CGFloat = 44
    static let cornerRadius: CGFloat = 10
}

struct WatchSportsSetupView: View {
    @Environment(WatchLinkService.self) private var linkService

    let onStart: (WatchScoreboardLaunchConfig) -> Void

    @State private var draft: WatchSportsSetupDraft
    @State private var namesExpanded: Bool
    @State private var selectedNameIndex: Int?
    @State private var toastMessage: String?

    init(
        sport: WatchSetupSport,
        playerCount: Int? = nil,
        onStart: @escaping (WatchScoreboardLaunchConfig) -> Void
    ) {
        let initialDraft = WatchSportsSetupDraft(sport: sport, playerCount: playerCount)
        _draft = State(initialValue: initialDraft)
        _namesExpanded = State(initialValue: sport.namesInitiallyExpanded)
        self.onStart = onStart
    }

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: WatchLayout.isCompactScreen ? 8 : 10) {
                    rulesSections
                    servingSideSection
                    namesSection
                }
                .padding(.horizontal, WatchLayout.pageHorizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, formBottomPadding)
            }
            .offset(y: -10)
            .ignoresSafeArea(.container, edges: .bottom)

            VStack {
                Spacer()
                startButton
                    .padding(.horizontal, WatchLayout.pageHorizontalPadding)
                    .padding(.bottom, 6)
                    .offset(y: 28)
            }

            if let index = selectedNameIndex {
                commonNamePicker(for: index)
            }

            if let toastMessage {
                VStack {
                    Spacer()
                    WatchToastView(message: toastMessage)
                        .padding(.bottom, 62)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(selectedNameIndex != nil)
    }

    /// 悬浮「开始」：watchOS 26 起用系统 Liquid Glass 主按钮样式（旧系统回退实色胶囊）。
    @ViewBuilder
    private var startButton: some View {
        if #available(watchOS 26.0, *) {
            Button(action: start) {
                startButtonLabel(.white)
            }
            .buttonStyle(.glassProminent)
            .tint(WatchTheme.accent.opacity(0.7))
        } else {
            Button(action: start) {
                startButtonLabel(.white)
                    .background(WatchTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func startButtonLabel(_ color: Color) -> some View {
        Text(NSLocalizedString("watch_setup_start", value: "开始", comment: ""))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
    }

    /// Keeps the final form control scrollable above the overlaid start button.
    private var formBottomPadding: CGFloat {
        WatchLayout.isCompactScreen ? 72 : 80
    }

    @ViewBuilder
    private var rulesSections: some View {
        switch draft.sport {
        case .badminton, .badmintonDoubles:
            integerSection(
                title: NSLocalizedString("watch_setup_sets", value: "局数", comment: ""),
                values: [1, 3, 5],
                selection: $draft.maxSets
            )
            integerSection(
                title: NSLocalizedString("watch_setup_points_per_set", value: "每局分数", comment: ""),
                values: [11, 15, 21],
                selection: $draft.pointsPerSet
            )
        case .pingpong, .pingpongDoubles:
            integerSection(
                title: NSLocalizedString("watch_setup_sets", value: "局数", comment: ""),
                values: [1, 3, 5, 7],
                selection: $draft.maxSets
            )
            integerSection(
                title: NSLocalizedString("watch_setup_points_per_set", value: "每局分数", comment: ""),
                values: draft.pingpongPointOptions,
                selection: $draft.pointsPerSet
            )
        case .shuttlecock:
            integerSection(
                title: NSLocalizedString("watch_setup_sets", value: "局数", comment: ""),
                values: [1, 3, 5],
                selection: $draft.maxSets
            )
            integerSection(
                title: NSLocalizedString("watch_setup_points_per_set", value: "每局分数", comment: ""),
                values: [11, 15, 21],
                selection: $draft.pointsPerSet
            )
        case .squash:
            integerSection(
                title: NSLocalizedString("watch_setup_sets", value: "局数", comment: ""),
                values: [1, 3, 5, 7],
                selection: $draft.maxSets
            )
        case .foosball:
            integerSection(
                title: NSLocalizedString("watch_setup_sets", value: "局数", comment: ""),
                values: [1, 3, 5, 7],
                selection: $draft.maxSets
            )
            integerSection(
                title: NSLocalizedString("watch_setup_points_per_set", value: "每局分数", comment: ""),
                values: [5, 7, 8],
                selection: $draft.pointsPerSet
            )
            // 对齐手机：净胜 2 分只作用于决胜局，开启后才可设封顶分。
            toggleSection(
                title: NSLocalizedString("watch_setup_win_by_two", value: "决胜局净胜 2 分", comment: ""),
                isOn: $draft.foosballWinByTwo
            )
            if draft.foosballWinByTwo {
                integerSection(
                    title: NSLocalizedString("watch_setup_score_cap", value: "封顶分", comment: ""),
                    values: scoreCapOptions,
                    selection: Binding(
                        get: { draft.foosballScoreCap ?? draft.pointsPerSet + 2 },
                        set: { draft.foosballScoreCap = $0 }
                    )
                )
            }
        case .tennis, .tennisDoubles:
            integerSection(
                title: NSLocalizedString("watch_setup_sets", value: "局数", comment: ""),
                values: [1, 3, 5],
                selection: $draft.maxSets
            )
            stringSection(
                title: NSLocalizedString("watch_setup_tennis_deuce", value: "平分规则", comment: ""),
                values: [
                    ("advantage", NSLocalizedString("watch_setup_tennis_advantage", value: "占先", comment: "")),
                    ("no_ad", NSLocalizedString("watch_setup_tennis_no_ad", value: "无占先", comment: ""))
                ],
                selection: $draft.tennisDeuceMode
            )
        case .pickleball, .pickleballDoubles:
            integerSection(
                title: NSLocalizedString("watch_setup_sets", value: "局数", comment: ""),
                values: [1, 3, 5],
                selection: $draft.maxSets
            )
            integerSection(
                title: NSLocalizedString("watch_setup_target_score", value: "目标分", comment: ""),
                values: [11, 15, 21],
                selection: $draft.pickleballTargetScore
            )
            toggleSection(
                title: NSLocalizedString("watch_setup_rally_scoring", value: "每球得分", comment: ""),
                isOn: $draft.pickleballUseRallyScoring
            )
        case .eightBall:
            integerSection(
                title: NSLocalizedString("watch_setup_race_racks", value: "抢局", comment: ""),
                values: WatchSportsSetupDraft.eightBallRackValues(including: draft.eightBallTargetRacks),
                selection: Binding(
                    get: { draft.eightBallTargetRacks },
                    set: {
                        draft.eightBallTargetRacks = $0
                        draft.normalizeEightBallHandicap()
                    }
                )
            )
            // 与手机端一致：档位只显示纯数字，含义用一句例子说明，不做整表枚举。
            Text(NSLocalizedString(
                "watch_setup_race_racks_help",
                value: "选 3 = 抢3：先赢 3 局",
                comment: ""
            ))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            if draft.eightBallTargetRacks > 1 {
                handicapBeneficiarySection
                if draft.eightBallHandicapBeneficiary != .none {
                    integerSection(
                        title: NSLocalizedString("watch_setup_handicap_racks", value: "让局数", comment: ""),
                        values: Array(1...WatchSportsSetupDraft.maxEightBallHandicap(for: draft.eightBallTargetRacks)),
                        selection: Binding(
                            get: { max(1, draft.eightBallHandicapRacks) },
                            set: { draft.eightBallHandicapRacks = $0 }
                        )
                    )
                }
            }
        case .snooker:
            integerSection(
                title: NSLocalizedString("watch_setup_frames", value: "局数", comment: ""),
                values: WatchSportsSetupDraft.snookerFrameOptions,
                selection: Binding(
                    get: { draft.maxSets },
                    set: {
                        draft.maxSets = $0
                        draft.snookerCustomFrames = ""
                    }
                )
            )
            VStack(spacing: 4) {
                sectionTitle(NSLocalizedString("watch_setup_custom_frames", value: "自定义局数", comment: ""))
                TextField(
                    NSLocalizedString("watch_setup_custom_frames_placeholder", value: "1-99", comment: ""),
                    text: Binding(
                        get: { draft.snookerCustomFrames },
                        set: { updateSnookerCustomFrames($0) }
                    )
                )
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(WatchTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .football, .football5v5:
            integerSection(
                title: NSLocalizedString("watch_setup_half_length", value: "半场时长（分钟）", comment: ""),
                values: WatchSportsSetupDraft.footballHalfLengthOptions(for: draft.sport),
                selection: $draft.footballHalfLengthMinutes
            )
        case .archery, .nineBall:
            EmptyView()
        }
    }

    private var handicapBeneficiarySection: some View {
        VStack(spacing: 4) {
            sectionTitle(NSLocalizedString("watch_setup_handicap", value: "让局", comment: ""))
            adaptiveOptionRow {
                handicapChip(
                    .none,
                    label: NSLocalizedString("watch_setup_handicap_none", value: "不让局", comment: "")
                )
                handicapChip(
                    .team2,
                    label: NSLocalizedString("watch_setup_handicap_red_gives_blue", value: "红让蓝", comment: "")
                )
                handicapChip(
                    .team1,
                    label: NSLocalizedString("watch_setup_handicap_blue_gives_red", value: "蓝让红", comment: "")
                )
            }
        }
    }

    private func handicapChip(
        _ value: WatchEightBallHandicapBeneficiary,
        label: String
    ) -> some View {
        setupChip(
            label: label,
            selected: draft.eightBallHandicapBeneficiary == value,
            minimumWidth: 72,
            fontSize: 11
        ) {
            draft.eightBallHandicapBeneficiary = value
            draft.normalizeEightBallHandicap()
        }
    }

    private var namesSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    namesExpanded.toggle()
                }
            } label: {
                HStack {
                    Spacer().frame(width: 20)
                    Text(namesSectionTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .rotationEffect(.degrees(namesExpanded ? 90 : 0))
                        .frame(width: 20)
                }
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(WatchTheme.listItemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if namesExpanded {
                ForEach(0..<visibleNameCount, id: \.self) { index in
                    nameInputRow(index: index)
                }
            }
        }
    }

    private var namesSectionTitle: String {
        if draft.sport.isFootball {
            return NSLocalizedString("watch_setup_teams", value: "队伍", comment: "")
        }
        return draft.sport == .archery
            ? NSLocalizedString("watch_setup_archers", value: "射手", comment: "")
            : NSLocalizedString("watch_setup_players", value: "选手", comment: "")
    }

    private var visibleNameCount: Int {
        draft.sport.isDoubles ? 4 : draft.playerCount
    }

    private func nameInputRow(index: Int) -> some View {
        HStack(spacing: 4) {
            TextFieldLink(
                prompt: Text(namePlaceholder(index: index)),
                label: {
                    Text(
                        draft.playerNames[index].isEmpty
                            ? namePlaceholder(index: index)
                            : draft.playerNames[index]
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(
                        draft.playerNames[index].isEmpty
                            ? WatchTheme.secondaryText
                            : WatchTheme.primaryText
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                },
                onSubmit: {
                    draft.playerNames[index] = String($0.prefix(24))
                }
            )
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .frame(maxWidth: .infinity)

            Button {
                selectedNameIndex = index
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WatchTheme.secondaryText)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("watch_common_names_select_player", value: "选择选手", comment: ""))
        }
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(WatchTheme.listItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func namePlaceholder(index: Int) -> String {
        WatchDefaultTeamNames.setupParticipantName(for: draft.sport, index: index)
    }

    private func integerSection(
        title: String,
        values: [Int],
        selection: Binding<Int>
    ) -> some View {
        VStack(spacing: 4) {
            sectionTitle(title)
            adaptiveOptionRow(height: SetupChipMetrics.minimumHitSide) {
                ForEach(values, id: \.self) { value in
                    numberChip(
                        value,
                        selected: selection.wrappedValue == value
                    ) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }

    /// 封顶分候选：每局分数 +2 起，最多到 99（对齐手机 5...99 的合法区间）。
    private var scoreCapOptions: [Int] {
        let base = max(1, draft.pointsPerSet)
        return [base + 2, base + 4, base + 6, 15].filter { $0 >= base && $0 <= 99 }
    }

    /// 发球/开球方：仅对抢分制项目有意义（壁球/射箭/台球各自有专门入口）。
    @ViewBuilder
    private var servingSideSection: some View {
        if supportsServingSide {
            stringSection(
                title: draft.sport.isFootball
                    ? NSLocalizedString("watch_setup_kickoff_side", value: "开球方", comment: "")
                    : NSLocalizedString("watch_setup_serving_side", value: "发球方", comment: ""),
                values: [
                    ("left", leftSideLabel),
                    ("right", rightSideLabel)
                ],
                selection: $draft.servingSide
            )
        }
    }

    private var supportsServingSide: Bool {
        switch draft.sport {
        case .badminton, .badmintonDoubles, .pingpong, .pingpongDoubles,
             .tennis, .tennisDoubles, .pickleball, .pickleballDoubles,
             .shuttlecock, .squash, .foosball, .football, .football5v5:
            return true
        default:
            return false
        }
    }

    private var leftSideLabel: String {
        draft.sport.isFootball
            ? NSLocalizedString("team_home", value: "主队", comment: "")
            : NSLocalizedString("watch_setup_side_left", value: "红方", comment: "")
    }

    private var rightSideLabel: String {
        draft.sport.isFootball
            ? NSLocalizedString("team_away", value: "客队", comment: "")
            : NSLocalizedString("watch_setup_side_right", value: "蓝方", comment: "")
    }

    private func stringSection(
        title: String,
        values: [(String, String)],
        selection: Binding<String>
    ) -> some View {
        VStack(spacing: 4) {
            sectionTitle(title)
            adaptiveOptionRow {
                ForEach(values, id: \.0) { value, label in
                    setupChip(
                        label: label,
                        selected: selection.wrappedValue == value,
                        minimumWidth: 72
                    ) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }

    private func adaptiveOptionRow<Content: View>(
        height: CGFloat = SetupChipMetrics.side,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
                .padding(.horizontal, 3)
                .frame(minWidth: proxy.size.width, alignment: .center)
            }
        }
        .frame(height: height)
    }

    private func toggleSection(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WatchTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                Capsule()
                    .fill(isOn.wrappedValue ? WatchTheme.accent : Color.white.opacity(0.12))
                    .frame(width: 42, height: 24)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle()
                            .fill(isOn.wrappedValue ? Color.white : WatchTheme.secondaryText)
                            .frame(width: 18, height: 18)
                            .padding(3)
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(WatchTheme.listItemBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WatchTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func setupChip(
        label: String,
        selected: Bool,
        minimumWidth: CGFloat = SetupChipMetrics.side,
        fontSize: CGFloat = 13,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : WatchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 11)
                .frame(minWidth: minimumWidth)
                .frame(height: SetupChipMetrics.side)
                .background(selected ? WatchTheme.accent : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: SetupChipMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 数值方格：对齐鸿蒙手表 36×36、圆角 10（鸿蒙手机 40×40 / r12、iOS 手机 44×44 / r12 同族），
    /// 不再用胶囊，避免数字被拉成长条。
    private func numberChip(
        _ value: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text("\(value)")
                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : WatchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: SetupChipMetrics.side, height: SetupChipMetrics.side)
                .background(selected ? WatchTheme.accent : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: SetupChipMetrics.cornerRadius, style: .continuous))
                .frame(width: SetupChipMetrics.minimumHitSide, height: SetupChipMetrics.minimumHitSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func commonNamePicker(for index: Int) -> some View {
        let compact = WatchLayout.isCompactScreen
        return ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()
                .onTapGesture { selectedNameIndex = nil }

            VStack(spacing: 0) {
                WatchDialogHeader(
                    title: NSLocalizedString("watch_common_names_select_player", value: "选择选手", comment: ""),
                    onClose: { selectedNameIndex = nil }
                )
                .padding(.bottom, compact ? 10 : 12)

                let names = WatchCommonNamesStore.shared.players
                if names.isEmpty {
                    Text(NSLocalizedString("watch_common_names_no_records", value: "暂无常用名称", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: compact ? 76 : 104)
                } else {
                    ScrollView {
                        VStack(spacing: compact ? 6 : 8) {
                            ForEach(names, id: \.self) { name in
                                Button {
                                    draft.playerNames[index] = String(name.prefix(24))
                                    selectedNameIndex = nil
                                } label: {
                                    Text(name)
                                        .font(.system(size: compact ? 13 : 14, weight: .medium))
                                        .foregroundStyle(WatchTheme.primaryText)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .frame(height: compact ? 38 : 42)
                                        .background(WatchTheme.subtleFill)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: compact ? 104 : 138)
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.top, compact ? 10 : 12)
            .padding(.bottom, compact ? 10 : 14)
            .frame(maxWidth: .infinity)
            .background(WatchTheme.listItemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.top, compact ? 26 : 32)
            .padding(.bottom, compact ? 6 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func updateSnookerCustomFrames(_ rawValue: String) {
        let digits = rawValue.filter(\.isNumber)
        let clipped = String(digits.prefix(2))
        draft.snookerCustomFrames = clipped
        if let value = Int(clipped), (1...99).contains(value) {
            draft.maxSets = value
        }
    }

    private func start() {
        let enteredNames = Array(draft.playerNames.prefix(visibleNameCount))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !draft.namesAreValid(whenExpanded: namesExpanded) {
            showToast(
                NSLocalizedString(
                    "watch_setup_name_missing",
                    value: "请填完所有名称，或全部留空",
                    comment: ""
                )
            )
            return
        }

        if draft.sport == .snooker,
           !draft.snookerCustomFrames.isEmpty,
           !(1...99).contains(Int(draft.snookerCustomFrames) ?? 0) {
            showToast(NSLocalizedString("watch_setup_custom_frames_invalid", value: "请输入 1-99", comment: ""))
            return
        }

        draft.normalizeEightBallHandicap()
        draft.persistRules()
        linkService.recordCommonNameUsage(enteredNames)
        onStart(WatchScoreboardLaunchConfig(draft: draft))
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toastMessage = nil }
        }
    }
}
