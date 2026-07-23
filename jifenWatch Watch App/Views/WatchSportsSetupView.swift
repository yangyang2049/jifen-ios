import SwiftUI

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
                    namesSection
                }
                .padding(.horizontal, WatchLayout.isCompactScreen ? 10 : 14)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .offset(y: -10)
            .ignoresSafeArea(.container, edges: .bottom)

            VStack {
                Spacer()
                startButton
                    .padding(.horizontal, WatchLayout.isCompactScreen ? 22 : 44)
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
    }

    private var startButton: some View {
        Button(action: start) {
            Text(NSLocalizedString("watch_setup_start", value: "开始", comment: ""))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(WatchTheme.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                values: [5, 7, 9, 11, 15, 21],
                selection: $draft.pointsPerSet
            )
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
                title: NSLocalizedString("watch_setup_target_racks", value: "目标局数", comment: ""),
                values: WatchSportsSetupDraft.eightBallRackOptions,
                selection: Binding(
                    get: { draft.eightBallTargetRacks },
                    set: {
                        draft.eightBallTargetRacks = $0
                        draft.normalizeEightBallHandicap()
                    }
                )
            )
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
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .archery, .nineBall:
            EmptyView()
        }
    }

    private var handicapBeneficiarySection: some View {
        VStack(spacing: 4) {
            sectionTitle(NSLocalizedString("watch_setup_handicap", value: "让局", comment: ""))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
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
                .padding(.horizontal, 3)
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
        draft.sport == .archery
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
        }
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(WatchTheme.listItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func namePlaceholder(index: Int) -> String {
        if draft.sport == .archery {
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_setup_archer_number", value: "射手 %d", comment: ""),
                index + 1
            )
        }
        if draft.sport.isDoubles {
            let keys = [
                ("watch_setup_red_a", "红A"),
                ("watch_setup_red_b", "红B"),
                ("watch_setup_blue_a", "蓝A"),
                ("watch_setup_blue_b", "蓝B")
            ]
            return NSLocalizedString(keys[index].0, value: keys[index].1, comment: "")
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_setup_player_number", value: "选手 %d", comment: ""),
            index + 1
        )
    }

    private func integerSection(
        title: String,
        values: [Int],
        selection: Binding<Int>
    ) -> some View {
        VStack(spacing: 4) {
            sectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if values.count > 3 { Spacer().frame(width: 18) }
                    ForEach(values, id: \.self) { value in
                        setupChip(
                            label: String(value),
                            selected: selection.wrappedValue == value
                        ) {
                            selection.wrappedValue = value
                        }
                    }
                    if values.count > 3 { Spacer().frame(width: 18) }
                }
            }
        }
    }

    private func stringSection(
        title: String,
        values: [(String, String)],
        selection: Binding<String>
    ) -> some View {
        VStack(spacing: 4) {
            sectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
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
                            .fill(isOn.wrappedValue ? Color.black : WatchTheme.secondaryText)
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
        minimumWidth: CGFloat = 44,
        fontSize: CGFloat = 13,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(selected ? Color.black : WatchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .frame(minWidth: minimumWidth)
                .frame(height: 38)
                .background(selected ? WatchTheme.accent : Color.white.opacity(0.10))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func commonNamePicker(for index: Int) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { selectedNameIndex = nil }

            VStack(spacing: 10) {
                Text(NSLocalizedString("watch_common_names_select_player", value: "选择选手", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WatchTheme.primaryText)

                let names = WatchCommonNamesStore.shared.players
                if names.isEmpty {
                    Text(NSLocalizedString("watch_common_names_no_records", value: "暂无常用名称", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .frame(height: 100)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(names, id: \.self) { name in
                                Button {
                                    draft.playerNames[index] = String(name.prefix(24))
                                    selectedNameIndex = nil
                                } label: {
                                    Text(name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(WatchTheme.primaryText)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .frame(height: 44)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 132)
                }

                Button {
                    selectedNameIndex = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WatchTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: 208)
            .background(WatchTheme.listItemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
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
