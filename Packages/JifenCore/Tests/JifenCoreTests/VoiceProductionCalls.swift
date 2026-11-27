import Foundation
import ScoreCore
import Testing

/// 使用对应的语音地区和应用的 ScoreVoice 模板渲染播报。
enum VoiceProductionCalls {
    static func templates(_ code: String) throws -> [String: String] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("jifen/Resources/\(code).lproj/ScoreVoice.strings"))
        let values = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(values as? [String: String], "Invalid ScoreVoice.strings for \(code)")
    }

    static func text(_ payload: VoiceAnnouncementPayload, _ code: String) throws -> String {
        let templates = try templates(code)
        let language = try #require(SportsVoiceLanguage.all.first { $0.localization == code })
        let message = LocalizedVoiceAnnouncementBuilder.buildReviewed(payload, localization: code)
        return try #require(
            message.render(locale: Locale(identifier: language.speechLocale), template: { templates[$0] }),
            "模板缺失：\(code) \(payload.gameType) \(payload.phase)"
        )
    }
}
