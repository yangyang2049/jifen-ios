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
    /// 比较基准须使用「用户当前全局主题」的默认样式，否则非默认主题下会误亮
    /// 且重置会把主题刷回 default（主题丢失）。
    private var resetBaselineTheme: ScoreboardTheme {
        ScoreboardTheme(rawValue: prefs.scoreboardTheme) ?? .defaultTheme
    }
    var canResetDraft: Bool {
        draft != ScoreboardStyleProfileV2.default(for: styleID, theme: resetBaselineTheme)
    }

    /// 字号/字体沿用既有 TypographySession（preview → apply/cancel），随会话开关联动。
    private weak var typographySession: ScoreboardTypographySession?

    init(
        styleID: ScoreboardStyleID,
        capabilities: ScoreboardStyleEditCapabilities?,
        preferences: PreferencesManager = .shared
    ) {
        let initialProfile = preferences.scoreboardStyleProfileV2(for: styleID)
        self.styleID = styleID
        self.capabilities = capabilities ?? .capabilities(elementKeys: [.teamName, .mainScore])
        self.prefs = preferences
        self.active = initialProfile
        self.draft = initialProfile
        self.revision = preferences.scoreboardRevision
    }

    /// 外部配置变化时同步；编辑中跳过，避免覆盖未保存草稿。
    func updateFromPreferences(_ preferences: PreferencesManager = .shared) {
        if isEditing || isSaving { return }
        active = preferences.scoreboardStyleProfileV2(for: styleID)
        draft = active
        revision = preferences.scoreboardRevision
    }

    func open(typographySession: ScoreboardTypographySession?) {
        draft = active
        // 清掉上次会话可能遗留的预览（draft == active 无需预览）。
        PreferencesManager.shared.setScoreboardStyleProfilePreview(nil, for: styleID)
        self.typographySession = typographySession
        isEditing = true
    }

    func updateDraft(_ value: ScoreboardStyleProfileV2) {
        draft = value.normalized()
        // 草稿推入内存预览：渲染层经 scoreboardRevision 通知立即取到 draft。
        PreferencesManager.shared.setScoreboardStyleProfilePreview(draft, for: styleID)
    }

    /// 恢复默认样式（对齐安卓 resetDraft：重置为「当前主题下」的默认样式 + 默认字号）。
    /// theme 取自用户全局主题，避免重置后主题被刷回 default（主题丢失）。
    func resetDraft(preferences: PreferencesManager = .shared) {
        let theme = ScoreboardTheme(rawValue: preferences.scoreboardTheme) ?? .defaultTheme
        draft = ScoreboardStyleProfileV2.default(for: styleID, theme: theme)
        preferences.setScoreboardStyleProfilePreview(draft, for: styleID)
        typographySession?.resetPreview(preferences: preferences)
    }

    /// 取消编辑：丢弃草稿与字号预览。
    func cancel(preferences: PreferencesManager = .shared) {
        guard !isSaving else { return }
        draft = active
        preferences.setScoreboardStyleProfilePreview(nil, for: styleID)
        typographySession?.cancelPreview()
        typographySession = nil
        isEditing = false
    }

    /// 保存事务：写本项目 styleID profile + revision++（PreferencesManager 内部自增并通知渲染）。
    /// 字号预览若有改动也在此一并落盘。
    @discardableResult
    func save(preferences: PreferencesManager = .shared) -> Result<Void, Error> {
        guard !isSaving else {
            return .failure(ScoreboardStyleEditorError.saveInProgress)
        }
        isSaving = true
        defer { isSaving = false }

        let next = draft.normalized()
        // 字号预览（若编辑过）随保存一起写回。
        typographySession?.applyPreview(preferences: preferences)
        typographySession = nil
        preferences.setScoreboardStyleProfileV2(next, for: styleID)
        // 清除草稿预览（正式 profile 已落盘）。
        preferences.setScoreboardStyleProfilePreview(nil, for: styleID)

        active = next
        draft = next
        revision = preferences.scoreboardRevision
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
