//
//  VibrationManager.swift
//  jifen
//
//  Haptic feedback manager
//

import UIKit

/// Haptic feedback manager
class VibrationManager {
    static let shared = VibrationManager()
    
    private let preferences = PreferencesManager.shared
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    
    private init() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
    }
    
    func vibrateLight() {
        guard preferences.vibrationEnabled else { return }
        lightImpact.impactOccurred()
    }
    
    func vibrateMedium() {
        guard preferences.vibrationEnabled else { return }
        mediumImpact.impactOccurred()
    }
    
    func vibrateHeavy() {
        guard preferences.vibrationEnabled else { return }
        heavyImpact.impactOccurred()
    }
}

