import Foundation
import Observation
import ScoreCore

nonisolated struct PersonalRecordSeat: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var side: String?
    var personRef: ParticipantPersonRef?
}

/// Durable identity sidecar: it never rewrites historical scores or replay data.
@MainActor @Observable
final class ParticipantIdentityStore {
    static let shared = ParticipantIdentityStore(
        fileURL: AppTestRuntime.storageRootURL?.appendingPathComponent("identity.json"),
        currentAccountID: { SessionStore.shared.user?.id }
    )

    struct State: Codable {
        var schemaVersion = 1
        var activeLibraryId: String
        var ledgers: [String: ParticipantIdentityLedger]
        var recordLibraries: [String: String] = [:]
        var migratedLegacy = false
        var legacyLibraryId: String?
        var activeAccountId: String?
        var archivedLibraries: Set<String> = []
        var pendingGuestOwners: [String: String]?
    }

    private(set) var state: State
    private(set) var lastError: String?
    private let fileURL: URL
    private let currentAccountID: @MainActor () -> String?
    private struct PersonalRecordKey: Hashable {
        var libraryId: String
        var recordKey: String
    }
    private struct PersonalClaimsIndex {
        var readableLibraryIds: Set<String>
        var claimsByRecord: [PersonalRecordKey: [String: ParticipantHistoricalClaim]]
    }
    @ObservationIgnored private var personalClaimsIndex: PersonalClaimsIndex?

