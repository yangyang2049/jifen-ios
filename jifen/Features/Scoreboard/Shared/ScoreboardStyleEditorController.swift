//
//  ScoreboardStyleEditorController.swift
//  jifen
//
//  阶段 2：样式编辑会话 Controller（对齐安卓 ScoreboardStyleEditorController.kt）。
//  管理单次编辑的 draft/active/revision；保存只写本项目 styleID 的 profile，
//  绝不改全局 theme/font，避免影响其它项目。
//

import SwiftUI

/// 样式编辑会话控制器：编辑中渲染取 `effective`（draft 实时预览），
/// 保存后写回 PreferencesManager 并通过 `scoreboardRevision` 自增通知渲染层。
@Observable
@MainActor
final class ScoreboardStyleEditorController {
    let styleID: ScoreboardStyleID
    let capabilities: ScoreboardStyleEditCapabilities
    private let prefs: PreferencesManager

    private(set) var active: ScoreboardStyleProfileV2
    private(set) var draft: ScoreboardStyleProfileV2
    private(set) var revision: UInt64
    private(set) var isEditing = false
    private(set) var isSaving = false

    /// 编辑中实时预览草稿，非编辑态为已保存样式。
    var effective: ScoreboardStyleProfileV2 { isEditing ? draft : active }

    /// 与安卓 canResetStyleEditor 对齐：草稿等于默认样式时重置按钮置灰。
    /// 工作台恢复本项目的经典主题与全局默认排版（resolvedDefaultScoreboardFont + 倍率 1）；
    /// 不会修改全局设置或其它项目。
    private var resetBaselineTheme: ScoreboardTheme {
        ScoreboardTheme.defaultTheme
    }
    var canResetDraft: Bool {
        guard draft == ScoreboardStyleProfileV2.default(for: styleID, theme: resetBaselineTheme) else { return true }
        guard let typographySession else { return false }
        // 只比语义：字体 + 解析后的各元素倍率。`elementMultipliers` 的
        // nil / 全量字典结构差异（`updateElementMultiplier` 会把 nil 展开成全量字典）
        // 不代表用户改过字号，否则重置后按钮永远不置灰。
        let baseline = ScoreboardTypographyPreference.default(font: prefs.resolvedDefaultScoreboardFont).resolved(for: styleID)
        let current = typographySession.effectivePreference
        return current.font != baseline.font
            || current.resolvedElementMultipliers != baseline.resolvedElementMultipliers
    }

    /// 字号/字体沿用既有 TypographySession（preview → apply/cancel），随会话开关联动。
    private weak var typographySession: ScoreboardTypographySession?

    init(
        styleID: ScoreboardStyleID,
        capabilities: ScoreboardStyleEditCapabilities?,
        preferences: PreferencesManager
    ) {
        let initialProfile = preferences.scoreboardStyleProfileV2(for: styleID)
        self.styleID = styleID
        self.capabilities = capabilities ?? .capabilities(elementKeys: [.teamName, .mainScore])
        self.prefs = preferences
        self.active = initialProfile
        self.draft = initialProfile
        self.revision = preferences.scoreboardRevision
    }

    convenience init(
        styleID: ScoreboardStyleID,
        capabilities: ScoreboardStyleEditCapabilities?
    ) {
        self.init(
            styleID: styleID,
            capabilities: capabilities,
            preferences: .shared
        )
    }

    /// 外部配置变化时同步；编辑中跳过，避免覆盖未保存草稿。
    func updateFromPreferences() {
        if isEditing || isSaving { return }
        active = prefs.scoreboardStyleProfileV2(for: styleID)
        draft = active
        revision = prefs.scoreboardRevision
    }

    func open(typographySession: ScoreboardTypographySession?) {
        draft = active
        // 清掉上次会话可能遗留的预览（draft == active 无需预览）。
        prefs.setScoreboardStyleProfilePreview(nil, for: styleID)
        self.typographySession = typographySession
        isEditing = true
    }

    func updateDraft(_ value: ScoreboardStyleProfileV2) {
        draft = value.normalized()
        // 草稿推入内存预览：渲染层经 scoreboardRevision 通知立即取到 draft。
        prefs.setScoreboardStyleProfilePreview(draft, for: styleID)
    }

    /// 恢复本项目经典样式与默认字号/字体（等价于该样式从未自定义过排版）。
    /// 排版走 `resetPreview(preferences:)` 单一路径：既有预览被覆盖（不会残留旧的
    /// 元素倍率），保存时 `applyPreview` 直接清掉持久化的排版键，而不是把倍率写回。
    func resetDraft() {
        let theme = ScoreboardTheme.defaultTheme
        draft = ScoreboardStyleProfileV2.default(for: styleID, theme: theme)
        prefs.setScoreboardStyleProfilePreview(draft, for: styleID)
        typographySession?.resetPreview(preferences: prefs)
    }

    /// 取消编辑：丢弃草稿与字号预览。
    func cancel() {
        guard !isSaving else { return }
        draft = active
        prefs.setScoreboardStyleProfilePreview(nil, for: styleID)
        typographySession?.cancelPreview()
        typographySession = nil
        isEditing = false
    }

    /// 保存事务：写本项目 styleID profile + revision++（PreferencesManager 内部自增并通知渲染）。
    /// 字号预览若有改动也在此一并落盘。
    @discardableResult
    func save() -> Result<Void, Error> {
        guard !isSaving else {
            return .failure(ScoreboardStyleEditorError.saveInProgress)
        }
        isSaving = true
        defer { isSaving = false }

        let next = draft.normalized()
        // 字号预览（若编辑过）随保存一起写回。
        typographySession?.applyPreview(preferences: prefs)
        typographySession = nil
        prefs.setScoreboardStyleProfileV2(next, for: styleID)
        // 清除草稿预览（正式 profile 已落盘）。
        prefs.setScoreboardStyleProfilePreview(nil, for: styleID)

        active = next
        draft = next
        revision = prefs.scoreboardRevision
        isEditing = false
        return .success(())
    }
}

enum ScoreboardStyleEditorError: LocalizedError {
    case saveInProgress

    var errorDescription: String? {
        switch self {
        case .saveInProgress:
            return String(localized: "scoreboard_save_failed")
        }
    }
}
