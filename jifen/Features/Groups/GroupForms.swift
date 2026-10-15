import SwiftUI
import PersistenceCore
import ScoreCore

struct GroupMatchEditor: View {
    let detail: GroupDetailCache
    var activity: GroupActivity? = nil
    var activitySession: GroupActivitySession? = nil
    var trainingSession: GroupTrainingSession? = nil
    let manual: Bool
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var format = GroupFormat.singles
    @State private var ids = ["", "", "", ""]
    @State private var setup = SportsSetupResult(team1Name: "", team2Name: "")
    @State private var presentedAccountID: String?
    @State private var frozenRules: GroupMatchRules?
    @State private var frozenLoading = false
    @State private var frozenLoadFailed = false
    @State private var showRules = false
    @State private var busy = false
    @State private var scoreA = ""
    @State private var scoreB = ""
    @State private var setDetails: [GroupScore] = []
    @State private var includesSets = false
    @State private var frozenSeats: [GroupSeat]?
    @State private var initialized = false
    @State private var playedAt = Date()
    @State private var error: String?
    @State private var frozenCreatorMemberID: String?
    @State private var sessionID = "ios-" + UUID().uuidString
    @State private var uploadKey = UUID().uuidString
    private var choices: [GroupMember] { detail.members.filter { $0.status == "active" && (activity == nil || activity!.registeredMemberIds.contains($0.id)) } }
    private var boundGameID: String? { activitySession?.gameID ?? trainingSession?.startedGameId.flatMap { $0.isEmpty ? nil : $0 } ?? activity.flatMap { $0.gameId.isEmpty ? nil : $0.gameId } }
    private var seatIDs: [String] { format == .singles ? [ids[0],ids[2]] : ids }
    private var ready: Bool { seatIDs.allSatisfy { !$0.isEmpty } && Set(seatIDs).count == seatIDs.count }
    /// 对齐安卓 GroupResultDraft.hasDetailInput：明细行只是占位，没填任何分数时按总分校验，
    /// 不能因为「展开了明细」就把一个合法的总分判成错误。
    private var scoredDetails: [GroupScore]? { GroupInputValidation.scoredDetails(includesSets: includesSets, sets: setDetails) }
    private var validManualResult: Bool {
        guard manual else { return true }
        guard let a = Int(scoreA), let b = Int(scoreB), playedAt <= Date() else { return false }
        return currentRules.validResult(.init(a: a, b: b), sets: scoredDetails)
    }
    private var currentRules: GroupMatchRules {
        if let frozenRules { return frozenRules }
        if let capability = store.capabilities?.sport(detail.group.sport), capability.supportsCustomRules == false, let defaults = capability.defaultRules { return defaults }
        return GroupMatchRules(sport: detail.group.sport, setup: setup)
    }
    private var seats: [GroupSeat] { seatIDs.enumerated().map { i,id in .init(memberId: id, side: i < format.seatsPerSide ? "A" : "B", seat: i % format.seatsPerSide, displayName: frozenSeats?.first(where: { $0.memberId == id })?.displayName ?? activitySession?.seats.first(where: { $0.memberId == id })?.displayName ?? trainingSession?.seats.first(where: { $0.memberId == id })?.displayName ?? choices.first { $0.id == id }?.displayName) } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if activity == nil && trainingSession == nil { Picker(groupText("format", "Format"), selection: $format) { ForEach(GroupFormat.allCases) { Text($0.title).tag($0) } } }
                    else { Text((activity?.title ?? trainingSession?.court ?? "") + " · " + format.title) }
                    if choices.count < format.seatsPerSide * 2 { GroupNotice(text: groupText("need_members", "Invite friends or add temporary members before starting a match.")) }
                    ForEach([0,1], id: \.self) { side in
                        ForEach(0..<format.seatsPerSide, id: \.self) { seat in
                            GroupSeatPicker(title: "\(side == 0 ? "A" : "B")\(seat + 1)", selectedID: $ids[side * 2 + seat], members: choices, excluded: Set(seatIDs), frozen: trainingSession != nil || activitySession != nil || frozenRules != nil, frozenName: seats.first(where: { $0.side == (side == 0 ? "A" : "B") && $0.seat == seat })?.displayName)

                        }
                    }
                } header: { Text(groupText("participants", "Participants")) }.disabled(frozenLoading || frozenLoadFailed)
                Section {
                    Button(groupText("match_rules", "Match rules")) { showRules = true }.disabled(frozenRules != nil || frozenLoading || frozenLoadFailed || store.capabilities?.sport(detail.group.sport) == nil)
                    let rules = currentRules
                    Text("\(rules.maxSets) · " + groupText(rules.matchCompletionMode, rules.matchCompletionMode) + " · \(rules.pointsToWinSet)").font(.caption).foregroundStyle(.secondary)
                }
                if manual {
                    Section(groupText("overall_score", "Overall set score")) {
                        LabeledContent("A") { TextField("A", text: $scoreA).keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityIdentifier("group_score_A") }
                        LabeledContent("B") { TextField("B", text: $scoreB).keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityIdentifier("group_score_B") }
                        DatePicker(groupText("played_at", "Played at"), selection: $playedAt, in: ...Date()).accessibilityIdentifier("group_result_played_at")
                        quickScores
                        Toggle(groupText("set_details", "Set details"), isOn: $includesSets).accessibilityIdentifier("group_result_sets_toggle")
                        if includesSets { GroupSetDetailsEditor(sets: $setDetails, maximum: currentRules.maxSets) }
                    }
                }
                if let error { GroupNotice(text: error) }
                if frozenLoadFailed { Button(groupText("retry", "Retry")) { Task { await loadFrozenGame() } }.disabled(frozenLoading) }
                if frozenLoading { ProgressView() }
                Button(manual ? groupText("submit_result", "Submit result") : groupText("start_score", "Start scoring")) { Task { await submit() } }.disabled(!ready || !validManualResult || busy || !store.enabled || !detail.group.isActive || frozenLoading || frozenLoadFailed).accessibilityIdentifier("group_match_submit")
            }.scrollDismissesKeyboard(.interactively).navigationTitle(manual ? groupText("manual_result", "Add a past match") : groupText("start_score", "Start scoring"))
                .navigationBarTitleDisplayMode(.inline)
                .disabled(busy)
                .interactiveDismissDisabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
                .onChange(of: store.identityRevision) { _, _ in dismiss() }
                .task { await initialize() }
                .sheet(isPresented: $showRules) {
                    GroupRulesEditor(rules: Binding(get: { GroupMatchRules(sport: detail.group.sport, setup: setup) }, set: { setup = $0.setup(format: format) }), capability: store.capabilities?.sport(detail.group.sport))
                }

        }.groupAdaptiveOrientation()
    }
    /// 对齐安卓 GroupQuickResultColumn：快捷比分按「A 胜 / B 胜」分列，平局单独一行
    /// （安卓新实现把 a == b 的比分漏掉了，这里保留，避免平局项目无法一键填分）。
    @ViewBuilder private var quickScores: some View {
        let scores = currentRules.overallScores
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top, spacing: Theme.sm) {
                quickColumn(title: groupText("entry_a_wins", "A wins"), scores: scores.filter { $0.a > $0.b })
                quickColumn(title: groupText("entry_b_wins", "B wins"), scores: scores.filter { $0.b > $0.a })
            }
            let draws = scores.filter { $0.a == $0.b }
            if !draws.isEmpty { quickColumn(title: groupText("result_draw", "Draw"), scores: draws) }
        }
    }
    private func quickColumn(title: String, scores: [GroupScore]) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                quickButton(score, chosen: Int(scoreA) == score.a && Int(scoreB) == score.b)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func quickButton(_ score: GroupScore, chosen: Bool) -> some View {
        let label = Text("\(score.a):\(score.b)").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        let action = { scoreA = String(score.a); scoreB = String(score.b) }
        if chosen { Button(action: action) { label }.buttonStyle(.borderedProminent).controlSize(.small).accessibilityIdentifier("group_quick_score_\(score.a)_\(score.b)") }
        else { Button(action: action) { label }.buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("group_quick_score_\(score.a)_\(score.b)") }
    }
    private func initialize() async {
        guard !initialized else { return }; initialized = true; presentedAccountID = store.accountID
        format = activitySession?.format ?? trainingSession?.format ?? activity?.format ?? .singles
        if let defaults = store.capabilities?.sport(detail.group.sport)?.defaultRules { setup = defaults.setup(format: format) }
        else { setup.maxSets = detail.group.sport == .tableTennis ? 5 : 3 }
        let fixed = activitySession?.seats ?? trainingSession?.seats
        if let fixed { for seat in fixed where (0..<2).contains(seat.seat) { ids[(seat.side == "A" ? 0 : 2) + seat.seat] = seat.memberId } }
        playedAt = min(Date(), activitySession?.date ?? trainingSession?.date ?? activity?.date ?? Date())
        await loadFrozenGame()
    }
    private func loadFrozenGame() async {
        guard let gameID = boundGameID else { return }
        frozenLoading = true; frozenLoadFailed = false; error = nil
        defer { frozenLoading = false }
        guard let accountID = presentedAccountID, accountID == store.accountID else { frozenLoadFailed = true; return }
        let revision = store.identityRevision
        do {
            let authRevision = await store.repository.client.authSessionRevision()
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            let snapshot: GroupGameSnapshot = try await store.repository.read("/\(detail.group.id)/games/\(gameID)", expectedAuthRevision: authRevision)
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            guard snapshot.hasValidFrozenConfiguration(groupID: detail.group.id, gameID: gameID, sport: detail.group.sport),
                  let rules = snapshot.rules, let seats = snapshot.participants else { throw GroupFormError.invalidRules }
            frozenRules = rules; frozenSeats = seats; frozenCreatorMemberID = snapshot.creatorMemberId; sessionID = snapshot.clientSessionId; setup = rules.setup(format: snapshot.format); format = snapshot.format
            ids = Array(repeating: "", count: 4)
            for seat in seats { ids[(seat.side == "A" ? 0 : 2) + seat.seat] = seat.memberId }
        } catch {
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            frozenLoadFailed = true; self.error = groupErrorMessage(error)
        }
    }
    private func configuredSetup() -> SportsSetupResult {
        var value = currentRules.setup(format: format); value.isSingles = format == .singles; value.competitionFormat = format == .singles ? .singles : .doubles
        let a = seats.filter { $0.side == "A" }.compactMap(\.displayName), b = seats.filter { $0.side == "B" }.compactMap(\.displayName)
        value.team1Name = a.joined(separator: " / "); value.team2Name = b.joined(separator: " / ")
        value.team1Player1Name = a.first; value.team1Player2Name = a.count > 1 ? a[1] : nil
        value.team2Player1Name = b.first; value.team2Player2Name = b.count > 1 ? b[1] : nil
        return value
    }
    private func submit() async {
        busy = true; defer { busy = false }
        guard let accountID = store.accountID, accountID == presentedAccountID else { error = groupText("need_login", "Please sign in to continue."); return }
        let revision = store.identityRevision
        let config = configuredSetup(), rules = currentRules
        do {
            let authRevision = await store.repository.client.authSessionRevision()
            guard store.matchesIdentity(accountID, revision: revision), SessionStore.shared.user?.id == accountID else { return }
            guard rules.isValid else { throw GroupFormError.invalidRules }
            guard frozenRules != nil || store.capabilities?.sport(detail.group.sport)?.defaultRules?.isValid == true else { throw GroupFlowError.noCapabilities }
            if let count = store.capabilities?.sport(detail.group.sport)?.seats?[format.rawValue], count != format.seatsPerSide * 2 { throw GroupFlowError.noCapabilities }
            guard store.capabilities?.allows(manual ? "submit_result" : "start_game") ?? false else { throw GroupFlowError.noCapabilities }
            if let activity { let me = detail.members.first { $0.accountId == accountID }; guard GroupPermissions.canScore(activity, me: me, seats: seats) || (manual && activitySession?.canCorrectResult == true) || (frozenCreatorMemberID != nil && frozenCreatorMemberID == me?.id) else { throw GroupFlowError.gameUnavailable } }
            if detail.group.isCoaching { guard GroupPermissions.coach(detail.group, member: detail.members.first(where: { $0.accountId == accountID })) else { throw GroupFlowError.gameUnavailable } }
            if manual {
                guard let a = Int(scoreA), let b = Int(scoreB) else { throw GroupFormError.invalidResult }
                let score = GroupScore(a: a, b: b)
                guard rules.validResult(score, sets: scoredDetails) else { throw GroupFormError.invalidResult }
                let body = GroupResultBody(gameId: boundGameID, clientSessionId: sessionID, clientRecordId: nil, activityId: activity?.id, format: format, bestOf: rules.maxSets, rules: rules, setScore: score, sets: details, playedAt: Int64(playedAt.timeIntervalSince1970 * 1000), source: "manual", participants: seats, trainingSessionId: trainingSession?.id, activitySessionId: activitySession?.id)
                guard await store.repository.client.authSessionRevision() == authRevision else { throw GroupFlowError.staleSession }
                try store.queuedResult(body, groupID: detail.group.id, id: uploadKey, key: uploadKey)
                dismiss(); return
            }
            let existing = try await ResumeSessionRepository().liveEntries()
            guard store.matchesIdentity(accountID, revision: revision), SessionStore.shared.user?.id == accountID else { return }
            guard existing.isEmpty else { throw GroupFormError.unfinishedMatch }
            var gameID: String? = boundGameID
            do {
                guard boundGameID == nil else { throw GroupFlowError.gameUnavailable }
                let game: GroupGameResponse = try await store.repository.write("/\(detail.group.id)/games", body: GroupGameBody(clientSessionId: sessionID, activityId: activity?.id, format: format, rules: rules, participants: seats.map { .init(memberId:$0.memberId,side:$0.side,seat:$0.seat) }, trainingSessionId: trainingSession?.id, activitySessionId: activitySession?.id), key: sessionID, expectedAuthRevision: authRevision)
                gameID = game.gameId
            } catch {
                guard activity == nil, trainingSession == nil, error is URLError else { throw error }
            }
            guard store.matchesIdentity(accountID, revision: revision), SessionStore.shared.user?.id == accountID else { return }
            let context = GroupMatchContext(accountID: accountID, groupID: detail.group.id, groupName: detail.group.name, activityID: activity?.id, gameID: gameID, clientSessionID: sessionID, format: format, rules: rules, participants: seats, trainingSessionID: trainingSession?.id, activitySessionID: activitySession?.id)
            guard let resumeID = await BookingStartPersistence.persist(.init(bookingId: "", gameType: detail.group.sport.gameType, setup: config), groupContext: context) else {
                if let gameID { try? await store.repository.action("/\(detail.group.id)/games/\(gameID)/abandon", expectedAuthRevision: authRevision) }; throw GroupFormError.saveFailed
            }
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            dismiss(); onStart(detail.group.sport.gameType, config, resumeID)
        } catch { if store.matchesIdentity(accountID, revision: revision) { self.error = groupErrorMessage(error) } }
    }
}
nonisolated enum GroupFormError: LocalizedError {
    case invalidRules, invalidResult, unfinishedMatch, saveFailed, invalidQR
    var errorDescription: String? {
        switch self {
        case .invalidQR: groupText("invalid_qr", "This is not a valid group QR code.")
        case .invalidRules: groupText("invalid_rules", "Please check the match rules.")
        case .invalidResult: groupText("invalid_result", "The result must match the completed match and its rules.")
        case .unfinishedMatch: groupText("unfinished_match", "Resume or finish your existing match before starting another.")
        case .saveFailed: groupText("save_failed", "Could not save the match. Please try again.")
        }
    }
}
