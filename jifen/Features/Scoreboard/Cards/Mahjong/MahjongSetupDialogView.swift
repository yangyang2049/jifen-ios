//
//  MahjongSetupDialogView.swift
//  jifen
//
//  麻将开局设置：字段、默认值与联动规则逐一对齐安卓 `MahjongSetupDialog.kt`。
//  座位风不可编辑（由初始庄家推导）；选择四川血战会强制底分 2、封顶 4 番。
//

import ScoreCore
import SwiftUI

/// 设置结果 → core 开局参数（安卓 `ScoreLaunchStore.mahjongSetup` 的 iOS 对应物）。
/// 只做一次映射，不在 app 侧重复校验：金额/番数区间由 `MahjongSetupResult` 自己判定。
extension SportsSetupResult {
    /// 由 setup 表单构造麻将开局参数；字段缺失时回落到通用记账默认值。
    var mahjongSetup: MahjongSetupResult? {
        let names = (playerNames ?? [team1Name, team2Name]).prefix(MAHJONG_PLAYER_COUNT).map { name in
            resolvedScoreboardSetupName(name, fallback: "")
        }
        guard names.count == MAHJONG_PLAYER_COUNT else { return nil }
        let resolvedRuleset = MahjongRuleset(rawValue: mahjongRuleset ?? MahjongRuleset.generic.rawValue) ?? .generic
        let resolvedMatchLength = MahjongMatchLength(rawValue: mahjongMatchLength ?? MahjongMatchLength.free.rawValue) ?? .free
        let resolvedDealerRule = MahjongDealerRule(rawValue: mahjongDealerRule ?? MahjongDealerRule.rotateEachHand.rawValue) ?? .rotateEachHand
        let dealerIndex = mahjongInitialDealerIndex ?? 0
        let setup = MahjongSetupResult(
            playerNames: Array(names),
            seatWinds: mahjongSeatWindsForDealer(dealerIndex: dealerIndex),
            ruleset: resolvedRuleset,
            startScore: mahjongStartScore ?? 0,
            baseScore: mahjongBaseScore ?? (resolvedRuleset == .sichuanBloodBattle ? 2 : 1),
            initialDealerIndex: dealerIndex,
            matchLength: resolvedMatchLength,
            dealerRule: resolvedDealerRule,
            maxFan: mahjongMaxFan ?? 4
        )
        return setup.validationError() == nil ? setup : nil
    }
}

enum MahjongSetupPolicy {
    /// 安卓 `limitCommonNameLength`：姓名最多 24 个字符。
    static let maximumNameLength = 24

    static func sanitizeName(_ raw: String) -> String {
        String(raw.prefix(maximumNameLength))
    }

    /// 安卓 `NumberField(signed:)`：只允许数字，signed 时允许一个前导负号。
    static func sanitizeNumber(_ raw: String, signed: Bool) -> String {
        let digits = raw.filter { $0.isNumber }
        guard signed, let first = raw.first, first == "-" else { return digits }
        return "-" + digits
    }

    /// 安卓 `isScoreRangeSafe`：底分 × 2^封顶番数不能溢出记分区间。
    static func isScoreRangeSafe(ruleset: MahjongRuleset, baseScore: Int, maxFan: Int) -> Bool {
        MahjongSetupResult(
            ruleset: ruleset,
            baseScore: baseScore,
            maxFan: maxFan
        ).isScoreRangeSafe
    }
}

struct MahjongSetupDialogView: View {
    let maxDialogHeight: CGFloat
    var initialSetup: SportsSetupResult? = nil
    let onConfirm: (SportsSetupResult) -> Void
    var onCancel: (() -> Void)? = nil

    @State private var playerNames: [String]
    @State private var ruleset: MahjongRuleset
    @State private var startScoreText: String
    @State private var baseScoreText: String
    @State private var dealerIndex: Int
    @State private var matchLength: MahjongMatchLength
    @State private var dealerRule: MahjongDealerRule
    @State private var maxFanText: String
    @State private var showsAdvanced = false
    @State private var activeCommonNameIndex: Int? = nil

    private let windCodes = ["east", "south", "west", "north"]

    init(
        maxDialogHeight: CGFloat,
        initialSetup: SportsSetupResult? = nil,
        onConfirm: @escaping (SportsSetupResult) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.maxDialogHeight = maxDialogHeight
        self.initialSetup = initialSetup
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let setup = initialSetup?.mahjongSetup
        let dealer = setup?.initialDealerIndex ?? 0
        let defaultNames = setup?.playerNames ?? mahjongDefaultPlayerNamesForDealer(dealerIndex: dealer)
        _playerNames = State(initialValue: Array(defaultNames.prefix(MAHJONG_PLAYER_COUNT)) +
            Array(repeating: "", count: max(0, MAHJONG_PLAYER_COUNT - defaultNames.count)))
        _ruleset = State(initialValue: setup?.ruleset ?? .generic)
        _startScoreText = State(initialValue: String(setup?.startScore ?? 0))
        _baseScoreText = State(initialValue: String(setup?.baseScore ?? 1))
        _dealerIndex = State(initialValue: dealer)
        _matchLength = State(initialValue: setup?.matchLength ?? .free)
        _dealerRule = State(initialValue: setup?.dealerRule ?? .rotateEachHand)
        _maxFanText = State(initialValue: String(setup?.maxFan ?? 4))
    }

