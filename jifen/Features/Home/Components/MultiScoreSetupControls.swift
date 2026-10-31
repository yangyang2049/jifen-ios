//
//  MultiScoreSetupControls.swift
//  jifen
//
//  多人计分人数选择与批量填名（对齐安卓 MultiScoreSetupControls / MultiScoreNameBatch / MultiScoreCapacity）。
//

import SwiftUI

/// 多人计分容量契约：3～50 人。UNO 仍为 2～10，不受此处影响。
enum MultiScoreCapacity {
    static let minPlayers = 3
    static let maxPlayers = 50
    /// 常用人数浮层选项，与安卓一致。
    static let quickCounts = [10, 20, 30, 40, 50]
    /// 批量填写与改名沿用的姓名长度上限（安卓 MAX_COMMON_NAME_LENGTH）。
    static let maxNameLength = 24

    static func isValid(_ count: Int) -> Bool {
        (minPlayers ... maxPlayers).contains(count)
    }

    static func parsePlayerCount(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = normalizedDecimalDigits(trimmed, limit: trimmed.count)
        guard !digits.isEmpty, digits.count == trimmed.unicodeScalars.count,
              let count = Int(digits), isValid(count) else { return nil }
        return count
    }

    static func normalized(_ count: Int) -> Int {
        min(maxPlayers, max(minPlayers, count))
    }
}

enum MultiScoreNameBatchError: Equatable {
    case empty
    case tooMany
    case nameTooLong
}

struct MultiScoreNameBatch: Equatable {
    var names: [String]
    var error: MultiScoreNameBatchError?
    var invalidNameIndex: Int
}

/// 保留重复、内嵌空格与输入顺序，绝不静默截断名单（与安卓同语义）。
enum MultiScoreNameBatchParser {
    private static let separators = CharacterSet(charactersIn: ",\u{FF0C}\u{3001};\u{FF1B}\t\r\n")

    static func parse(_ raw: String) -> MultiScoreNameBatch {
        let names = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let invalidIndex = names.firstIndex { $0.count > MultiScoreCapacity.maxNameLength } ?? -1
        let error: MultiScoreNameBatchError?
        if names.isEmpty {
            error = .empty
        } else if names.count > MultiScoreCapacity.maxPlayers {
            error = .tooMany
        } else if invalidIndex >= 0 {
            error = .nameTooLong
        } else {
            error = nil
        }

        return MultiScoreNameBatch(names: names, error: error, invalidNameIndex: invalidIndex)
    }
}

// MARK: - 人数选择

/// 3～9 快捷项保留，右侧铅笔进入自定义；10/20/30/40/50 使用锚定浮层，不挤动设置内容。
struct MultiScoreCountSelector: View {
    var playerCount: Int
    var onPlayerCountChange: (Int) -> Void
    var onValidationChange: (Bool) -> Void

    @State private var customMode: Bool
    @State private var draft: String
    @State private var showQuickCounts = false
    @FocusState private var customFieldFocused: Bool

    init(playerCount: Int, onValidationChange: @escaping (Bool) -> Void = { _ in }, onPlayerCountChange: @escaping (Int) -> Void) {
        self.playerCount = playerCount
        self.onPlayerCountChange = onPlayerCountChange
        self.onValidationChange = onValidationChange
        _customMode = State(initialValue: playerCount > 9)
        _draft = State(initialValue: "\(playerCount)")
    }

    private var parsedDraft: Int? {
        MultiScoreCapacity.parsePlayerCount(draft)
    }

