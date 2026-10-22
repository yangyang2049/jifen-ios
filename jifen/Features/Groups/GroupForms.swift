import SwiftUI
import PersistenceCore
import ScoreCore

struct GroupMatchEditor: View {
    let detail: GroupDetailCache
    var activity: GroupActivity? = nil
    var activitySession: GroupActivitySession? = nil
    var trainingSession: GroupTrainingSession? = nil
    let manual: Bool
    var usesParentNavigation = false
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
    @State private var rulesExpanded = false
    @State private var busy = false
    @State private var resultDraft = GroupResultEntryDraft()
    @State private var frozenSeats: [GroupSeat]?
    @State private var initialized = false
    @State private var playedAt = Date()
    @State private var error: String?
    @State private var frozenCreatorMemberID: String?
    @State private var sessionID = "ios-" + UUID().uuidString
    @State private var uploadKey = UUID().uuidString
    private var currentDetail: GroupDetailCache { store.cache.details[detail.group.id] ?? detail }
    private var choices: [GroupMember] { currentDetail.members.filter { $0.status == "active" && (activity == nil || activity!.registeredMemberIds.contains($0.id)) } }
    private var boundGameID: String? { activitySession?.gameID ?? trainingSession?.startedGameId.flatMap { $0.isEmpty ? nil : $0 } ?? activity.flatMap { $0.gameId.isEmpty ? nil : $0.gameId } }
    private var seatIDs: [String] { format == .singles ? [ids[0],ids[2]] : ids }
    private var ready: Bool { seatIDs.allSatisfy { !$0.isEmpty } && Set(seatIDs).count == seatIDs.count }
    private var validManualResult: Bool { !manual || (playedAt <= Date() && resultDraft.isValid(currentRules)) }
    private var currentRules: GroupMatchRules {
        if let frozenRules { return frozenRules }
        if let capability = store.capabilities?.sport(detail.group.sport), capability.supportsCustomRules == false, let defaults = capability.defaultRules { return defaults }
        return GroupMatchRules(sport: detail.group.sport, setup: setup)
    }
    private var seats: [GroupSeat] { seatIDs.enumerated().map { i,id in .init(memberId: id, side: i < format.seatsPerSide ? "A" : "B", seat: i % format.seatsPerSide, displayName: frozenSeats?.first(where: { $0.memberId == id })?.displayName ?? activitySession?.seats.first(where: { $0.memberId == id })?.displayName ?? trainingSession?.seats.first(where: { $0.memberId == id })?.displayName ?? choices.first { $0.id == id }?.displayName) } }
    private var rosterFrozen: Bool { trainingSession != nil || activitySession != nil || frozenRules != nil }
    private var editableRules: Bool {
        !rosterFrozen && !frozenLoading && !frozenLoadFailed &&
        store.capabilities?.sport(detail.group.sport) != nil &&
        store.capabilities?.sport(detail.group.sport)?.supportsCustomRules != false
    }
    private var rulesBinding: Binding<GroupMatchRules> {
        Binding(get: { currentRules }, set: { setup = $0.setup(format: format) })
    }
    private var canSubmit: Bool {
        ready && validManualResult && !busy && store.enabled && currentDetail.group.isActive && !frozenLoading && !frozenLoadFailed
    }

