//
//  TennisViewModel.swift
//  jifen
//
//  Tennis score view model - handles games, sets, and tie-break rules
//

import Foundation
import ScoreCore

@Observable
class TennisViewModel: BaseScoreViewModel {
    enum AdvantageState {
        case none
        case left
        case right
    }
    
    var currentSet: Int = 1
    var maxSets: Int = 3
    var tieBreakTarget: Int = 7
    var gamesPerSet: Int = 6
    var setScoringMode: String = "regular"
    var isTieBreak: Bool = false
    var isDeuce: Bool = false
    var advantage: AdvantageState = .none
    var autoChangeSides: Bool = true
    var isSingles: Bool = true
    var sidesSwapped: Bool = false
    var matchCompletionMode: MatchCompletionMode = .bestOf
    var usesNoAdScoring: Bool = false
    var openingServerSide: MatchSide = .left
    var voiceAnnouncement: Bool = false
    /// First server of the current set (continuous match order, Android-aligned).
    var firstServerInSet: MatchSide = .left
    /// Doubles identity slots: 0=红上, 1=蓝上, 2=红下, 3=蓝下.
    var firstServerSlotInSet: Int = 0
    var team0FirstReceiverSlot: Int = 1
    var team1FirstReceiverSlot: Int = 0

    private var tieBreakChangeSidesCount: Int = 0
    private var currentGameInSet: Int = 0
    var tieBreakFirstServer: MatchSide = .left
    var tieBreakFirstServerSlot: Int = 0

    var onGameEndCallback: ((Int, Int, Int) -> Void)? = nil
    var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil
    /// Fired when sides should change: already swapped if auto, otherwise remind manually.
    var onSideChangeCallback: ((Bool) -> Void)? = nil

