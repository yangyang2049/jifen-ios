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
        speak([payload])
    }

    /// Speaks one reducer event as an atomic, ordered batch. This prevents a
    /// delayed score call from interrupting the following interval/change-ends call.
    func speak(_ payloads: [VoiceAnnouncementPayload]) {
        let language = VoiceAnnouncementLanguage.resolve()
        let texts = payloads
            .map { VoiceAnnouncementMessageBuilder.build($0, language: language) }
            .filter { !$0.isEmpty }
        guard !texts.isEmpty else { return }

        let policy = VoiceAnnouncementBatchPolicy.queuePolicy(payloads)
        cancelPendingScore()
        if policy == .latestScore {
            scoreChangeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: self?.scoreChangeDebounceNanoseconds ?? 420_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.speakTexts(texts, language: language, interruptCurrent: true)
                }
            }
        } else {
            speakTexts(texts, language: language, interruptCurrent: policy == .flush)
        }
    }

    func cancelPendingScore() {
        scoreChangeTask?.cancel()
        scoreChangeTask = nil
    }

    func stop() {
        cancelPendingScore()
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakTexts(
        _ texts: [String],
        language: VoiceAnnouncementLanguage,
        interruptCurrent: Bool
    ) {
        if interruptCurrent {
            synthesizer.stopSpeaking(at: .immediate)
        }
        for text in texts {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.resolveVoice(for: language)
            if utterance.voice == nil {
                utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
            }
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        }
    }

    /// Traditional Chinese falls back through zh-HK/zh-CN voices so playback
    /// never goes silent when a device lacks a dedicated zh-TW voice.
    private static func resolveVoice(for language: VoiceAnnouncementLanguage) -> AVSpeechSynthesisVoice? {
        if language != .zhTW {
            return AVSpeechSynthesisVoice(language: language.rawValue)
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let exact = voices.first(where: { $0.language == VoiceAnnouncementLanguage.zhTW.rawValue }) {
            #if DEBUG
            print("[Voice] zh-TW exact voice: \(exact.identifier)")
            #endif
            return exact
        }
        if let prefixed = voices.first(where: { $0.language.hasPrefix("zh-TW") }) {
            #if DEBUG
            print("[Voice] zh-TW prefixed voice: \(prefixed.language)")
            #endif
            return prefixed
        }
        for fallback in ["zh-HK", "zh-CN"] {
            if let voice = voices.first(where: { $0.language.hasPrefix(fallback) }) {
                #if DEBUG
                print("[Voice] zh-TW degraded to \(voice.language) voice")
                #endif
                return voice
            }
        }
        #if DEBUG
        print("[Voice] zh-TW: no Chinese voice available, using utterance.language")
        #endif
        return nil
    }
}
