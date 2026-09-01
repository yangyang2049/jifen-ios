//
//  RecordNotesCard.swift
//  jifen
//
//  记录详情笔记区域，1:1 对齐安卓 RecordNotesCard（RecordNotesSection）。
//  语音笔记默认开放，不做 VIP/登录门禁（产品决策：后续按端逐步接入）。
//

import AVFoundation
import SwiftUI

enum RecordNoteSheetMode: Equatable {
    case none
    case menu
    case viewText
    case editText
    case recordVoice
}

private enum RecordNoteDeleteKind {
    case text
    case voice
}

private let maxTextNoteLength = ScoreboardRecordNote.maximumUnicodeScalars
private let recordingWaveInitial: [CGFloat] = Array(repeating: 4, count: 28)
private let voiceNoteWaveHeights: [CGFloat] = [
    6, 12, 9, 18, 13, 22, 10, 16, 8, 20, 12, 17, 7, 14,
    11, 19, 9, 15, 13, 21, 8, 16, 12, 18, 10, 14, 6, 12
]
private let playbackWaveMultipliers: [CGFloat] = [0.72, 0.9, 1.08, 0.82, 1.16, 0.96]

private let whistleRed = Color(red: 1, green: 0x3B / 255, blue: 0x30 / 255)

struct RecordNotesSectionView: View {
    let recordId: String
    let note: String?
    let voiceNote: ScoreboardRecordVoiceNote?
    @Binding var sheetMode: RecordNoteSheetMode
    let onNotesChanged: () -> Void
    /// 笔记相关提示统一回调到详情页顶层展示（sheet 关闭后仍可见）。
    let onToast: (String) -> Void

    @State private var confirmDelete: RecordNoteDeleteKind?

