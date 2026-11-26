//
//  WatchCounterView.swift
//  jifenWatch Watch App
//
//  计数器：点击屏幕 +1，支持重置。与主应用/鸿蒙计数器对齐。
//

import SwiftUI

struct WatchCounterSession {
    private(set) var count = 0
    private var undoStack: [Int] = []
    private var startedAt = Date()

    var canUndo: Bool { !undoStack.isEmpty }

    mutating func increment() {
        undoStack.append(count)
        count += 1
    }

    mutating func undo() {
        if let previous = undoStack.popLast() { count = previous }
    }

    mutating func reset() {
        count = 0
        undoStack.removeAll()
    }

    mutating func finish(save: (WatchScoreboardRecord) -> Bool) -> Bool {
        let end = Date()
        if count > 0 {
            let record = WatchScoreboardRecord(
                id: "w_counter_\(UUID().uuidString)",
                gameType: .counter,
                startTime: startedAt,
                endTime: end,
                duration: end.timeIntervalSince(startedAt),
                team1Name: NSLocalizedString("game_counter", comment: "Counter"),
                team2Name: "",
                team1FinalScore: count,
                team2FinalScore: 0,
                team1SetScore: 0,
                team2SetScore: 0,
                winner: nil,
                actions: [],
                totalScoreChanges: count
            )
            guard save(record) else { return false }
        }
        reset()
        startedAt = end
        return true
    }
}

struct WatchCounterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = WatchCounterSession()
    @State private var showResetConfirm = false
    @State private var showFinishConfirm = false
    @State private var showSaveFailure = false

    /// 杠铃布局：顶部 48、中间数字、底部 48（重置放在底部 48 里）
    private let barHeight: CGFloat = 48

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: barHeight)

                ZStack {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            session.increment()
                            WatchHaptics.shared.play(.light)
                        }
                    Text("\(session.count)")
                        .font(WatchScoreTypography.primaryScore(size: 72))
                        .foregroundColor(WatchTheme.accent)
                        .contentTransition(.numericText())
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 0) {
                    Button {
                        guard session.canUndo else { return }
                        session.undo()
                        WatchHaptics.shared.play(.undo)
                    } label: {
                        Text(NSLocalizedString("menu_undo", value: "撤销", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(session.canUndo ? WatchTheme.secondaryText : WatchTheme.secondaryText.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canUndo)
                    .accessibilityIdentifier("watch_counter_undo")

                    Button {
                        showResetConfirm = true
                    } label: {
                        Text(NSLocalizedString("menu_reset", comment: "Reset"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(WatchTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFinishConfirm = true
                    } label: {
                        Text(NSLocalizedString("watch_end_match", value: "结束", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(WatchTheme.accent)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch_counter_finish")
                }
                .frame(height: barHeight)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(NSLocalizedString("game_counter", comment: "Counter"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(NSLocalizedString("menu_reset", comment: "Reset"), isPresented: $showResetConfirm) {
            Button(NSLocalizedString("menu_reset", comment: "Reset"), role: .destructive) {
                session.reset()
                WatchHaptics.shared.play(.undo)
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("press_again_to_reset", comment: ""))
        }
        .confirmationDialog(
            NSLocalizedString("watch_counter_finish_confirm_title", value: "结束计数？", comment: ""),
            isPresented: $showFinishConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("watch_end_match", value: "结束", comment: "")) {
                finishAndSave()
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("watch_counter_finish_confirm_message", value: "将结束并保存本次计数。", comment: ""))
        }
        .alert(
            NSLocalizedString("watch_common_names_error_generic", value: "Couldn't save. Try again.", comment: "Generic save failure"),
            isPresented: $showSaveFailure
        ) {
            Button(NSLocalizedString("confirm", comment: "Confirm"), role: .cancel) {}
        }
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
    }

    private func finishAndSave() {
        guard session.finish(save: { WatchRecordManager.shared.saveRecord($0, transferToPhone: false) }) else {
            showSaveFailure = true
            return
        }
        WatchHaptics.shared.play(.finish)
    }
}

#Preview {
    NavigationStack {
        WatchCounterView()
    }
}
