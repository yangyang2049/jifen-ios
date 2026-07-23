//
//  BoardTimerVoiceAnnouncer.swift
//  jifen
//
//  Pre-recorded board-timer voice clips (Harmony rawfile 1:1).
//

import AVFoundation
import Foundation
import TimerCore

@MainActor
final class BoardTimerVoiceAnnouncer {
    static let shared = BoardTimerVoiceAnnouncer()

    private var primaryPlayer: AVAudioPlayer?
    private var secondaryPlayer: AVAudioPlayer?
    private var scheduleToken: UInt64 = 0
    private var scheduledWorkItem: DispatchWorkItem?

    private init() {}

    func playControl(_ sound: BoardTimerVoice.ControlSound) {
        playBaseName(sound.rawValue)
    }

    func playPlayerColor(gameType: GameType, playerID: Int) {
        guard let color = BoardTimerVoice.playerColorSound(
            gameTypeRawValue: gameType.rawValue,
            playerID: playerID
        ) else { return }
        playBaseName(color.rawValue, preferSecondaryChannel: true)
    }

    func playByoyomiPhrase(periodsRemaining: Int) {
        let phrase = BoardTimerVoice.byoyomiPhrase(periodsRemaining: periodsRemaining)
        playBaseName(phrase.rawValue)
    }

    /// Standalone countdown tool end (Harmony `CountdownPage` → `SoundType.TIMEOUT`).
    func playTimeout() {
        playBaseName(BoardTimerVoice.timeoutSoundBaseName)
    }

    /// Start clip, then announce player 1 after Harmony delay (cancelled if interrupted).
    func playStartThenSchedulePlayer1(gameType: GameType) {
        cancelScheduled()
        playControl(.start)
        let delayMs = BoardTimerVoice.postStartPlayerAnnouncementDelayMs()
        schedulePlayerColor(gameType: gameType, playerID: 1, delayMs: delayMs)
    }

    func playResumeWithCurrentPlayer(gameType: GameType, playerID: Int) {
        cancelScheduled()
        playControl(.resume)
        playPlayerColor(gameType: gameType, playerID: playerID)
    }

    func cancelScheduled() {
        scheduleToken &+= 1
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
    }

    // MARK: - Private

    private func schedulePlayerColor(gameType: GameType, playerID: Int, delayMs: Int) {
        scheduleToken &+= 1
        let token = scheduleToken
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, token == self.scheduleToken else { return }
                self.playPlayerColor(gameType: gameType, playerID: playerID)
            }
        }
        scheduledWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: work)
    }

    private func playBaseName(_ baseName: String, preferSecondaryChannel: Bool = false) {
        guard PreferencesManager.shared.soundEnabled else { return }
        let resolved = BoardTimerVoice.resolvedSoundName(baseName)
        guard let url = Self.resolveURL(forSoundName: resolved) else {
            #if DEBUG
            print("Board timer sound not found: \(resolved).mp3")
            #endif
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            if preferSecondaryChannel {
                secondaryPlayer = player
            } else {
                primaryPlayer = player
            }
            player.play()
        } catch {
            #if DEBUG
            print("Board timer sound error: \(error)")
            #endif
        }
    }

    private static func resolveURL(forSoundName soundName: String) -> URL? {
        if let bundleUrl = Bundle.main.url(forResource: soundName, withExtension: "mp3") {
            return bundleUrl
        }
        if let resourceUrl = Bundle.main.url(
            forResource: soundName,
            withExtension: "mp3",
            subdirectory: "Resources"
        ) {
            return resourceUrl
        }
        if let resourcesPath = Bundle.main.resourcePath {
            let filePath = (resourcesPath as NSString)
                .appendingPathComponent("Resources/\(soundName).mp3")
            if FileManager.default.fileExists(atPath: filePath) {
                return URL(fileURLWithPath: filePath)
            }
        }
        return nil
    }
}
