//
//  SoundManager.swift
//  jifen
//
//  Sound effects manager
//

import AVFoundation
import Foundation
import ScoreCore

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

@MainActor
final class ScoreVoiceAnnouncer {
    static let shared = ScoreVoiceAnnouncer()

    private let synthesizer = AVSpeechSynthesizer()
    private var scoreChangeTask: Task<Void, Never>?
    private let scoreChangeDebounceNanoseconds: UInt64 = 420_000_000

    private init() {}

    /// International-standard scoreboard voice (BWF / ITTF / ITF).
    func speak(_ payload: VoiceAnnouncementPayload) {
        let language = resolveLanguage()
        let text = VoiceAnnouncementMessageBuilder.build(payload, language: language)
        guard !text.isEmpty else { return }

        switch payload.phase {
        case .scoreChange:
            scoreChangeTask?.cancel()
            scoreChangeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: self?.scoreChangeDebounceNanoseconds ?? 420_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.speakText(text, language: language, queue: false)
                }
            }
        case .sideChange:
            speakText(text, language: language, queue: true)
        default:
            scoreChangeTask?.cancel()
            scoreChangeTask = nil
            speakText(text, language: language, queue: false)
        }
    }

    func stop() {
        scoreChangeTask?.cancel()
        scoreChangeTask = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakText(_ text: String, language: VoiceAnnouncementLanguage, queue: Bool) {
        if !queue {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func resolveLanguage() -> VoiceAnnouncementLanguage {
        Locale.current.language.languageCode?.identifier == "en" ? .enUS : .zhCN
    }
}
