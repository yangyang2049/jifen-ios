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
    
    private var tieBreakChangeSidesCount: Int = 0
    private var currentGameInSet: Int = 0
    
    var onGameEndCallback: ((Int, Int, Int) -> Void)? = nil
    var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil
    var onSideChangeCallback: (() -> Void)? = nil
    
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
        voiceAnnouncement: Bool = false
    ) {
        self.maxSets = maxSets
        self.autoChangeSides = autoChangeSides
        self.matchCompletionMode = matchCompletionMode
        self.usesNoAdScoring = usesNoAdScoring
        self.openingServerSide = openingServerSide
        self.voiceAnnouncement = voiceAnnouncement
    }
    
    func setOnGameEndCallback(_ callback: @escaping (Int, Int, Int) -> Void) {
        onGameEndCallback = callback
    }
    
    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        onSetEndCallback = callback
    }
    
    func setOnSideChangeCallback(_ callback: @escaping () -> Void) {
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

    /// Harmony-aligned server rule for tennis:
    /// first server alternates by set, then alternates each game.
    func isLeftServing() -> Bool {
        let opensFromLeft = openingServerSide == .left
        let firstServerIsLeft = (currentSet % 2 == 1) ? opensFromLeft : !opensFromLeft
        let totalGames = (leftTeam.games ?? 0) + (rightTeam.games ?? 0)
        return firstServerIsLeft == (totalGames % 2 == 0)
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
                onSideChangeCallback?()
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
        isTieBreak = false
        isDeuce = false
        advantage = .none
        sidesSwapped = false
        tieBreakChangeSidesCount = 0
        currentGameInSet = 0
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
        
        if shouldStartTieBreak(leftGames: leftGames, rightGames: rightGames) {
            startTieBreak()
        } else {
            leftTeam.score = 0
            rightTeam.score = 0
            isDeuce = false
            advantage = .none
            
            // Auto side change disabled - side changes are handled manually
        }
        
        checkSetWinner()
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
        return leftGames == 6 && rightGames == 6
    }
    
    private func startTieBreak() {
        isTieBreak = true
        leftTeam.score = 0
        rightTeam.score = 0
        tieBreakChangeSidesCount = 0
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
        
        if leftGames >= 6 && leftGames - rightGames >= 2 {
            winnerLeft = true
        } else if rightGames >= 6 && rightGames - leftGames >= 2 {
            winnerLeft = false
        } else if (leftGames == 7 && rightGames == 6) || (rightGames == 7 && leftGames == 6) {
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
        let shouldChangeSides = !isGameFinished && setNumber % 2 == 1
        
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
        leftTeam.sets = newLeftSets
        rightTeam.sets = newRightSets
        isTieBreak = false
        isDeuce = false
        advantage = .none
        tieBreakChangeSidesCount = 0

        // Save record in real-time when set ends
        saveGameRecordInRealTime(isGameFinished: isGameFinished)

        if isGameFinished {
            checkMatchWinner()
        } else {
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
                "isTieBreak": isTieBreak
            ],
            status: isGameFinished ? .finished : .draft
        )
    }
    
    private func resetGames() {
        leftTeam.games = 0
        rightTeam.games = 0
        currentSet += 1
        currentGameInSet = 0
    }
    
    private func checkMatchWinner() {
        gameFinished = matchCompletionMode.isMatchFinished(
            maxSets: maxSets,
            leftSets: leftTeam.sets ?? 0,
            rightSets: rightTeam.sets ?? 0
        )
    }
    
    // MARK: - Edit Mode Adjustments
    
    func adjustScore(isLeft: Bool, delta: Int) {
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
        saveTennisSnapshot()
        
        let maxGames = 7
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
            currentGameInSet: currentGameInSet
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
}
