import Foundation

public typealias DoublesPlayerSlotIndex = Int

public struct PingPongDoublesRotationState: Codable, Equatable, Sendable {
    public var serverSlotIndex: DoublesPlayerSlotIndex
    public var receiverSlotIndex: DoublesPlayerSlotIndex
    public let openingServerSlotIndex: DoublesPlayerSlotIndex
    public let openingReceiverSlotIndex: DoublesPlayerSlotIndex
    public var decidingReceiverOrderChanged: Bool

    public init(
        serverSlotIndex: DoublesPlayerSlotIndex,
        receiverSlotIndex: DoublesPlayerSlotIndex,
        openingServerSlotIndex: DoublesPlayerSlotIndex,
        openingReceiverSlotIndex: DoublesPlayerSlotIndex,
        decidingReceiverOrderChanged: Bool = false
    ) {
        self.serverSlotIndex = serverSlotIndex
        self.receiverSlotIndex = receiverSlotIndex
        self.openingServerSlotIndex = openingServerSlotIndex
        self.openingReceiverSlotIndex = openingReceiverSlotIndex
        self.decidingReceiverOrderChanged = decidingReceiverOrderChanged
    }
}

public struct PingPongDoublesRotationResult: Codable, Equatable, Sendable {
    public let state: PingPongDoublesRotationState
    public let shouldExchangeEnds: Bool

    public init(state: PingPongDoublesRotationState, shouldExchangeEnds: Bool) {
        self.state = state
        self.shouldExchangeEnds = shouldExchangeEnds
    }
}

public struct BadmintonDoublesRotationState: Codable, Equatable, Sendable {
    public var serverSlotIndex: DoublesPlayerSlotIndex
    public var receiverSlotIndex: DoublesPlayerSlotIndex
    public var team0CourtOrderSwapped: Bool
    public var team1CourtOrderSwapped: Bool

    public init(
        serverSlotIndex: DoublesPlayerSlotIndex,
        receiverSlotIndex: DoublesPlayerSlotIndex,
        team0CourtOrderSwapped: Bool = false,
        team1CourtOrderSwapped: Bool = false
    ) {
        self.serverSlotIndex = serverSlotIndex
        self.receiverSlotIndex = receiverSlotIndex
        self.team0CourtOrderSwapped = team0CourtOrderSwapped
        self.team1CourtOrderSwapped = team1CourtOrderSwapped
    }
}

/// USA pickleball doubles: server #1/#2, first-serve-of-game (0-0-2), partner swap on serve score.
public struct PickleballDoublesRotationState: Codable, Equatable, Sendable {
    public var serverNumber: Int
    public var isFirstServeOfGame: Bool
    public var team0PartnersSwapped: Bool
    public var team1PartnersSwapped: Bool
    public var serverSlotIndex: DoublesPlayerSlotIndex
    public var receiverSlotIndex: DoublesPlayerSlotIndex

    public init(
        serverNumber: Int = 2,
        isFirstServeOfGame: Bool = true,
        team0PartnersSwapped: Bool = false,
        team1PartnersSwapped: Bool = false,
        serverSlotIndex: DoublesPlayerSlotIndex = 2,
        receiverSlotIndex: DoublesPlayerSlotIndex = 3
    ) {
        self.serverNumber = serverNumber == 2 ? 2 : 1
        self.isFirstServeOfGame = isFirstServeOfGame
        self.team0PartnersSwapped = team0PartnersSwapped
        self.team1PartnersSwapped = team1PartnersSwapped
        self.serverSlotIndex = serverSlotIndex
        self.receiverSlotIndex = receiverSlotIndex
    }
}

public enum RallyDoublesRotationState: Codable, Equatable, Sendable {
    case pingPong(PingPongDoublesRotationState)
    case badminton(BadmintonDoublesRotationState)
    case pickleball(PickleballDoublesRotationState)
    /// Foosball 2V2 has four fixed corner participants and no serving rotation.
    case foosball
}

public struct RallyDoublesState: Codable, Equatable, Sendable {
    public var playerNames: [String]
    public var rotation: RallyDoublesRotationState

    public init(playerNames: [String], rotation: RallyDoublesRotationState) {
        let defaults = ["Player 1", "Player 2", "Player 3", "Player 4"]
        self.playerNames = (0..<4).map { index in
            guard playerNames.indices.contains(index) else { return defaults[index] }
            let name = playerNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? defaults[index] : name
        }
        self.rotation = rotation
    }

    public static func pingPong(
        playerNames: [String],
        openingServerSlotIndex: DoublesPlayerSlotIndex = 0,
        openingReceiverSlotIndex: DoublesPlayerSlotIndex = 1
    ) -> Self {
        .init(
            playerNames: playerNames,
            rotation: .pingPong(createPingPongDoublesRotation(
                openingServerSlotIndex: openingServerSlotIndex,
                openingReceiverSlotIndex: openingReceiverSlotIndex
            ))
        )
    }

