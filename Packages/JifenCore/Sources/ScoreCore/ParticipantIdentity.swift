import Foundation

/// A person reference is separate from a game's stable seat and from the account
/// which owns a private record. Names are presentation snapshots, never IDs.
public struct ParticipantPersonRef: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case guest, account }
    public var id: String
    public var kind: Kind
    public init(id: String, kind: Kind) { self.id = id; self.kind = kind }
}

public struct ParticipantSelection: Codable, Hashable, Sendable {
    public var name: String
    public var personRef: ParticipantPersonRef?
    public init(name: String, personRef: ParticipantPersonRef? = nil) {
        self.name = name; self.personRef = personRef
    }
}

public struct ParticipantAlias: Codable, Hashable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable { case active, pending, removed }
    public var id: String
    public var name: String
    public var normalizedName: String
    public var state: State
    public var visibleInPicker: Bool
    public var revision: Int
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(id: String = UUID().uuidString, name: String, state: State = .active,
                visibleInPicker: Bool = true, revision: Int = 0,
                createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) {
        self.id = id; self.name = ParticipantIdentityRules.displayName(name)
        normalizedName = ParticipantIdentityRules.normalizedName(name)
        self.state = state; self.visibleInPicker = visibleInPicker
        self.revision = revision; self.createdAt = createdAt; updatedAt = createdAt
    }
}

public struct ParticipantHistoricalClaim: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var libraryId: String
    public var recordKey: String
    public var seatKey: String
    public var aliasId: String?
    public var nameSnapshot: String
    public var participantKind: String = "PERSON"
    public var provenance: String
    public var revoked: Bool
    public var revision: Int

    public init(id: String = UUID().uuidString, libraryId: String, recordKey: String,
                seatKey: String, aliasId: String? = nil, nameSnapshot: String,
                provenance: String = "alias", revoked: Bool = false, revision: Int = 0) {
        self.id = id; self.libraryId = libraryId; self.recordKey = recordKey
        self.seatKey = seatKey; self.aliasId = aliasId; self.nameSnapshot = nameSnapshot
        self.provenance = provenance; self.revoked = revoked; self.revision = revision
    }
}

public enum ParticipantIdentityError: Error, Equatable {
    case emptyName, aliasLimit, duplicatePerson, invalidParticipantKind, ownerMismatch
}

public enum ParticipantIdentityRules {
    public static let maximumActiveAliases = 3
    public static func displayName(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func normalizedName(_ value: String) -> String { displayName(value).lowercased() }

    public static func containsDuplicatePerson(_ selections: [ParticipantSelection]) -> Bool {
        let people = selections.compactMap(\.personRef)
        return Set(people).count != people.count
    }

    /// A typed or replaced name must not retain a previously chosen identity.
    public static func retainingIdentity(_ selection: ParticipantSelection, afterEditing name: String) -> ParticipantSelection {
        ParticipantSelection(name: name, personRef: name == selection.name ? selection.personRef : nil)
    }
}

/// Persisted per-library ledger. Historical membership survives hiding a name
/// and account-merge overflow; only an explicit unlink revokes alias claims.
public struct ParticipantIdentityLedger: Codable, Sendable {
    public var schemaVersion = 1
    public var libraryId: String
    public var ownerAccountId: String?
    public var person: ParticipantPersonRef
    public var aliases: [ParticipantAlias] = []
    public var claims: [ParticipantHistoricalClaim] = []
    public var preferredAliasId: String?
    public var recordSelections: [String: [String: ParticipantSelection]] = [:]
    public var revision = 0

    public init(libraryId: String = UUID().uuidString, ownerAccountId: String? = nil,
                person: ParticipantPersonRef? = nil) {
        self.libraryId = libraryId; self.ownerAccountId = ownerAccountId
        self.person = person ?? .init(id: UUID().uuidString, kind: ownerAccountId == nil ? .guest : .account)
    }

    public var activeAliases: [ParticipantAlias] { aliases.filter { $0.state == .active } }
    public var preferredName: String? {
        aliases.first { $0.id == preferredAliasId && $0.state == .active && $0.visibleInPicker }?.name
            ?? activeAliases.first { $0.visibleInPicker }?.name
    }

