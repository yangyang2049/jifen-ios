//
//  SoundManager.swift
//  jifen
//
//  Sound effects manager
//

import AVFoundation
import Foundation
import ScoreCore

/// Explicit tool sounds and announcements remain audible in Silent mode.
/// Configure at playback time because voice-note recording changes the shared session.
enum AppAudioPlaybackSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // playAndRecord already ignores the Silent switch. Keep its input route
        // intact while a voice note is being recorded.
        if !RecordNoteAudioManager.shared.isRecording {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
    }
}

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
            try AppAudioPlaybackSession.activate()
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

    private var sessionGate = SportsVoiceSessionGate()

    private init() {
        synthesizer.usesApplicationAudioSession = true
    }

    func beginSession(_ id: UUID) {
        guard sessionGate.beginSession(id) else { return }
        stop()
    }

    @discardableResult
    func prepareToEnable() -> Bool {
        guard let language = SportsVoiceSupport.language else { return false }
        guard SportsVoiceSupport.voice(for: language) != nil else {
            presentDownloadGuide(language)
            return false
        }
        return true
    }

    func refreshAfterForeground() {
        // Resolve the inventory again. Playback always checks it afresh; the
        // per-match notification budget survives background/foreground changes.
        guard let language = SportsVoiceSupport.language,
              SportsVoiceSupport.voice(for: language) != nil else { stop(); return }
    }

    private func presentDownloadGuide(_ language: SportsVoiceLanguage) {
        NotificationCenter.default.post(name: .sportsVoiceNeedsDownload, object: nil, userInfo: [
            "title": SportsVoiceSupport.template("voice_download_title", language: language) ?? "",
            "message": SportsVoiceSupport.template("voice_download_guide", language: language) ?? ""
        ])
    }

    /// Validate restored voice-enabled matches even when their opening call was already spoken.
    func checkSessionVoice() {
        _ = playbackLanguage()
    }

    private func playbackLanguage() -> SportsVoiceLanguage? {
        let target = SportsVoiceSupport.language
        let available = target.map { SportsVoiceSupport.voice(for: $0) != nil } ?? false
        switch sessionGate.evaluate(language: target, voiceAvailable: available) {
        case .unsupported: stop(); return nil
        case .missingVoice(let showDownloadGuide):
            stop()
            if showDownloadGuide, let language = target { presentDownloadGuide(language) }
            return nil
        case .ready: return target
        }
    }

    /// International-standard scoreboard voice (BWF / ITTF / ITF).
    func speak(_ payload: VoiceAnnouncementPayload) {
        speak([payload])
    }

    /// Speaks one reducer event as an atomic, ordered batch. This prevents a
    /// delayed score call from interrupting the following interval/change-ends call.
    func speak(_ payloads: [VoiceAnnouncementPayload]) {
        guard let language = playbackLanguage() else { return }
        var texts: [String] = []
        for payload in payloads {
            let announceServer = UserDefaults.standard.object(forKey: "pingpongAnnounceServer") as? Bool ?? true
            guard let text = SportsVoiceSupport.message(payload, language: language, announceServer: announceServer) else { stop(); return }
            if !text.isEmpty { texts.append(text) }
        }
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
        language: SportsVoiceLanguage,
        interruptCurrent: Bool
    ) {
        if interruptCurrent {
            synthesizer.stopSpeaking(at: .immediate)
        }
        guard SportsVoiceSupport.language == language,
              let voice = SportsVoiceSupport.voice(for: language) else { return }
        do {
            try AppAudioPlaybackSession.activate()
        } catch {
            #if DEBUG
            print("Error preparing speech audio: \(error)")
            #endif
            return
        }
        for text in texts {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        }
    }

}
