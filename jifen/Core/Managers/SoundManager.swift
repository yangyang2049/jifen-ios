//
//  SoundManager.swift
//  jifen
//
//  Sound effects manager
//

import AVFoundation
import Foundation

/// Sound effects manager
class SoundManager {
    static let shared = SoundManager()
    
    private var audioPlayer: AVAudioPlayer?
    private let preferences = PreferencesManager.shared
    
    private init() {}
    
    func playSound(_ soundName: String) {
        guard preferences.soundEnabled else { return }
        
        // Try to find the sound file in multiple locations
        var url: URL?
        
        // First try: root bundle (most common)
        if let bundleUrl = Bundle.main.url(forResource: soundName, withExtension: "mp3") {
            url = bundleUrl
        }
        // Second try: Resources subdirectory
        else if let resourceUrl = Bundle.main.url(forResource: soundName, withExtension: "mp3", subdirectory: "Resources") {
            url = resourceUrl
        }
        // Third try: direct path in Resources folder
        else if let resourcesPath = Bundle.main.resourcePath {
            let filePath = (resourcesPath as NSString).appendingPathComponent("Resources/\(soundName).mp3")
            if FileManager.default.fileExists(atPath: filePath) {
                url = URL(fileURLWithPath: filePath)
            }
        }
        
        guard let soundUrl = url else {
            #if DEBUG
            print("Sound file not found: \(soundName).mp3")
            #endif
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundUrl)
            audioPlayer?.play()
        } catch {
            #if DEBUG
            print("Error playing sound: \(error)")
            #endif
        }
    }
}