    private var seatLabels: [String] {
        mahjongSeatWindsForDealer(dealerIndex: dealerIndex).map { code in
            windLabel(windCodes.firstIndex(of: code) ?? 0)
        }
    }

    private func windLabel(_ index: Int) -> String {
        let keys = ["mahjong_seat_east", "mahjong_seat_south", "mahjong_seat_west", "mahjong_seat_north"]
        let fallbacks = ["东", "南", "西", "北"]
        return NSLocalizedString(keys[index], value: fallbacks[index], comment: "Mahjong seat wind")
    }

    private var parsedStartScore: Int? { Int(startScoreText) }
    private var parsedBaseScore: Int? { Int(baseScoreText) }
    private var parsedMaxFan: Int? { Int(maxFanText) }

    private var trimmedNames: [String] { playerNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }

    /// 安卓 `valid`：四家非空且互不相同、三个数字字段合法、区间安全。
    private var canConfirm: Bool {
        trimmedNames.allSatisfy { !$0.isEmpty }
            && Set(trimmedNames).count == MAHJONG_PLAYER_COUNT
            && parsedStartScore != nil
            && (parsedBaseScore ?? 0) > 0
            && (parsedMaxFan.map { (0...30).contains($0) } ?? false)
            && MahjongSetupPolicy.isScoreRangeSafe(
                ruleset: ruleset,
                baseScore: parsedBaseScore ?? 0,
                maxFan: parsedMaxFan ?? 0
            )
    }