    init(fileURL: URL? = nil, currentAccountID: @escaping @MainActor () -> String? = { nil }) {
        self.currentAccountID = currentAccountID
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v3/participant-identity", isDirectory: true)
        self.fileURL = fileURL ?? AppTestRuntime.storageRootURL?.appendingPathComponent("identity.json")
            ?? root.appendingPathComponent("identity.json")
        if let data = try? Data(contentsOf: self.fileURL), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            let ledger = ParticipantIdentityLedger()
            state = State(activeLibraryId: ledger.libraryId, ledgers: [ledger.libraryId: ledger])
        }
    }

    var storageFileURL: URL { fileURL }
    var ledger: ParticipantIdentityLedger { state.ledgers[state.activeLibraryId]! }
    var person: ParticipantPersonRef { ledger.person }
    private var matchesCurrentSession: Bool { currentAccountID().map { $0 == state.activeAccountId } ?? true }
    var aliases: [ParticipantAlias] { matchesCurrentSession ? ledger.aliases.filter { $0.state != .removed } : [] }
    var activeCount: Int { matchesCurrentSession ? ledger.activeAliases.count : 0 }
    var isGuest: Bool { state.activeAccountId == nil }
    var currentName: String {
        if !isGuest, let name = SessionStore.shared.user?.displayName, !name.isEmpty { return name }
        return ledger.preferredName ?? identityText("self", "我")
    }

    var pickerSelections: [ParticipantSelection] {
        guard matchesCurrentSession else { return [] }
        var result = [ParticipantSelection(name: currentName, personRef: person)]
        var seen = Set([ParticipantIdentityRules.normalizedName(currentName)])
        for alias in aliases where alias.state == .active && alias.visibleInPicker {
            if seen.insert(alias.normalizedName).inserted { result.append(.init(name: alias.name, personRef: person)) }
        }
        return result
    }

    var readableLibraryIds: Set<String> {
        if let current = currentAccountID(), let active = state.activeAccountId, current != active { return [] }
        return Set(state.ledgers.values.filter {
            !state.archivedLibraries.contains($0.libraryId) && (state.activeAccountId == nil
                ? $0.libraryId == state.activeLibraryId : $0.ownerAccountId == state.activeAccountId
                    || ($0.ownerAccountId == nil && state.pendingGuestOwners?[$0.libraryId] == state.activeAccountId))
        }.map(\.libraryId))
    }

    func pinPendingGuest(libraryId: String, accountId: String) throws {
        guard state.ledgers[libraryId]?.ownerAccountId == nil, !state.archivedLibraries.contains(libraryId) else { return }
        if let owner = state.pendingGuestOwners?[libraryId], owner != accountId { throw ParticipantIdentityError.ownerMismatch }
        var next = state
        if next.pendingGuestOwners == nil { next.pendingGuestOwners = [:] }
        next.pendingGuestOwners?[libraryId] = accountId; try commit(next)
    }

    func canRead(recordKey: String) -> Bool {
        guard matchesCurrentSession else { return false }
        guard let library = state.recordLibraries[recordKey] else {
            return !state.migratedLegacy && readableLibraryIds.contains(state.legacyLibraryId ?? state.activeLibraryId)
        }
        return readableLibraryIds.contains(library)
    }

    func libraryId(for recordKey: String) -> String { state.recordLibraries[recordKey] ?? state.activeLibraryId }

    func migrateLegacyIfNeeded(scoreIDs: [String], timerIDs: [String]) throws {
        guard !state.migratedLegacy else { return }
        var next = state
        let library = next.legacyLibraryId ?? next.activeLibraryId
        next.legacyLibraryId = library
        for key in scoreIDs + timerIDs where next.recordLibraries[key] == nil { next.recordLibraries[key] = library }
        next.migratedLegacy = true
        try commit(next)
    }

    func registerRecord(_ key: String, selections: [String: ParticipantSelection] = [:]) throws {
        if state.recordLibraries[key] != nil, selections.isEmpty { return }
        if state.recordLibraries[key] != nil, self.selections(for: key) == selections { return }
        guard matchesCurrentSession else { throw CancellationError() }
        var next = state
        let library = next.recordLibraries[key] ?? next.activeLibraryId
        next.recordLibraries[key] = library
        if !selections.isEmpty { try next.ledgers[library]?.register(recordKey: key, selections: selections) }
        try commit(next)
    }

    func registerLegacyResumeIfNeeded(recordKey: String, expectedLibraryId: String) throws {
        guard state.recordLibraries[recordKey] == nil, state.activeLibraryId == expectedLibraryId else { return }
        var next = state
        let library = next.legacyLibraryId ?? next.activeLibraryId
        next.legacyLibraryId = library; next.recordLibraries[recordKey] = library
        try commit(next)
    }

    func selections(for recordKey: String) -> [String: ParticipantSelection] {
        state.ledgers[libraryId(for: recordKey)]?.recordSelections[recordKey] ?? [:]
    }

    func copySelections(from source: String, to destination: String) {
        guard canRead(recordKey: source) else { return }
        do { try registerRecord(destination, selections: selections(for: source)) }
        catch { lastError = error.localizedDescription }
    }

    func reconcileSelections(record: ScoreboardRecord) throws {
        let existing = selections(for: record.id)
        let names = Dictionary(uniqueKeysWithValues: PersonalRecordAdapter.seats(record).map { ($0.id, $0.name) })
        let valid = existing.filter { names[$0.key] == $0.value.name }
        var next = state, changed = false
        if valid != existing {
            next.ledgers[libraryId(for: record.id)]?.recordSelections[record.id] = valid; changed = true
        }
        let library = libraryId(for: record.id)
        for key in Array(next.ledgers.keys) {
            guard var value = next.ledgers[key] else { continue }
            for index in value.claims.indices {
                let claim = value.claims[index]
                if claim.libraryId == library && claim.recordKey == record.id && !claim.revoked
                    && names[claim.seatKey].map(ParticipantIdentityRules.normalizedName) != ParticipantIdentityRules.normalizedName(claim.nameSnapshot) {
                    value.claims[index].revoked = true; value.claims[index].revision += 1; changed = true
                }
            }
            next.ledgers[key] = value
        }
        if changed { try commit(next) }
        else { try registerRecord(record.id) }
    }

    func personalSeats(for recordKey: String, libraryId explicitLibrary: String? = nil, matchingSeatNames: [String: String]? = nil) -> Set<String> {
        // Keep an observable state read even when the derived index is cached,
        // so record filters update after linking, unlinking, or account changes.
        let snapshot = state
        let library = explicitLibrary ?? snapshot.recordLibraries[recordKey] ?? snapshot.activeLibraryId
        let readable = readableLibraryIds
        guard readable.contains(library) else { return [] }
        var result = Set<String>()
        let removed = Set((snapshot.ledgers[snapshot.activeLibraryId]?.aliases ?? []).filter { $0.state == .removed }.map(\.id))
        if let value = snapshot.ledgers[library] {
            result.formUnion((value.recordSelections[recordKey] ?? [:]).filter {
                $0.value.personRef == value.person && (matchingSeatNames == nil || matchingSeatNames?[$0.key] == $0.value.name)
            }.map(\.key))
        }
        if personalClaimsIndex?.readableLibraryIds != readable {
            var grouped: [PersonalRecordKey: [String: ParticipantHistoricalClaim]] = [:]
            for value in snapshot.ledgers.values where readable.contains(value.libraryId) {
                for claim in value.claims {
                    let key = PersonalRecordKey(libraryId: claim.libraryId, recordKey: claim.recordKey)
                    if let previous = grouped[key]?[claim.id], previous.revision > claim.revision || (previous.revision == claim.revision && previous.revoked) { continue }
                    grouped[key, default: [:]][claim.id] = claim
                }
            }
            personalClaimsIndex = PersonalClaimsIndex(readableLibraryIds: readable, claimsByRecord: grouped)
        }
        let key = PersonalRecordKey(libraryId: library, recordKey: recordKey)
        for claim in personalClaimsIndex?.claimsByRecord[key]?.values ?? Dictionary<String, ParticipantHistoricalClaim>().values where !claim.revoked && !(claim.aliasId.map(removed.contains) ?? false) {
            if let matchingSeatNames,
               matchingSeatNames[claim.seatKey].map(ParticipantIdentityRules.normalizedName) != ParticipantIdentityRules.normalizedName(claim.nameSnapshot) { continue }
            result.insert(claim.seatKey)
        }
        return result
    }

    @discardableResult func link(name: String, seats: [(String, PersonalRecordSeat)] = []) throws -> ParticipantAlias {
        guard matchesCurrentSession else { throw CancellationError() }
        var next = state
        var value = ledger
        let alias = try value.link(name: name)
        value.linkClaims(seats.map { record, seat in
            .init(libraryId: libraryId(for: record), recordKey: record, seatKey: seat.id,
                  aliasId: alias.id, nameSnapshot: seat.name)
        })
        next.ledgers[next.activeLibraryId] = value
        try commit(next)
        PersonalRecordsCloudSync.shared.enqueueIdentity(accountId: state.activeAccountId, operation: "linkAlias", alias: alias)
        return alias
    }

    private func validateCurrentAlias(_ alias: ParticipantAlias) throws {
        guard matchesCurrentSession, ledger.aliases.contains(where: { $0.id == alias.id && $0.state != .removed }) else {
            throw CancellationError()
        }
    }

    func setVisibility(_ alias: ParticipantAlias, visible: Bool) throws {
        try validateCurrentAlias(alias)
        var next = state; next.ledgers[next.activeLibraryId]?.setVisible(aliasId: alias.id, visible: visible)
        try commit(next); PersonalRecordsCloudSync.shared.enqueueIdentity(accountId: state.activeAccountId, operation: "setAliasVisibility", alias: alias, visible: visible)
    }

    func activate(_ alias: ParticipantAlias) throws {
        try validateCurrentAlias(alias)
        var next = state; try next.ledgers[next.activeLibraryId]?.activate(aliasId: alias.id)
        try commit(next); PersonalRecordsCloudSync.shared.enqueueIdentity(accountId: state.activeAccountId, operation: "activateAlias", alias: alias)
    }

    func unlink(_ alias: ParticipantAlias) throws {
        try validateCurrentAlias(alias)
        var next = state; next.ledgers[next.activeLibraryId]?.unlink(aliasId: alias.id)
        try commit(next); PersonalRecordsCloudSync.shared.enqueueIdentity(accountId: state.activeAccountId, operation: "removeAlias", alias: alias)
    }

    func markAliasPending(id: String?) throws {
        guard let id else { return }
        var next = state
        if let index = next.ledgers[next.activeLibraryId]?.aliases.firstIndex(where: { $0.id == id }) {
            next.ledgers[next.activeLibraryId]?.aliases[index].state = .pending
        }
        try commit(next)
    }

    func useAsGuestName(_ alias: ParticipantAlias) throws {
        try validateCurrentAlias(alias)
        guard isGuest, alias.state == .active else { return }
        var next = state; next.ledgers[next.activeLibraryId]?.preferredAliasId = alias.id
        try commit(next)
    }

    func beginAccount(_ accountId: String) throws {
        var next = state
        if let existing = next.ledgers.values.first(where: { $0.ownerAccountId == accountId && !next.archivedLibraries.contains($0.libraryId) }) {
            next.activeLibraryId = existing.libraryId
        } else {
            if let pending = next.ledgers.values.first(where: { $0.ownerAccountId == nil && next.pendingGuestOwners?[$0.libraryId] == accountId && !next.archivedLibraries.contains($0.libraryId) }) {
                next.activeLibraryId = pending.libraryId
            } else {
                let value = ParticipantIdentityLedger(ownerAccountId: accountId)
                next.ledgers[value.libraryId] = value; next.activeLibraryId = value.libraryId
            }
        }
        next.activeAccountId = accountId
        try commit(next)
    }

    func beginNewGuest() throws {
        guard state.activeAccountId != nil else { return }
        var next = state; let guest = ParticipantIdentityLedger()
        // Unindexed legacy files still belong to the library that existed before
        // logout; a newly created guest must not inherit them.
        if !next.migratedLegacy && next.legacyLibraryId == nil { next.legacyLibraryId = next.activeLibraryId }
        next.ledgers[guest.libraryId] = guest; next.activeLibraryId = guest.libraryId; next.activeAccountId = nil
        do { try commit(next) }
        catch {
            // Logout must hide the old account even if storage is unavailable.
            // Keep commit's persistence error, but fail closed for this process.
            personalClaimsIndex = nil
            state = next
            throw error
        }
    }

    var unownedLedgers: [ParticipantIdentityLedger] {
        state.ledgers.values.filter { $0.ownerAccountId == nil && !state.archivedLibraries.contains($0.libraryId) }
    }

    func adopt(libraryId: String, accountId: String, person: ParticipantPersonRef) throws {
        var next = state
        try next.ledgers[libraryId]?.adopt(accountId: accountId, personRef: person)
        next.pendingGuestOwners?.removeValue(forKey: libraryId)
        next.activeAccountId = accountId; next.activeLibraryId = libraryId
        try commit(next)
    }

    func install(person: ParticipantPersonRef, aliases cloudAliases: [ParticipantAlias], revision: Int) throws {
        var next = state; var value = ledger
        if let owner = value.ownerAccountId { try value.adopt(accountId: owner, personRef: person) }
        else { value.person = person }
        var combined = cloudAliases
        for local in value.aliases where !cloudAliases.contains(where: { $0.id == local.id || $0.normalizedName == local.normalizedName }) { combined.append(local) }
        var active = 0
        for index in combined.indices where combined[index].state == .active {
            active += 1
            if active > ParticipantIdentityRules.maximumActiveAliases { combined[index].state = .pending }
        }
        for index in value.claims.indices {
            if let old = value.aliases.first(where: { $0.id == value.claims[index].aliasId }),
               let replacement = cloudAliases.first(where: { $0.normalizedName == old.normalizedName }) {
                value.claims[index].aliasId = replacement.id
                if replacement.state == .removed && value.claims[index].provenance == "alias" && !value.claims[index].revoked {
                    value.claims[index].revoked = true; value.claims[index].revision += 1
                }
            }
        }
        value.aliases = combined; value.revision = revision
        next.ledgers[next.activeLibraryId] = value
        for key in Array(next.ledgers.keys) where key != next.activeLibraryId && next.ledgers[key]?.ownerAccountId == next.activeAccountId {
            guard var other = next.ledgers[key], let owner = other.ownerAccountId else { continue }
            try other.adopt(accountId: owner, personRef: person)
            for index in other.claims.indices {
                if let old = other.aliases.first(where: { $0.id == other.claims[index].aliasId }),
                   let replacement = cloudAliases.first(where: { $0.normalizedName == old.normalizedName }) {
                    other.claims[index].aliasId = replacement.id
                    if replacement.state == .removed && other.claims[index].provenance == "alias" && !other.claims[index].revoked {
                        other.claims[index].revoked = true; other.claims[index].revision += 1
                    }
                }
            }
            other.aliases = other.aliases.map { local in
                cloudAliases.first(where: { $0.normalizedName == local.normalizedName }) ?? local
            }
            next.ledgers[key] = other
        }
        try commit(next)
    }

    func installClaims(_ claims: [ParticipantHistoricalClaim]) throws {
        var next = state; next.ledgers[next.activeLibraryId]?.linkClaims(claims); try commit(next)
    }

    func recordReceived(key: String, libraryId: String) throws {
        var next = state
        if next.ledgers[libraryId] == nil {
            next.ledgers[libraryId] = ParticipantIdentityLedger(libraryId: libraryId, ownerAccountId: next.activeAccountId, person: person)
        }
        if next.recordLibraries[key] == nil { next.recordLibraries[key] = libraryId }
        try commit(next)
    }

    func archive(libraryIds: Set<String>) throws {
        var next = state; next.archivedLibraries.formUnion(libraryIds); try commit(next)
    }

    func clearLocalState(accountId: String?) throws {
        let guest = ParticipantIdentityLedger()
        try commit(State(activeLibraryId: guest.libraryId, ledgers: [guest.libraryId: guest]))
        if let accountId { try beginAccount(accountId) }
    }

    func completeAccountLink(masterId: String, sourceId: String?, mode: String) throws {
        var next = state
        if let sourceId {
            for (library, owner) in next.pendingGuestOwners ?? [:] where owner == sourceId {
                if mode == "merge" { next.pendingGuestOwners?[library] = masterId }
                else { next.archivedLibraries.insert(library) }
            }
            for key in Array(next.ledgers.keys) where next.ledgers[key]?.ownerAccountId == sourceId {
                if mode == "merge" { next.ledgers[key]?.ownerAccountId = masterId }
                else { next.archivedLibraries.insert(key) }
            }
        }
        try commit(next); try beginAccount(masterId)
    }

    private func commit(_ next: State) throws {
        do {
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            personalClaimsIndex = nil
            state = next; lastError = nil
        } catch { lastError = error.localizedDescription; throw error }
    }
}

func identityText(_ key: String, _ fallback: String) -> String {
    NSLocalizedString(key, tableName: "ParticipantIdentity", value: fallback, comment: "Participant identity")
}
