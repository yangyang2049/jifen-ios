import SwiftUI

enum MediaVolumeHint {
    static var message: String {
        NSLocalizedString(
            "media_volume_hint",
            value: "Sound uses media volume. Use the volume buttons to adjust it.",
            comment: "Hint for whistle sounds and enabled voice announcements"
        )
    }
}

/// A brief, non-blocking reminder once per visit, when voice is enabled.
struct VoiceMediaVolumeHint: ViewModifier {
    let isEnabled: Bool
    @State private var hasShownHint = false
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isVisible {
                    Text(MediaVolumeHint.message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("voice_media_volume_hint")
                }
            }
            .task(id: isEnabled) {
                isVisible = false
                guard isEnabled, !hasShownHint else { return }
                hasShownHint = true
                isVisible = true
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                isVisible = false
            }
            .onDisappear { isVisible = false }
    }
}