    private var tennisHistory: [TennisStateSnapshot] = []

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.sets = 0
        rightTeam.sets = 0
        leftTeam.games = 0
        rightTeam.games = 0
    }

    // MARK: - Configuration

    func setConfig(
        maxSets: Int,
        autoChangeSides: Bool = true,
        matchCompletionMode: MatchCompletionMode = .bestOf,
        usesNoAdScoring: Bool = false,
        openingServerSide: MatchSide = .left,
        voiceAnnouncement: Bool = false,
        isSingles: Bool = true,
        gamesPerSet: Int = 6,
        setScoringMode: String = "regular"
    ) {
        self.setScoringMode = setScoringMode == "tiebreak_only" ? "tiebreak_only" : "regular"
        self.gamesPerSet = gamesPerSet == 4 ? 4 : 6
        self.maxSets = self.setScoringMode == "tiebreak_only" ? 1 : maxSets
        self.autoChangeSides = autoChangeSides
        self.matchCompletionMode = self.setScoringMode == "tiebreak_only" ? .bestOf : matchCompletionMode
        self.usesNoAdScoring = usesNoAdScoring
        self.openingServerSide = openingServerSide
        self.voiceAnnouncement = voiceAnnouncement
        self.isSingles = isSingles
        self.firstServerInSet = openingServerSide
        self.firstServerSlotInSet = openingServerSide == .left ? 0 : 1
        self.team0FirstReceiverSlot = 1
        self.team1FirstReceiverSlot = 0
        self.isTieBreak = self.setScoringMode == "tiebreak_only"
        self.tieBreakFirstServer = openingServerSide
        self.tieBreakFirstServerSlot = self.firstServerSlotInSet
    }

    func setOnGameEndCallback(_ callback: @escaping (Int, Int, Int) -> Void) {
        onGameEndCallback = callback
    }

    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        onSetEndCallback = callback
    }

    func setOnSideChangeCallback(_ callback: @escaping (Bool) -> Void) {
        onSideChangeCallback = callback
    }
    
    func scoreDisplay(isLeft: Bool) -> String {
        let score = isLeft ? leftTeam.score : rightTeam.score
        
        if isTieBreak {
            return "\(score)"
        }
        
        if isDeuce {
            switch advantage {
            case .none:
                return "40"
            case .left:
                return isLeft ? "AD" : "40"
            case .right:
                return isLeft ? "40" : "AD"
            }
        }
        
        switch score {
        case 0:
            return "0"
        case 1:
            return "15"
        case 2:
            return "30"
        default:
            return "40"
        }
    }

    func getWinnerName() -> String {
        guard gameFinished else { return "" }
        let leftSets = leftTeam.sets ?? 0
        let rightSets = rightTeam.sets ?? 0
        if leftSets > rightSets {
            return leftTeam.name
        } else if rightSets > leftSets {
            return rightTeam.name
        }
        return ""
    }

    override func endGame() {
        guard !gameFinished else { return }
        saveTennisSnapshot()
        gameFinished = true
        saveGameRecordInRealTime(isGameFinished: true)
    }

    /// Android-aligned: continuous set first-server + per-game alternate;
    /// tiebreak uses 1 then 2-2 blocks from tiebreak first server.
    func isLeftServing() -> Bool {
        servingSide() == .left
    }

    func servingSide() -> MatchSide {
        if isTieBreak {
            let pointsPlayed = leftTeam.score + rightTeam.score
            let block = (pointsPlayed + 1) / 2
            return block.isMultiple(of: 2) ? tieBreakFirstServer : tieBreakFirstServer.opposite
        }
        let completedGames = (leftTeam.games ?? 0) + (rightTeam.games ?? 0)
        return completedGames.isMultiple(of: 2) ? firstServerInSet : firstServerInSet.opposite
    }

    /// Doubles identity slot currently serving (nil in singles).
    func currentServerSlot() -> Int? {
        guard !isSingles else { return nil }
        if isTieBreak {
            let pointsPlayed = leftTeam.score + rightTeam.score
            let offset = pointsPlayed <= 0 ? 0 : (pointsPlayed + 1) / 2
            return modServerSlot(tieBreakFirstServerSlot + offset)
        }
        let completedGames = (leftTeam.games ?? 0) + (rightTeam.games ?? 0)
        return modServerSlot(firstServerSlotInSet + completedGames)
    }

    func currentReceiverSlot() -> Int? {
        guard let server = currentServerSlot() else { return nil }
        let indexInGame = leftTeam.score + rightTeam.score
        return resolveTennisDoublesReceiverSlot(
            serverSlotIndex: server,
            pointIndexInGame: indexInGame,
            team0FirstReceiverSlotIndex: team0FirstReceiverSlot,
            team1FirstReceiverSlotIndex: team1FirstReceiverSlot
        )
    }

    /// True when doubles server is in the top row (slots 0/1).
    func isDoublesServerTopRow() -> Bool {
        guard let slot = currentServerSlot() else { return true }
        return slot == 0 || slot == 1
    }
    
    // MARK: - Override Score Operations
    
    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        
        // If game or tiebreak is already won (e.g. by rapid tap), do not add more points
        if isTieBreak {
            let leftScore = leftTeam.score
            let rightScore = rightTeam.score
            if max(leftScore, rightScore) >= tieBreakTarget && abs(leftScore - rightScore) >= 2 {
                return
            }
        } else {
            if canWinGame(leftScore: leftTeam.score, rightScore: rightTeam.score) {
                return
            }
        }
        
        saveTennisSnapshot()
        
        if isTieBreak {
            if isLeft {
                leftTeam.score += points
            } else {
                rightTeam.score += points
            }
            announceScoreIfNeeded()
            
            let totalScore = leftTeam.score + rightTeam.score
            let expectedChangeCount = totalScore / 6
            if expectedChangeCount > tieBreakChangeSidesCount {
                tieBreakChangeSidesCount = expectedChangeCount
                applySideChangeIfNeeded()
            }
            
            handleTieBreak()
        } else {
            if isLeft {
                leftTeam.score += points
            } else {
                rightTeam.score += points
            }
            announceScoreIfNeeded()
            checkGameWinner()
        }
        
        controller?.performVibration(type: .light)
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
    }
    
    override func reset() {
        super.reset()
        currentSet = 1
        leftTeam.sets = 0
        rightTeam.sets = 0
        leftTeam.games = 0
        rightTeam.games = 0
        isTieBreak = setScoringMode == "tiebreak_only"
        isDeuce = false
        advantage = .none
        sidesSwapped = false
        tieBreakChangeSidesCount = 0
        currentGameInSet = 0
        firstServerInSet = openingServerSide
        firstServerSlotInSet = openingServerSide == .left ? 0 : 1
        tieBreakFirstServer = openingServerSide
        tieBreakFirstServerSlot = firstServerSlotInSet
        tennisHistory.removeAll()
    }
    
    override func undo() -> Bool {
        guard let controller = controller, controller.undoEnabled else { return false }
        
        guard let snapshot = tennisHistory.popLast() else {
            return super.undo()
        }
        
        restoreTennisSnapshot(snapshot)
        controller.performVibration(type: .light)
        return true
    }
    
    override func exchangeSides() {
        guard !gameFinished else { return }

        saveTennisSnapshot()

        let tempName = leftTeam.name
        let tempScore = leftTeam.score
        let tempSets = leftTeam.sets
        let tempGames = leftTeam.games

        leftTeam.name = rightTeam.name
        leftTeam.score = rightTeam.score
        leftTeam.sets = rightTeam.sets
        leftTeam.games = rightTeam.games

        rightTeam.name = tempName
        rightTeam.score = tempScore
        rightTeam.sets = tempSets
        rightTeam.games = tempGames

        sidesSwapped.toggle()
        openingServerSide = openingServerSide.opposite
        firstServerInSet = firstServerInSet.opposite
        tieBreakFirstServer = tieBreakFirstServer.opposite
        firstServerSlotInSet = swapDoublesSlotSides(firstServerSlotInSet)
        tieBreakFirstServerSlot = swapDoublesSlotSides(tieBreakFirstServerSlot)
        let prevTeam0Receiver = team0FirstReceiverSlot
        team0FirstReceiverSlot = swapDoublesSlotSides(team1FirstReceiverSlot)
        team1FirstReceiverSlot = swapDoublesSlotSides(prevTeam0Receiver)
        controller?.performVibration(type: .medium)
    }
    
    // MARK: - Game Logic
    
    private func checkGameWinner() {
        let leftScore = leftTeam.score
        let rightScore = rightTeam.score
        
        updateDeuceState(leftScore: leftScore, rightScore: rightScore)
        
        guard canWinGame(leftScore: leftScore, rightScore: rightScore) else {
            return
        }
        
        if leftScore > rightScore {
            leftTeam.games = (leftTeam.games ?? 0) + 1
        } else {
            rightTeam.games = (rightTeam.games ?? 0) + 1
        }
        
        currentGameInSet += 1
        let leftGames = leftTeam.games ?? 0
        let rightGames = rightTeam.games ?? 0
        
        onGameEndCallback?(leftGames, rightGames, currentGameInSet)

        let setJustWon = setWinnerIsDecided(leftGames: leftGames, rightGames: rightGames)
        // Odd games in set → change ends, unless the set itself just ended (set-end path handles that).
        if !setJustWon,
           !shouldStartTieBreak(leftGames: leftGames, rightGames: rightGames),
           (leftGames + rightGames) > 0,
           (leftGames + rightGames) % 2 == 1 {
            applySideChangeIfNeeded()
        }

        if shouldStartTieBreak(leftGames: leftGames, rightGames: rightGames) {
            startTieBreak()
        } else {
            leftTeam.score = 0
            rightTeam.score = 0
            isDeuce = false
            advantage = .none
        }

        checkSetWinner()
    }

    private func setWinnerIsDecided(leftGames: Int, rightGames: Int) -> Bool {
        if setScoringMode == "tiebreak_only" { return leftGames == 1 || rightGames == 1 }
        if leftGames >= gamesPerSet && leftGames - rightGames >= 2 { return true }
        if rightGames >= gamesPerSet && rightGames - leftGames >= 2 { return true }
        if (leftGames == gamesPerSet + 1 && rightGames == gamesPerSet) ||
            (rightGames == gamesPerSet + 1 && leftGames == gamesPerSet) { return true }
        return false
    }
    
    private func canWinGame(leftScore: Int, rightScore: Int) -> Bool {
        if usesNoAdScoring, leftScore >= 3, rightScore >= 3 {
            return leftScore != rightScore
        }
        if max(leftScore, rightScore) >= 4 {
            return abs(leftScore - rightScore) >= 2
        }
        return false
    }
    
    private func updateDeuceState(leftScore: Int, rightScore: Int) {
        if leftScore >= 3 && rightScore >= 3 {
            isDeuce = true
            if usesNoAdScoring || leftScore == rightScore {
                advantage = .none
            } else if leftScore > rightScore {
                advantage = .left
            } else {
                advantage = .right
            }
        } else {
            isDeuce = false
            advantage = .none
        }
    }

    private func announceScoreIfNeeded() {
        guard voiceAnnouncement else { return }
        ScoreVoiceAnnouncer.shared.announce(left: leftTeam.score, right: rightTeam.score)
    }
    
    private func shouldStartTieBreak(leftGames: Int, rightGames: Int) -> Bool {
        return setScoringMode == "tiebreak_only" ||
            (leftGames == gamesPerSet && rightGames == gamesPerSet)
    }
    
    private func startTieBreak() {
        isTieBreak = true
        leftTeam.score = 0
        rightTeam.score = 0
        tieBreakChangeSidesCount = 0
        // At 6–6, completedGames is even → first server of set opens the tiebreak.
        tieBreakFirstServer = firstServerInSet
        tieBreakFirstServerSlot = firstServerSlotInSet
    }
    
    private func handleTieBreak() {
        let leftScore = leftTeam.score
        let rightScore = rightTeam.score
        
        if max(leftScore, rightScore) >= tieBreakTarget && abs(leftScore - rightScore) >= 2 {
            if leftScore > rightScore {
                leftTeam.games = (leftTeam.games ?? 0) + 1
            } else {
                rightTeam.games = (rightTeam.games ?? 0) + 1
            }
            
            currentGameInSet += 1
            
            isTieBreak = false
            leftTeam.score = 0
            rightTeam.score = 0
            
            checkSetWinner()
        }
    }
    
    // MARK: - Set Logic
    
    private func checkSetWinner() {
        let leftGames = leftTeam.games ?? 0
        let rightGames = rightTeam.games ?? 0
        let setNumber = currentSet
        
        var winnerLeft: Bool? = nil
        
        if setScoringMode == "tiebreak_only", leftGames == 1 {
            winnerLeft = true
        } else if setScoringMode == "tiebreak_only", rightGames == 1 {
            winnerLeft = false
        } else if leftGames >= gamesPerSet && leftGames - rightGames >= 2 {
            winnerLeft = true
        } else if rightGames >= gamesPerSet && rightGames - leftGames >= 2 {
            winnerLeft = false
        } else if (leftGames == gamesPerSet + 1 && rightGames == gamesPerSet) ||
                    (rightGames == gamesPerSet + 1 && leftGames == gamesPerSet) {
            winnerLeft = leftGames > rightGames
        }
        
        guard let winnerIsLeft = winnerLeft else { return }
        
        let winnerName = winnerIsLeft ? leftTeam.name : rightTeam.name
        let newLeftSets = winnerIsLeft ? (leftTeam.sets ?? 0) + 1 : (leftTeam.sets ?? 0)
        let newRightSets = !winnerIsLeft ? (rightTeam.sets ?? 0) + 1 : (rightTeam.sets ?? 0)
        let isGameFinished = matchCompletionMode.isMatchFinished(
            maxSets: maxSets,
            leftSets: newLeftSets,
            rightSets: newRightSets
        )
        let shouldChangeSides = !isGameFinished && (leftGames + rightGames) % 2 == 1

        if let callback = onSetEndCallback {
            let callbackData = SetEndCallbackData(
                finalLeftScore: leftGames,
                finalRightScore: rightGames,
                winnerName: winnerName,
                setNumber: setNumber,
                leftSets: newLeftSets,
                rightSets: newRightSets,
                leftGames: leftGames,
                rightGames: rightGames,
                shouldChangeSides: shouldChangeSides,
                isGameFinished: isGameFinished,
                continueUpdate: {
                    self.doSetEndUpdate(
                        leftGames: leftGames,
                        rightGames: rightGames,
                        setNumber: setNumber,
                        newLeftSets: newLeftSets,
                        newRightSets: newRightSets,
                        isGameFinished: isGameFinished
                    )
                }
            )
            callback(callbackData)
        } else {
            doSetEndUpdate(
                leftGames: leftGames,
                rightGames: rightGames,
                setNumber: setNumber,
                newLeftSets: newLeftSets,
                newRightSets: newRightSets,
                isGameFinished: isGameFinished
            )
        }
    }
    
    private func doSetEndUpdate(
        leftGames: Int,
        rightGames: Int,
        setNumber: Int,
        newLeftSets: Int,
        newRightSets: Int,
        isGameFinished: Bool
    ) {
        // Continuous serve order into the next set (Android nextTennisFirstServerInSetAfterCompletedSet).
        let completedGames = leftGames + rightGames
        let nextFirstServer = completedGames.isMultiple(of: 2) ? firstServerInSet : firstServerInSet.opposite
        let nextFirstSlot = modServerSlot(firstServerSlotInSet + completedGames)

        leftTeam.sets = newLeftSets
        rightTeam.sets = newRightSets
        isTieBreak = false
        isDeuce = false
        advantage = .none
        tieBreakChangeSidesCount = 0

        saveGameRecordInRealTime(isGameFinished: isGameFinished)

        if isGameFinished {
            checkMatchWinner()
        } else {
            firstServerInSet = nextFirstServer
            firstServerSlotInSet = nextFirstSlot
            resetGames()
        }
    }

    func saveGameRecordInRealTime(isGameFinished: Bool) {
        let endTime = Date()
        let duration = endTime.timeIntervalSince(controller?.getGameStartTime() ?? Date())

        var winner: String? = nil
        if isGameFinished {
            if (leftTeam.sets ?? 0) > (rightTeam.sets ?? 0) {
                winner = "left"
            } else if (rightTeam.sets ?? 0) > (leftTeam.sets ?? 0) {
                winner = "right"
            }
        }

        controller?.saveScoreboardRecord(
            id: "tennis_\(Int(controller?.getGameStartTime().timeIntervalSince1970 ?? 0))",
            endTime: endTime,
            duration: duration,
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftTeam.sets ?? 0,
            team2FinalScore: rightTeam.sets ?? 0,
            team1SetScore: leftTeam.sets ?? 0,
            team2SetScore: rightTeam.sets ?? 0,
            winner: winner,
            totalScoreChanges: controller?.getGameActions().count ?? 0,
            extraData: [
                "maxSets": maxSets,
                "matchCompletionMode": matchCompletionMode.rawValue,
                "tieBreakPoints": tieBreakTarget,
                "gamesPerSet": gamesPerSet,
                "setScoringMode": setScoringMode,
                "autoChangeSides": autoChangeSides,
                "tennisDeuceMode": usesNoAdScoring ? "no_ad" : "advantage",
                "servingSide": openingServerSide.rawValue,
                "voiceAnnouncement": voiceAnnouncement,
                "isSingles": isSingles,
                "finalLeftGames": leftTeam.games ?? 0,
                "finalRightGames": rightTeam.games ?? 0,
                "currentSet": currentSet,
                "currentLeftScore": leftTeam.score,
                "currentRightScore": rightTeam.score,
                "isTieBreak": isTieBreak,
                "sidesSwapped": sidesSwapped,
                "firstServerInSet": firstServerInSet.rawValue,
                "firstServerSlotInSet": firstServerSlotInSet,
                "tieBreakFirstServer": tieBreakFirstServer.rawValue,
                "tieBreakFirstServerSlot": tieBreakFirstServerSlot,
                "advantage": advantage == .left ? "left" : (advantage == .right ? "right" : "none")
            ],
            status: isGameFinished ? .finished : .draft
        )
    }
    
    private func resetGames() {
        leftTeam.games = 0
        rightTeam.games = 0
        currentSet += 1
        currentGameInSet = 0
        isTieBreak = setScoringMode == "tiebreak_only"
    }
    
    private func checkMatchWinner() {
        gameFinished = matchCompletionMode.isMatchFinished(
            maxSets: maxSets,
            leftSets: leftTeam.sets ?? 0,
            rightSets: rightTeam.sets ?? 0
        )
    }
    
    private func applySideChangeIfNeeded() {
        if autoChangeSides {
            exchangeSides()
            onSideChangeCallback?(true)
        } else {
            onSideChangeCallback?(false)
        }
    }

    private func modServerSlot(_ value: Int) -> Int {
        let cycle = 4
        return ((value % cycle) + cycle) % cycle
    }

    private func swapDoublesSlotSides(_ slot: Int) -> Int {
        switch modServerSlot(slot) {
        case 0: return 1
        case 1: return 0
        case 2: return 3
        default: return 2
        }
    }

    func rebuildDeuceStateFromScores() {
        if isTieBreak {
            isDeuce = false
            advantage = .none
        } else {
            updateDeuceState(leftScore: leftTeam.score, rightScore: rightTeam.score)
        }
    }

    // MARK: - Edit Mode Adjustments
    
    override func adjustScore(isLeft: Bool, delta: Int) {
        saveTennisSnapshot()
        
        if isLeft {
            leftTeam.score = max(0, leftTeam.score + delta)
        } else {
            rightTeam.score = max(0, rightTeam.score + delta)
        }
        
        updateDeuceState(leftScore: leftTeam.score, rightScore: rightTeam.score)
        controller?.performVibration(type: .light)
    }
    
    func adjustGames(isLeft: Bool, delta: Int) {
        guard setScoringMode != "tiebreak_only" else { return }
        saveTennisSnapshot()
        
        let maxGames = gamesPerSet + 1
        if isLeft {
            let newGames = (leftTeam.games ?? 0) + delta
            leftTeam.games = max(0, min(newGames, maxGames))
        } else {
            let newGames = (rightTeam.games ?? 0) + delta
            rightTeam.games = max(0, min(newGames, maxGames))
        }
        
        controller?.performVibration(type: .light)
    }
    
    func adjustSets(isLeft: Bool, delta: Int) {
        let leftSets = (leftTeam.sets ?? 0) + (isLeft ? delta : 0)
        let rightSets = (rightTeam.sets ?? 0) + (isLeft ? 0 : delta)
        guard matchCompletionMode.allowsSetScore(
            maxSets: maxSets,
            leftSets: leftSets,
            rightSets: rightSets
        ) else { return }
        saveTennisSnapshot()
        leftTeam.sets = leftSets
        rightTeam.sets = rightSets
        gameFinished = matchCompletionMode.isMatchFinished(
            maxSets: maxSets,
            leftSets: leftSets,
            rightSets: rightSets
        )
        
        controller?.performVibration(type: .light)
    }
    
    // MARK: - Snapshot Helpers
    
    private func saveTennisSnapshot() {
        tennisHistory.append(TennisStateSnapshot(
            leftScore: leftTeam.score,
            rightScore: rightTeam.score,
            leftGames: leftTeam.games ?? 0,
            rightGames: rightTeam.games ?? 0,
            leftSets: leftTeam.sets ?? 0,
            rightSets: rightTeam.sets ?? 0,
            currentSet: currentSet,
            isTieBreak: isTieBreak,
            isDeuce: isDeuce,
            advantage: advantage,
            gameFinished: gameFinished,
            sidesSwapped: sidesSwapped,
            matchCompletionMode: matchCompletionMode,
            tieBreakChangeSidesCount: tieBreakChangeSidesCount,
            currentGameInSet: currentGameInSet,
            firstServerInSet: firstServerInSet,
            firstServerSlotInSet: firstServerSlotInSet,
            tieBreakFirstServer: tieBreakFirstServer,
            tieBreakFirstServerSlot: tieBreakFirstServerSlot,
            openingServerSide: openingServerSide,
            team0FirstReceiverSlot: team0FirstReceiverSlot,
            team1FirstReceiverSlot: team1FirstReceiverSlot
        ))

        if tennisHistory.count > 50 {
            tennisHistory.removeFirst()
        }
    }

    private func restoreTennisSnapshot(_ snapshot: TennisStateSnapshot) {
        leftTeam.score = snapshot.leftScore
        rightTeam.score = snapshot.rightScore
        leftTeam.games = snapshot.leftGames
        rightTeam.games = snapshot.rightGames
        leftTeam.sets = snapshot.leftSets
        rightTeam.sets = snapshot.rightSets
        currentSet = snapshot.currentSet
        isTieBreak = snapshot.isTieBreak
        isDeuce = snapshot.isDeuce
        advantage = snapshot.advantage
        gameFinished = snapshot.gameFinished
        sidesSwapped = snapshot.sidesSwapped
        matchCompletionMode = snapshot.matchCompletionMode
        tieBreakChangeSidesCount = snapshot.tieBreakChangeSidesCount
        currentGameInSet = snapshot.currentGameInSet
        firstServerInSet = snapshot.firstServerInSet
        firstServerSlotInSet = snapshot.firstServerSlotInSet
        tieBreakFirstServer = snapshot.tieBreakFirstServer
        tieBreakFirstServerSlot = snapshot.tieBreakFirstServerSlot
        openingServerSide = snapshot.openingServerSide
        team0FirstReceiverSlot = snapshot.team0FirstReceiverSlot
        team1FirstReceiverSlot = snapshot.team1FirstReceiverSlot
    }
}

private struct TennisStateSnapshot {
    let leftScore: Int
    let rightScore: Int
    let leftGames: Int
    let rightGames: Int
    let leftSets: Int
    let rightSets: Int
    let currentSet: Int
    let isTieBreak: Bool
    let isDeuce: Bool
    let advantage: TennisViewModel.AdvantageState
    let gameFinished: Bool
    let sidesSwapped: Bool
    let matchCompletionMode: MatchCompletionMode
    let tieBreakChangeSidesCount: Int
    let currentGameInSet: Int
    let firstServerInSet: MatchSide
    let firstServerSlotInSet: Int
    let tieBreakFirstServer: MatchSide
    let tieBreakFirstServerSlot: Int
    let openingServerSide: MatchSide
    let team0FirstReceiverSlot: Int
    let team1FirstReceiverSlot: Int
}