    public static func badminton(playerNames: [String], servingTeam0: Bool = true) -> Self {
        .init(
            playerNames: playerNames,
            rotation: .badminton(createBadmintonDoublesRotation(servingTeam0: servingTeam0))
        )
    }

    public static func pickleball(playerNames: [String], servingTeam0: Bool = true) -> Self {
        .init(
            playerNames: playerNames,
            rotation: .pickleball(createPickleballDoublesRotation(servingTeam0: servingTeam0))
        )
    }

    public static func foosball(playerNames: [String]) -> Self {
        .init(playerNames: playerNames, rotation: .foosball)
    }

    public var serverSlotIndex: DoublesPlayerSlotIndex {
        switch rotation {
        case .pingPong(let state): state.serverSlotIndex
        case .badminton(let state): state.serverSlotIndex
        case .pickleball(let state): state.serverSlotIndex
        case .foosball: 0
        }
    }

    public var receiverSlotIndex: DoublesPlayerSlotIndex {
        switch rotation {
        case .pingPong(let state): state.receiverSlotIndex
        case .badminton(let state): state.receiverSlotIndex
        case .pickleball(let state): state.receiverSlotIndex
        case .foosball: 1
        }
    }

    public var pickleballServerNumber: Int? {
        if case .pickleball(let state) = rotation { return state.serverNumber }
        return nil
    }

    public var pickleballPartnersSwapped: (team0: Bool, team1: Bool)? {
        if case .pickleball(let state) = rotation {
            return (state.team0PartnersSwapped, state.team1PartnersSwapped)
        }
        return nil
    }

    public var serverName: String? {
        playerName(at: serverSlotIndex)
    }

    public var receiverName: String? {
        playerName(at: receiverSlotIndex)
    }

    public func playerName(at slotIndex: DoublesPlayerSlotIndex) -> String? {
        guard playerNames.indices.contains(slotIndex) else { return nil }
        return playerNames[slotIndex]
    }
}

public func doublesPartnerSlot(_ slot: DoublesPlayerSlotIndex) -> DoublesPlayerSlotIndex {
    switch ((slot % 4) + 4) % 4 {
    case 0: 2
    case 2: 0
    case 1: 3
    default: 1
    }
}

public func isTeam0DoublesSlot(_ slot: DoublesPlayerSlotIndex) -> Bool {
    let normalized = ((slot % 4) + 4) % 4
    return normalized == 0 || normalized == 2
}

public func createPingPongDoublesRotation(
    openingServerSlotIndex: DoublesPlayerSlotIndex,
    openingReceiverSlotIndex: DoublesPlayerSlotIndex
) -> PingPongDoublesRotationState {
    PingPongDoublesRotationState(
        serverSlotIndex: openingServerSlotIndex,
        receiverSlotIndex: openingReceiverSlotIndex,
        openingServerSlotIndex: openingServerSlotIndex,
        openingReceiverSlotIndex: openingReceiverSlotIndex
    )
}

public func advancePingPongDoublesRotation(
    current: PingPongDoublesRotationState,
    previousTeam0Score: Int,
    previousTeam1Score: Int,
    nextTeam0Score: Int,
    nextTeam1Score: Int,
    pointsToWin: Int,
    isDecidingSet: Bool
) -> PingPongDoublesRotationResult {
    var next = current
    let switchPoint = max(1, max(1, pointsToWin) / 2)
    let crossedSwitchPoint = isDecidingSet && !current.decidingReceiverOrderChanged && (
        (previousTeam0Score < switchPoint && nextTeam0Score >= switchPoint) ||
        (previousTeam1Score < switchPoint && nextTeam1Score >= switchPoint)
    )

    if crossedSwitchPoint {
        next.receiverSlotIndex = doublesPartnerSlot(next.receiverSlotIndex)
        next.decidingReceiverOrderChanged = true
    }

    let deucePoint = max(1, pointsToWin - 1)
    let nextTotal = nextTeam0Score + nextTeam1Score
    let serviceChanges = nextTeam0Score >= deucePoint && nextTeam1Score >= deucePoint
        ? true
        : nextTotal.isMultiple(of: 2)
    if serviceChanges {
        let previousServer = next.serverSlotIndex
        next.serverSlotIndex = next.receiverSlotIndex
        next.receiverSlotIndex = doublesPartnerSlot(previousServer)
    }

    return PingPongDoublesRotationResult(state: next, shouldExchangeEnds: crossedSwitchPoint)
}

