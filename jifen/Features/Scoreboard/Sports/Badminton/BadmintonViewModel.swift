//
//  BadmintonViewModel.swift
//  jifen
//
//  Badminton score view model - handles set logic and side changes
//

import Foundation

@Observable
class BadmintonViewModel: BaseScoreViewModel {
    // MARK: - Badminton Specific Properties
    
    var currentSet: Int = 1
    var maxSets: Int = 3
    var normalSetPoints: Int = 21
    var autoChangeSides: Bool = true
    var sidesSwapped: Bool = false
    
    private var decidingSetChangedSides: Bool = false
    private var midGameRestTriggered: Bool = false
    
    // MARK: - Callbacks
    
    var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil
    var onDecidingSetSidesChangeCallback: (() -> Void)? = nil
    var onMidGameRestCallback: (() -> Void)? = nil
    
    // MARK: - Full State History
    
    private var fullStateHistory: [BadmintonStateSnapshot] = []
    
    // MARK: - Initialization
    
    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.sets = 0
        rightTeam.sets = 0
    }
    
    // MARK: - Configuration
    
    func setConfig(maxSets: Int, normalSetPoints: Int, autoChangeSides: Bool = true) {
        self.maxSets = maxSets
        self.normalSetPoints = normalSetPoints
        self.autoChangeSides = autoChangeSides
    }
    
    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        onSetEndCallback = callback
    }
    
    func setOnDecidingSetSidesChangeCallback(_ callback: @escaping () -> Void) {
        onDecidingSetSidesChangeCallback = callback
    }
    
    func setOnMidGameRestCallback(_ callback: @escaping () -> Void) {
        onMidGameRestCallback = callback
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
    
    // MARK: - Override Score Operations
    
    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        
        let currentLeftScore = leftTeam.score
        let currentRightScore = rightTeam.score
        let targetPoints = normalSetPoints
        let isDecidingSet = currentSet == maxSets
        
        if canWinSet(leftScore: currentLeftScore, rightScore: currentRightScore, targetPoints: targetPoints) {
            checkSetWinner()
            return
        }
        
        // Deciding set cap check (30 max)
        let currentMaxScore = max(currentLeftScore, currentRightScore)
        if isDecidingSet && currentMaxScore >= 30 {
            if !(currentLeftScore == 29 && currentRightScore == 29) {
                if canWinSet(leftScore: currentLeftScore, rightScore: currentRightScore, targetPoints: targetPoints) {
                    checkSetWinner()
                }
                return
            }
        }
        
        saveFullStateHistory()
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets
        )
        
        if isLeft {
            leftTeam.score += points
        } else {
            rightTeam.score += points
        }
        
        // Deciding set cap
        if isDecidingSet {
            leftTeam.score = min(leftTeam.score, 30)
            rightTeam.score = min(rightTeam.score, 30)
        }
        
        controller?.performVibration(type: .light)
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
        
        handleMidGameRestTrigger()
        handleDecidingSetSidesChange()
        checkSetWinner()
    }
    
    override func reset() {
        super.reset()
        currentSet = 1
        leftTeam.sets = 0
        rightTeam.sets = 0
        sidesSwapped = false
        decidingSetChangedSides = false
        midGameRestTriggered = false
        fullStateHistory.removeAll()
    }
    
    override func undo() -> Bool {
        guard let controller = controller, controller.undoEnabled else { return false }
        
        guard let state = fullStateHistory.popLast() else {
            return super.undo()
        }
        
        leftTeam.score = state.leftScore
        rightTeam.score = state.rightScore
        leftTeam.sets = state.leftSets
        rightTeam.sets = state.rightSets
        currentSet = state.currentSet
        sidesSwapped = state.sidesSwapped
        decidingSetChangedSides = state.decidingSetChangedSides
        midGameRestTriggered = state.midGameRestTriggered
        
        controller.performVibration(type: .light)
        return true
    }
    
    override func exchangeSides() {
        guard !gameFinished else { return }
        
        saveFullStateHistory()
        
        let tempName = leftTeam.name
        let tempScore = leftTeam.score
        let tempSets = leftTeam.sets
        
        leftTeam.name = rightTeam.name
        leftTeam.score = rightTeam.score
        leftTeam.sets = rightTeam.sets
        
        rightTeam.name = tempName
        rightTeam.score = tempScore
        rightTeam.sets = tempSets
        
        sidesSwapped.toggle()
        controller?.performVibration(type: .medium)
    }
    
    // MARK: - Set Logic
    
    private func checkSetWinner() {
        let targetPoints = normalSetPoints
        
        guard canWinSet(leftScore: leftTeam.score, rightScore: rightTeam.score, targetPoints: targetPoints) else {
            return
        }
        
        let setEndLeftScore = leftTeam.score
        let setEndRightScore = rightTeam.score
        let setNumber = currentSet
        let winnerName = leftTeam.score > rightTeam.score ? leftTeam.name : rightTeam.name
        
        let setsToWin = (maxSets + 1) / 2
        let newLeftSets = leftTeam.score > rightTeam.score ? (leftTeam.sets ?? 0) + 1 : (leftTeam.sets ?? 0)
        let newRightSets = rightTeam.score > leftTeam.score ? (rightTeam.sets ?? 0) + 1 : (rightTeam.sets ?? 0)
        let isGameFinished = newLeftSets >= setsToWin || newRightSets >= setsToWin
        
        if let callback = onSetEndCallback {
            let callbackData = SetEndCallbackData(
                finalLeftScore: setEndLeftScore,
                finalRightScore: setEndRightScore,
                winnerName: winnerName,
                setNumber: setNumber,
                leftSets: newLeftSets,
                rightSets: newRightSets,
                leftGames: nil,
                rightGames: nil,
                shouldChangeSides: !isGameFinished,
                isGameFinished: isGameFinished,
                continueUpdate: {
                    self.doSetEndUpdate(
                        setEndLeftScore: setEndLeftScore,
                        setEndRightScore: setEndRightScore,
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
                setEndLeftScore: setEndLeftScore,
                setEndRightScore: setEndRightScore,
                setNumber: setNumber,
                newLeftSets: newLeftSets,
                newRightSets: newRightSets,
                isGameFinished: isGameFinished
            )
        }
    }
    
    private func doSetEndUpdate(
        setEndLeftScore: Int,
        setEndRightScore: Int,
        setNumber: Int,
        newLeftSets: Int,
        newRightSets: Int,
        isGameFinished: Bool
    ) {
        leftTeam.sets = newLeftSets
        rightTeam.sets = newRightSets
        
        if isGameFinished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
        } else {
            startNextSet()
        }
    }
    
    private func startNextSet() {
        currentSet += 1
        leftTeam.score = 0
        rightTeam.score = 0
        decidingSetChangedSides = false
        midGameRestTriggered = false
        
        controller?.clearHistory()
        fullStateHistory.removeAll()
    }
    
    private func canWinSet(leftScore: Int, rightScore: Int, targetPoints: Int) -> Bool {
        let isDecidingSet = currentSet == maxSets
        let maxScore = max(leftScore, rightScore)
        let scoreDiff = abs(leftScore - rightScore)
        
        if isDecidingSet && maxScore >= 30 {
            return scoreDiff >= 1
        }
        
        if maxScore < targetPoints {
            return false
        }
        
        return scoreDiff >= 2
    }
    
    private func handleDecidingSetSidesChange() {
        guard !decidingSetChangedSides else { return }
        
        let isDecidingSet = currentSet == maxSets
        if isDecidingSet && (leftTeam.score == 11 || rightTeam.score == 11) {
            decidingSetChangedSides = true
            if let callback = onDecidingSetSidesChangeCallback {
                callback()
            } else if autoChangeSides {
                exchangeSides()
            }
        }
    }
    
    private func handleMidGameRestTrigger() {
        guard !midGameRestTriggered else { return }
        
        let midPoint = Int(ceil(Double(normalSetPoints) / 2.0))
        if leftTeam.score == midPoint || rightTeam.score == midPoint {
            midGameRestTriggered = true
            onMidGameRestCallback?()
        }
    }
    
    // MARK: - Edit Mode Adjustments
    
    func adjustScore(isLeft: Bool, delta: Int) {
        saveFullStateHistory()
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets
        )
        
        let maxScore = min(normalSetPoints + 10, 30)
        
        if isLeft {
            let newScore = leftTeam.score + delta
            leftTeam.score = max(0, min(newScore, maxScore))
        } else {
            let newScore = rightTeam.score + delta
            rightTeam.score = max(0, min(newScore, maxScore))
        }
        
        controller?.performVibration(type: .light)
    }
    
    func adjustSets(isLeft: Bool, delta: Int) {
        saveFullStateHistory()
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets
        )
        
        let maxSetsValue = maxSets
        
        if isLeft {
            let newSets = (leftTeam.sets ?? 0) + delta
            leftTeam.sets = max(0, min(newSets, maxSetsValue))
        } else {
            let newSets = (rightTeam.sets ?? 0) + delta
            rightTeam.sets = max(0, min(newSets, maxSetsValue))
        }
        
        controller?.performVibration(type: .light)
    }
    
    // MARK: - Helper Methods
    
    private func saveFullStateHistory() {
        fullStateHistory.append(BadmintonStateSnapshot(
            leftScore: leftTeam.score,
            rightScore: rightTeam.score,
            leftSets: leftTeam.sets ?? 0,
            rightSets: rightTeam.sets ?? 0,
            currentSet: currentSet,
            sidesSwapped: sidesSwapped,
            decidingSetChangedSides: decidingSetChangedSides,
            midGameRestTriggered: midGameRestTriggered
        ))
        
        if fullStateHistory.count > 50 {
            fullStateHistory.removeFirst()
        }
    }
}

private struct BadmintonStateSnapshot {
    let leftScore: Int
    let rightScore: Int
    let leftSets: Int
    let rightSets: Int
    let currentSet: Int
    let sidesSwapped: Bool
    let decidingSetChangedSides: Bool
    let midGameRestTriggered: Bool
}
