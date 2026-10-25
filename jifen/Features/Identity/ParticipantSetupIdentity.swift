import Foundation
import ScoreCore
import SwiftUI

extension SportsSetupDraft {
    func validParticipantSelections(gameType: GameType) -> [String: ParticipantSelection] {
        guard PersonalRecordAdapter.supportsPerson(gameType) else { return [:] }
        guard !(gameType == .shuttlecock && competitionFormat == .team) else { return [:] }
        let named = gameType == .padel || (gameType == .shuttlecock && competitionFormat != .singles)
            || ([GameType.pingpong, .badminton, .tennis, .softTennis, .pickleball, .foosball].contains(gameType) && !isSingles)
        let names: [String: String]
        if named {
            var players = ["side:0:player:0": team1Player1Name, "side:0:player:1": team1Player2Name,
                           "side:1:player:0": team2Player1Name, "side:1:player:1": team2Player2Name]
            if gameType == .shuttlecock && competitionFormat == .team {
                players["side:0:player:2"] = team1Player3Name; players["side:1:player:2"] = team2Player3Name
            }
            names = players
        } else { names = ["side:0": team1Name, "side:1": team2Name] }
        return participantSelections.filter { key, value in value.personRef != nil && names[key] == value.name }
    }
}

/// SwiftUI may construct a scoreboard many times before installing its State.
/// Register only after appearance, using the record ID held by installed State.
/// A nil selection snapshot denotes a restored session and preserves its ledger.
private struct ParticipantSetupIdentityRegistration: ViewModifier {
    let recordID: String
    let selections: [String: ParticipantSelection]?
    let identity: ParticipantIdentityStore?
    @State private var didRegisterInitialRecord = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !didRegisterInitialRecord, let selections else { return }
            didRegisterInitialRecord = true
            do { try (identity ?? .shared).registerRecord(recordID, selections: selections) }
            catch {
                didRegisterInitialRecord = false
                ScoreboardPersistenceFailureReporter.report(error, context: "Participant setup persistence")
            }
        }
    }
}

extension View {
    func registerParticipantSetupOnAppear(
        recordID: String,
        selections: [String: ParticipantSelection]?,
        identity: ParticipantIdentityStore? = nil
    ) -> some View {
        modifier(ParticipantSetupIdentityRegistration(recordID: recordID, selections: selections, identity: identity))
    }
}
