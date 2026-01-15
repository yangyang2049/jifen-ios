//
//  BaseScoreViewModel.swift
//  jifen
//
//  Base score view model - manages score state
//

import Foundation

@Observable
class BaseScoreViewModel: ScoreViewModelProtocol {
    // MARK: - Properties
    
    var leftTeam: TeamData = TeamData(name: "红队", score: 0)
    var rightTeam: TeamData = TeamData(name: "蓝队", score: 0)
    var gameFinished: Bool = false
    
    // MARK: - Edit State
    
    var editState: EditState = EditState()
    
    // MARK: - Controller Reference

    var controller: BaseScoreboardController?
    
    // MARK: - Initialization
    
    init(controller: BaseScoreboardController? = nil) {
        self.controller = controller
    }
    
    // MARK: - Score Operations
    
    func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        
        // Save history before change
        saveHistory()
        
        if isLeft {
            leftTeam.score += points
        } else {
            rightTeam.score += points
        }
        
        // Record action
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
        
        // Vibration feedback
        controller?.performVibration(type: .medium)
    }
    
    func subtractScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        
        // Save history before change
        saveHistory()
        
        if isLeft {
            leftTeam.score = max(0, leftTeam.score - points)
        } else {
            rightTeam.score = max(0, rightTeam.score - points)
        }
        
        // Record action
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(points)")
        
        // Vibration feedback
        controller?.performVibration(type: .light)
    }
    
    func reset() {
        saveHistory()
        leftTeam.score = 0
        rightTeam.score = 0
        leftTeam.sets = nil
        rightTeam.sets = nil
        leftTeam.games = nil
        rightTeam.games = nil
        gameFinished = false
        controller?.clearHistory()
    }
    
    func undo() -> Bool {
        guard let controller = controller, controller.undoEnabled else { return false }
        
        guard let history = controller.popHistory() else { return false }
        
        leftTeam.score = history.left
        rightTeam.score = history.right
        leftTeam.sets = history.leftSets
        rightTeam.sets = history.rightSets
        leftTeam.games = history.leftGames
        rightTeam.games = history.rightGames
        
        controller.performVibration(type: .light)
        return true
    }
    
    func exchangeSides() {
        saveHistory()
        
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
        
        controller?.performVibration(type: .medium)
    }
    
    // MARK: - Edit Mode
    
    func toggleEditMode() {
        editState.isEditMode.toggle()
        if !editState.isEditMode {
            // Exit edit mode - confirm any pending edits
            confirmEditName(isLeft: true)
            confirmEditName(isLeft: false)
            editState.editingSide = nil
            editState.currentInput = ""
        }
        controller?.performVibration(type: .medium)
    }
    
    // MARK: - Team Name Editing
    
    func startEditName(isLeft: Bool) {
        editState.editingSide = isLeft ? .left : .right
        editState.currentInput = isLeft ? leftTeam.name : rightTeam.name
    }
    
    func updateInput(isLeft: Bool, value: String) {
        guard editState.editingSide == (isLeft ? .left : .right) else { return }
        editState.currentInput = value
    }
    
    func confirmEditName(isLeft: Bool) {
        // Only confirm if we're editing this side
        guard editState.editingSide == (isLeft ? .left : .right) else { return }
        
        let input = editState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Always update, even if empty (to allow clearing)
        if isLeft {
            leftTeam.name = input.isEmpty ? "红队" : input
        } else {
            rightTeam.name = input.isEmpty ? "蓝队" : input
        }
        
        // Clear editing state
        editState.editingSide = nil
        editState.currentInput = ""
    }
    
    // MARK: - Helper Methods
    
    private func saveHistory() {
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets,
            leftGames: leftTeam.games,
            rightGames: rightTeam.games
        )
    }
}

// MARK: - Edit State

@Observable
class EditState {
    var isEditMode: Bool = false
    var editingSide: EditingSide? = nil
    var currentInput: String = ""
}

enum EditingSide {
    case left
    case right
}

