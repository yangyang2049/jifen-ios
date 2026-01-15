import AVFoundation
import WatchKit

final class WatchSoundManager {
    static let shared = WatchSoundManager()

    private var player: AVAudioPlayer?

    private init() {}

    func playSound(named name: String, fileExtension: String = "wav") {
        guard WatchPreferences.shared.soundEnabled else { return }

        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.play()
            } catch {
                WKInterfaceDevice.current().play(.click)
            }
        } else {
            WKInterfaceDevice.current().play(.click)
        }
    }
}