    var body: some View {
        Group {
            if usesParentNavigation { editorContent }
            else { NavigationStack { editorContent } }
        }.groupAccountBoundary()
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                if activity == nil && trainingSession == nil {
                    GroupMatchFormatChoices(format: $format)
                        .disabled(rosterFrozen || frozenLoading || frozenLoadFailed)
                        .accessibilityIdentifier("group_match_format")
                } else {
                    Text((activity?.title ?? trainingSession?.court ?? "") + " · " + format.title)
                        .font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                }
                if choices.count < format.seatsPerSide * 2 && !rosterFrozen {
                    GroupNotice(text: groupText("need_members", "Invite friends or add temporary members before starting a match.") + " (\(choices.count) / \(format.seatsPerSide * 2))")
                }
                GroupInlineMatchRoster(format: format, ids: $ids, members: choices, frozen: rosterFrozen,
                                       frozenSeats: frozenSeats ?? activitySession?.seats ?? trainingSession?.seats ?? [])
                    .disabled(frozenLoading || frozenLoadFailed)
                if activity == nil && trainingSession == nil && frozenRules == nil {
                    GroupRosterAddButton(groupID: detail.group.id)
                }
                if manual {
                    GroupActivityDateField(selection: $playedAt, maximum: Date(), compact: true)
                        .accessibilityLabel(groupText("played_at", "Played at"))
                        .accessibilityIdentifier("group_result_played_at")
                }
                Text(manual ? groupText("score_and_rules", "Score and rules") : groupText("match_rules", "Match rules"))
                    .font(.system(size: Theme.fontBody1, weight: .medium)).foregroundStyle(Theme.textPrimary)
                VStack(alignment: .leading, spacing: Theme.sm) {
                    if manual { Text(groupText("match_rules", "Match rules")).font(.system(size: Theme.fontBody2, weight: .medium)) }
                    GroupMatchRuleSummary(rules: currentRules, expanded: rulesExpanded, editable: editableRules) {
                        rulesExpanded.toggle()
                    }
                    if rulesExpanded && editableRules {
                        GroupRulesFields(rules: rulesBinding, capability: store.capabilities?.sport(detail.group.sport))
                    }
                    if manual {
                        Divider().padding(.vertical, Theme.sm)
                        Text(groupText("match_score", "Match score")).font(.system(size: Theme.fontBody2, weight: .medium))
                        GroupResultScoreControls(draft: $resultDraft, rules: currentRules)
                    }
                }
                .padding(Theme.padding).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                if let error { GroupNotice(text: error) }
                if frozenLoadFailed {
                    Button(groupText("retry", "Retry")) { Task { await loadFrozenGame() } }.disabled(frozenLoading)
                }
                if frozenLoading { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, Theme.padding).padding(.top, Theme.padding).padding(.bottom, Theme.lg)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.backgroundColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GroupAlignedFooter {
                Button(manual ? groupText("submit_result", "Submit result") : groupText("start_score", "Start scoring")) {
                    Task { await submit() }
                }
                .buttonStyle(GroupAlignedActionStyle()).disabled(!canSubmit)
                .accessibilityIdentifier("group_match_submit")
            }
        }
        .navigationTitle(manual ? groupText("manual_result", "Add match result") : groupText("start_score", "Start scoring"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
        .tint(Theme.primary).disabled(busy).interactiveDismissDisabled(busy)
        .toolbar {
            if !usesParentNavigation {
                ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() }.disabled(busy) }
            }
        }
        .onChange(of: store.identityRevision) { _, _ in dismiss() }
        .task { await initialize() }
        .onChange(of: resultDraft.detailsExpanded) { _, value in if value { resultDraft.reconcileDetails(currentRules) } }
        .onChange(of: resultDraft.total) { _, _ in resultDraft.reconcileDetails(currentRules) }
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
            guard ready, Set(choices.map(\.id)).isSuperset(of: seatIDs) || frozenSeats != nil || activitySession != nil || trainingSession != nil else { throw GroupFlowError.gameUnavailable }
            guard rules.isValid else { throw GroupFormError.invalidRules }
            guard frozenRules != nil || store.capabilities?.sport(detail.group.sport)?.defaultRules?.isValid == true else { throw GroupFlowError.noCapabilities }
            if let count = store.capabilities?.sport(detail.group.sport)?.seats?[format.rawValue], count != format.seatsPerSide * 2 { throw GroupFlowError.noCapabilities }
            guard store.capabilities?.allows(manual ? "submit_result" : "start_game") ?? false else { throw GroupFlowError.noCapabilities }
            guard GroupActivityPolicy.allowsMatchEntry(activityStatus: activity?.status ?? "", sessionStatus: activitySession?.status) else { throw GroupFlowError.gameUnavailable }
            if let activity { let me = detail.members.first { $0.accountId == accountID }; guard GroupPermissions.canScore(activity, me: me, seats: seats) || (manual && activitySession?.canCorrectResult == true) || (frozenCreatorMemberID != nil && frozenCreatorMemberID == me?.id) else { throw GroupFlowError.gameUnavailable } }
            if detail.group.isCoaching { guard GroupPermissions.coach(detail.group, member: detail.members.first(where: { $0.accountId == accountID })) else { throw GroupFlowError.gameUnavailable } }
            if manual {
                guard resultDraft.isValid(rules), let score = resultDraft.score, playedAt <= Date() else { throw GroupFormError.invalidResult }
                let body = GroupResultBody(gameId: boundGameID, clientSessionId: sessionID, clientRecordId: nil, activityId: activity?.id, format: format, bestOf: rules.maxSets, rules: rules, setScore: score, sets: resultDraft.details, playedAt: Int64(playedAt.timeIntervalSince1970 * 1000), source: "manual", participants: seats, trainingSessionId: trainingSession?.id, activitySessionId: activitySession?.id)
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
