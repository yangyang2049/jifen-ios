import SwiftUI
import PersistenceCore

// MARK: - 入口参数

/// 台球开赛 / 补记 / 编排的入口参数。
///
/// 2026-11-14 起入口是**一步式**：概览底栏的「开始计分 / 补记赛果」直接进本页（配置页），
/// 不再先弹「先选玩法」层。玩法在页内顶部一排 4 个 chip 里选，九球的民间 / 比赛积分是页内分段。
/// 活动场次、编排、待上传修复、作废后更正仍按服务端冻结口径进同一页。
nonisolated struct BilliardsEntryRequest: Identifiable, Sendable {
    enum Mode: String, Sendable {
        /// 开赛：自由局（POST /games）或活动场次续打。
        case launch
        /// 补记：自由补记、活动场次补记、待上传修复、作废后更正。
        case manual
        /// 编排：活动「添加场次 / 编辑第 N 场」，保存即 PUT lineup。
        case arrange
    }
    var id = UUID()
    var mode: Mode
    /// 已知变体（活动场次 / 编排预填 / 修复 / 更正）。自由入口留空：进页时预选本机上次在该小组
    /// 开过的玩法（对应安卓 BilliardsUploads.launch 的 rules.variant → groupOf），没有记录就落在九球。
    var variant: GroupBilliardsVariant? = nil
    var activityID: String? = nil
    var activitySessionID: String? = nil
    var gameID: String? = nil
    /// 待上传队列行 id：按队列里的冻结请求体回填。
    var uploadID: String? = nil
    /// 原赛果 id：作废后按原成绩回填更正。
    var correctionID: String? = nil
    /// 服务端冻结的规则（活动场次 / 修复 / 更正）。
    var rules: GroupBilliardsRules? = nil
    var seats: [GroupBilliardsSeat] = []
    var allowedMemberIDs: [String]? = nil
    /// 编排场景的场次序号（编辑第 N 场时用于按钮文案，0 表示新增）。
    var orderNo: Int = 0
    /// 冻结场次只能沿原规则续打或补记：玩法 chip 与席位只读，规则只给摘要，
    /// 不出现展开箭头与「调整」入口（对齐安卓 BilliardsRulesSummary）。
    var frozen: Bool { rules != nil && mode != .arrange }
    var canAdjustAtStart = false
}

/// 卡片内次级控件的统一底色：浅色白底 + 1px 描边，深色沿用既有层次。
/// 对齐安卓 groupControlOnCard* / controlOnCard* 两组 token 的取舍，
/// 只作用于台球入口页与台球页签，不做全 App 扫描式改造。
enum BilliardsControlStyle {
    static let fill = GroupEditorColors.control
    static let stroke = Color(uiColor: .separator)
}

extension View {
    /// 次按钮 / 徽章 / 席位块 / 输入位共用这一层底。
    /// 选中态用主色实底 + 白字（AGENTS：实心绿按钮必须白字），不再是深色下也看不清的灰叠灰。
    func billiardsControl(active: Bool = false, radius: CGFloat = 10) -> some View {
        foregroundStyle(active ? Theme.textOnPrimary : Theme.textPrimary)
            .background(active ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(BilliardsControlStyle.fill),
                        in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(active ? Theme.primary : BilliardsControlStyle.stroke, lineWidth: 1))
    }
}

// MARK: - 一步式配置页

/// 开赛 / 补记 / 编排共用的一张配置页（对齐安卓 BilliardsEntryScreen + BilliardsSetupLayout）：
///
/// - 顶部一排 4 个玩法组 chip（九球合一，可横滑），进页预选本机上次开过的玩法；
/// - 除「规则设置」外不出现任何小标题；某个玩法没有的项整块不渲染；
/// - 参赛成员：两人 A 方 / B 方两列，三 / 四人纵向带序号，下方一排组内成员胶囊；
/// - 底部吸底主操作只有一个。
struct GroupBilliardsEntryView: View {
    let detail: GroupDetailCache
    let request: BilliardsEntryRequest
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var onDone: () -> Void = {}
    var hostsScoreboardSetup = false

    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var group: GroupBilliardsGroup
    @State private var rules: GroupBilliardsRules
    @State private var selected = ["", "", "", ""]
    @State private var activeSeat: Int?
    private struct PickerSeat: Identifiable { let id: Int }
    @State private var pickerSeat: PickerSeat?
    @State private var reducedToTwo = false
    private var usesMatchPicker: Bool { request.mode == .launch && !request.frozen }
    private var pickerRosterGroupID: String? { request.allowedMemberIDs == nil ? detail.group.id : nil }
    @State private var scoreSeat: BilliardsScoreSeat?
    @State private var scores = ["0", "0", "0", "0"]
    @State private var racks = ""
    @State private var early = false
    @State private var playedAt = Date()
    @State private var rulesExpanded = false
    @State private var sessionID: String
    @State private var repairBody: GroupBilliardsSubmission?
    @State private var extraMembers: [GroupMember] = []
    @State private var temporaryName = ""
    @State private var busy = false
    @State private var error: String?
    @State private var initialized = false

    init(detail: GroupDetailCache, request: BilliardsEntryRequest, hostsScoreboardSetup: Bool = false, onStart: @escaping (GameType, SportsSetupResult, String) -> Void, onDone: @escaping () -> Void = {}) {
        self.detail = detail
        self.request = request
        self.onStart = onStart
        self.hostsScoreboardSetup = hostsScoreboardSetup
        self.onDone = onDone
        let seed = request.rules ?? GroupBilliardsRules.defaults(request.variant ?? .folk)
        _rules = State(initialValue: seed)
        _group = State(initialValue: GroupBilliardsGroup.group(of: seed.knownVariant ?? request.variant ?? .folk))
        _sessionID = State(initialValue: request.uploadID ?? "ios-" + UUID().uuidString)
        var seats = ["", "", "", ""]
        for seat in request.seats {
            let position = seat.participant.position
            if (0..<4).contains(position) { seats[position] = seat.memberId }
        }
        _selected = State(initialValue: seats)
    }

    // MARK: 派生状态

