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
