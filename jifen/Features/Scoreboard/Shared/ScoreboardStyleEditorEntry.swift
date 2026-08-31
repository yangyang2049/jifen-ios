//
//  ScoreboardStyleEditorEntry.swift
//  jifen
//
//  样式编辑入口宿主：为各计分视图（Rally/Tennis/Doudizhu/MultiScore/
//  TwoSideScaffold）提供与 ScoreboardTemplate 相同的 "displaySettings"
//  分叉逻辑——白名单项目打开新样式编辑器（对齐安卓 useStyleEditLabel
//  分叉），非白名单项目回落到旧显示设置侧滑面板。
//

import SwiftUI

@MainActor
@Observable
final class ScoreboardStyleEditorEntry {
    private(set) var controller: ScoreboardStyleEditorController?
    let uiState = ScoreboardStyleEditorUiState()

    var isEditing: Bool { controller?.isEditing == true }

    /// 菜单"displaySettings"分叉：白名单项目返回 true 并打开新编辑器。
    @discardableResult
    func handleDisplaySettings(
        styleID: ScoreboardStyleID,
        typographySession: ScoreboardTypographySession?
    ) -> Bool {
        guard ScoreboardStyleV2Registry.isEnabled(styleID) else { return false }
        open(styleID: styleID, typographySession: typographySession)
        return true
    }

    func open(styleID: ScoreboardStyleID, typographySession: ScoreboardTypographySession?) {
        if controller?.styleID != styleID {
            controller = ScoreboardStyleEditorController(
                styleID: styleID,
                capabilities: ScoreboardStyleV2Registry.capabilities(for: styleID)
            )
        }
        controller?.updateFromPreferences()
        controller?.open(typographySession: typographySession)
    }

    func cancel() {
        controller?.cancel()
    }
}

extension View {
    /// 挂载样式编辑悬浮层；isEditing 变化通过回调通知宿主刷新沉浸式 chrome。
    func scoreboardStyleEditorEntry(
        _ entry: ScoreboardStyleEditorEntry,
        typographySession: ScoreboardTypographySession?,
        onEditingChange: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(
            ScoreboardStyleEditorEntryModifier(
                entry: entry,
                typographySession: typographySession,
                onEditingChange: onEditingChange
            )
        )
    }
}

private struct ScoreboardStyleEditorEntryModifier: ViewModifier {
    let entry: ScoreboardStyleEditorEntry
    let typographySession: ScoreboardTypographySession?
    var onEditingChange: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        content
            .scoreboardStyleEditOverlay(
                controller: entry.controller,
                typographySession: typographySession,
                uiState: entry.uiState,
                onCancel: { entry.cancel() }
            )
            .onChange(of: entry.isEditing) { _, newValue in
                onEditingChange?(newValue)
            }
    }
}