    private var writable: Bool { detail.group.isActive && store.enabled && SessionStore.shared.isAuthenticated }
    private var manager: Bool { GroupPermissions.manager(detail.members.first { $0.accountId == store.accountID }) }
    private var canEditPlannedRules: Bool {
        request.canAdjustAtStart && request.mode == .launch && (request.gameID?.isEmpty ?? true) && manager
    }
    private var choices: [GroupMember] {
        let members = store.cache.details[detail.group.id]?.members ?? detail.members
        let active = (members + extraMembers.filter { added in !members.contains { $0.id == added.id } })
            .filter { $0.status == "active" }
        return active.filter { request.allowedMemberIDs == nil || request.allowedMemberIDs!.contains($0.id) }
    }
    /// 玩法组 → 后端合法变体。冻结场次直接用快照里的变体，避免「界面换族、请求换族」两套口径。
    private var backendVariant: GroupBilliardsVariant {
        if request.frozen, let known = request.rules?.knownVariant { return known }
        return group.backend(family: rules.family.rawValue)
    }
    /// 人数只有九球民间可调；锦标赛与其余玩法固定 2 人（与后端变体语义一致）。
    private var count: Int { backendVariant == .folk ? min(4, max(2, rules.playerCount)) : 2 }
    private var seatIDs: [String] { (0..<count).map { seatID($0) } }
    private var firstEmptyIndex: Int? { (0..<count).first { seatIDs[$0].isEmpty } }
    /// 下一个要填的席位：点过座位用它，否则用第一个空位。
    private var targetSeat: Int? { activeSeat ?? firstEmptyIndex }
    private var ready: Bool {
        let ids = seatIDs
        guard ids.count == count, ids.allSatisfy({ !$0.isEmpty }) else { return false }
        // 冻结场次的席位来自服务端快照：即使成员已不在在组列表里，也要允许续打 / 补记。
        if request.frozen { return Set(ids).count == ids.count }
        let canonicals = ids.map { id in choices.first { $0.id == id }?.canonicalMemberId ?? id }
        return Set(ids).count == ids.count && Set(canonicals).count == ids.count
            && ids.allSatisfy { id in choices.contains { $0.id == id } }
    }
    private var participants: [GroupBilliardsParticipant] {
        (0..<count).map { GroupBilliardsParticipant(participantId: "p\($0)", memberId: seatID($0), position: $0) }
    }
    private var netTotal: Int { scores.prefix(count).reduce(0) { $0 + (Int($1) ?? 0) } }
    /// 规则摘要：折叠时只露这一行，展开明细仍在同一张卡里。
    private var rulesSummary: String { rules.summary }
    /// 页面标题沿用开赛 / 补记 / 编排三种模式；编排必须是「编排场次」，不能复用「录入赛果」。
    private var title: String {
        switch request.mode {
        case .manual: billiardsText("manual")
        case .launch: groupText("copy_start_score", "Start scoring")
        case .arrange: groupText("edit_lineup", "Arrange match")
        }
    }
    /// 底部只有一个主操作：编排=保存 / 冻结续打=继续计分 / 开赛=开始计分 / 补记=保存并提交成绩。
    /// 席位没选齐时按钮禁用，文案改成「选择第 N 位参赛者」。
    private var ctaTitle: String {
        guard ready else { return String(format: billiardsText("choose_member"), (firstEmptyIndex ?? 0) + 1) }
        switch request.mode {
        case .arrange: return groupText("save", "Save")
        case .launch: return request.gameID?.isEmpty == false ? billiardsText("resume") : groupText("copy_start_score", "Start scoring")
        case .manual:
            if !validFolkScores { return billiardsText("invalid_score") }
            return canSubmit ? billiardsText("submit") : billiardsText("balance")
        }
    }

    private func seatID(_ position: Int) -> String { selected.indices.contains(position) ? selected[position] : "" }
    private func member(_ position: Int) -> GroupMember? { choices.first { $0.id == seatID(position) } }
    private func seatName(_ position: Int) -> String {
        if let live = member(position)?.displayName, !live.isEmpty { return live }
        if let frozen = request.seats.first(where: { $0.participant.position == position })?.displayName, !frozen.isEmpty { return frozen }
        return ""
    }
    /// 两人 = A1 / B1；三 / 四人 = 1 / 2 / 3 / 4（与 GroupInlineMatchRoster 同一套编号）。
    /// 席位编号：不论几人局都从 1 开始（两人局旧版是 A1/B1，与三四人局的 1234 不一致，已统一）。
    private func badge(_ index: Int) -> String { "\(index + 1)" }

    // MARK: 版式

    var body: some View {
        Group {
            if hostsScoreboardSetup { scoreboardSetup.interactiveDismissDisabled(busy) }
            else { entryContent }
        }.groupAccountBoundary()
    }

    @ViewBuilder private var scoreboardSetup: some View {
        if initialized {
            let setup = try? rules.setup(names: [])
            let selection = GroupSetupSelection(groupID: detail.group.id, members: choices, ids: $selected, busy: busy, error: error,
                                                projectRow: AnyView(projectRow))
            if group == .nineBall {
                NineBallSetupDialogView(initialSetup: setup, onConfirm: submitSharedSetup,
                    onCancel: { if !busy { dismiss() } }, groupSelection: selection)
            } else {
                let game = group.backend(family: rules.family.rawValue).gameType
                SportsSetupDialogView(gameType: game, defaultTeam1Name: "", defaultTeam2Name: "",
                    initialMaxSets: setup?.maxSets, initialPointsPerSet: nil, initialTieBreakPoints: nil,
                    initialSetup: setup, onConfirm: submitSharedSetup, onCancel: { if !busy { dismiss() } },
                    groupSelection: selection).id(game)
            }
        } else {
            ProgressView().task { await prepare() }
        }
    }

    private func submitSharedSetup(_ setup: SportsSetupResult) {
        let variant = group.backend(family: setup.nineBallRuleFamily ?? "folk")
        var next = GroupBilliardsRules.defaults(variant, count: setup.playerCount ?? 2)
        switch variant {
        case .folk, .tournament:
            next.initialBreakerParticipantId = setup.nineBallBreakerPlayer.map { "p\($0)" }
            next.config.bigGold = setup.nineBallBigGold
            next.config.smallGold = setup.nineBallSmallGold
            next.config.normalWin = setup.nineBallNormalWin
            next.config.foul = setup.nineBallFoul
            if variant == .folk {
                next.config.pointScheme = setup.nineBallPointScheme
                next.config.goldenNine = setup.nineBallGoldenNine
                next.config.smallGoldAllPay = setup.nineBallSmallGoldAllPay
                next.config.goldRetainsBreak = setup.nineBallGoldRetainsBreak
                next.config.handoffEnabled = setup.nineBallHandoffEnabled
            } else {
                next.config.thirdFoul = setup.nineBallThirdFoul
                next.config.breakRule = setup.nineBallBreakRule
                next.config.totalRacks = setup.nineBallTotalRacks
            }
        case .eight:
            next.config.targetRacks = setup.maxSets ?? 9
            let handicap = min(setup.eightBallHandicapRacks ?? 0, (next.config.targetRacks ?? 9) - 1)
            next.config.handicapRacks = handicap
            next.config.handicapBeneficiary = handicap > 0 ? (setup.eightBallHandicapBeneficiary == "team1" ? "p0" : "p1") : nil
        case .snooker:
            next.config.maxFrames = setup.maxSets ?? 1
            next.initialBreakerParticipantId = setup.servingSide == "right" ? "p1" : "p0"
        case .standard: break
        }
        rules = next
        guard ready, writable else { return }
        Task { await start() }
    }