    @discardableResult public mutating func link(name: String, participantKind: String = "PERSON") throws -> ParticipantAlias {
        guard participantKind == "PERSON" else { throw ParticipantIdentityError.invalidParticipantKind }
        let normalized = ParticipantIdentityRules.normalizedName(name)
        guard !normalized.isEmpty else { throw ParticipantIdentityError.emptyName }
        if let index = aliases.firstIndex(where: { $0.normalizedName == normalized && $0.state != .removed }) {
            return aliases[index]
        }
        guard activeAliases.count < ParticipantIdentityRules.maximumActiveAliases else { throw ParticipantIdentityError.aliasLimit }
        let alias = ParticipantAlias(name: name)
        aliases.append(alias)
        if preferredAliasId == nil { preferredAliasId = alias.id }
        return alias
    }

    public mutating func setVisible(aliasId: String, visible: Bool) {
        guard let index = aliases.firstIndex(where: { $0.id == aliasId }) else { return }
        aliases[index].visibleInPicker = visible
    }

    public mutating func activate(aliasId: String) throws {
        guard let index = aliases.firstIndex(where: { $0.id == aliasId && $0.state == .pending }) else { return }
        guard activeAliases.count < ParticipantIdentityRules.maximumActiveAliases else { throw ParticipantIdentityError.aliasLimit }
        aliases[index].state = .active
    }

    public mutating func unlink(aliasId: String) {
        guard let index = aliases.firstIndex(where: { $0.id == aliasId }) else { return }
        aliases[index].state = .removed
        for index in claims.indices where claims[index].aliasId == aliasId && claims[index].provenance == "alias" {
            claims[index].revoked = true
        }
        if preferredAliasId == aliasId { preferredAliasId = nil }
        // New explicit selections remain personal even after an old alias is removed.
    }

    public mutating func linkClaims(_ incoming: [ParticipantHistoricalClaim]) {
        for claim in incoming where claim.participantKind == "PERSON" {
            if let index = claims.firstIndex(where: { $0.id == claim.id }) {
                if incomingRevisionWins(claim, over: claims[index]) { claims[index] = claim }
            } else if !claims.contains(where: { !$0.revoked && $0.libraryId == claim.libraryId && $0.recordKey == claim.recordKey && $0.seatKey == claim.seatKey && $0.aliasId == claim.aliasId }) {
                claims.append(claim)
            }
        }
    }

    private func incomingRevisionWins(_ incoming: ParticipantHistoricalClaim, over current: ParticipantHistoricalClaim) -> Bool {
        incoming.revision > current.revision || (incoming.revision == current.revision && incoming.revoked)
    }

    public mutating func register(recordKey: String, selections: [String: ParticipantSelection]) throws {
        guard !ParticipantIdentityRules.containsDuplicatePerson(Array(selections.values)) else { throw ParticipantIdentityError.duplicatePerson }
        recordSelections[recordKey] = selections
    }

    public func personalSeats(recordKey: String, libraryId: String? = nil) -> Set<String> {
        var seats = Set((recordSelections[recordKey] ?? [:]).filter { $0.value.personRef == person }.map(\.key))
        for claim in claims where !claim.revoked && claim.recordKey == recordKey && claim.libraryId == (libraryId ?? self.libraryId) {
            seats.insert(claim.seatKey)
        }
        return seats
    }

    public mutating func adopt(accountId: String, personRef: ParticipantPersonRef) throws {
        guard ownerAccountId == nil || ownerAccountId == accountId else { throw ParticipantIdentityError.ownerMismatch }
        let previous = person
        ownerAccountId = accountId; person = personRef
        for recordKey in Array(recordSelections.keys) {
            for seatKey in Array(recordSelections[recordKey]?.keys ?? Dictionary<String, ParticipantSelection>().keys) {
                if recordSelections[recordKey]?[seatKey]?.personRef == previous {
                    recordSelections[recordKey]?[seatKey]?.personRef = personRef
                }
            }
        }
    }
}
