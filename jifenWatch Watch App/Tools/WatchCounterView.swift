//
//  WatchCounterView.swift
//  jifenWatch Watch App
//
//  计数器：点击屏幕 +1，支持重置。与主应用/鸿蒙计数器对齐。
//

import SwiftUI

struct WatchCounterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var count: Int = 0
    /// 每次 +1 前的值，用于撤销（对齐鸿蒙 WatchCounter 的 undo）。
    @State private var undoStack: [Int] = []
    @State private var startTime: Date = Date()
    @State private var showResetConfirm: Bool = false
    @State private var showFinishConfirm: Bool = false
    @State private var didSaveRecord = false

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
                            undoStack.append(count)
                            count += 1
                            WatchHaptics.shared.play(.light)
                        }
                    Text("\(count)")
                        .font(WatchScoreTypography.primaryScore(size: 72))
                        .foregroundColor(WatchTheme.accent)
                        .contentTransition(.numericText())
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 0) {
                    Button {
                        guard let previous = undoStack.popLast() else { return }
                        count = previous
                        WatchHaptics.shared.play(.undo)
                    } label: {
                        Text(NSLocalizedString("menu_undo", value: "撤销", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(undoStack.isEmpty ? WatchTheme.secondaryText.opacity(0.45) : WatchTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(undoStack.isEmpty)
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
                count = 0
                undoStack.removeAll()
                WatchHaptics.shared.play(.undo)
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("press_again_to_reset", comment: ""))
        }
        .confirmationDialog(
            NSLocalizedString("watch_finish_confirm_title", value: "结束比赛？", comment: ""),
            isPresented: $showFinishConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("watch_end_match", value: "结束", comment: "")) {
                finishAndSave()
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("watch_finish_confirm_message", value: "将结束并保存本场比赛。", comment: ""))
        }
        .onAppear { startTime = Date() }
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
    }

    /// 结束并保存为手表本地「计数器」记录；不回传手机（对齐鸿蒙 WatchCounter 的计数记录）。
    private func finishAndSave() {
        guard !didSaveRecord else {
            dismiss()
            return
        }
        didSaveRecord = true
        let end = Date()
        let record = WatchScoreboardRecord(
            id: "w_counter_\(UUID().uuidString)",
            gameType: .counter,
            startTime: startTime,
            endTime: end,
            duration: end.timeIntervalSince(startTime),
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
        WatchRecordManager.shared.saveRecord(record, transferToPhone: false)
        WatchHaptics.shared.play(.finish)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        WatchCounterView()
    }
}
