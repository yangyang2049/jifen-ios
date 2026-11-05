import SwiftUI
import PersistenceCore

nonisolated struct GroupBilliardsSession: Codable, Identifiable, Sendable {
    var id: String; var orderNo: Int; var court: String; var startsAt: Int64; var rules: GroupBilliardsRules
    var participants: [GroupBilliardsSeat]; var status: String; var gameId: String? = nil; var resultId: String? = nil
    var isFrozen: Bool? = nil; var canStart: Bool? = nil; var canResume: Bool? = nil; var canCorrect: Bool? = nil
    var submission: GroupBilliardsSessionBody { .init(id: id, orderNo: orderNo, court: court, startsAt: startsAt, rules: rules, participants: participants.map(\.participant)) }
}
nonisolated struct GroupBilliardsSessionBody: Codable, Sendable {
    var id: String? = nil; var orderNo: Int; var court: String; var startsAt: Int64; var rules: GroupBilliardsRules; var participants: [GroupBilliardsParticipant]
}
nonisolated struct GroupBilliardsLineup: Codable, Sendable {
    var activity: GroupActivity; var sessions: [GroupBilliardsSession]; var sessionMinutes: Int; var revision: Int64; var canManage: Bool
}
nonisolated struct GroupBilliardsLineupBody: Codable, Sendable { var sessionMinutes: Int; var sessions: [GroupBilliardsSessionBody] }
nonisolated struct GroupBilliardsActivityBody: Codable, Sendable {
    var title: String; var startsAt: Int64; var place: String; var matchMode = "multi"; var timingMode = "sequence"
    var activityType: String; var defaultMatchConfig: GroupBilliardsRules
}
nonisolated private struct BilliardsBrowseCache:Codable,Sendable {var rows:[GroupBilliardsRow];var activities:[GroupActivity];var ranking:GroupBilliardsRanking;var lineup:GroupBilliardsLineup?}
private struct BilliardsEdit: Identifiable {
    var id = UUID(); var manual = false; var rules: GroupBilliardsRules? = nil; var seats: [GroupBilliardsSeat] = []
    var row: GroupBilliardsRow? = nil; var session: GroupBilliardsSession? = nil; var activityID: String? = nil; var arranging = false; var allowedMemberIDs: [String]? = nil; var repair:GroupBilliardsUpload? = nil
}
struct GroupBilliardsTab: View {
    let detail: GroupDetailCache; let tab: Int; var resultID: String? = nil; var initialActivityID: String? = nil; var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var rows: [GroupBilliardsRow] = []
    @State private var ranking = GroupBilliardsRanking()
    @State private var variant = GroupBilliardsVariant.folk
    @State private var bucket = ""
    @State private var activities: [GroupActivity] = []
    @State private var lineup: GroupBilliardsLineup?
    @State private var edit: BilliardsEdit?
    @State private var error: String?
    @State private var busy = false
    @State private var newActivity = false
    @State private var reason = ""
    @State private var voiding: GroupBilliardsRow?
    @State private var uploads: [GroupBilliardsUpload] = []
    @State private var sources: [String: GroupBilliardsSource] = [:]
    @State private var discard: GroupBilliardsUpload?
    private var store: GroupStore { .shared }
    private var writable: Bool { detail.group.isActive && store.enabled && SessionStore.shared.isAuthenticated }
    private var me: GroupMember? { detail.members.first { $0.accountId == store.accountID } }
    private var manager: Bool { GroupPermissions.manager(me) }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if let error { GroupNotice(text: error) }
            Button(billiardsText("refresh")) { run { await GroupBilliardsSync.shared.sync(force: true) } }.buttonStyle(.bordered).accessibilityIdentifier("billiards_refresh")
            if busy { ProgressView() }
            switch tab {
            case 0: overview
            case 1: activityList
            default: results
            }
        }.tint(Theme.primary)
        .task(id: "\(tab):\(variant.rawValue):\(bucket):\(store.identityRevision)") { await reload() }
        .sheet(item: $edit) { request in
            NavigationStack {
                GroupBilliardsEditor(detail: detail, request: request, onStart: onStart) { rules, participants in
                    guard let old = lineup else { return }
                    let original = request.session
                    var sessions = old.sessions.filter { $0.id != original?.id }.map(\.submission)
                    let order = original?.orderNo ?? (sessions.map(\.orderNo).max() ?? 0) + 1
                    sessions.append(.init(id: original?.id, orderNo: order, court: original?.court ?? "", startsAt: original?.startsAt ?? old.activity.startsAt + Int64(order-1)*Int64(old.sessionMinutes)*60000, rules: rules, participants: participants))
                    let _: GroupBilliardsLineup = try await store.repository.write("/\(detail.group.id)/activities/\(old.activity.id)/lineup", body: GroupBilliardsLineupBody(sessionMinutes: old.sessionMinutes, sessions: sessions), method: .put, revision: old.revision)
                }
            }.groupAccountBoundary()
        }.onChange(of: edit?.id) { _, next in if next == nil { Task { await reload() } } }
        .sheet(isPresented: $newActivity, onDismiss: { Task { await reload() } }) { NavigationStack { GroupBilliardsActivityEditor(groupID: detail.group.id) }.groupAccountBoundary() }
        .alert(billiardsText("void"), isPresented: Binding(get: { voiding != nil }, set: { if !$0 { voiding = nil } })) {
            TextField(billiardsText("correction_reason"), text: $reason)
            Button(billiardsText("confirm"), role: .destructive) { if let row = voiding { run { try await resultAction(row, action: "void", reason: reason) }; voiding = nil } }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(billiardsText("cancel"), role: .cancel) { voiding = nil }
        }
        .confirmationDialog(billiardsText("discard_upload"), isPresented: Binding(get: { discard != nil }, set: { if !$0 { discard = nil } })) {
            Button(billiardsText("confirm"), role: .destructive) { if let row = discard { run { try GroupBilliardsPersistence.shared.finish(row, discard: true) }; discard = nil } }
        } message: { Text(billiardsText("discard_message")) }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(billiardsText("intro"))
            Button(billiardsText("start")) { edit = .init() }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary).disabled(!writable).accessibilityIdentifier("billiards_start")
            Button(billiardsText("manual")) { edit = .init(manual: true) }.buttonStyle(.bordered).disabled(!writable).accessibilityIdentifier("billiards_manual")
            ForEach(sources.keys.sorted(), id: \.self) { id in
                if let source = sources[id] {
                    Button(billiardsText("resume")) { run {
                        if let game = source.gameID, !game.isEmpty {
                            let frozen: BilliardsFrozenGame = try await store.repository.read("/\(source.groupID)/games/\(game)")
                            guard frozen.state == "started" else { throw GroupBilliardsError.otherDevice }
                        }
                        onStart(try source.rules.knownVariant.unwrap().gameType, try source.rules.setup(names: source.names), id)
                    } }.disabled(!writable)
                    Button(billiardsText("abandon"), role: .destructive) { run {
                        if let game = source.gameID { try await store.repository.action("/\(source.groupID)/games/\(game)/abandon") }
                        try GroupBilliardsPersistence.shared.abandon(recordID: id, source: source)
                    } }.disabled(!writable)
                }
            }
            ForEach(uploads) { upload in
                GroupSurface {
                    VStack(alignment: .leading) {
                        Text(billiardsText("pending"))
                        if upload.failure != nil { Text(billiardsText("review")) }
                        if ["RULES_REVIEW_REQUIRED","INVALID_RESULT","INVALID_RULES"].contains(upload.failure ?? "") { Button(billiardsText("manual")){edit = .init(manual:true,repair:upload)} }
                        Button(billiardsText("discard_upload")) { discard = upload }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private var activityList: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if manager { Button(billiardsText("activity")) { newActivity = true }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary).disabled(!writable) }
            ForEach(activities) { a in Button(a.title) { run { lineup = try await store.repository.read("/\(detail.group.id)/activities/\(a.id)/lineup") } } }
            if let l = lineup {
                Text(l.activity.title).font(.headline)
                if l.activity.isDirect == false && l.activity.registrationOpen {
                    Button(billiardsText(l.activity.registeredMemberIds.contains(me?.id ?? "") ? "unregister" : "register")) { run { try await store.repository.action("/\(detail.group.id)/activities/\(l.activity.id)/" + (l.activity.registeredMemberIds.contains(me?.id ?? "") ? "unregister" : "register")) } }.disabled(!writable)
                }
                ForEach(l.sessions) { s in
                    GroupSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(s.orderNo) · \(s.rules.knownVariant?.title ?? billiardsText("unsupported"))").font(.headline)
                            Text(s.participants.compactMap(\.displayName).joined(separator: " / "))
                            if s.rules.knownVariant != nil && writable {
                                if s.canStart == true || s.canResume == true { Button(billiardsText("start")) { edit = .init(rules: s.rules, seats: s.participants, session: s, activityID: l.activity.id) } }
                                if !["completed","cancelled"].contains(s.status) || s.canCorrect == true { Button(billiardsText("manual")) { edit = .init(manual: true, rules: s.rules, seats: s.participants, session: s, activityID: l.activity.id) } }
                                if l.canManage && s.isFrozen != true {
                                    Button(billiardsText("configure")) { edit = .init(rules: s.rules, seats: s.participants, session: s, activityID: l.activity.id, arranging: true) }
                                    Button(billiardsText("remove_session").replacingOccurrences(of: "%1$d", with: String(s.orderNo)), role: .destructive) { run {
                                        let _: GroupBilliardsLineup = try await store.repository.write("/\(detail.group.id)/activities/\(l.activity.id)/lineup", body: GroupBilliardsLineupBody(sessionMinutes: l.sessionMinutes, sessions: l.sessions.filter { $0.id != s.id }.map(\.submission)), method: .put, revision: l.revision)
                                    } }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if l.canManage && writable {
                    Button(billiardsText("add_session")) { edit = .init(activityID: l.activity.id, arranging: true, allowedMemberIDs: l.activity.isDirect ? nil : l.activity.registeredMemberIds) }.disabled(l.sessions.count >= 12)
                    Button(billiardsText("complete_activity")) { run { try await store.repository.action("/\(detail.group.id)/activities/\(l.activity.id)/complete", revision: l.revision) } }
                    if l.activity.status == "recruiting" { Button(billiardsText("cancel_activity"), role: .destructive) { run { try await store.repository.action("/\(detail.group.id)/activities/\(l.activity.id)/cancel", revision: l.revision) } } }
                }
            }
        }
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Picker(billiardsText("rules"), selection: $variant) { ForEach(GroupBilliardsVariant.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu).onChange(of: variant) { bucket = "" }
            ForEach(ranking.buckets ?? []) { b in Button(b.rules.summary) { bucket = b.key }.buttonStyle(.bordered).tint(bucket == b.key ? Theme.primary : Theme.textSecondary) }
            Text(billiardsText("ranking")).font(.headline)
            ForEach(ranking.items ?? []) { row in
                Text("\(row.rank)  \(row.displayName)  \(variant == .folk ? String(row.totalPoints ?? 0) : String(row.wins ?? 0))\(row.games >= 5 ? "  " + (row.winRateText ?? "") : "")")
            }
            Text(billiardsText("records")).font(.headline)
            ForEach(rows) { row in
                GroupSurface {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.rules.knownVariant?.title ?? billiardsText("unsupported")).font(.headline)
                        Text(billiardsText(row.status == "confirmed" ? "confirmed" : row.status == "voided" ? "voided" : "pending"))
                        Text(row.rules.summary).font(.caption)
                        if row.result.completion == "early_stop" { Text(billiardsText("early_stop")) }
                        Text(Date(timeIntervalSince1970: Double(row.playedAt)/1000), style: .date)
                        ForEach(row.result.scores, id: \.participantId) { score in
                            let seat = row.participants.first { $0.participant.participantId == score.participantId }
                            Text("\(seat?.displayName ?? billiardsText("unknown"))  \(row.rules.knownVariant == .folk && score.points > 0 ? "+" : "")\(score.points)")
                        }
                        ShareLink(item:row.shareText)
                        if writable && !busy && row.rules.knownVariant != nil {
                            if row.canConfirm == true { Button(billiardsText("confirm")) { run { try await resultAction(row, action: "confirm") } } }
                            if row.canAuthorityConfirm == true { Button(billiardsText("owner_confirm")) { run { try await resultAction(row, action: "confirm", authority: true) } } }
                            if row.canVoid == true { Button(billiardsText("void"), role: .destructive) { reason = ""; voiding = row } }
                            if row.canCorrect == true { Button(billiardsText("correct")) { edit = .init(manual: true, rules: row.rules, seats: row.participants, row: row, activityID: row.activityId) } }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private func resultAction(_ row: GroupBilliardsRow, action: String, authority: Bool = false, reason: String? = nil) async throws {
        nonisolated struct Body: Encodable, Sendable { var authority: Bool; var reason: String? }
        let _: EmptyResponse = try await store.repository.write("/\(detail.group.id)/results/\(row.id)/\(action)", body: Body(authority: authority, reason: reason), revision: row.revision)
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        let account = store.accountID, revision = store.identityRevision
        Task { defer { if store.accountID == account && store.identityRevision == revision { busy = false } }
            let success=await store.perform {try await action()}
            guard store.accountID==account && store.identityRevision==revision else{return}
            if success {await reload()} else {error=store.error}
        }
    }
    private func reload() async {
        guard let account = store.accountID else { return }; let revision = store.identityRevision
        do {
            uploads=try GroupBilliardsPersistence.shared.rows(accountID:account)
            let allSources=try GroupBilliardsPersistence.shared.sources(accountID:account,groupID:detail.group.id)
            let liveSources=try await ResumeSessionRepository().liveEntries();let liveIDs=Set(liveSources.map(\.sessionId))
            sources=allSources.filter{ManualResumeSessionStore.sessionID(for:$0.key).map{liveIDs.contains($0)}==true}
            if rows.isEmpty,let cached=GroupLocalPersistence.shared.loadDraft(BilliardsBrowseCache.self,key:"billiards-cache:"+detail.group.id,accountID:account){rows=cached.rows;activities=cached.activities;ranking=cached.ranking;lineup=cached.lineup}
            let rows: [GroupBilliardsRow]
            if let resultID { rows = [try await store.repository.read("/\(detail.group.id)/results/\(resultID)")] }
            else { rows = try await store.repository.allPages("/\(detail.group.id)/results") }
            let a: [GroupActivity] = try await store.repository.allPages("/\(detail.group.id)/activities")
            let rank: GroupBilliardsRanking = try await store.repository.read("/\(detail.group.id)/rankings", query: [.init(name:"variant",value:variant.rawValue), .init(name:"bucket",value:bucket.isEmpty ? nil : bucket)].filter { $0.value != nil })
            let activityID = lineup?.activity.id ?? initialActivityID
            let updated: GroupBilliardsLineup? = if let activityID { try await store.repository.read("/\(detail.group.id)/activities/\(activityID)/lineup") } else { nil }
            guard store.matchesIdentity(account, revision: revision), !Task.isCancelled else { return }
            self.rows = rows; activities = a; ranking = rank; lineup = updated
            try GroupLocalPersistence.shared.saveDraft(BilliardsBrowseCache(rows:rows,activities:a,ranking:rank,lineup:updated),key:"billiards-cache:"+detail.group.id,accountID:account)
            uploads = try GroupBilliardsPersistence.shared.rows(accountID: account)
            let all = try GroupBilliardsPersistence.shared.sources(accountID: account, groupID: detail.group.id)
            let live = try await ResumeSessionRepository().liveEntries()
            let sessionIDs = Set(live.map(\.sessionId))
            let ids = Set(all.keys.filter { key in ManualResumeSessionStore.sessionID(for: key).map { sessionIDs.contains($0) } == true })
            sources = all.filter { ids.contains($0.key) }
        } catch { if store.matchesIdentity(account, revision: revision), !Task.isCancelled { self.error = groupErrorMessage(error) } }
    }
}
private extension Optional { func unwrap() throws -> Wrapped { guard let value = self else { throw GroupBilliardsError.rules }; return value } }
nonisolated private struct BilliardsFrozenGame: Decodable, Sendable { var state: String }

private struct GroupBilliardsEditor: View {
    let detail: GroupDetailCache; let request: BilliardsEdit; var onStart: (GameType, SportsSetupResult, String) -> Void
    var onArrange: (GroupBilliardsRules, [GroupBilliardsParticipant]) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rules = GroupBilliardsRules.defaults(.folk)
    @State private var selected = [String](repeating: "", count: 4)
    @State private var scores = [String](repeating: "0", count: 4)
    @State private var racks = "0"
    @State private var early = false
    @State private var playedAt = Date()
    @State private var sessionID = "ios-" + UUID().uuidString
    @State private var error: String?
    @State private var busy = false
    @State private var repairBody:GroupBilliardsSubmission?
    @State private var temporary = ""
    @State private var extraMembers: [GroupMember] = []
    private var store: GroupStore { .shared }
    private var frozen: Bool { (request.rules != nil || request.repair != nil) && !request.arranging }
    private var choices: [GroupMember] {
        let active = (detail.members + extraMembers).filter { $0.status == "active" }
        return active.filter { request.allowedMemberIDs == nil || request.allowedMemberIDs!.contains($0.id) }
    }
    private var ready: Bool {
        let ids = Array(selected.prefix(rules.playerCount))
        let canonicals = ids.map { id in choices.first { $0.id == id }?.canonicalMemberId ?? id }
        return ids.allSatisfy { !$0.isEmpty } && Set(ids).count == ids.count && Set(canonicals).count == ids.count
    }
    var body: some View {
        Form {
            if let error { GroupNotice(text: error) }
            GroupBilliardsRulesFields(rules: $rules, locked: frozen)
            Section(billiardsText("choose_members")) {
                ForEach(0..<rules.playerCount, id: \.self) { i in
                    if frozen { Text(request.seats.first { $0.participant.position == i }?.displayName ?? billiardsText("unknown")) }
                    else {
                        Picker("\(i+1)", selection: $selected[i]) {
                            Text(billiardsText("select")).tag("")
                            ForEach(choices) { m in Text(m.displayName).tag(m.id) }
                        }.accessibilityIdentifier("billiards_seat_\(i)")
                    }
                }
                if !frozen {
                    TextField(billiardsText("new_member"), text: $temporary)
                    Button(billiardsText("add_member")) { Task { do {
                        guard let account=store.accountID else {throw GroupFlowError.staleSession};let identity=store.identityRevision
                        let auth=await store.repository.client.authSessionRevision();guard store.matchesIdentity(account,revision:identity),SessionStore.shared.user?.id==account else{return}
                        let member: GroupMember = try await store.repository.write("/\(detail.group.id)/members/temporary", body: GroupActionBody(displayName: temporary),expectedAuthRevision:auth)
                        guard store.matchesIdentity(account,revision:identity) else{return};extraMembers.append(member); temporary = ""
                    } catch { self.error = groupErrorMessage(error) } } }.disabled(temporary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            }
            if request.manual {
                Section(billiardsText("score")) {
                    ForEach(0..<rules.playerCount, id: \.self) { i in
                        HStack {
                            Text(request.seats.first { $0.participant.position == i }?.displayName ?? choices.first { $0.id == selected[i] }?.displayName ?? "\(i+1)").frame(maxWidth:.infinity,alignment:.leading)
                            TextField(billiardsText("score"), text:$scores[i]).multilineTextAlignment(.trailing).frame(width:120).keyboardType(rules.knownVariant == .folk ? .numbersAndPunctuation:.numberPad).accessibilityIdentifier("billiards_score_\(i)")
                        }
                    }
                    if rules.knownVariant == .folk { Text(String(format: billiardsText("net_total"), scores.prefix(rules.playerCount).reduce(0) { $0 + (Int($1) ?? 0) })) }
                    if rules.knownVariant == .tournament { TextField(billiardsText("completed_racks"), text: $racks).keyboardType(.numberPad) }
                    if ![.folk,.standard].contains(rules.knownVariant) { Toggle(billiardsText("early_stop"), isOn: $early) }
                    DatePicker(billiardsText("played_at"), selection: $playedAt, in: ...Date())
                }
            }
            Button(billiardsText(request.arranging ? "save" : request.manual ? "submit" : "start")) { Task { await submit() } }
                .disabled(!ready || busy).accessibilityIdentifier("billiards_submit")
            if busy { ProgressView() }
        }.tint(Theme.primary).navigationTitle(billiardsText(request.manual ? "manual" : "start"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(billiardsText("cancel")) { dismiss() }.disabled(busy) } }.interactiveDismissDisabled(busy)
        .task {
            rules = request.rules ?? (try? GroupBilliardsPersistence.shared.rememberedRules(accountID:store.accountID ?? "",groupID:detail.group.id)) ?? .defaults(.folk)
            for s in request.seats { let p = s.participant; if (0..<4).contains(p.position) { selected[p.position] = p.memberId } }
            if let upload=request.repair {
                do {
                    var body=upload.body
                    if body==nil,let record=ScoreboardRecordManager.shared.loadAllRecords().first(where:{$0.id==upload.id}),let source=record.billiardsSource {
                        let values=(record.extraData?["chasePlayerPoints"]?.value as? [Int]) ?? [record.team1SetScore ?? record.team1FinalScore,record.team2SetScore ?? record.team2FinalScore]
                        body = .init(rules:source.rules,participants:source.participants,clientSessionId:source.clientSessionID,activityId:source.activityID,activitySessionId:source.activitySessionID,gameId:source.gameID,clientRecordId:upload.id,playedAt:Int64((record.endTime ?? record.startTime).timeIntervalSince1970*1000),source:"manual",result:.init(resultKind:source.rules.knownVariant?.resultKind ?? "",completion:"completed",scores:values.enumerated().map{.init(participantId:"p\($0.offset)",points:$0.element)}))
                    }
                    guard let body else {throw GroupBilliardsError.result};repairBody=body;rules=body.rules;sessionID=upload.id
                    for p in body.participants {selected[p.position]=p.memberId}
                    for p in body.result.scores {if let i=Int(p.participantId.dropFirst()),i<4{scores[i]=String(p.points)}}
                    racks=String(body.result.completedRacks ?? 0);early=body.result.completion=="early_stop";playedAt=Date(timeIntervalSince1970:Double(body.playedAt)/1000)
                } catch {self.error=groupErrorMessage(error)}
            }
            if let row = request.row {
                for s in row.result.scores { if let i = Int(s.participantId.dropFirst()), (0..<4).contains(i) { scores[i] = String(s.points) } }
                racks = String(row.result.completedRacks ?? 0); early = row.result.completion == "early_stop"; playedAt = Date(timeIntervalSince1970: Double(row.playedAt)/1000)
            }
        }
    }
    private func submit() async {
        guard !busy, ready, let account = store.accountID else { return }
        busy = true; defer { busy = false }; let identity = store.identityRevision
        do {
            try rules.validate()
            try GroupBilliardsPersistence.shared.rememberRules(rules,accountID:account,groupID:detail.group.id)
            let auth = await store.repository.client.authSessionRevision()
            let participants = (0..<rules.playerCount).map { GroupBilliardsParticipant(participantId: "p\($0)", memberId: selected[$0], position: $0) }
            guard store.matchesIdentity(account, revision: identity),SessionStore.shared.user?.id==account else { return }
            if request.arranging { try await GroupRequestIdentity.$authRevision.withValue(auth) {try await onArrange(rules, participants)}; dismiss(); return }
            let gameID = request.row?.gameId ?? request.session?.gameId
            if request.manual {
                let points = try scores.prefix(rules.playerCount).enumerated().map { i, text -> GroupBilliardsScore in guard let p = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GroupBilliardsError.result }; return .init(participantId: "p\(i)", points: p) }
                let result = GroupBilliardsResult(resultKind: rules.knownVariant?.resultKind ?? "", completion: early ? "early_stop" : "completed", scores: points, completedRacks: rules.knownVariant == .tournament ? Int(racks) : nil)
                let body = GroupBilliardsSubmission(rules: rules, participants: participants, clientSessionId: repairBody?.clientSessionId ?? sessionID, activityId: repairBody?.activityId ?? request.activityID, activitySessionId: repairBody?.activitySessionId ?? request.row?.activitySessionId ?? request.session?.id, gameId: repairBody?.gameId ?? (gameID?.isEmpty == false ? gameID : nil), clientRecordId: sessionID, playedAt: Int64(playedAt.timeIntervalSince1970*1000), source: "manual", result: result)
                try body.validate(); guard store.matchesIdentity(account, revision: identity), await store.repository.client.authSessionRevision() == auth else { return }
                let row=GroupBilliardsUpload(id:sessionID,accountID:account,groupID:detail.group.id,body:body)
                if request.repair != nil {try GroupBilliardsPersistence.shared.repair(row)} else {try GroupBilliardsPersistence.shared.add(row)}
                await GroupBilliardsSync.shared.sync(); dismiss(); return
            }
            if let gameID, !gameID.isEmpty {
                let sources = try GroupBilliardsPersistence.shared.sources(accountID:account,groupID:detail.group.id)
                guard let local = sources.first(where: { $0.value.gameID == gameID }) else { throw GroupBilliardsError.otherDevice }
                dismiss(); onStart(try local.value.rules.knownVariant.unwrap().gameType,try local.value.rules.setup(names:local.value.names),local.key); return
            }
            let existing = try await ResumeSessionRepository().liveEntries()
            guard existing.isEmpty else { throw GroupBilliardsError.unfinished }
            nonisolated struct Game: Encodable, Sendable { var rules: GroupBilliardsRules; var participants: [GroupBilliardsParticipant]; var clientSessionId: String; var activityId: String?; var activitySessionId: String? }
            var game: String?
            do {
                let response: GroupGameResponse = try await store.repository.write("/\(detail.group.id)/games", body: Game(rules: rules, participants: participants, clientSessionId: sessionID, activityId: request.activityID, activitySessionId: request.session?.id), key: sessionID, expectedAuthRevision: auth)
                game = response.gameId
            } catch { guard request.activityID == nil, error is URLError else { throw error } }
            let names = participants.map { p in request.seats.first { $0.memberId == p.memberId }?.displayName ?? choices.first { $0.id == p.memberId }?.displayName ?? "" }
            let setup = try rules.setup(names: names)
            guard let variant = rules.knownVariant else { throw GroupBilliardsError.rules }
            guard store.matchesIdentity(account, revision: identity), await store.repository.client.authSessionRevision() == auth else { return }
            guard let recordID = await BookingStartPersistence.persist(.init(bookingId:"",gameType:variant.gameType,setup:setup)) else {
                if let game { try? await store.repository.action("/\(detail.group.id)/games/\(game)/abandon", expectedAuthRevision: auth) }; throw GroupFormError.saveFailed
            }
            let source = GroupBilliardsSource(accountID: account, groupID: detail.group.id, groupName: detail.group.name, clientSessionID: sessionID, gameID: game, activityID: request.activityID, activitySessionID: request.session?.id, rules: rules, participants: participants, names: names)
            try GroupBilliardsPersistence.shared.saveSource(source, recordID: recordID)
            guard store.matchesIdentity(account, revision: identity),SessionStore.shared.user?.id==account else { return }
            dismiss(); onStart(variant.gameType, setup, recordID)
        } catch { if store.matchesIdentity(account, revision: identity) { self.error = groupErrorMessage(error) } }
    }
}
struct GroupBilliardsRulesFields: View {
    @Binding var rules: GroupBilliardsRules; var locked = false
    private func value(_ path: WritableKeyPath<GroupBilliardsConfig, Int?>, default n: Int = 1) -> Binding<Int> { Binding(get: { rules.config[keyPath:path] ?? n }, set: { rules.config[keyPath:path] = $0 }) }
    private func flag(_ path: WritableKeyPath<GroupBilliardsConfig, Bool?>) -> Binding<Bool> { Binding(get: { rules.config[keyPath:path] ?? false }, set: { rules.config[keyPath:path] = $0 }) }
    var body: some View {
        Section(billiardsText("rules")) {
            Picker(billiardsText("rules"), selection: Binding(get: { rules.knownVariant ?? .folk }, set: { rules = .defaults($0) })) {
                ForEach(GroupBilliardsVariant.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("billiards_variant")
            if rules.knownVariant == .folk {
                Picker(billiardsText("players"), selection: $rules.playerCount) { ForEach(2...4,id:\.self) { Text(String($0)).tag($0) } }.accessibilityIdentifier("billiards_count")
            }
            if rules.knownVariant == .folk {
                Picker("14710 / 1357",selection:Binding(get:{rules.config.pointScheme ?? "14710"},set:{scheme in rules.config.pointScheme=scheme;rules.config.bigGold=scheme=="1357" ? 7:10;rules.config.smallGold=scheme=="1357" ? 5:7;rules.config.goldenNine=scheme=="1357" ? 3:4;rules.config.normalWin=scheme=="1357" ? 3:4})) {Text("14710").tag("14710");Text("1357").tag("1357")}
            }
            if [.folk,.tournament].contains(rules.knownVariant) {
                Stepper("\(billiardsText("big_gold")): \(rules.config.bigGold ?? 10)", value:value(\.bigGold), in:1...99)
                Stepper("\(billiardsText("small_gold")): \(rules.config.smallGold ?? 7)", value:value(\.smallGold), in:1...99)
                Stepper("\(billiardsText("normal_win")): \(rules.config.normalWin ?? 4)", value:value(\.normalWin), in:1...99)
                Stepper("\(billiardsText("foul")): \(rules.config.foul ?? 1)", value:value(\.foul), in:1...99)
                if rules.knownVariant == .folk {
                    Stepper("\(billiardsText("golden")): \(rules.config.goldenNine ?? 4)", value:value(\.goldenNine), in:1...99)
                    Toggle(billiardsText("all_pay"),isOn:flag(\.smallGoldAllPay)); Toggle(billiardsText("retains_break"),isOn:flag(\.goldRetainsBreak)); Toggle(billiardsText("handoff"),isOn:flag(\.handoffEnabled))
                } else {
                    Stepper("\(billiardsText("third_foul")): \(rules.config.thirdFoul ?? 10)", value:value(\.thirdFoul), in:1...99)
                    Stepper("\(billiardsText("total_racks")): \(rules.config.totalRacks ?? 9)", value:value(\.totalRacks), in:1...99)
                    Picker(billiardsText("break_rule"),selection:Binding(get:{rules.config.breakRule ?? "alternate"},set:{rules.config.breakRule=$0})) { Text(billiardsText("alternate")).tag("alternate"); Text(billiardsText("winner_breaks")).tag("winner") }
                }
            }
            if rules.knownVariant == .eight {
                Stepper("\(billiardsText("target")): \(rules.config.targetRacks ?? 9)",value:value(\.targetRacks),in:1...99)
                Stepper("\(billiardsText("handicap")): \(rules.config.handicapRacks ?? 0)",value:value(\.handicapRacks,default:0),in:0...max(0,(rules.config.targetRacks ?? 9)-1))
                if (rules.config.handicapRacks ?? 0)>0 {
                    Picker(billiardsText("beneficiary"),selection:Binding(get:{rules.config.handicapBeneficiary ?? "p1"},set:{rules.config.handicapBeneficiary=$0})) { Text("1").tag("p0");Text("2").tag("p1") }
                }
            }
            if rules.knownVariant == .snooker { Stepper("\(billiardsText("frames")): \(rules.config.maxFrames ?? 1)",value:value(\.maxFrames),in:1...99,step:2) }
            if [.folk,.tournament,.snooker].contains(rules.knownVariant) {
                Picker(billiardsText("breaker"),selection:Binding(get:{rules.initialBreakerParticipantId ?? "p0"},set:{rules.initialBreakerParticipantId=$0})) { ForEach(0..<rules.playerCount,id:\.self) { Text(String($0+1)).tag("p\($0)") } }
            }
            Text(rules.summary).font(.caption)
        }.disabled(locked)
        .onChange(of: rules.config.handicapRacks) { _, n in rules.config.handicapBeneficiary = (n ?? 0)>0 ? rules.config.handicapBeneficiary ?? "p1" : nil }
        .onChange(of: rules.config.targetRacks) { _, n in rules.config.handicapRacks = min(rules.config.handicapRacks ?? 0,max(0,(n ?? 1)-1)) }
        .onChange(of: rules.playerCount) { if !locked { rules.initialBreakerParticipantId = nil } }
    }
}
private struct GroupBilliardsActivityEditor: View {
    let groupID: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var place = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var signup = false
    @State private var rules = GroupBilliardsRules.defaults(.folk)
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Form {
            TextField(billiardsText("activity_name"),text:$title);TextField(billiardsText("place"),text:$place)
            DatePicker(billiardsText("activity_date"),selection:$date,in:Date()...)
            Toggle(billiardsText("signup"),isOn:$signup)
            GroupBilliardsRulesFields(rules:$rules)
            if let error { GroupNotice(text:error) }
            Button(billiardsText("save")) { Task { busy=true;defer{busy=false};do {
                try rules.validate();let store=GroupStore.shared
                guard let account=store.accountID else { throw GroupFlowError.staleSession }
                let body=GroupBilliardsActivityBody(title:title,startsAt:Int64(date.timeIntervalSince1970*1000),place:place,activityType:signup ? "signup":"direct",defaultMatchConfig:rules)
                let pending=try GroupLocalPersistence.shared.pendingWrite(accountID:account,path:"/\(groupID)/activities",body:body)
                let _: GroupActivity=try await store.repository.write("/\(groupID)/activities",body:body,key:pending.key)
                try GroupLocalPersistence.shared.completeWrite(key:pending.key,accountID:account);dismiss()
            } catch { self.error=groupErrorMessage(error) } } }.disabled(busy)
        }.tint(Theme.primary).navigationTitle(billiardsText("activity")).toolbar { ToolbarItem(placement:.cancellationAction) { Button(billiardsText("cancel")){dismiss()}.disabled(busy) } }.interactiveDismissDisabled(busy)
    }
}
extension GroupBilliardsRules {
    @MainActor var summary: String {
        let title=knownVariant?.title ?? billiardsText("unsupported"),c=config
        switch knownVariant {
        case .folk: return title+" · "+String(format:billiardsText("folk_rules"),playerCount,c.foul ?? 0,c.normalWin ?? 0,c.smallGold ?? 0,c.bigGold ?? 0)+" · "+billiardsText(c.smallGoldAllPay == true ? "all_pay":"breaker_pays")+" · "+String(format:billiardsText("golden_nine"),c.goldenNine ?? 0)+(c.goldRetainsBreak == true ? " · "+billiardsText("retains_break"):"")+(c.handoffEnabled == true ? " · "+billiardsText("handoff"):"")
        case .tournament: return title+" · "+String(format:billiardsText("tournament_rules"),c.totalRacks ?? 0,c.foul ?? 0,c.normalWin ?? 0,c.smallGold ?? 0,c.bigGold ?? 0)+" · \(c.thirdFoul ?? 0) · "+billiardsText(c.breakRule == "alternate" ? "alternate":"winner_breaks")
        case .eight: return title+" · "+String(format:billiardsText("eight_rules"),c.targetRacks ?? 0,c.handicapRacks ?? 0)+" · "+Self.beneficiaryLabel(c.handicapBeneficiary)
        case .snooker: return title+" · "+String(format:billiardsText("snooker_rules"),c.maxFrames ?? 1)
        default:return title
        }
    }
    /// 受让方在配置里存的是参与者 ID（`p0`/`p1`），摘要里要显示和 Picker 一致的 1 起序号，
    /// 不能把内部 ID 直接透给用户；无法解析时退回原值，避免静默丢信息。
    static func beneficiaryLabel(_ participantID: String?) -> String {
        guard let participantID, participantID.hasPrefix("p"), let index = Int(participantID.dropFirst()) else {
            return participantID ?? ""
        }
        return String(index + 1)
    }
}
