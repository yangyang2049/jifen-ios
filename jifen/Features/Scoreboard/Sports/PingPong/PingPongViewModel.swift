//
//  PingPongViewModel.swift
//  jifen
//
//  Ping pong score view model - handles set logic
//

import Foundation

@Observable
class PingPongViewModel: BaseScoreViewModel {
    // MARK: - Ping Pong Specific Properties
    
    var currentSet: Int = 1
    var maxSets: Int = 5  // Default: best of 5 (first to 3)
    var pointsPerSet: Int = 11  // Default: 11 points per set
    var autoChangeSides: Bool = true
    var sidesSwapped: Bool = false
    private var decidingSetChangedSides: Bool = false
    
    // MARK: - Callbacks
    
    var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil
    var onDecidingSetSidesChangeCallback: (() -> Void)? = nil
    
    // MARK: - Full State History
    
    private var fullStateHistory: [(leftScore: Int, rightScore: Int, leftSets: Int, rightSets: Int, currentSet: Int)] = []
    
    // MARK: - Initialization
    
    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.sets = 0
        rightTeam.sets = 0
    }
    
    // MARK: - Configuration
    
    func setConfig(maxSets: Int, pointsPerSet: Int, autoChangeSides: Bool = true) {
        self.maxSets = maxSets
        self.pointsPerSet = pointsPerSet
        self.autoChangeSides = autoChangeSides
    }
    
    // MARK: - Callback Setup
    
    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        self.onSetEndCallback = callback
    }
    
    func setOnDecidingSetSidesChangeCallback(_ callback: @escaping () -> Void) {
        self.onDecidingSetSidesChangeCallback = callback
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
        
        // Save history before change
        saveFullStateHistory()
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets
        )
        
        // Add score
        if isLeft {
            leftTeam.score += points
        } else {
            rightTeam.score += points
        }
        
        // Vibration
        controller?.performVibration(type: .light)
        
        // Check if set is won after adding score
        if canWinSet(leftScore: leftTeam.score, rightScore: rightTeam.score) {
            checkSetWinner()
            return
        }
        
        // Check deciding set sides change (at 5 points)
        if !decidingSetChangedSides {
            let isDecidingSet = currentSet == maxSets
            
            if isDecidingSet && (leftTeam.score == 5 || rightTeam.score == 5) {
                decidingSetChangedSides = true
                if autoChangeSides {
                    // Trigger callback if exists
                    if let callback = onDecidingSetSidesChangeCallback {
                        callback()
                    } else {
                        // Fallback: direct exchange
                        exchangeSides()
                    }
                }
            }
        }
        
        // Check set winner (in case score change triggered win condition)
        checkSetWinner()
        
    }
    
    override func reset() {
        super.reset()
        currentSet = 1
        leftTeam.sets = 0
        rightTeam.sets = 0
        sidesSwapped = false
        decidingSetChangedSides = false
        fullStateHistory.removeAll()
    }
    
    override func undo() -> Bool {
        guard let controller = controller, controller.undoEnabled else { return false }
        
        // Try to restore from full state history first
        if !fullStateHistory.isEmpty {
            let state = fullStateHistory.removeLast()
            leftTeam.score = state.leftScore
            rightTeam.score = state.rightScore
            leftTeam.sets = state.leftSets
            rightTeam.sets = state.rightSets
            currentSet = state.currentSet
            controller.performVibration(type: .light)
            return true
        }
        
        // Fallback to base undo
        return super.undo()
    }
    
    override func exchangeSides() {
        guard !gameFinished else { return }
        
        saveFullStateHistory()
        
        // Exchange team data
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
    
    private func canWinSet(leftScore: Int, rightScore: Int) -> Bool {
        let targetPoints = pointsPerSet
        
        // Win condition: reach target points and lead by 2
        if leftScore >= targetPoints && leftScore - rightScore >= 2 {
            return true
        }
        if rightScore >= targetPoints && rightScore - leftScore >= 2 {
            return true
        }
        
        return false
    }
    
    private func checkSetWinner() {
        guard canWinSet(leftScore: leftTeam.score, rightScore: rightTeam.score) else {
            return
        }
        
        // Save set end scores before reset
        let setEndLeftScore = leftTeam.score
        let setEndRightScore = rightTeam.score
        let setNumber = currentSet
        let winnerName = leftTeam.score > rightTeam.score ? leftTeam.name : rightTeam.name
        
        // Calculate new sets
        let setsToWin = (maxSets + 1) / 2  // First to win majority
        let newLeftSets = leftTeam.score > rightTeam.score ? (leftTeam.sets ?? 0) + 1 : (leftTeam.sets ?? 0)
        let newRightSets = rightTeam.score > leftTeam.score ? (rightTeam.sets ?? 0) + 1 : (rightTeam.sets ?? 0)
        let isGameFinished = newLeftSets >= setsToWin || newRightSets >= setsToWin
        
        // If callback exists, use delayed update flow
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
                shouldChangeSides: !isGameFinished, // Mark need to change sides if game not finished
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
            // No callback, update immediately (backward compatibility)
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
        // Update sets
        leftTeam.sets = newLeftSets
        rightTeam.sets = newRightSets
        
        if isGameFinished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
        } else {
            // Start next set
            startNextSet()
        }
    }
    
    private func startNextSet() {
        currentSet += 1
        leftTeam.score = 0
        rightTeam.score = 0
        decidingSetChangedSides = false
        
        // Clear history for new set
        controller?.clearHistory()
        fullStateHistory.removeAll()
        
        // Auto change sides between sets
        if autoChangeSides && currentSet <= maxSets {
            exchangeSides()
        }
        
        controller?.performVibration(type: .medium)
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
        
        let maxScore = min(pointsPerSet + 10, 30)
        
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
        
        let maxSetsValue = maxSets // Maximum sets for ping pong
        
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
        fullStateHistory.append((
            leftScore: leftTeam.score,
            rightScore: rightTeam.score,
            leftSets: leftTeam.sets ?? 0,
            rightSets: rightTeam.sets ?? 0,
            currentSet: currentSet
        ))
        
        // Limit history size
        if fullStateHistory.count > 50 {
            fullStateHistory.removeFirst()
        }
    }
}
