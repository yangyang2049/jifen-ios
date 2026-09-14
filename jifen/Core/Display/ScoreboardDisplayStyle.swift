import Foundation

/// Resolved wire colors, matching Android/HarmonyOS DisplayStyleSnapshotV2.
/// Color modes belong to the editor; display endpoints receive their resolved colors.
struct ScoreboardDisplayStyle: Codable, Equatable, Sendable {
    struct Panel: Codable, Equatable, Sendable {
        var slotKey: String
        var participantId: String? = nil
        var backgroundColor: String
    }
    struct TextColor: Codable, Equatable, Sendable {
        var slotKey: String
        var color: String
    }
    struct Element: Codable, Equatable, Sendable {
        var elementKey: String
        var textColors: [TextColor]
    }
    var version: Int = 2
    var themeCode: String
    var fontCode: String
    var fontSizeMultipliers: [String: Double] = [:]
    var panels: [Panel]
    var elements: [Element]
    var serverIndicatorColor: String
    var styleRevision: Int64 = 0

    func color(_ element: String, slot: String) -> String? {
        elements.first { $0.elementKey == element }?.textColors.first { $0.slotKey == slot }?.color
    }

    /// V2 uses RGBA; legacy iOS Color(hex:) and flat fields use ARGB.
    nonisolated static func renderHex(_ rgba: String) -> String {
        guard rgba.hasPrefix("#"), rgba.count == 9 else { return rgba }
        let digits = String(rgba.dropFirst())
        return "#" + digits.suffix(2) + digits.prefix(6)
    }

    nonisolated static func wireHex(_ argb: String) -> String {
        guard argb.hasPrefix("#"), argb.count == 9 else { return argb }
        let digits = String(argb.dropFirst())
        return "#" + digits.dropFirst(2) + digits.prefix(2)
    }

    func renderColor(_ element: String, slot: String) -> String? {
        color(element, slot: slot).map(Self.renderHex)
    }

    func panelColor(slot: String) -> String? {
        panels.first { $0.slotKey == slot }.map { Self.renderHex($0.backgroundColor) }
    }

    func slot(for participantID: String?, fallback: String) -> String {
        guard let participantID else { return fallback }
        let matches = panels.filter { $0.participantId == participantID }
        return matches.count == 1 ? matches[0].slotKey : fallback
    }

    /// Local profiles belong to logical teams; wire slots describe the visible panels.
    func projected(team0OnRight: Bool) -> Self {
        var copy = self
        func source(_ slot: String) -> String {
            guard team0OnRight else { return slot }
            if slot == "side_left" { return "side_right" }
            if slot == "side_right" { return "side_left" }
            return slot
        }
        copy.panels = panels.map { panel in
            let key = source(panel.slotKey)
            var resolved = panels.first { $0.slotKey == key } ?? panel
            resolved.slotKey = panel.slotKey
            if key == "side_left" { resolved.participantId = "team_0" }
            if key == "side_right" { resolved.participantId = "team_1" }
            return resolved
        }
        copy.elements = elements.map { element in
            var resolved = element
            resolved.textColors = element.textColors.map { color in
                var value = element.textColors.first { $0.slotKey == source(color.slotKey) } ?? color
                value.slotKey = color.slotKey
                return value
            }
            return resolved
        }
        return copy
    }

    init(appearance: ScoreboardDisplayAppearance) {
        themeCode = appearance.theme
        fontCode = appearance.fontCode
        panels = [Panel(slotKey: "side_left", backgroundColor: Self.wireHex(appearance.leftPanelHex)),
                  Panel(slotKey: "side_right", backgroundColor: Self.wireHex(appearance.rightPanelHex)),
                  Panel(slotKey: "side_center", backgroundColor: Self.wireHex(appearance.centerPanelHex))]
        let slots = ["side_left", "side_right", "side_center"]
        let names = [appearance.leftTextHex, appearance.rightTextHex, appearance.centerTextHex]
        let scores = [appearance.leftMainTextHex, appearance.rightMainTextHex, appearance.centerTextHex]
        let secondary = [appearance.leftSecondaryTextHex, appearance.rightSecondaryTextHex, appearance.centerTextHex]
        elements = ["mainScore", "teamName", "playerName", "setScore", "gameScore", "setGameScore", "matchTitle"].map { key in
            let colors = key == "mainScore" ? scores : (["teamName", "playerName", "matchTitle"].contains(key) ? names : secondary)
            return Element(elementKey: key, textColors: slots.enumerated().map { index, slot in
                TextColor(slotKey: slot, color: Self.wireHex(colors[index]))
            })
        }
        serverIndicatorColor = "#30D158"
    }

    init(profile: ScoreboardStyleProfileV2, fontCode: String) {
        themeCode = profile.themeCode
        self.fontCode = fontCode
        let candidates = (profile.panels?.map(\.slotKey) ?? [.sideLeft, .sideRight])
            + (profile.elements?.flatMap { $0.textColors.map(\.slotKey) } ?? []) + [.sideCenter]
        var slots: [ScoreboardStyleSlotKeyV2] = []
        for slot in candidates where !slots.contains(slot) { slots.append(slot) }
        panels = slots.map { slot in
            Panel(slotKey: slot.rawValue, backgroundColor: "#" + profile.slotBackgroundHex(slot))
        }
        elements = ScoreboardStyleElementKeyV2.allCases.map { key in
            Element(elementKey: key.rawValue, textColors: slots.map { slot in
                TextColor(slotKey: slot.rawValue, color: "#" + profile.resolvedElementTextHex(key, slotKey: slot))
            })
        }
        serverIndicatorColor = "#" + (profile.serverIndicatorColorHex ?? "30D158")
    }
}
