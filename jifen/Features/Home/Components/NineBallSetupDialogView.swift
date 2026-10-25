import LinkCore
import ScoreCore
import SwiftUI

func nineBallText(_ key: String, _ fallback: String) -> String {
    NSLocalizedString(key, value: fallback, comment: "Nine-ball rules")
}

enum NineBallPointField: String, CaseIterable, Identifiable {
    case bigGold, smallGold, goldenNine, normalWin, foul, thirdFoul
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bigGold: nineBallText("nine_ball_big_gold", "Big gold")
        case .smallGold: nineBallText("nine_ball_small_gold", "Small gold")
        case .goldenNine: nineBallText("nine_ball_golden_nine", "Golden 9")
        case .normalWin: nineBallText("nine_ball_normal_win", "Normal win")
        case .foul: nineBallText("nine_ball_foul", "Foul")
        case .thirdFoul: nineBallText("nine_ball_third_foul", "Third-foul loss")
        }
    }
    var keyPath: WritableKeyPath<NineBallChaseConfig, Int> {
        switch self {
        case .bigGold: \.bigGold
        case .smallGold: \.smallGold
        case .goldenNine: \.goldenNine
        case .normalWin: \.normalWin
        case .foul: \.foul
        case .thirdFoul: \.thirdFoul
        }
    }
    static func summary(for family: NineBallRuleFamily) -> [Self] {
        [.foul, .normalWin, .smallGold, .bigGold] + (family == .folk ? [.goldenNine] : [])
    }
}

private struct NineBallFieldScrollTarget: Equatable {
    let fieldID: String?
    let viewportHeight: CGFloat
}

struct NineBallSetupDialogView: View {
    var initialSetup: SportsSetupResult? = nil
    var maxDialogHeight: CGFloat = 680
    var onConfirm: (SportsSetupResult) -> Void
    var onCancel: (() -> Void)?
    @State private var family: NineBallRuleFamily = .folk
    @State private var folk = NineBallChaseConfig()
    @State private var tournament = NineBallChaseConfig(ruleFamily: .tournament)
    @State private var playerCount = 2
    @State private var playerNames = (1...4).map {
        String.localizedStringWithFormat(NSLocalizedString("multi_score_player_default_format", value: "Player %d", comment: ""), $0)
    }
    @State private var folkBreaker = 0
    @State private var tournamentBreaker = 0
    @State private var activeNameIndex: Int?
    @State private var participantSelections: [String: ParticipantSelection] = [:]
    @State private var expanded = false
    @State private var showRules = false
    @State private var pointDrafts: [String: String] = [:]
    @State private var numericRevision = 0
    @State private var customRacksText = ""
    @State private var customRacksActive = false
    @State private var error = ""
    @State private var initialized = false
    @FocusState private var focusedInput: String?

    private var isFolk: Bool { family == .folk }
    private var count: Int { isFolk ? playerCount : 2 }
    private var config: NineBallChaseConfig { isFolk ? folk : tournament }
    private var configBinding: Binding<NineBallChaseConfig> { isFolk ? $folk : $tournament }
    private var breaker: Binding<Int> { isFolk ? $folkBreaker : $tournamentBreaker }
    private var fields: [NineBallPointField] { isFolk ? [.bigGold, .smallGold, .goldenNine, .normalWin, .foul] : [.bigGold, .smallGold, .normalWin, .foul, .thirdFoul] }
    private var modified: Bool {
        config != .preset(config.pointScheme, family: family) || breaker.wrappedValue != 0 || !inputsValid
    }
    private var inputsValid: Bool {
        fields.allSatisfy { field in
            let value = pointDrafts[draftKey(field)] ?? String(config[keyPath: field.keyPath])
            return Int(value).map { (1...99).contains($0) } ?? false
        } && (isFolk || !customRacksActive || Int(customRacksText).map { (1...99).contains($0) } ?? false)
    }
    private func draftKey(_ field: NineBallPointField) -> String { family.rawValue + field.rawValue }