    private var entryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let error { GroupNotice(text: error) }
                if busy { ProgressView().frame(maxWidth: .infinity) }
                if rules.knownVariant == nil { GroupNotice(text: billiardsText("unsupported")) }
                projectRow
                // 九球的民间 / 比赛积分是页内分段，不是第 5 个项目；其它玩法整块不渲染。
                if !request.frozen, group == .nineBall {
                    if !usesMatchPicker { familySegment }
                    // 人数只有九球民间可调，锦标赛与其余玩法固定 2 人，不出现这一块。
                    if backendVariant == .folk { playerCountSegment }
                }
                seatsBlock
                if usesMatchPicker {
                    if [.folk, .tournament, .snooker].contains(backendVariant) { openingBreaker }
                    if backendVariant == .tournament { openingRacks }
                    if group == .nineBall { familySegment }
                    if reducedToTwo {
                        Text(NSLocalizedString("billiards_group_switch_to_two", value: "Switched to 2 players", comment: ""))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                rulesSection
                if request.mode == .manual { scoreSection }
            }
            .padding(Theme.padding).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor).scrollDismissesKeyboard(.interactively)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .sheet(item: $scoreSeat) { seat in
            BilliardsScorePanel(name: seatName(seat.id), score: $scores[seat.id])
                .groupAccountBoundary()
        }
        .sheet(item: $pickerSeat) { seat in
            NavigationStack {
                GroupMemberSelector(title: billiardsText("select") + " · " + badge(seat.id),
                                    selectedID: Binding(get: { seatID(seat.id) }, set: { memberID in
                                        guard usesMatchPicker, seat.id < count else { return }
                                        selected[seat.id] = memberID
                                    }),
                                    members: choices, excluded: Set((0..<count).filter { $0 != seat.id }.map(seatID)),
                                    rosterGroupID: pickerRosterGroupID, matchPicker: true)
            }.groupAccountBoundary()
        }
        .task { await prepare() }
        .onChange(of: count) { _, value in
            if let activeSeat, activeSeat >= value { self.activeSeat = nil }
        }
    }

    /// 项目：一排 4 个玩法组 chip，可横滑；冻结场次只读。
    private var projectRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.sm) {
                ForEach(GroupBilliardsGroup.allCases) { value in
                    let active = group == value
                    Button { pick(group: value) } label: {
                        Text(value.title).font(GroupTypography.caption.weight(.medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, Theme.spacing).frame(minHeight: 40)
                            .billiardsControl(active: active, radius: usesMatchPicker ? 8 : 20)
                    }.buttonStyle(.plain)
                        .disabled(request.frozen || busy)
                        .accessibilityAddTraits(active ? .isSelected : [])
                        .accessibilityIdentifier("billiards_variant_chip_" + value.rawValue)
                }
            }.padding(.vertical, 1)
        }.accessibilityIdentifier("billiards_variant_row")
    }

    /// 九球的民间追分 / 比赛积分：页内分段，选中态主色实底 + 白字。
    private var familySegment: some View {
        HStack(spacing: 0) {
            ForEach(GroupBilliardsFamily.allCases) { family in
                let active = rules.family == family
                Button { pick(family: family) } label: {
                    Text(family.title).font(GroupTypography.caption.weight(.medium))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(active ? Theme.textOnPrimary : Theme.textPrimary)
                        .background(active ? Theme.primary : Color.clear)
                }.buttonStyle(.plain).disabled(busy)
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("billiards_family_" + family.rawValue)
            }
        }
        .background(BilliardsControlStyle.fill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BilliardsControlStyle.stroke, lineWidth: 1))
    }

    /// 人数：九球民间 2 / 3 / 4。
    private var playerCountSegment: some View {
        HStack(spacing: Theme.sm) {
            ForEach(2...4, id: \.self) { value in
                let active = count == value
                Button { pick(count: value) } label: {
                    Text(String(value)).font(GroupTypography.body.weight(.medium))
                        .frame(minWidth: 44, minHeight: 40)
                        .billiardsControl(active: active, radius: 10)
                }.buttonStyle(.plain).disabled(busy)
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("billiards_count_\(value)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 参赛成员（不设标题）

    /// 座位与成员胶囊同处一块：点座位 → 选中该位；点下面的成员 → 填进当前位；再点一次已在场的人 → 移出。
    private var seatsBlock: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            if manager, !request.frozen, request.mode == .arrange { temporaryRow }
            if count == 2 {
                // 两人局也用序号 1 / 2，不再显示 A / B 侧标签：
                // 台球是个人对抗，侧标签与席位里的序号徽标重复表达同一件事。
                HStack(alignment: .top, spacing: Theme.spacing) {
                    ForEach(0..<2, id: \.self) { index in
                        seatButton(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(spacing: Theme.sm) {
                    ForEach(0..<count, id: \.self) { index in seatButton(index) }
                }
            }
            if !request.frozen, !usesMatchPicker { memberChips }
        }
    }

    private func seatButton(_ index: Int) -> some View {
        let highlighted = !request.frozen && !usesMatchPicker && (activeSeat == index || (activeSeat == nil && firstEmptyIndex == index))
        let name = seatName(index)
        return Button {
            guard !request.frozen, !busy else { return }
            if usesMatchPicker { pickerSeat = PickerSeat(id: index) }
            else { activeSeat = index }
        } label: {
            HStack(spacing: Theme.sm) {
                if let member = member(index) {
                    GroupAvatar(name: name, url: member.avatarUrl, size: 22)
                } else {
                    // 空位只放加号图标占位，不放文字符号。
                    Image(systemName: "plus").font(.system(size: Theme.fontBody2))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.textSecondary)
                        .background(Theme.primary.opacity(0.12), in: Circle())
                }
                Text(name.isEmpty ? billiardsText("select") : name)
                    .font(GroupTypography.body).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(badge(index)).font(GroupTypography.caption.weight(.semibold)).opacity(0.72)
            }
            .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .billiardsControl(active: highlighted, radius: 10)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(request.frozen || busy)
            .accessibilityIdentifier("billiards_seat_\(index)")
            .accessibilityLabel(badge(index)).accessibilityValue(name)
            .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    /// 一排组内成员胶囊（可换行），不标「我 / 队员」身份。
    private var memberChips: some View {
        GroupMemberPoolLayout(spacing: Theme.xs) {
            ForEach(choices) { member in
                let assigned = (0..<count).first { seatID($0) == member.id }
                Button { pick(member: member) } label: {
                    HStack(spacing: Theme.xs) {
                        GroupAvatar(name: member.displayName, url: member.avatarUrl, size: 18)
                        Text(member.displayName).font(GroupTypography.caption.weight(.medium)).lineLimit(1)
                        if let assigned { Text(badge(assigned)).font(GroupTypography.caption.weight(.semibold)).opacity(0.8) }
                    }
                    .padding(.horizontal, Theme.sm).padding(.vertical, 6)
                    .frame(minHeight: 36)
                    .billiardsControl(active: assigned != nil, radius: 18)
                }.buttonStyle(.plain)
                    .disabled(busy || (assigned == nil && targetSeat == nil))
                    .accessibilityIdentifier("billiards_member_" + member.id)
                    .accessibilityAddTraits(assigned == nil ? [] : .isSelected)
            }
            if request.mode == .manual, let groupID = pickerRosterGroupID {
                GroupRosterAddButton(groupID: groupID, chip: true)
            }
        }
    }

    private var temporaryRow: some View {
        HStack(spacing: Theme.sm) {
            TextField(billiardsText("new_member"), text: $temporaryName)
                .font(GroupTypography.body).tint(Theme.primary)
                .padding(.horizontal, Theme.sm).frame(minHeight: 40)
                .billiardsControl(radius: 10)
                .accessibilityIdentifier("billiards_temporary_name")
            Button(billiardsText("add_member")) { Task { await addTemporary() } }
                .font(GroupTypography.caption.weight(.semibold)).foregroundStyle(Theme.primary)
                .padding(.horizontal, Theme.spacing).frame(minHeight: 40)
                .billiardsControl(radius: 10)
                .buttonStyle(.plain)
                .disabled(busy || temporaryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("billiards_add_temporary")
        }
    }

    private var openingBreaker: some View {
        HStack {
            Text(billiardsText("breaker")).font(GroupTypography.body)
            Spacer()
            Picker(billiardsText("breaker"), selection: Binding(
                get: { rules.initialBreakerParticipantId ?? "p0" },
                set: { rules.initialBreakerParticipantId = $0 }
            )) {
                ForEach(0..<count, id: \.self) { index in
                    let name = seatName(index)
                    Text(name.isEmpty ? badge(index) : "\(badge(index)) · \(name)").tag("p\(index)")
                }
            }.pickerStyle(.menu).tint(Theme.primary).accessibilityIdentifier("billiards_breaker")
        }.disabled(busy)
    }

    private var openingRacks: some View {
        Stepper(value: Binding(get: { rules.config.totalRacks ?? 10 }, set: { rules.config.totalRacks = $0 }), in: 1...99) {
            Text(billiardsText("total_racks") + " · " + String(rules.config.totalRacks ?? 10))
                .font(GroupTypography.body)
        }.disabled(busy).accessibilityIdentifier("billiards_total_racks")
    }

    // MARK: 规则设置（页面上唯一带标题的一块）

    @ViewBuilder private var rulesSection: some View {
        if request.frozen && !canEditPlannedRules {
            // 冻结场次只给摘要文本：不出现展开箭头，也没有「调整」入口。
            GroupSectionTitle(title: billiardsText("rules"))
            GroupSurface {
                Text(rulesSummary).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).groupLineHeight(.caption)
                    .accessibilityIdentifier("billiards_rules_summary")
            }
        } else if rules.knownVariant?.hasAdjustableRules == true {
            GroupSectionTitle(title: billiardsText("rules"))
            GroupSurface {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    Button { withAnimation(.easeInOut(duration: 0.18)) { rulesExpanded.toggle() } } label: {
                        HStack(spacing: Theme.sm) {
                            Text(rulesSummary).font(GroupTypography.caption).foregroundStyle(Theme.textPrimary)
                                .lineLimit(3).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true).groupLineHeight(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .font(.system(size: Theme.fontCaption, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .rotationEffect(.degrees(rulesExpanded ? 180 : 0))
                        }
                        .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(busy)
                        .accessibilityIdentifier("billiards_rules_toggle")
                        .accessibilityValue(rulesExpanded ? "expanded" : "collapsed")
                    if rulesExpanded {
                        Divider()
                        BilliardsRuleDetailFields(rules: $rules, group: group, names: (0..<count).map(seatName), inlineOpening: !usesMatchPicker)
                            .accessibilityIdentifier("billiards_rules_detail")
                    }
                }
            }
        }
        // 普通台球只记净胜分，没有任何可调规则：整块「规则设置」不出现。
    }

    // MARK: 补记字段（逐人成绩 / ± 与净积分合计 / 已完成局数 / 提前结束 / 时间）

    private var scoreSection: some View {
        GroupSurface {
            VStack(alignment: .leading, spacing: Theme.sm) {
                ForEach(0..<count, id: \.self) { index in
                    HStack(spacing: Theme.sm) {
                        Text(seatName(index)).font(GroupTypography.body).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if backendVariant == .folk { folkScoreButton(index) }
                        else { scoreField(index) }
                    }
                }
                if backendVariant == .folk {
                    Text(String(format: billiardsText("net_total"), netTotal))
                        .font(GroupTypography.caption)
                        .foregroundStyle(netTotal == 0 ? Theme.textSecondary : Theme.destructiveText)
                        .accessibilityIdentifier("billiards_net_total")
                }
                if backendVariant == .tournament {
                    HStack(spacing: Theme.sm) {
                        Text(billiardsText("completed_racks")).font(GroupTypography.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TextField("0", text: $racks).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .font(GroupTypography.body).padding(.horizontal, Theme.sm).frame(maxWidth: 96, minHeight: 40)
                            .billiardsControl(radius: 10)
                            .accessibilityIdentifier("billiards_completed_racks")
                    }
                }
                if ![.folk, .standard].contains(backendVariant) {
                    Toggle(billiardsText("early_stop"), isOn: $early)
                        .font(GroupTypography.body).tint(Theme.primary)
                        .accessibilityIdentifier("billiards_early_stop")
                }
                HStack(spacing: Theme.sm) {
                    Text(billiardsText("played_at")).font(GroupTypography.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DatePicker("", selection: $playedAt, in: ...Date()).labelsHidden()
                        .accessibilityIdentifier("billiards_played_at")
                }
            }
        }
    }

    private func scoreField(_ index: Int) -> some View {
        TextField("0", text: Binding(get: { scores.indices.contains(index) ? scores[index] : "0" },
                                    set: { if scores.indices.contains(index) { scores[index] = $0 } }))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing).font(GroupTypography.body)
            .padding(.horizontal, Theme.sm).frame(maxWidth: 96, minHeight: 40)
            .billiardsControl(radius: 10)
            .accessibilityIdentifier("billiards_score_\(index)")
    }

    private func folkScoreButton(_ index: Int) -> some View {
        let score = Int(scores[index]) ?? 0
        let enabled = !seatID(index).isEmpty
        return Button { scoreSeat = .init(id: index) } label: {
            Text(enabled ? (scores[index].isEmpty ? "—" : (score > 0 ? "+\(score)" : "\(score)")) : billiardsText("score"))
                .font(GroupTypography.body.monospacedDigit())
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.sm).frame(minWidth: 96, minHeight: 44)
                .billiardsControl()
        }.buttonStyle(.plain).disabled(!enabled || busy)
            .accessibilityLabel(seatName(index) + " · " + billiardsText("score"))
            .accessibilityValue("\(score)")
            .accessibilityIdentifier("billiards_score_\(index)")
    }

    /// 补记的民间追分要求「净积分合计 = 0」才能提交，这里直接禁用主按钮（红字提示仍在成绩卡里）。
    private var validFolkScores: Bool {
        // 面板「清空」写回空串，净积分按 0 计；这里同样把空串当 0，否则清零后永远提交不了。
        backendVariant != .folk || scores.prefix(count).allSatisfy { $0.isEmpty || Int($0) != nil }
    }

    private var canSubmit: Bool {
        guard ready else { return false }
        if request.mode == .manual, backendVariant == .folk { return validFolkScores && netTotal == 0 }
        return true
    }

    private var footer: some View {
        GroupAlignedFooter {
            Button(ctaTitle) { Task { await primary() } }
                .buttonStyle(GroupAlignedActionStyle())
                .disabled(!canSubmit || busy || !writable)
                .accessibilityIdentifier(request.mode == .manual ? "billiards_submit" : "billiards_cta")
        }
    }

    // MARK: 交互

    private func pick(group value: GroupBilliardsGroup) {
        guard !request.frozen, !busy, group != value else { return }
        group = value
        if hostsScoreboardSetup { selected = ["", "", "", ""] }
        reducedToTwo = false
        // 切玩法：本机有同玩法的上次记录就按它预填，否则按目标玩法的默认值。
        let remembered = try? GroupBilliardsPersistence.shared.rememberedRules(accountID: store.accountID ?? "", groupID: detail.group.id)
        if let remembered, remembered.knownVariant != nil, remembered.group == value {
            rules = remembered
        } else {
            rules = GroupBilliardsRules.defaults(for: value, family: .folk)
        }
        activeSeat = nil
        rulesExpanded = false
    }

    private func pick(family value: GroupBilliardsFamily) {
        guard !request.frozen, !busy, rules.family != value else { return }
        // 与计分板的台球设置一致：切到锦标赛固定 2 人，民间沿用当前人数。
        let nextCount = value == .tournament ? 2 : min(4, max(2, rules.playerCount))
        reducedToTwo = usesMatchPicker && nextCount < count
        if reducedToTwo {
            for index in nextCount..<selected.count { selected[index] = "" }
        }
        rules = rules.converting(to: group.backend(family: value.rawValue), count: nextCount)
        activeSeat = nil
    }

    private func pick(count value: Int) {
        guard !request.frozen, !busy, rules.playerCount != value else { return }
        rules.playerCount = value
        rules.initialBreakerParticipantId = nil
        if let activeSeat, activeSeat >= value { self.activeSeat = nil }
    }

    /// 点成员：已在本场 → 移出；否则填进当前空位。
    private func pick(member: GroupMember) {
        guard !request.frozen, !busy else { return }
        var ids = seatIDs
        if let assigned = ids.firstIndex(of: member.id) {
            ids[assigned] = ""
            selected = ids
            activeSeat = assigned
            return
        }
        guard let seat = targetSeat, seat < ids.count else { return }
        ids[seat] = member.id
        selected = ids
        activeSeat = nil
    }

    private func addTemporary() async {
        guard !busy, manager, let account = store.accountID else { return }
        let name = temporaryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            let member: GroupMember = try await store.repository.write("/\(detail.group.id)/members/temporary", body: GroupActionBody(displayName: name))
            guard store.accountID == account else { return }
            extraMembers.append(member); temporaryName = ""
        } catch { self.error = groupErrorMessage(error) }
    }

    // MARK: 预填与回填

    private func prepare() async {
        guard !initialized else { return }
        initialized = true
        let account = store.accountID ?? ""
        if !request.frozen, request.rules == nil {
            // 预选顺序与安卓一致：入口明确指定的变体（活动默认规则）优先，
            // 其次是本机上次在该小组开过的玩法，最后才是九球默认值。
            if let variant = request.variant {
                group = GroupBilliardsGroup.group(of: variant)
                rules = GroupBilliardsRules.defaults(variant)
            } else if let remembered = try? GroupBilliardsPersistence.shared.rememberedRules(accountID: account, groupID: detail.group.id),
                      remembered.knownVariant != nil {
                group = remembered.group
                rules = remembered
                if backendVariant != .folk { rules.playerCount = 2 }
            }
        }
        if let uploadID = request.uploadID, let upload = try? GroupBilliardsPersistence.shared.rows(accountID: account, groupID: detail.group.id).first(where: { $0.id == uploadID }) {
            do {
                var body = upload.body
                if body == nil, let record = ScoreboardRecordManager.shared.loadAllRecords().first(where: { $0.id == upload.id }), let source = record.billiardsSource {
                    // 没有冻结请求体时从本地比赛记录重建（锦标赛要带上已完成局数）。
                    let values = (record.extraData?["chasePlayerPoints"]?.value as? [Int]) ?? [record.team1SetScore ?? record.team1FinalScore, record.team2SetScore ?? record.team2FinalScore]
                    let completedRacks = max(0, (record.extraData?["chaseRoundNumber"]?.value as? Int ?? 1) - 1)
                    body = .init(rules: source.rules, participants: source.participants, clientSessionId: source.clientSessionID,
                                 activityId: source.activityID, activitySessionId: source.activitySessionID, gameId: source.gameID,
                                 clientRecordId: upload.id, playedAt: Int64((record.endTime ?? record.startTime).timeIntervalSince1970 * 1000),
                                 source: "manual", result: .init(resultKind: source.rules.knownVariant?.resultKind ?? "", completion: "completed",
                                                                 scores: values.enumerated().map { .init(participantId: "p\($0.offset)", points: $0.element) },
                                                                 completedRacks: source.rules.knownVariant == .tournament ? completedRacks : nil))
                }
                guard let body else { throw GroupBilliardsError.result }
                repairBody = body
                apply(body: body)
            } catch { self.error = groupErrorMessage(error) }
        }
        if let correctionID = request.correctionID {
            do {
                let row: GroupBilliardsRow = try await store.repository.read("/\(detail.group.id)/results/\(correctionID)")
                apply(row: row)
            } catch { self.error = groupErrorMessage(error) }
        }
    }

    private func apply(body: GroupBilliardsSubmission) {
        apply(rules: body.rules)
        sessionID = body.clientSessionId
        for participant in body.participants where (0..<4).contains(participant.position) { selected[participant.position] = participant.memberId }
        for score in body.result.scores { if let index = Int(score.participantId.dropFirst()), (0..<4).contains(index) { scores[index] = String(score.points) } }
        racks = String(body.result.completedRacks ?? 0)
        early = body.result.completion == "early_stop"
        playedAt = Date(timeIntervalSince1970: Double(body.playedAt) / 1000)
    }

    private func apply(row: GroupBilliardsRow) {
        apply(rules: row.rules)
        for seat in row.participants where (0..<4).contains(seat.participant.position) { selected[seat.participant.position] = seat.memberId }
        for score in row.result.scores { if let index = Int(score.participantId.dropFirst()), (0..<4).contains(index) { scores[index] = String(score.points) } }
        racks = String(row.result.completedRacks ?? 0)
        early = row.result.completion == "early_stop"
        playedAt = Date(timeIntervalSince1970: Double(row.playedAt) / 1000)
    }

    /// 冻结规则回填时 chip 与分段要跟着快照走，不能停在进页时的默认玩法上。
    private func apply(rules value: GroupBilliardsRules) {
        rules = value
        if let known = value.knownVariant { group = GroupBilliardsGroup.group(of: known) }
    }

    // MARK: 主操作

    private func primary() async {
        guard !busy, canSubmit, writable else { return }
        switch request.mode {
        case .arrange: await submitArrange()
        case .manual: await submitManual()
        case .launch: await start()
        }
    }

    private func finish() {
        onDone()
        dismiss()
    }

    /// 编排（添加 / 编辑第 N 场）：本页自己取最新 lineup、算好新场次并带上 revision 提交。
    private func submitArrange() async {
        guard let account = store.accountID, !busy else { return }
        busy = true; defer { busy = false }
        let revision = store.identityRevision
        do { try rules.validate() } catch { self.error = groupErrorMessage(error); return }
        let success = await store.perform {
            let lineup: GroupBilliardsLineup = try await store.repository.read("/\(detail.group.id)/activities/\(request.activityID ?? "")/lineup")
            var sessions = lineup.sessions.filter { $0.id != request.activitySessionID }.map(\.submission)
            let edited = lineup.sessions.first { $0.id == request.activitySessionID }
            let order = edited?.orderNo ?? ((sessions.map(\.orderNo).max() ?? 0) + 1)
            let minutes = lineup.sessionMinutes > 0 ? lineup.sessionMinutes : 30
            let start = edited?.startsAt ?? (lineup.activity.startsAt + Int64(order - 1) * Int64(minutes) * 60_000)
            sessions.append(.init(id: edited?.id, orderNo: order, court: edited?.court ?? "", startsAt: start, rules: rules, participants: participants))
            let _: GroupBilliardsLineup = try await store.repository.write("/\(detail.group.id)/activities/\(request.activityID ?? "")/lineup",
                body: GroupBilliardsLineupBody(sessionMinutes: minutes, sessions: sessions), method: .put, revision: lineup.revision)
        }
        guard store.matchesIdentity(account, revision: revision) else { return }
        if success { finish() } else { error = store.error }
    }

    /// 补记：写入本机队列并立刻尝试同步，失败也保留本地行（可修正 / 仅重试）。
    private func submitManual() async {
        guard let account = store.accountID, !busy else { return }
        busy = true; defer { busy = false }
        let revision = store.identityRevision
        do {
            try rules.validate()
            let points = try scores.prefix(count).enumerated().map { index, text -> GroupBilliardsScore in
                guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GroupBilliardsError.result }
                return .init(participantId: "p\(index)", points: value)
            }
            if backendVariant == .folk {
                guard points.reduce(Int64(0), { $0 + Int64($1.points) }) == 0 else { throw GroupBilliardsError.result }
            }
            let result = GroupBilliardsResult(resultKind: backendVariant.resultKind,
                                              completion: early ? "early_stop" : "completed", scores: points,
                                              completedRacks: backendVariant == .tournament ? Int(racks) : nil)
            let body = GroupBilliardsSubmission(rules: rules, participants: participants,
                                                clientSessionId: repairBody?.clientSessionId ?? sessionID,
                                                activityId: repairBody?.activityId ?? request.activityID,
                                                activitySessionId: repairBody?.activitySessionId ?? request.activitySessionID,
                                                gameId: repairBody?.gameId ?? (request.gameID?.isEmpty == false ? request.gameID : nil),
                                                clientRecordId: sessionID,
                                                playedAt: Int64(playedAt.timeIntervalSince1970 * 1000), source: "manual", result: result)
            try body.validate()
            try GroupBilliardsPersistence.shared.rememberRules(rules, accountID: account, groupID: detail.group.id)
            let row = GroupBilliardsUpload(id: sessionID, accountID: account, groupID: detail.group.id, body: body)
            if request.uploadID != nil { try GroupBilliardsPersistence.shared.repair(row) }
            else { try GroupBilliardsPersistence.shared.add(row) }
            guard store.matchesIdentity(account, revision: revision) else { return }
            await GroupBilliardsSync.shared.sync()
            guard store.matchesIdentity(account, revision: revision) else { return }
            finish()
        } catch { if store.matchesIdentity(account, revision: revision) { self.error = groupErrorMessage(error) } }
    }

    private func start() async {
        guard let account = store.accountID, !busy else { return }
        busy = true; defer { busy = false }
        let revision = store.identityRevision
        do {
            try rules.validate()
            try GroupBilliardsPersistence.shared.rememberRules(rules, accountID: account, groupID: detail.group.id)
            let names = (0..<count).map { seatName($0) }
            let setup = try rules.setup(names: names)
            let variant = try rules.knownVariant.unwrapOrThrow()
            if let gameID = request.gameID, !gameID.isEmpty {
                // 冻结场次只能同机续打：本机没有该 gameId 的快照时按「其它设备开局」提示补记。
                let sources = try GroupBilliardsPersistence.shared.sources(accountID: account, groupID: detail.group.id)
                guard let local = sources.first(where: { $0.value.gameID == gameID }) else { throw GroupBilliardsError.otherDevice }
                do {
                    let frozen: BilliardsFrozenGame = try await store.repository.read("/\(detail.group.id)/games/\(gameID)")
                    guard frozen.state == "started" else { throw GroupBilliardsError.otherDevice }
                } catch is URLError {
                    // 本机草稿允许离线续打，上传时会重新校验冻结对局。
                }
                guard store.matchesIdentity(account, revision: revision) else { return }
                // 先退出本页再推计分板：onStart 会往同一条导航栈里 append，顺序反了会把刚 push 的计分板顶掉。
                finish()
                onStart(variant.gameType, setup, local.key)
                return
            }
            let existing = try await ResumeSessionRepository().liveEntries()
            guard existing.isEmpty else { throw GroupBilliardsError.unfinished }
            nonisolated struct Game: Encodable, Sendable {
                var clientSessionId: String; var rules: GroupBilliardsRules; var participants: [GroupBilliardsParticipant]
                var activityId: String?; var activitySessionId: String?
            }
            var game: String?
            do {
                let response: GroupGameResponse = try await store.repository.write("/\(detail.group.id)/games",
                    body: Game(clientSessionId: sessionID, rules: rules, participants: participants,
                               activityId: request.activityID, activitySessionId: request.activitySessionID), key: sessionID)
                game = response.gameId
            } catch {
                // 自由局允许离线开局（本机保存、联网后补传），活动场次必须拿到服务端 gameId。
                guard request.activityID == nil, error is URLError else { throw error }
            }
            guard let recordID = await BookingStartPersistence.persist(.init(bookingId: "", gameType: variant.gameType, setup: setup)) else {
                if let game { try? await store.repository.action("/\(detail.group.id)/games/\(game)/abandon") }
                throw GroupFormError.saveFailed
            }
            let source = GroupBilliardsSource(accountID: account, groupID: detail.group.id, groupName: detail.group.name,
                                              clientSessionID: sessionID, gameID: game, activityID: request.activityID,
                                              activitySessionID: request.activitySessionID, rules: rules, participants: participants, names: names)
            try GroupBilliardsPersistence.shared.saveSource(source, recordID: recordID)
            guard store.matchesIdentity(account, revision: revision) else { return }
            // 先关闭配置页，再进入计分板（与安卓 popBackStack → navigate 同序）。
            finish()
            onStart(variant.gameType, setup, recordID)
        } catch { if store.matchesIdentity(account, revision: revision) { self.error = groupErrorMessage(error) } }
    }
}

private extension Optional {
    func unwrapOrThrow() throws -> Wrapped { guard let value = self else { throw GroupBilliardsError.rules }; return value }
}

nonisolated private struct BilliardsFrozenGame: Decodable, Sendable { var state: String }

// MARK: - 页内规则细则

/// 规则细则（对齐安卓 BilliardsInlineSetup）：九球两族 / 黑八让局 / 斯诺克局数。
/// 这里**不含**玩法与人数选择（已由顶部 chip 与页内分段负责），
/// 因此可以整块塞进「规则设置」卡片里，折叠时只露一行摘要。
struct BilliardsRuleDetailFields: View {
    @Binding var rules: GroupBilliardsRules
    var group: GroupBilliardsGroup
    var names: [String] = []
    var inlineOpening = true

    private func number(_ path: WritableKeyPath<GroupBilliardsConfig, Int?>, default value: Int = 1) -> Binding<Int> {
        Binding(get: { rules.config[keyPath: path] ?? value }, set: { rules.config[keyPath: path] = $0 })
    }
    private func flag(_ path: WritableKeyPath<GroupBilliardsConfig, Bool?>) -> Binding<Bool> {
        Binding(get: { rules.config[keyPath: path] ?? false }, set: { rules.config[keyPath: path] = $0 })
    }
    private var breaker: Binding<String> {
        Binding(get: { rules.initialBreakerParticipantId ?? "p0" }, set: { rules.initialBreakerParticipantId = $0 })
    }
    private var breakerNames: [String] {
        let fallback = [billiardsText("member"), billiardsText("member"), billiardsText("member"), billiardsText("member")]
        return (0..<rules.playerCount).map { index in
            let name = names.indices.contains(index) ? names[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return name.isEmpty ? fallback[min(index, fallback.count - 1)] : name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            switch group {
            case .nineBall: nineBall
            case .eight: eight
            case .snooker: snooker
            case .standard: EmptyView()
            }
        }
    }

    @ViewBuilder private var nineBall: some View {
        if rules.family == .folk {
            HStack(spacing: Theme.sm) {
                Text(nineBallText("nine_ball_point_scheme", "Point scheme")).font(GroupTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("", selection: Binding(get: { rules.config.pointScheme ?? "14710" }, set: { scheme in
                    // 与计分板设置页同一套分值口径：换方案就把四项分值换成该方案的预设。
                    rules.config.pointScheme = scheme
                    rules.config.bigGold = scheme == "1357" ? 7 : 10
                    rules.config.smallGold = scheme == "1357" ? 5 : 7
                    rules.config.goldenNine = scheme == "1357" ? 3 : 4
                    rules.config.normalWin = scheme == "1357" ? 3 : 4
                })) {
                    Text("14710").tag("14710"); Text("1357").tag("1357")
                }.pickerStyle(.segmented).frame(maxWidth: 150)
                    .accessibilityIdentifier("billiards_point_scheme")
            }
        }
        numberRow(billiardsText("big_gold"), number(\.bigGold))
        numberRow(billiardsText("small_gold"), number(\.smallGold))
        if rules.family == .folk {
            numberRow(billiardsText("golden"), number(\.goldenNine))
        }
        numberRow(billiardsText("normal_win"), number(\.normalWin))
        numberRow(billiardsText("foul"), number(\.foul))
        if rules.family == .tournament {
            numberRow(billiardsText("third_foul"), number(\.thirdFoul))
            if inlineOpening { numberRow(billiardsText("total_racks"), number(\.totalRacks)) }
            HStack(spacing: Theme.sm) {
                Text(billiardsText("break_rule")).font(GroupTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("", selection: Binding(get: { rules.config.breakRule ?? "winner" }, set: { rules.config.breakRule = $0 })) {
                    Text(billiardsText("winner_breaks")).tag("winner")
                    Text(billiardsText("alternate")).tag("alternate")
                }.pickerStyle(.menu).tint(Theme.primary)
                    .accessibilityIdentifier("billiards_break_rule")
            }
        } else {
            Toggle(billiardsText("all_pay"), isOn: flag(\.smallGoldAllPay)).font(GroupTypography.body).tint(Theme.primary)
            Toggle(billiardsText("retains_break"), isOn: flag(\.goldRetainsBreak)).font(GroupTypography.body).tint(Theme.primary)
            Toggle(billiardsText("handoff"), isOn: flag(\.handoffEnabled)).font(GroupTypography.body).tint(Theme.primary)
        }
        if inlineOpening && rules.playerCount > 1 {
            HStack(spacing: Theme.sm) {
                Text(billiardsText("breaker")).font(GroupTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("", selection: breaker) {
                    ForEach(Array(0..<rules.playerCount), id: \.self) { index in
                        Text(String(index + 1) + (breakerNames.indices.contains(index) ? " · " + breakerNames[index] : "")).tag("p\(index)")
                    }
                }.pickerStyle(.menu).tint(Theme.primary)
                    .accessibilityIdentifier("billiards_breaker")
            }
        }
    }

    @ViewBuilder private var eight: some View {
        numberRow(billiardsText("target"), number(\.targetRacks, default: 9))
        HStack(spacing: Theme.sm) {
            Text(billiardsText("handicap")).font(GroupTypography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Stepper("", value: Binding(get: { rules.config.handicapRacks ?? 0 }, set: { rules.config.handicapRacks = $0 }),
                    in: 0...max(0, (rules.config.targetRacks ?? 9) - 1)).labelsHidden()
            Text("\(rules.config.handicapRacks ?? 0)").font(GroupTypography.body.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityIdentifier("billiards_handicap")
        }
        if (rules.config.handicapRacks ?? 0) > 0 {
            HStack(spacing: Theme.sm) {
                Text(billiardsText("beneficiary")).font(GroupTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("", selection: Binding(get: { rules.config.handicapBeneficiary ?? "p1" }, set: { rules.config.handicapBeneficiary = $0 })) {
                    Text("1").tag("p0"); Text("2").tag("p1")
                }.pickerStyle(.menu).tint(Theme.primary)
                    .accessibilityIdentifier("billiards_beneficiary")
            }
        }
    }

    @ViewBuilder private var snooker: some View {
        numberRow(billiardsText("frames"), Binding(get: { rules.config.maxFrames ?? 1 },
                                                    set: { rules.config.maxFrames = max(1, $0 % 2 == 0 ? $0 + 1 : $0) }), step: 2)
    }

    private func numberRow(_ title: String, _ binding: Binding<Int>, step: Int = 1) -> some View {
        HStack(spacing: Theme.sm) {
            Text(title).font(GroupTypography.body).frame(maxWidth: .infinity, alignment: .leading)
            Stepper("", value: binding, in: 1...99, step: step).labelsHidden()
            Text("\(binding.wrappedValue)").font(GroupTypography.body.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
        }
    }
}

// MARK: - 活动默认规则（Form 内使用）

/// 台球规则设置（九球两族 / 黑八让局 / 斯诺克局数 / 普通台球）。
/// 与安卓 SportsSetupScreen 的台球分支同字段；活动默认规则用它，
/// 开赛 / 补记页改用页内的 BilliardsRuleDetailFields（卡片内可折叠）。
struct GroupBilliardsRulesFields: View {
    @Binding var rules: GroupBilliardsRules
    var locked = false
    private func value(_ path: WritableKeyPath<GroupBilliardsConfig, Int?>, default n: Int = 1) -> Binding<Int> { Binding(get: { rules.config[keyPath: path] ?? n }, set: { rules.config[keyPath: path] = $0 }) }
    private func flag(_ path: WritableKeyPath<GroupBilliardsConfig, Bool?>) -> Binding<Bool> { Binding(get: { rules.config[keyPath: path] ?? false }, set: { rules.config[keyPath: path] = $0 }) }
    var body: some View {
        Section(billiardsText("rules")) {
            Picker(billiardsText("rules"), selection: Binding(get: { rules.knownVariant ?? .folk }, set: { rules = .defaults($0) })) {
                ForEach(GroupBilliardsVariant.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("billiards_variant")
            if rules.knownVariant == .folk {
                Picker(billiardsText("players"), selection: $rules.playerCount) { ForEach(2...4, id: \.self) { Text(String($0)).tag($0) } }.accessibilityIdentifier("billiards_count")
            }
            if rules.knownVariant == .folk {
                Picker("14710 / 1357", selection: Binding(get: { rules.config.pointScheme ?? "14710" }, set: { scheme in
                    rules.config.pointScheme = scheme
                    rules.config.bigGold = scheme == "1357" ? 7 : 10; rules.config.smallGold = scheme == "1357" ? 5 : 7
                    rules.config.goldenNine = scheme == "1357" ? 3 : 4; rules.config.normalWin = scheme == "1357" ? 3 : 4
                })) { Text("14710").tag("14710"); Text("1357").tag("1357") }
            }
            if [.folk, .tournament].contains(rules.knownVariant) {
                Stepper("\(billiardsText("big_gold")): \(rules.config.bigGold ?? 10)", value: value(\.bigGold), in: 1...99)
                Stepper("\(billiardsText("small_gold")): \(rules.config.smallGold ?? 7)", value: value(\.smallGold), in: 1...99)
                Stepper("\(billiardsText("normal_win")): \(rules.config.normalWin ?? 4)", value: value(\.normalWin), in: 1...99)
                Stepper("\(billiardsText("foul")): \(rules.config.foul ?? 1)", value: value(\.foul), in: 1...99)
                if rules.knownVariant == .folk {
                    Stepper("\(billiardsText("golden")): \(rules.config.goldenNine ?? 4)", value: value(\.goldenNine), in: 1...99)
                    Toggle(billiardsText("all_pay"), isOn: flag(\.smallGoldAllPay))
                    Toggle(billiardsText("retains_break"), isOn: flag(\.goldRetainsBreak))
                    Toggle(billiardsText("handoff"), isOn: flag(\.handoffEnabled))
                } else {
                    Stepper("\(billiardsText("third_foul")): \(rules.config.thirdFoul ?? 10)", value: value(\.thirdFoul), in: 1...99)
                    Stepper("\(billiardsText("total_racks")): \(rules.config.totalRacks ?? 9)", value: value(\.totalRacks), in: 1...99)
                    Picker(billiardsText("break_rule"), selection: Binding(get: { rules.config.breakRule ?? "alternate" }, set: { rules.config.breakRule = $0 })) {
                        Text(billiardsText("alternate")).tag("alternate"); Text(billiardsText("winner_breaks")).tag("winner")
                    }
                }
            }
            if rules.knownVariant == .eight {
                Stepper("\(billiardsText("target")): \(rules.config.targetRacks ?? 9)", value: value(\.targetRacks), in: 1...99)
                Stepper("\(billiardsText("handicap")): \(rules.config.handicapRacks ?? 0)", value: value(\.handicapRacks, default: 0), in: 0...max(0, (rules.config.targetRacks ?? 9) - 1))
                if (rules.config.handicapRacks ?? 0) > 0 {
                    Picker(billiardsText("beneficiary"), selection: Binding(get: { rules.config.handicapBeneficiary ?? "p1" }, set: { rules.config.handicapBeneficiary = $0 })) {
                        Text("1").tag("p0"); Text("2").tag("p1")
                    }
                }
            }
            if rules.knownVariant == .snooker { Stepper("\(billiardsText("frames")): \(rules.config.maxFrames ?? 1)", value: value(\.maxFrames), in: 1...99, step: 2) }
            if [.folk, .tournament, .snooker].contains(rules.knownVariant) {
                Picker(billiardsText("breaker"), selection: Binding(get: { rules.initialBreakerParticipantId ?? "p0" }, set: { rules.initialBreakerParticipantId = $0 })) {
                    ForEach(Array(0..<rules.playerCount), id: \.self) { Text(String($0 + 1)).tag("p\($0)") }
                }
            }
            Text(rules.summary).font(.caption)
        }.disabled(locked)
        .onChange(of: rules.config.handicapRacks) { _, n in rules.config.handicapBeneficiary = (n ?? 0) > 0 ? rules.config.handicapBeneficiary ?? "p1" : nil }
        .onChange(of: rules.config.targetRacks) { _, n in rules.config.handicapRacks = min(rules.config.handicapRacks ?? 0, max(0, (n ?? 1) - 1)) }
        .onChange(of: rules.playerCount) { if !locked { rules.initialBreakerParticipantId = nil } }
    }
}

extension GroupBilliardsRules {
    /// 规则摘要（卡片上最多 3 行）：与安卓 biliiardsRulesLabel 同字段、同顺序。
    @MainActor var summary: String {
        let title = knownVariant?.title ?? billiardsText("unsupported"), c = config
        switch knownVariant {
        case .folk: return title + " · " + String(format: billiardsText("folk_rules"), playerCount, c.foul ?? 0, c.normalWin ?? 0, c.smallGold ?? 0, c.bigGold ?? 0) + " · " + billiardsText(c.smallGoldAllPay == true ? "all_pay" : "breaker_pays") + " · " + String(format: billiardsText("golden_nine"), c.goldenNine ?? 0) + (c.goldRetainsBreak == true ? " · " + billiardsText("retains_break") : "") + (c.handoffEnabled == true ? " · " + billiardsText("handoff") : "")
        case .tournament: return title + " · " + String(format: billiardsText("tournament_rules"), c.totalRacks ?? 0, c.foul ?? 0, c.normalWin ?? 0, c.smallGold ?? 0, c.bigGold ?? 0) + " · \(c.thirdFoul ?? 0) · " + billiardsText(c.breakRule == "alternate" ? "alternate" : "winner_breaks")
        case .eight: return title + " · " + String(format: billiardsText("eight_rules"), c.targetRacks ?? 0, c.handicapRacks ?? 0) + " · " + Self.beneficiaryLabel(c.handicapBeneficiary)
        case .snooker: return title + " · " + String(format: billiardsText("snooker_rules"), c.maxFrames ?? 1)
        default: return title
        }
    }
    /// 受让方在配置里存的是参与者 ID（p0/p1），摘要里要显示和 Picker 一致的 1 起序号，
    /// 不能把内部 ID 直接透给用户；无法解析时退回原值，避免静默丢信息。
    static func beneficiaryLabel(_ participantID: String?) -> String {
        guard let participantID, participantID.hasPrefix("p"), let index = Int(participantID.dropFirst()) else {
            return participantID ?? ""
        }
        return String(index + 1)
    }
}

private struct BilliardsScoreSeat: Identifiable { let id: Int }

private struct BilliardsScorePanel: View {
    let name: String
    @Binding var score: String
    @Environment(\.dismiss) private var dismiss
    @State private var negative = false

    private var points: Int { Int(score) ?? 0 }
    private var signedPoints: String { score.isEmpty ? "—" : (points > 0 ? "+\(points)" : "\(points)") }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                Text(name).font(GroupTypography.body.weight(.semibold))
                HStack(spacing: Theme.sm) {
                    scoreKey("−1") { step(-1) }
                    Text(signedPoints).font(GroupTypography.body.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .accessibilityValue(signedPoints)
                    scoreKey("+1") { step(1) }
                }
                HStack(spacing: Theme.sm) {
                    signButton(false)
                    signButton(true)
                }
                Grid(horizontalSpacing: Theme.sm, verticalSpacing: Theme.sm) {
                    ForEach(0..<3) { row in
                        GridRow {
                            ForEach(1...3, id: \.self) { column in
                                let digit = row * 3 + column
                                scoreKey("\(digit)") { append(digit) }
                            }
                        }
                    }
                    GridRow {
                        scoreKey(NSLocalizedString("clear", value: "Clear", comment: ""), id: "clear") {
                            score = ""
                        }
                        scoreKey("0") { append(0) }
                        scoreKey(billiardsText("confirm"), id: "done") { dismiss() }
                    }
                }
            }.padding(Theme.padding).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        .presentationDragIndicator(.visible)
        .onAppear { negative = points < 0 }
        .accessibilityIdentifier("billiards_score_panel")
    }

    private func scoreKey(_ title: String, id: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(GroupTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, Theme.xs)
                .billiardsControl()
        }.buttonStyle(.plain).accessibilityIdentifier("billiards_score_key_" + (id ?? title))
    }

    private func signButton(_ value: Bool) -> some View {
        Button {
            negative = value
            if !score.isEmpty { assign(abs(points)) }
        } label: {
            Image(systemName: value ? "minus" : "plus")
                .frame(maxWidth: .infinity, minHeight: 44)
                .billiardsControl(active: negative == value)
        }.buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString(value ? "billiards_group_score_panel_negative" : "billiards_group_score_panel_positive",
                                                    value: value ? "Negative" : "Positive", comment: ""))
            .accessibilityAddTraits(negative == value ? .isSelected : [])
            .accessibilityIdentifier(value ? "billiards_score_negative" : "billiards_score_positive")
    }

    private func assign(_ magnitude: Int) { score = String(negative ? -magnitude : magnitude) }

    private func append(_ digit: Int) {
        let magnitude = abs(points) * 10 + digit
        if magnitude <= 9999 { assign(magnitude) }
    }

    private func step(_ delta: Int) {
        let next = min(9999, max(-9999, points + delta))
        negative = next < 0
        score = String(next)
    }
}