    private var isValid: Bool {
        !customMode || parsedDraft != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MultiScoreCapacity.minPlayers ... 9, id: \.self) { count in
                            countChip(count, selected: !customMode && playerCount == count) {
                                select(count, useCustom: false)
                            }
                            .accessibilityIdentifier("setup_multi_count_\(count)")
                        }
                    }
                }

                if customMode {
                    customCountField
                        .popover(isPresented: $showQuickCounts, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                            quickCountPopover
                                .presentationCompactAdaptation(.popover)
                        }
                } else {
                    Button {
                        customMode = true
                        showQuickCounts = true
                        customFieldFocused = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Theme.dialogControlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("custom", value: "自定义", comment: "Custom"))
                    .accessibilityIdentifier("setup_multi_count_custom")
                }
            }

            if !isValid {
                Text(NSLocalizedString("multi_score_count_invalid", value: "请输入 3～50 的整数", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.destructiveText)
            }
        }
        .onAppear { onValidationChange(isValid) }
        .onChange(of: isValid) { _, valid in onValidationChange(valid) }
        .onChange(of: playerCount) { _, newValue in
            // 恢复偏好或批量输入时同步显示，不覆盖正在输入的本机草稿。
            guard parsedDraft != newValue else { return }
            customMode = newValue > 9
            draft = "\(newValue)"
        }
    }

    private var customCountField: some View {
        TextField(
            "",
            text: Binding(
                get: { draft },
                set: { raw in
                    draft = normalizedDecimalDigits(raw, limit: 3)
                    if let value = parsedDraft {
                        onPlayerCountChange(value)
                    }
                }
            ),
            prompt: Text(NSLocalizedString("multi_score_count_placeholder", value: "3–50", comment: ""))
                .foregroundColor(Theme.textOnPrimary.opacity(0.7))
        )
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(Theme.textOnPrimary)
        .frame(width: 88, height: 44)
        .background(Theme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focused($customFieldFocused)
        .onTapGesture { showQuickCounts = true }
        .onChange(of: customFieldFocused) { _, focused in
            if focused { showQuickCounts = true }
        }
        .onSubmit {
            if isValid { showQuickCounts = false; customFieldFocused = false }
        }
        .accessibilityIdentifier("setup_multi_count_custom_input")
    }

    private var quickCountPopover: some View {
        HStack(spacing: 6) {
            ForEach(MultiScoreCapacity.quickCounts, id: \.self) { count in
                countChip(count, selected: playerCount == count, minimumWidth: 44, includesUnit: false) {
                    select(count, useCustom: true)
                }
                .frame(minWidth: 44)
                .accessibilityIdentifier("setup_multi_quick_count_\(count)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 280)
    }

    private func countChip(_ count: Int, selected: Bool, minimumWidth: CGFloat = 80, includesUnit: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(includesUnit ? countText(count) : String(count))
                .font(.system(size: 15, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? Theme.textOnPrimary : Theme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: minimumWidth, minHeight: 44)
                .background(selected ? Theme.primary : Theme.dialogControlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(countText(count))
    }

    private func countText(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("players_count_format", value: "%d人", comment: "Player count format"),
            count
        )
    }

    private func select(_ count: Int, useCustom: Bool) {
        customMode = useCustom
        draft = "\(count)"
        showQuickCounts = false
        customFieldFocused = false
        onPlayerCountChange(count)
    }
}

// MARK: - 批量填名

/// 按顺序替换姓名、保留未被覆盖的姓名，超过当前人数时明确提示扩容。
struct MultiScoreBulkNamesDialog: View {
    var playerCount: Int
    var onApply: ([String]) -> Void
    var onDismiss: () -> Void

    @State private var raw = ""
    @FocusState private var editorFocused: Bool

    private var batch: MultiScoreNameBatch {
        MultiScoreNameBatchParser.parse(raw)
    }

    private var feedback: String {
        Self.feedback(for: batch, playerCount: playerCount)
    }

    static func feedback(for batch: MultiScoreNameBatch, playerCount: Int) -> String {
        switch batch.error {
        case .empty:
            return NSLocalizedString("multi_score_bulk_empty", value: "按顺序替换，未填到的玩家姓名保留", comment: "")
        case .tooMany:
            return NSLocalizedString("multi_score_bulk_too_many", value: "最多 50 人，请调整名单后再应用", comment: "")
        case .nameTooLong:
            return String.localizedStringWithFormat(
                NSLocalizedString("multi_score_bulk_name_long", value: "第 %d 个姓名超过 24 字", comment: ""),
                batch.invalidNameIndex + 1
            )
        case .none:
            if batch.names.count > playerCount {
                return String.localizedStringWithFormat(
                    NSLocalizedString("multi_score_bulk_expand", value: "%d 个姓名，人数将改为 %d 人", comment: ""),
                    batch.names.count,
                    batch.names.count
                )
            }
            return String.localizedStringWithFormat(
                NSLocalizedString("multi_score_bulk_apply", value: "%d 个姓名，替换前 %d 位，其余保留", comment: ""),
                batch.names.count,
                min(batch.names.count, playerCount)
            )
        }
    }

    private var showsError: Bool {
        if case .none = batch.error { return false }
        if case .empty? = batch.error { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            Text(NSLocalizedString("multi_score_bulk_names", value: "批量填写", comment: ""))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            TextEditor(text: $raw)
                .font(.system(size: 15))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 144, maxHeight: 260)
                .padding(8)
                .background(Theme.dialogControlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($editorFocused)
                .overlay(alignment: .topLeading) {
                    if raw.isEmpty {
                        Text(NSLocalizedString("multi_score_bulk_placeholder", value: "每行一个姓名，可直接粘贴名单", comment: ""))
                            .font(.system(size: 15))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("setup_multi_bulk_input")

            Text(feedback)
                .font(.system(size: 13))
                .foregroundColor(showsError ? Theme.destructiveText : Theme.textSecondary)

            HStack(spacing: Theme.md) {
                Button(action: onDismiss) {
                    Text(NSLocalizedString("cancel", comment: "Cancel button"))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 100, height: 48)
                        .background(Theme.dialogControlBackground)
                        .cornerRadius(.infinity)
                }
                .buttonStyle(.plain)

                Button {
                    onApply(batch.names)
                } label: {
                    Text(NSLocalizedString("confirm", value: "确定", comment: ""))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(batch.error == nil ? Theme.textOnPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(batch.error == nil ? Theme.primary : Theme.dialogControlBackground)
                        .cornerRadius(.infinity)
                }
                .buttonStyle(.plain)
                .disabled(batch.error != nil)
                .accessibilityIdentifier("setup_multi_bulk_apply")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.dialogSurfaceBackground)
        .onAppear { editorFocused = true }
    }
}