public func createBadmintonDoublesRotation(servingTeam0: Bool) -> BadmintonDoublesRotationState {
    BadmintonDoublesRotationState(
        serverSlotIndex: badmintonPlayerAtServiceCourt(
            team0: servingTeam0,
            rightCourt: true,
            team0CourtOrderSwapped: false,
            team1CourtOrderSwapped: false
        ),
        receiverSlotIndex: badmintonPlayerAtServiceCourt(
            team0: !servingTeam0,
            rightCourt: true,
            team0CourtOrderSwapped: false,
            team1CourtOrderSwapped: false
        )
    )
}

public func advanceBadmintonDoublesRotation(
    current: BadmintonDoublesRotationState,
    scoringTeam0: Bool,
    nextTeam0Score: Int,
    nextTeam1Score: Int
) -> BadmintonDoublesRotationState {
    let servingTeam0 = isTeam0DoublesSlot(current.serverSlotIndex)
    var next = current

    if scoringTeam0 == servingTeam0 {
        if servingTeam0 {
            next.team0CourtOrderSwapped.toggle()
        } else {
            next.team1CourtOrderSwapped.toggle()
        }
    } else {
        let servingScore = scoringTeam0 ? nextTeam0Score : nextTeam1Score
        next.serverSlotIndex = badmintonPlayerAtServiceCourt(
            team0: scoringTeam0,
            rightCourt: servingScore.isMultiple(of: 2),
            team0CourtOrderSwapped: next.team0CourtOrderSwapped,
            team1CourtOrderSwapped: next.team1CourtOrderSwapped
        )
    }

    let servingScore = isTeam0DoublesSlot(next.serverSlotIndex) ? nextTeam0Score : nextTeam1Score
    next.receiverSlotIndex = badmintonPlayerAtServiceCourt(
        team0: !isTeam0DoublesSlot(next.serverSlotIndex),
        rightCourt: servingScore.isMultiple(of: 2),
        team0CourtOrderSwapped: next.team0CourtOrderSwapped,
        team1CourtOrderSwapped: next.team1CourtOrderSwapped
    )
    return next
}

public func badmintonPlayerAtServiceCourt(
    team0: Bool,
    rightCourt: Bool,
    team0CourtOrderSwapped: Bool,
    team1CourtOrderSwapped: Bool
) -> DoublesPlayerSlotIndex {
    if team0 {
        let top = team0CourtOrderSwapped ? 2 : 0
        let bottom = team0CourtOrderSwapped ? 0 : 2
        return rightCourt ? bottom : top
    }
    let top = team1CourtOrderSwapped ? 3 : 1
    let bottom = team1CourtOrderSwapped ? 1 : 3
    return rightCourt ? top : bottom
}

public func resolveTennisDoublesReceiverSlot(
    serverSlotIndex: DoublesPlayerSlotIndex,
    pointIndexInGame: Int,
    team0FirstReceiverSlotIndex: DoublesPlayerSlotIndex,
    team1FirstReceiverSlotIndex: DoublesPlayerSlotIndex
) -> DoublesPlayerSlotIndex {
    let firstReceiver = isTeam0DoublesSlot(serverSlotIndex)
        ? team1FirstReceiverSlotIndex
        : team0FirstReceiverSlotIndex
    return max(0, pointIndexInGame).isMultiple(of: 2)
        ? firstReceiver
        : doublesPartnerSlot(firstReceiver)
}

/// Aligns with Android `resolvePickleballDoublesServingTop` + initial `serverNumber = 2`.
public func createPickleballDoublesRotation(servingTeam0: Bool = true) -> PickleballDoublesRotationState {
    var state = PickleballDoublesRotationState(
        serverNumber: 2,
        isFirstServeOfGame: true,
        team0PartnersSwapped: false,
        team1PartnersSwapped: false
    )
    refreshPickleballDoublesSlots(&state, servingTeam0: servingTeam0)
    return state
}

public func refreshPickleballDoublesSlots(
    _ state: inout PickleballDoublesRotationState,
    servingTeam0: Bool
) {
    let swapped = servingTeam0 ? state.team0PartnersSwapped : state.team1PartnersSwapped
    let logicalServerOnTop = state.serverNumber == 2
    let displayLogicalTop = logicalServerOnTop != swapped
    if servingTeam0 {
        state.serverSlotIndex = displayLogicalTop ? 0 : 2
        // Right team visual flip mirrors Android servingTeamOnRight path.
        state.receiverSlotIndex = displayLogicalTop ? 3 : 1
    } else {
        state.serverSlotIndex = displayLogicalTop ? 3 : 1
        state.receiverSlotIndex = displayLogicalTop ? 0 : 2
    }
}

public func togglePickleballPartnerSwap(
    _ state: inout PickleballDoublesRotationState,
    servingTeam0: Bool
) {
    if servingTeam0 {
        state.team0PartnersSwapped.toggle()
    } else {
        state.team1PartnersSwapped.toggle()
    }
}
