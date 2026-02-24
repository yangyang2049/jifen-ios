//
//  BaseScoreboardController.swift
//  jifen
//
//  Base scoreboard controller - handles infrastructure services
//

import Foundation
import UIKit
import Photos

class BaseScoreboardController: BaseScoreboardControllerProtocol {
    // MARK: - Properties
    
    let config: ScoreboardControllerConfig
    
    var isTablet: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var hideButtons: Bool = false
    var undoEnabled: Bool = true
    var swipeScreenshotEnabled: Bool = true
    
    // MARK: - History Management
    
    private var scoreHistory: [HistoryItem] = []
    
    // MARK: - Double Tap Exit
    
    private var exitClickTime: TimeInterval = 0
    
    // MARK: - Screenshot
    
    var screenshotImage: UIImage? = nil
    
    // MARK: - Game Recording
    
    var gameStartTime: Date = Date()
    var gameRecordSaved: Bool = false
    var gameActions: [String] = [] // Simplified for now
    
    // MARK: - Initialization
    
    init(config: ScoreboardControllerConfig) {
        self.config = config
        self.undoEnabled = config.enableUndo
        self.swipeScreenshotEnabled = config.enableScreenshot
    }
    
    // MARK: - Vibration
    
    func performVibration(type: VibrationType) {
        switch type {
        case .light:
            VibrationManager.shared.vibrateLight()
        case .medium:
            VibrationManager.shared.vibrateMedium()
        case .heavy:
            VibrationManager.shared.vibrateHeavy()
        }
    }
    
    // MARK: - History Management
    
    func pushHistory(left: Int, right: Int, leftSets: Int? = nil, rightSets: Int? = nil, leftGames: Int? = nil, rightGames: Int? = nil) {
        let item = HistoryItem(
            left: left,
            right: right,
            leftSets: leftSets,
            rightSets: rightSets,
            leftGames: leftGames,
            rightGames: rightGames
        )
        scoreHistory.append(item)
        
        // Limit history size
        if scoreHistory.count > config.maxHistorySize {
            scoreHistory.removeFirst()
        }
    }
    
    func popHistory() -> HistoryItem? {
        guard !scoreHistory.isEmpty else { return nil }
        return scoreHistory.removeLast()
    }
    
    func clearHistory() {
        scoreHistory.removeAll()
    }
    
    // MARK: - Scoring Options (Override in subclasses)
    
    func getScoringOptions() -> [Int] {
        return [1] // Default: only +1
    }
    
    // MARK: - Game Recording
    
    func recordScoreAction(action: String) {
        if config.enableRecording {
            gameActions.append(action)
        }
    }
    
    func saveScoreboardRecord(
        id: String,
        endTime: Date,
        duration: TimeInterval,
        team1Name: String,
        team2Name: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        winner: String?,
        totalScoreChanges: Int,
        extraData: [String: Any],
        status: ScoreboardRecordStatus = .finished
    ) {
        // Allow saving with set scores if provided
        saveScoreboardRecord(
            id: id,
            endTime: endTime,
            duration: duration,
            team1Name: team1Name,
            team2Name: team2Name,
            team1FinalScore: team1FinalScore,
            team2FinalScore: team2FinalScore,
            team1SetScore: nil,
            team2SetScore: nil,
            winner: winner,
            totalScoreChanges: totalScoreChanges,
            extraData: extraData,
            status: status
        )
    }
    
    func saveScoreboardRecord(
        id: String,
        endTime: Date,
        duration: TimeInterval,
        team1Name: String,
        team2Name: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int?,
        team2SetScore: Int?,
        winner: String?,
        totalScoreChanges: Int,
        extraData: [String: Any],
        status: ScoreboardRecordStatus = .finished
    ) {
        // Allow saving/updating records multiple times (e.g., for multi-set games)
        // ScoreboardRecordManager will handle updating records with the same ID
        
        // Create record
        var record = ScoreboardRecord(
            id: id,
            gameType: config.gameType,
            startTime: gameStartTime,
            endTime: endTime,
            duration: duration,
            team1Name: team1Name,
            team2Name: team2Name,
            team1FinalScore: team1FinalScore,
            team2FinalScore: team2FinalScore,
            team1SetScore: team1SetScore,
            team2SetScore: team2SetScore,
            winner: winner,
            actions: gameActions,
            totalScoreChanges: totalScoreChanges,
            extraData: nil,
            status: status
        )
        
        // Convert extraData to AnyCodable
        if !extraData.isEmpty {
            record.extraData = extraData.mapValues { AnyCodable($0) }
        }
        
        // Save to manager (will update if same ID exists)
        #if DEBUG
        print("[BaseScoreboardController] 💾 Attempting to save record: \(id) for game: \(config.gameType.rawValue)")
        #endif
        do {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
            
            // Mark as saved only if not already saved (to prevent duplicate notifications)
            if !gameRecordSaved {
                gameRecordSaved = true
            }

            // Notify ViewModel to refresh
            DispatchQueue.main.async {
                ScoreboardRecordsViewModel.shared.refreshRecords()
                #if DEBUG
                print("[BaseScoreboardController] 🔄 ViewModel refreshed after saving record")
                #endif
            }

            #if DEBUG
            print("[BaseScoreboardController] ✅ Record saved successfully: \(id)")
            #endif
        } catch {
            #if DEBUG
            print("[BaseScoreboardController] ❌ Failed to save record \(id): \(error)")
            #endif
        }
    }
    
    func getGameActions() -> [String] {
        return gameActions
    }
    
    func getGameStartTime() -> Date {
        return gameStartTime
    }
    
    func isRecordSaved() -> Bool {
        return gameRecordSaved
    }
    
    // MARK: - Double Tap Exit
    
    /// Handle exit click (double tap to exit)
    /// - Returns: true if can exit, false if need to tap again
    func handleExitClick() -> Bool {
        let currentTime = Date().timeIntervalSince1970 * 1000 // milliseconds
        if currentTime - exitClickTime < 2000 && exitClickTime > 0 {
            exitClickTime = 0
            return true // Can exit
        }
        exitClickTime = currentTime
        return false // Need to tap again
    }
    
    // MARK: - Screenshot
    
    /// Capture screenshot of the view
    /// - Parameter view: The view to capture
    /// - Returns: UIImage if successful, nil otherwise
    func captureScreenshot(of view: UIView) -> UIImage? {
        guard config.enableScreenshot else {
            #if DEBUG
            print("[BaseScoreboardController] ⚠️ Screenshot feature is disabled")
            #endif
            return nil
        }
        
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        
        screenshotImage = image
        return image
    }
    
    /// Save screenshot to photo library
    /// - Parameter image: The image to save
    /// - Parameter completion: Completion handler with success status
    func saveScreenshotToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        // Check current authorization status
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        if currentStatus == .authorized {
            // Already authorized - save directly
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        } else if currentStatus == .notDetermined {
            // Not determined - request authorization
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized {
                    // Authorized - save
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }) { success, error in
                        DispatchQueue.main.async {
                            completion(success, error)
                        }
                    }
                } else {
                    // Denied or restricted
                    DispatchQueue.main.async {
                        completion(false, NSError(domain: "ScreenshotError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                    }
                }
            }
        } else {
            // Denied or restricted
            DispatchQueue.main.async {
                completion(false, NSError(domain: "ScreenshotError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied. Please enable in Settings."]))
            }
        }
    }
    
    /// Generate screenshot file name
    /// - Returns: File name string
    func generateScreenshotFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = formatter.string(from: Date())
        let gameTypeName = config.gameType.displayName
        return "\(gameTypeName)_\(dateString)"
    }
}