    var body: some View {
        AdaptiveSetupDialogLayout(maxHeight: maxDialogHeight) {
            ZStack {
                HStack(spacing: 6) {
                    AppCatalogIcon(gameType: .nineBall, size: 17)
                    Text(nineBallText("nine_ball_rules_title", "Nine-ball chase"))
                        .font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.textPrimary)
                }.padding(.horizontal, 44)
                HStack {
                    Spacer()
                    Button { focusedInput = nil; showRules = true } label: {
                        Image(systemName: "questionmark.circle").foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(nineBallText("nine_ball_rules_help", "Format guide"))
                        .accessibilityIdentifier("nine_ball_setup_help")
                }.padding(.horizontal, 8)
            }.frame(height: 56)
        } content: { maxContentHeight in
            ScrollViewReader { scrollProxy in
            AdaptiveSetupDialogScrollView(maxHeight: maxContentHeight) {
                VStack(spacing: 18) {
                    Picker("", selection: $family) {
                        Text(nineBallText("nine_ball_folk", "Casual chase")).tag(NineBallRuleFamily.folk)
                        Text(nineBallText("nine_ball_tournament", "Tournament points")).tag(NineBallRuleFamily.tournament)
                    }.pickerStyle(.segmented).accessibilityIdentifier("nine_ball_family")
                    if isFolk {
                        Picker("", selection: $playerCount) {
                            ForEach(2...4, id: \.self) { n in
                                Text(String.localizedStringWithFormat(NSLocalizedString("players_count_format", value: "%d players", comment: ""), n)).tag(n)
                            }
                        }.pickerStyle(.segmented)
                    }
                    VStack(spacing: 8) {
                        ForEach(0..<count, id: \.self) { index in
                            InlineCommonNameTextField(placeholder: playerLabel(index), text: nameBinding(index),
                                onChevronTap: { focusedInput = nil; activeNameIndex = index }, leadingLabel: String(index + 1))
                        }
                    }
                    ParticipantDuplicateNamesHint(names: Array(playerNames.prefix(count)))
                    Text(NineBallPointField.summary(for: family).map { "\($0.title) \(config[keyPath: $0.keyPath])" }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("nine_ball_point_summary")
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 12) {
                            Text(nineBallText("nine_ball_points_break", "Points & break"))
                                .font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 4)
                            if modified {
                                Button(nineBallText("nine_ball_restore_preset", "Restore preset"), action: restore)
                                    .font(.system(size: 11)).foregroundStyle(Theme.primary)
                                    .accessibilityIdentifier("nine_ball_restore_preset")
                            }
                            Button { focusedInput = nil; expanded.toggle() } label: {
                                HStack(spacing: 6) {
                                    Text(expanded ? nineBallText("nine_ball_collapse", "Collapse") : nineBallText("nine_ball_adjust", "Adjust"))
                                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10))
                                }.font(.system(size: 11)).foregroundStyle(Theme.textSecondary).frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityIdentifier("nine_ball_adjust")
                                .accessibilityValue(expanded ? "expanded" : "collapsed")
                        }
                        if expanded { adjustments }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }
            .task(id: NineBallFieldScrollTarget(fieldID: focusedInput, viewportHeight: maxContentHeight)) {
                guard let fieldID = focusedInput else { return }
                // Re-run after keyboard resizing as well as initial focus.
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard focusedInput == fieldID else { return }
                withAnimation(.easeOut(duration: 0.2)) { scrollProxy.scrollTo(fieldID, anchor: .center) }
            }
            }
        } actions: {
            VStack(spacing: 8) {
                if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(Theme.destructiveText) }
                HStack(spacing: 12) {
                    Button { onCancel?() } label: {
                        Text(NSLocalizedString("cancel", comment: "")).foregroundStyle(Theme.textPrimary)
                            .frame(width: 100, height: 44).background(Theme.dialogControlBackground).clipShape(Capsule())
                    }
                    Button { focusedInput = nil; Task { await confirm() } } label: {
                        Text(NSLocalizedString("start_game", comment: "")).fontWeight(.medium).foregroundStyle(Theme.textOnPrimary)
                            .frame(maxWidth: .infinity).frame(height: 44).background(Theme.primary).clipShape(Capsule())
                    }.disabled(!inputsValid).opacity(inputsValid ? 1 : 0.4).accessibilityIdentifier("nine_ball_setup_start")
                }.font(.system(size: 16))
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 16)
        }
        .sheet(isPresented: $showRules) { NavigationStack { NineBallRulesView(folk: folk, tournament: tournament) } }
        .sheet(isPresented: Binding(get: { activeNameIndex != nil }, set: { if !$0 { activeNameIndex = nil } })) {
            if let index = activeNameIndex {
                CommonNameSelectorDialog(nameType: .player,
                    unavailablePeople: Set(validParticipantSelections.filter { $0.key != "player:\(index)" }.values.compactMap(\.personRef)),
                    onParticipantSelect: { selection in
                        if selection.personRef != nil { participantSelections["player:\(index)"] = selection }
                        else { participantSelections.removeValue(forKey: "player:\(index)") }
                    }) { value in
                    playerNames[index] = value; activeNameIndex = nil
                }
            }
        }
        .onAppear(perform: applyInitialSetup)
        .onChange(of: playerCount) { _, count in folkBreaker = min(folkBreaker, count - 1) }
        .onChange(of: family) { _, _ in focusedInput = nil; error = "" }
        .onChange(of: focusedInput) { _, input in
            if input == "racks", !customRacksActive {
                customRacksActive = true; customRacksText = String(tournament.totalRacks)
            }
        }
    }

    private var adjustments: some View {
        VStack(spacing: 10) {
            if isFolk {
                HStack {
                    Text(nineBallText("nine_ball_point_scheme", "Point scheme")).font(.system(size: 13))
                    Spacer()
                    Picker("", selection: Binding(get: { folk.pointScheme }, set: { scheme in
                        numericRevision += 1; focusedInput = nil
                        let base = NineBallChaseConfig.preset(scheme)
                        folk.pointScheme = scheme; folk.bigGold = base.bigGold; folk.smallGold = base.smallGold
                        folk.goldenNine = base.goldenNine; folk.normalWin = base.normalWin; folk.foul = base.foul
                        pointDrafts = pointDrafts.filter { !$0.key.hasPrefix("folk") }
                    })) { ForEach(NineBallPointScheme.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(maxWidth: 170)
                }
            }
            ForEach(fields) { field in pointRow(field) }
            Divider().padding(.vertical, 4)
            HStack {
                Text(nineBallText("nine_ball_first_breaker", "First break"))
                Spacer()
                Picker("", selection: breaker) {
                    ForEach(0..<count, id: \.self) { Text(resolvedName($0)).tag($0) }
                }.pickerStyle(.menu).tint(Theme.primary)
            }
            if isFolk {
                if count > 2 { Toggle(nineBallText("nine_ball_small_gold_all_pay", "Small gold: all opponents pay"), isOn: $folk.smallGoldAllPay) }
                Toggle(nineBallText("nine_ball_gold_retains_break", "Big gold / golden 9 winner breaks"), isOn: $folk.goldRetainsBreak)
                Toggle(nineBallText("nine_ball_handoff_enabled", "Allow handoff"), isOn: $folk.handoffEnabled)
            } else {
                HStack {
                    Text(nineBallText("nine_ball_break_rule", "Break order")); Spacer()
                    Picker("", selection: $tournament.breakRule) {
                        Text(nineBallText("nine_ball_winner_breaks", "Winner breaks")).tag(NineBallBreakRule.winner)
                        Text(nineBallText("nine_ball_alternate_breaks", "Alternate breaks")).tag(NineBallBreakRule.alternate)
                    }.pickerStyle(.menu).tint(Theme.primary)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(nineBallText("nine_ball_total_racks", "Total racks"))
                    NineBallWrappingLayout(spacing: 8) {
                        ForEach([1, 5, 10, 20], id: \.self) { n in
                            Button { focusedInput = nil; customRacksActive = false; customRacksText = ""; tournament.totalRacks = n } label: {
                                Text(String(n)).frame(width: 44, height: 44)
                                    .background(!customRacksActive && tournament.totalRacks == n ? Theme.primary.opacity(0.15) : Theme.dialogControlBackground)
                                    .foregroundStyle(!customRacksActive && tournament.totalRacks == n ? Theme.primary : Theme.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.accessibilityIdentifier("nine_ball_racks_\(n)")
                        }
                        TextField(NSLocalizedString("custom", comment: ""), text: Binding(get: { customRacksText }, set: { text in
                            guard focusedInput == "racks" else { return }
                            customRacksText = String(text.filter(\.isNumber).prefix(2))
                            if let value = Int(customRacksText), (1...99).contains(value) { tournament.totalRacks = value }
                        })).keyboardType(.numberPad).multilineTextAlignment(.center)
                            .focused($focusedInput, equals: "racks").frame(width: 64, height: 44)
                            .background(Theme.dialogControlBackground).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(!customRacksActive ? Color.clear : Theme.primary, lineWidth: 1))
                            .accessibilityIdentifier("nine_ball_custom_racks").id("racks")
                    }.frame(maxWidth: .infinity)
                    Text(nineBallText("nine_ball_racks_hint", "Total racks, not a race to wins. Ties go to extra racks."))
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }.font(.system(size: 14)).foregroundStyle(Theme.textPrimary).tint(Theme.primary)
    }

    private func pointRow(_ field: NineBallPointField) -> some View {
        let revision = numericRevision
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.title)
                if field == .thirdFoul { Text(nineBallText("nine_ball_third_hint", "Ends the rack; no additional foul or win points."))
                    .font(.system(size: 10)).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                Button { step(field, -1) } label: { Image(systemName: "minus").frame(width: 37, height: 40) }
                    .disabled(config[keyPath: field.keyPath] <= 1).accessibilityLabel("− \(field.title)")
                Divider().frame(height: 22)
                TextField("", text: Binding(get: { pointDrafts[draftKey(field)] ?? String(config[keyPath: field.keyPath]) }, set: { value in
                    guard numericRevision == revision, focusedInput == draftKey(field) else { return }
                    let raw = String(value.filter(\.isNumber).prefix(2)); pointDrafts[draftKey(field)] = raw
                    if let n = Int(raw), (1...99).contains(n) { configBinding.wrappedValue[keyPath: field.keyPath] = n }
                })).keyboardType(.numberPad).multilineTextAlignment(.center).monospacedDigit().frame(width: 43, height: 40)
                    .focused($focusedInput, equals: draftKey(field)).accessibilityLabel(field.title)
                    .accessibilityIdentifier("nine_ball_points_\(field.rawValue)")
                Divider().frame(height: 22)
                Button { step(field, 1) } label: { Image(systemName: "plus").frame(width: 37, height: 40) }
                    .disabled(config[keyPath: field.keyPath] >= 99).accessibilityLabel("+ \(field.title)")
            }.font(.system(size: 15)).background(Theme.dialogControlBackground).clipShape(Capsule()).fixedSize()
        }.frame(minHeight: 44).buttonStyle(.plain).id(draftKey(field))
    }
    private func step(_ field: NineBallPointField, _ delta: Int) {
        let value = min(99, max(1, config[keyPath: field.keyPath] + delta))
        configBinding.wrappedValue[keyPath: field.keyPath] = value; pointDrafts[draftKey(field)] = String(value)
    }
    private func restore() {
        numericRevision += 1
        focusedInput = nil
        configBinding.wrappedValue = .preset(config.pointScheme, family: family)
        pointDrafts = pointDrafts.filter { !$0.key.hasPrefix(family.rawValue) }; breaker.wrappedValue = 0
        if !isFolk { customRacksActive = false; customRacksText = "" }; error = ""
    }
    private func playerLabel(_ index: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString("multi_score_player_default_format", value: "Player %d", comment: ""), index + 1)
    }
    private func resolvedName(_ index: Int) -> String { let value = playerNames[index].trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? playerLabel(index) : value }
    private func nameBinding(_ index: Int) -> Binding<String> { Binding(get: { playerNames[index] }, set: {
        if $0 != participantSelections["player:\(index)"]?.name { participantSelections.removeValue(forKey: "player:\(index)") }
        playerNames[index] = $0
    }) }
    private var validParticipantSelections: [String: ParticipantSelection] {
        participantSelections.filter { key, value in
            guard let index = Int(key.replacingOccurrences(of: "player:", with: "")), index < count, playerNames.indices.contains(index) else { return false }
            return value.personRef != nil && value.name == playerNames[index]
        }
    }
    private func applyInitialSetup() {
        guard !initialized else { return }; initialized = true
        guard let setup = initialSetup, case let .nineBall(names, config) = setup.billiardsConfiguration(for: .nineBall) else { return }
        family = config.ruleFamily
        if family == .folk { folk = config; folkBreaker = setup.nineBallBreakerPlayer ?? 0 } else {
            tournament = config; tournamentBreaker = min(1, max(0, setup.nineBallBreakerPlayer ?? 0))
            if ![1, 5, 10, 20].contains(config.totalRacks) { customRacksActive = true; customRacksText = String(config.totalRacks) }
        }
        playerCount = min(4, max(2, names.count)); folkBreaker = min(playerCount - 1, max(0, folkBreaker))
        for (index, name) in names.prefix(4).enumerated() { playerNames[index] = name }
        participantSelections = setup.participantSelections ?? [:]
    }
    @MainActor private func confirm() async {
        guard inputsValid else { return }
        let names = (0..<count).map(resolvedName)
        guard !ParticipantIdentityRules.containsDuplicatePerson(Array(validParticipantSelections.values)) else { error = identityText("already_playing", "你已在其他位置参赛"); return }
        for (index, name) in names.enumerated() where name != playerLabel(index) { await CommonNamesManager.shared.saveNameIfNeeded(name, .player) }
        var result = SportsSetupResult(team1Name: names[0], team2Name: names[1], team3Name: names.count > 2 ? names[2] : nil,
            team4Name: names.count > 3 ? names[3] : nil, nineBallBigGold: config.bigGold, nineBallSmallGold: config.smallGold,
            nineBallGoldenNine: config.goldenNine, nineBallNormalWin: config.normalWin, nineBallBallInHand: 1, nineBallFoul: config.foul,
            nineBallBreakerPlayer: breaker.wrappedValue, nineBallSmallGoldAllPay: isFolk && count > 2 && config.smallGoldAllPay,
            nineBallGoldRetainsBreak: config.goldRetainsBreak, nineBallRuleFamily: family.rawValue, nineBallPointScheme: config.pointScheme.rawValue,
            nineBallHandoffEnabled: config.handoffEnabled, nineBallThirdFoul: config.thirdFoul, nineBallBreakRule: config.breakRule.rawValue,
            nineBallTotalRacks: config.totalRacks, playerCount: count, playerNames: names)
        result.participantSelections = validParticipantSelections.isEmpty ? nil : validParticipantSelections
        onConfirm(result)
    }
}

struct NineBallWrappingLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(width: proposal.width ?? 320, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = positions(width: bounds.width, subviews: subviews)
        for (index, point) in layout.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func positions(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
