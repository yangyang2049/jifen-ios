import SwiftUI

nonisolated enum ShotTrainingMode: String, Codable, CaseIterable, Identifiable {
    case fixed1 = "fixed_1"
    case fixed2 = "fixed_2"
    case fixed3 = "fixed_3"
    case free

    var id: String { rawValue }

    var fixedPoints: Int? {
        switch self {
        case .fixed1: return 1
        case .fixed2: return 2
        case .fixed3: return 3
        case .free: return nil
        }
    }

    var title: String {
        switch self {
        case .fixed1: return NSLocalizedString("shot_training_mode_1", value: "1 分球", comment: "")
        case .fixed2: return NSLocalizedString("shot_training_mode_2", value: "2 分球", comment: "")
        case .fixed3: return NSLocalizedString("shot_training_mode_3", value: "3 分球", comment: "")
        case .free: return NSLocalizedString("shot_training_mode_free", value: "自由模式", comment: "")
        }
    }
}

struct ShotTrainingSetupDialogView: View {
    var maxDialogHeight: CGFloat = 680
    var initialMode: ShotTrainingMode = .fixed1
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    @State private var mode: ShotTrainingMode

    init(
        maxDialogHeight: CGFloat = 680,
        initialMode: ShotTrainingMode = .fixed1,
        onConfirm: ((SportsSetupResult) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.maxDialogHeight = maxDialogHeight
        self.initialMode = initialMode
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        AdaptiveSetupDialogLayout(maxHeight: maxDialogHeight) {
            HStack(spacing: 8) {
                Text("🏀")
                Text(NSLocalizedString("shot_training_setup_title", value: "投篮训练设置", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        } content: { _ in
            VStack(alignment: .leading, spacing: Theme.md) {
                Text(NSLocalizedString("shot_training_scoring_mode", value: "计分模式", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ShotTrainingMode.allCases) { option in
                        Button {
                            mode = option
                        } label: {
                            Text(option.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(mode == option ? .white : Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(mode == option ? Theme.primary : Theme.dialogControlBackground)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(NSLocalizedString(
                    "shot_training_mode_help",
                    value: "固定模式每次记录同一分值；自由模式可在每次出手时选择 1、2 或 3 分。",
                    comment: ""
                ))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.lg)
            .padding(.vertical, Theme.md)
        } actions: {
            HStack(spacing: Theme.md) {
                Button(NSLocalizedString("cancel", value: "取消", comment: "")) { onCancel?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 100, height: 44)
                    .background(Theme.dialogControlBackground, in: Capsule())
                Button(NSLocalizedString("start_game", value: "开始", comment: "")) {
                    onConfirm?(SportsSetupResult(
                        team1Name: NSLocalizedString("shot_training_miss", value: "未中", comment: ""),
                        team2Name: NSLocalizedString("shot_training_made", value: "命中", comment: ""),
                        basketballTrainingScoringMode: mode.rawValue
                    ))
                }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.primary, in: Capsule())
            }
            .padding(.horizontal, Theme.lg)
            .padding(.top, Theme.sm)
            .padding(.bottom, Theme.md)
        }
    }
}
