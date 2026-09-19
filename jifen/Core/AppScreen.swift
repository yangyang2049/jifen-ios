import UIKit

/// iOS 26 起 `UIScreen.main` 已废弃。这里统一从连接的场景取屏幕信息：
/// 优先前台活动场景，没有活动场景时退回任意已连接窗口场景。
@MainActor
enum AppScreen {
    static var bounds: CGRect {
        screens.first?.bounds ?? .zero
    }

    static var scale: CGFloat {
        screens.first?.scale ?? UITraitCollection.current.displayScale
    }

    private static var screens: [UIScreen] {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        return (active.isEmpty ? scenes : active).map(\.screen)
    }
}