    var body: some View {
        AdaptiveSetupDialogLayout(maxHeight: maxDialogHeight) {
            HStack(spacing: 6) {
                Text("🀄").font(.system(size: 20))
                Text(NSLocalizedString("mahjong_setup_title", value: "麻将记分设置", comment: "")
                    + NSLocalizedString("setup_suffix", value: " 设置", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.horizontal, Theme.md)
        } content: { maxContentHeight in
            AdaptiveSetupDialogScrollView(maxHeight: maxContentHeight, bottomClearance: 88) {
                VStack(alignment: .leading, spacing: Theme.md) {
                    ForEach(0..<MAHJONG_PLAYER_COUNT, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text(seatLabels[index])
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.primary)
                                .frame(minWidth: 24)
                            InlineCommonNameTextField(
                                placeholder: playerPlaceholder(index),
                                text: Binding(
                                    get: { playerNames.indices.contains(index) ? playerNames[index] : "" },
                                    set: { playerNames[index] = MahjongSetupPolicy.sanitizeName($0) }
                                ),
                                onChevronTap: { activeCommonNameIndex = index }
                            )
                            .accessibilityIdentifier("mahjong_setup_player_\(index)")
                        }
                    }

                    setupLabel(NSLocalizedString("mahjong_ruleset", value: "模板", comment: ""))
                    chipRow([
                        (MahjongRuleset.generic.rawValue, NSLocalizedString("mahjong_ruleset_generic", value: "通用记账", comment: "")),
                        (MahjongRuleset.sichuanBloodBattle.rawValue, NSLocalizedString("mahjong_ruleset_sichuan", value: "四川血战", comment: ""))
                    ], selected: ruleset.rawValue) { value in
                        ruleset = MahjongRuleset(rawValue: value) ?? .generic
                        if ruleset == .sichuanBloodBattle {
                            // 安卓：选择血战强制底分 2、封顶 4 番。
                            baseScoreText = "2"
                            maxFanText = "4"
                        }
                    }

                    HStack(spacing: 10) {
                        numberField(
                            NSLocalizedString("mahjong_start_score", value: "起始分", comment: ""),
                            text: $startScoreText,
                            signed: true
                        )
                        numberField(
                            NSLocalizedString("mahjong_base_score", value: "底分", comment: ""),
                            text: $baseScoreText,
                            signed: false
                        )
                    }

                    Button {
                        showsAdvanced.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(NSLocalizedString("mahjong_advanced_settings", value: "高级设置", comment: ""))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.primary)
                            Image(systemName: showsAdvanced ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mahjong_setup_advanced")

                    if showsAdvanced {
                        advancedSection
                    }
                }
                .padding(.horizontal, Theme.lg)
                .padding(.vertical, Theme.md)
            }
        } actions: {
            HStack(spacing: Theme.md) {
                Button(action: { onCancel?() }) {
                    Text(NSLocalizedString("cancel", comment: "Cancel button"))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 100, height: 44)
                        .background(Theme.dialogControlBackground)
                        .cornerRadius(.infinity)
                }
                .buttonStyle(.plain)

                Button(action: confirm) {
                    Text(NSLocalizedString("start_game", comment: "Start Game button"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(canConfirm ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(canConfirm ? Theme.primary : Theme.dialogControlBackground)
                        .cornerRadius(.infinity)
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)
                .accessibilityIdentifier("mahjong_setup_start")
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
                    playerNames[index] = MahjongSetupPolicy.sanitizeName(name)
                }
                activeCommonNameIndex = nil
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            setupLabel(NSLocalizedString("mahjong_initial_dealer", value: "初始庄家", comment: ""))
            chipRow(
                (0..<MAHJONG_PLAYER_COUNT).map { ("\($0)", seatLabels[safe: $0] ?? "\($0 + 1)") },
                selected: "\(dealerIndex)"
            ) { value in
                guard let next = Int(value) else { return }
                // 安卓：名字仍是默认四家时随庄家一起轮转。
                if trimmedNames == mahjongDefaultPlayerNamesForDealer(dealerIndex: dealerIndex) {
                    playerNames = mahjongDefaultPlayerNamesForDealer(dealerIndex: next)
                }
                dealerIndex = next
            }

            setupLabel(NSLocalizedString("mahjong_match_length", value: "局程", comment: ""))
            chipRow([
                (MahjongMatchLength.free.rawValue, NSLocalizedString("mahjong_match_free", value: "自由局", comment: "")),
                (MahjongMatchLength.eastOnly.rawValue, NSLocalizedString("mahjong_match_east", value: "东风圈", comment: "")),
                (MahjongMatchLength.hanchan.rawValue, NSLocalizedString("mahjong_match_hanchan", value: "半庄", comment: ""))
            ], selected: matchLength.rawValue) { value in
                matchLength = MahjongMatchLength(rawValue: value) ?? .free
            }

            setupLabel(NSLocalizedString("mahjong_dealer_rule", value: "庄家规则", comment: ""))
            chipRow([
                (MahjongDealerRule.rotateEachHand.rawValue, NSLocalizedString("mahjong_dealer_rotate", value: "每手轮庄", comment: "")),
                (MahjongDealerRule.dealerWinOrDrawStays.rawValue, NSLocalizedString("mahjong_dealer_stays", value: "庄家胡牌/流局连庄", comment: ""))
            ], selected: dealerRule.rawValue) { value in
                dealerRule = MahjongDealerRule(rawValue: value) ?? .rotateEachHand
            }

            if ruleset == .sichuanBloodBattle {
                // 封顶番数只在四川血战下出现（安卓同条件）。
                numberField(
                    NSLocalizedString("mahjong_max_fan", value: "封顶番数", comment: ""),
                    text: $maxFanText,
                    signed: false
                )
            }
        }
    }

    private func playerPlaceholder(_ index: Int) -> String {
        let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
        return "\(base) \(index + 1)"
    }

    private func setupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
    }

    private func numberField(_ label: String, text: Binding<String>, signed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            TextField("", text: Binding(
                get: { text.wrappedValue },
                set: { text.wrappedValue = MahjongSetupPolicy.sanitizeNumber($0, signed: signed) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .foregroundStyle(Theme.textPrimary)
            .keyboardType(signed ? .numbersAndPunctuation : .numberPad)
            .padding(.horizontal, Theme.sm)
            .frame(height: 44)
            .background(Theme.dialogControlBackground)
            .cornerRadius(Theme.sm)
        }
        .frame(maxWidth: .infinity)
    }

    private func chipRow(_ options: [(String, String)], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    Button {
                        onSelect(option.0)
                    } label: {
                        Text(option.1)
                            .font(.system(size: 14, weight: selected == option.0 ? .semibold : .regular))
                            .foregroundStyle(selected == option.0 ? Color.white : Theme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(selected == option.0 ? Theme.primary : Theme.dialogControlBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func confirm() {
        guard canConfirm else { return }
        let names = trimmedNames
        var result = SportsSetupResult(team1Name: names[0], team2Name: names[1])
        result.team3Name = names[2]
        result.team4Name = names[3]
        result.playerCount = MAHJONG_PLAYER_COUNT
        result.playerNames = names
        result.mahjongRuleset = ruleset.rawValue
        result.mahjongStartScore = parsedStartScore
        result.mahjongBaseScore = parsedBaseScore
        result.mahjongInitialDealerIndex = dealerIndex
        result.mahjongMatchLength = matchLength.rawValue
        result.mahjongDealerRule = dealerRule.rawValue
        result.mahjongMaxFan = parsedMaxFan
        onConfirm(result)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