    var body: some View {
        Group {
            if hasNotes {
                notesCard
            }
        }
        .alert(deleteTitle, isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) { confirmDelete = nil }
            Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive) {
                if confirmDelete == .voice { deleteVoice() } else { deleteText() }
                confirmDelete = nil
            }
        } message: {
            Text(confirmDelete == .voice
                 ? NSLocalizedString("record_note_delete_voice_confirm", value: "确定删除这条语音笔记吗？删除后不可恢复。", comment: "")
                 : NSLocalizedString("record_note_delete_text_confirm", value: "确定删除这条文字笔记吗？删除后不可恢复。", comment: ""))
        }
        .onDisappear {
            RecordNoteAudioManager.shared.stopPlayback()
        }
    }

    private var hasNotes: Bool {
        !(note ?? "").isEmpty || voiceNote != nil
    }

    private var deleteTitle: String {
        NSLocalizedString("record_note_delete_title", value: "删除笔记", comment: "")
    }

    // MARK: - 笔记卡片

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            notesCardTitle
            if let voiceNote {
                VoiceNoteEntryView(
                    voiceNote: voiceNote,
                    isRecordingBlocked: RecordNoteAudioManager.shared.isRecording,
                    onRequestVoice: { requestVoiceRecording() },
                    onDeleteVoice: { confirmDelete = .voice },
                    onVoiceUnavailable: { handleVoiceUnavailable() }
                )
            }
            if let note, !note.isEmpty {
                TextNoteEntryView(
                    text: note,
                    onOpenViewer: { sheetMode = .viewText },
                    onOpenEditor: { sheetMode = .editText },
                    onDeleteText: { confirmDelete = .text }
                )
            }
        }
        .padding(.bottom, 8)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var notesCardTitle: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.primary)
                .frame(width: 3, height: 16)
            Text(NSLocalizedString("record_note_title", value: "笔记", comment: ""))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - 动作（卡片）

    /// 卡片上的"重新录制"入口：申请权限并开始录音，录音界面由详情页顶层 sheet 呈现。
    private func requestVoiceRecording() {
        guard sheetMode == .none else { return }
        Task {
            let granted = await requestMicrophonePermission()
            await MainActor.run {
                if granted {
                    startNoteRecording()
                } else {
                    onToast(NSLocalizedString(
                        "record_note_microphone_denied",
                        value: "未获得麦克风权限，无法录制语音笔记",
                        comment: ""
                    ))
                }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { return true }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startNoteRecording() {
        let started = RecordNoteAudioManager.shared.startRecording(recordId: recordId) { result in
            handleRecordingFinished(result)
        }
        if started {
            sheetMode = .recordVoice
        }
    }

    private func handleRecordingFinished(_ result: RecordNoteRecordingResult) {
        if result.success {
            onToast(NSLocalizedString("record_note_voice_saved", value: "语音笔记已保存", comment: ""))
            sheetMode = .none
            onNotesChanged()
            return
        }
        if result.reason == "cancelled" {
            sheetMode = .none
            return
        }
        switch result.reason {
        case "permission_denied":
            onToast(NSLocalizedString("record_note_microphone_denied", value: "未获得麦克风权限，无法录制语音笔记", comment: ""))
        case "too_short":
            onToast(NSLocalizedString("record_note_voice_too_short", value: "录音不足 2 秒，未保存", comment: ""))
        case "record_unavailable":
            onToast(NSLocalizedString("record_note_record_unavailable", value: "比赛记录不存在，无法保存笔记", comment: ""))
        case "interrupted":
            onToast(NSLocalizedString("record_note_voice_interrupted", value: "录音被系统中断，本次未保存", comment: ""))
        case "file_create_failed":
            onToast(NSLocalizedString("record_note_voice_file_create_failed", value: "无法创建录音文件，请检查存储空间后重试", comment: ""))
        case "file_failed":
            onToast(NSLocalizedString("record_note_voice_file_failed", value: "录音文件无效，原语音未修改", comment: ""))
        case "save_failed":
            onToast(NSLocalizedString("record_note_voice_save_failed", value: "录音已完成，但保存失败，原语音未修改", comment: ""))
        default:
            onToast(NSLocalizedString("record_note_voice_failed", value: "录音失败，原语音未修改", comment: ""))
        }
        sheetMode = .none
    }

    private func deleteText() {
        do {
            try ScoreboardRecordManager.shared.updateRecordNote(id: recordId, note: nil)
            onNotesChanged()
        } catch {
            onToast(NSLocalizedString("record_note_delete_failed", value: "笔记删除失败，请重试", comment: ""))
        }
    }

    private func deleteVoice() {
        RecordNoteAudioManager.shared.stopPlayback()
        do {
            try ScoreboardRecordManager.shared.deleteRecordVoiceNote(id: recordId)
            onNotesChanged()
        } catch {
            onToast(NSLocalizedString("record_note_delete_failed", value: "笔记删除失败，请重试", comment: ""))
        }
    }

    private func handleVoiceUnavailable() {
        onToast(NSLocalizedString("record_note_voice_unavailable", value: "语音不可用", comment: ""))
        try? ScoreboardRecordManager.shared.deleteRecordVoiceNote(id: recordId)
        onNotesChanged()
    }
}

// MARK: - 笔记弹层（挂在详情页顶层，避免依赖笔记卡片的存在）

struct RecordNoteSheet: View {
    let recordId: String
    let note: String?
    @Binding var sheetMode: RecordNoteSheetMode
    let onNotesChanged: () -> Void
    let onToast: (String) -> Void

    @State private var textDraft = ""
    @State private var isSaving = false
    @State private var confirmDelete: RecordNoteDeleteKind?
    @State private var toast: String?

    @State private var recordingSeconds = 0
    @State private var recordingWave: [CGFloat] = recordingWaveInitial
    @State private var smoothedAmplitude: Float = 0
    @State private var recordingPeak: Float = 0

    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        Group {
            switch sheetMode {
            case .menu:
                menuSheet
            case .editText:
                textEditorSheet
            case .viewText:
                textViewerSheet
            case .recordVoice:
                recorderSheet
            case .none:
                EmptyView()
            }
        }
        .presentationDetents(sheetDetents)
        .presentationDragIndicator(.visible)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        self.toast = nil
                    }
            }
        }
        .alert(deleteTitle, isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) { confirmDelete = nil }
            Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive) {
                if confirmDelete == .voice { deleteVoice() } else { deleteText() }
                confirmDelete = nil
            }
        } message: {
            Text(confirmDelete == .voice
                 ? NSLocalizedString("record_note_delete_voice_confirm", value: "确定删除这条语音笔记吗？删除后不可恢复。", comment: "")
                 : NSLocalizedString("record_note_delete_text_confirm", value: "确定删除这条文字笔记吗？删除后不可恢复。", comment: ""))
        }
        .onAppear {
            // 从卡片"查看/编辑"进入时预填当前笔记；从菜单进入编辑则保留上次草稿（原行为）。
            if sheetMode == .editText || sheetMode == .viewText {
                textDraft = note ?? ""
            }
            if sheetMode == .editText {
                scheduleTextEditorFocus()
            }
        }
        .onChange(of: sheetMode) { _, newMode in
            // 从菜单切到文字编辑时自动聚焦打开键盘
            if newMode == .editText {
                scheduleTextEditorFocus()
            }
        }
    }

    /// 等 sheet 呈现/内容切换动画完成后再聚焦，过早赋值会被动画吞掉。
    private func scheduleTextEditorFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if sheetMode == .editText {
                isTextEditorFocused = true
            }
        }
    }

    private var deleteTitle: String {
        NSLocalizedString("record_note_delete_title", value: "删除笔记", comment: "")
    }

    private var sheetDetents: Set<PresentationDetent> {
        switch sheetMode {
        case .recordVoice: return [.height(430)]
        case .editText: return [.medium, .large]
        case .menu: return [.height(480)]
        default: return [.medium]
        }
    }

    private var menuSheet: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("record_note_title", value: "笔记", comment: ""))
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { sheetMode = .editText } label: { menuRow(icon: "square.and.pencil", title: textTitle, hint: textHint) }
            Button { requestVoiceRecording() } label: { menuRow(icon: "mic.fill", title: voiceTitle, hint: voiceHint) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private var textTitle: String { NSLocalizedString("record_note_text_title", value: "文字笔记", comment: "") }
    private var voiceTitle: String { NSLocalizedString("record_note_voice_title", value: "语音笔记", comment: "") }
    private var textHint: String { NSLocalizedString("record_note_text_action_hint", value: "添加或编辑本场文字笔记", comment: "") }
    private var voiceHint: String { NSLocalizedString("record_note_voice_action_hint", value: "录制最长 60 秒的语音笔记", comment: "") }

    private func menuRow(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 60, height: 60)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Text(hint)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var textEditorSheet: some View {
        VStack(spacing: 16) {
            Text(editTextTitle)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            TextEditor(text: Binding(
                get: { textDraft },
                set: { textDraft = String($0.prefix(maxTextNoteLength)) }
            ))
            .focused($isTextEditorFocused)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: 176)
            .background(Theme.dialogControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                if textDraft.isEmpty {
                    Text(NSLocalizedString("record_note_text_placeholder", value: "记录这场比赛的想法、关键点或复盘…", comment: ""))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            Text("\(textDraft.unicodeScalars.count)/\(maxTextNoteLength)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Button(action: saveText) {
                Text(NSLocalizedString("record_note_save", value: "保存", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSaveText ? .white : Theme.textSecondary)
            .background(canSaveText ? Theme.primary : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(!canSaveText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private var editTextTitle: String {
        (note ?? "").isEmpty
            ? NSLocalizedString("record_note_add_text", value: "添加文字笔记", comment: "")
            : NSLocalizedString("record_note_edit_text", value: "编辑文字笔记", comment: "")
    }

    private var canSaveText: Bool {
        !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private var textViewerSheet: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("record_note_text_title", value: "文字笔记", comment: ""))
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                Text(note ?? "")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 250)
            HStack(spacing: 12) {
                Button(role: .destructive) { confirmDelete = .text } label: {
                    Text(NSLocalizedString("delete", value: "删除", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                Button { sheetMode = .editText } label: {
                    Text(NSLocalizedString("record_note_edit_text", value: "编辑文字笔记", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private var recorderSheet: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(whistleRed).frame(width: 8, height: 8)
                Text(NSLocalizedString("record_note_recording", value: "正在录音", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(String(format: "%02d:%02d", recordingSeconds / 60, recordingSeconds % 60))
                .font(.system(size: 34, weight: .medium, design: .monospaced))
            HStack(spacing: 3) {
                ForEach(Array(recordingWave.enumerated()), id: \.offset) { _, height in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.primary)
                        .frame(width: 4, height: max(height, 4))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
            HStack {
                recordingControl(icon: "xmark", label: NSLocalizedString("cancel", value: "取消", comment: ""), background: Color.primary.opacity(0.08)) {
                    RecordNoteAudioManager.shared.cancelRecording()
                    sheetMode = .none
                }
                Spacer()
                recordingControl(icon: "stop.fill", label: NSLocalizedString("record_note_stop", value: "停止并保存", comment: ""), background: whistleRed, isDestructive: true) {
                    RecordNoteAudioManager.shared.stopRecording()
                }
            }
            .padding(.horizontal, 48)
            Spacer(minLength: 0)
            Text(NSLocalizedString("record_note_recording_hint", value: "点击停止后立即保存；退出或进入后台会取消本次录音。", comment: ""))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("record_note_minimum_hint", value: "不足 2 秒将自动丢弃，不会替换原语音", comment: ""))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .interactiveDismissDisabled()
        .task(id: "clock") {
            while !Task.isCancelled {
                recordingSeconds = min(RecordNoteAudioManager.shared.currentRecordingDurationMs() / 1000, 60)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        .task(id: "wave") {
            while !Task.isCancelled {
                let amplitude = RecordNoteAudioManager.shared.readCurrentRecordingAmplitude()
                recordingPeak = max(amplitude, recordingPeak * 0.96)
                let scaled: Float = recordingPeak > 0 ? min(max(amplitude / recordingPeak, 0), 1) : 0
                let target: Float = 0.08 + 0.92 * powf(scaled, 0.8)
                let smoothing: Float = target > smoothedAmplitude ? 0.5 : 0.22
                let delta = min(max((target - smoothedAmplitude) * smoothing, -0.16), 0.3)
                smoothedAmplitude = min(max(smoothedAmplitude + delta, 0), 1)
                let height = 4 + smoothedAmplitude * (72 - 4)
                recordingWave = Array(recordingWave.dropFirst()) + [CGFloat(height)]
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func recordingControl(icon: String, label: String, background: Color, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 7) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isDestructive ? .white : Theme.textPrimary)
                    .frame(width: 56, height: 56)
                    .background(background, in: Circle())
            }
            .buttonStyle(.plain)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - 动作（弹层）

    private func requestVoiceRecording() {
        guard !RecordNoteAudioManager.shared.isRecording else { return }
        Task {
            let granted = await requestMicrophonePermission()
            await MainActor.run {
                if granted {
                    startNoteRecording()
                } else {
                    onToast(NSLocalizedString(
                        "record_note_microphone_denied",
                        value: "未获得麦克风权限，无法录制语音笔记",
                        comment: ""
                    ))
                }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { return true }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startNoteRecording() {
        let started = RecordNoteAudioManager.shared.startRecording(recordId: recordId) { result in
            handleRecordingFinished(result)
        }
        if started {
            recordingSeconds = 0
            recordingWave = recordingWaveInitial
            smoothedAmplitude = 0
            recordingPeak = 0
            sheetMode = .recordVoice
        }
    }

    private func handleRecordingFinished(_ result: RecordNoteRecordingResult) {
        if result.success {
            onToast(NSLocalizedString("record_note_voice_saved", value: "语音笔记已保存", comment: ""))
            sheetMode = .none
            onNotesChanged()
            return
        }
        if result.reason == "cancelled" {
            recordingSeconds = 0
            sheetMode = .none
            return
        }
        switch result.reason {
        case "permission_denied":
            onToast(NSLocalizedString("record_note_microphone_denied", value: "未获得麦克风权限，无法录制语音笔记", comment: ""))
        case "too_short":
            onToast(NSLocalizedString("record_note_voice_too_short", value: "录音不足 2 秒，未保存", comment: ""))
        case "record_unavailable":
            onToast(NSLocalizedString("record_note_record_unavailable", value: "比赛记录不存在，无法保存笔记", comment: ""))
        case "interrupted":
            onToast(NSLocalizedString("record_note_voice_interrupted", value: "录音被系统中断，本次未保存", comment: ""))
        case "file_create_failed":
            onToast(NSLocalizedString("record_note_voice_file_create_failed", value: "无法创建录音文件，请检查存储空间后重试", comment: ""))
        case "file_failed":
            onToast(NSLocalizedString("record_note_voice_file_failed", value: "录音文件无效，原语音未修改", comment: ""))
        case "save_failed":
            onToast(NSLocalizedString("record_note_voice_save_failed", value: "录音已完成，但保存失败，原语音未修改", comment: ""))
        default:
            onToast(NSLocalizedString("record_note_voice_failed", value: "录音失败，原语音未修改", comment: ""))
        }
        sheetMode = .none
    }

    private func saveText() {
        guard canSaveText else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try ScoreboardRecordManager.shared.updateRecordNote(id: recordId, note: textDraft)
            sheetMode = .none
            onNotesChanged()
        } catch {
            onToast(NSLocalizedString("record_note_save_failed", value: "笔记保存失败，请重试", comment: ""))
        }
    }

    private func deleteText() {
        do {
            try ScoreboardRecordManager.shared.updateRecordNote(id: recordId, note: nil)
            sheetMode = .none
            onNotesChanged()
        } catch {
            onToast(NSLocalizedString("record_note_delete_failed", value: "笔记删除失败，请重试", comment: ""))
        }
    }

    private func deleteVoice() {
        RecordNoteAudioManager.shared.stopPlayback()
        do {
            try ScoreboardRecordManager.shared.deleteRecordVoiceNote(id: recordId)
            sheetMode = .none
            onNotesChanged()
        } catch {
            onToast(NSLocalizedString("record_note_delete_failed", value: "笔记删除失败，请重试", comment: ""))
        }
    }
}

// MARK: - 文字条目

private struct TextNoteEntryView: View {
    let text: String
    let onOpenViewer: () -> Void
    let onOpenEditor: () -> Void
    let onDeleteText: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.08), in: Circle())
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(4)
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button(NSLocalizedString("record_note_edit_text", value: "编辑文字笔记", comment: ""), action: onOpenEditor)
                Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive, action: onDeleteText)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenViewer)
    }
}

// MARK: - 语音条目

private struct VoiceNoteEntryView: View {
    let voiceNote: ScoreboardRecordVoiceNote
    let isRecordingBlocked: Bool
    let onRequestVoice: () -> Void
    let onDeleteVoice: () -> Void
    /// 音频文件缺失时回调（清理引用并提示）。
    let onVoiceUnavailable: () -> Void

    @State private var isPlaying = false
    @State private var playbackPositionMs = 0
    @State private var voiceWave: [CGFloat] = voiceNoteWaveHeights

    private var timeText: String {
        if !isPlaying || voiceNote.durationMs <= 0 {
            return Self.formatDuration(ms: voiceNote.durationMs)
        }
        let remaining = max(voiceNote.durationMs - playbackPositionMs, 0)
        return "-\(Self.formatDuration(ms: remaining))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isRecordingBlocked)
            HStack(spacing: 3) {
                ForEach(Array(voiceWave.enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.primary)
                        .frame(width: 3, height: max(height, 4))
                        .id(index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(timeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isPlaying ? Theme.textPrimary : Theme.textSecondary)
            Menu {
                Button(NSLocalizedString("record_note_voice_rerecord", value: "重新录制", comment: ""), action: onRequestVoice)
                Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive, action: onDeleteVoice)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .task(id: isPlaying) {
            guard isPlaying else {
                playbackPositionMs = 0
                voiceWave = voiceNoteWaveHeights
                return
            }
            var frame = 0
            while !Task.isCancelled {
                frame += 1
                playbackPositionMs = RecordNoteAudioManager.shared.currentPlaybackPositionMs()
                voiceWave = voiceNoteWaveHeights.enumerated().map { index, height in
                    let multiplier = playbackWaveMultipliers[(index + frame) % playbackWaveMultipliers.count]
                    return min(max(height * multiplier, 4), 26)
                }
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
        }
    }

    private func togglePlayback() {
        if RecordNoteAudioManager.shared.isRecording { return }
        RecordNoteAudioManager.shared.togglePlayback(relativePath: voiceNote.relativePath) { playing, failure in
            DispatchQueue.main.async {
                isPlaying = playing
                if failure == "missing_file" {
                    onVoiceUnavailable()
                }
            }
        }
    }

    private static func formatDuration(ms: Int) -> String {
        let seconds = Int((Double(ms) / 1000).rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
