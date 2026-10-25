import Foundation
import ScoreCore

/// 英文播报的名字罗马化:汉字转无声调拼音,非汉字原样保留。
/// 纯 Foundation 实现(CFStringTransform),与鸿蒙 i18n.Transliterator、
/// 安卓 ICU Transliterator 同一角色;分数/状态字段不经过这里。
enum NameTransliteration {
    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    /// 百家姓多音字按姓氏读音覆盖,仅作用于名字首字;只收基础音节与常规
    /// 读音不同的常用姓氏(曾 céng→zēng 等),声调由去声调步骤统一剥掉。
    private static let surnameReadings: [Character: String] = [
        "曾": "zeng", "单": "shan", "解": "xie", "仇": "qiu", "朴": "piao",
        "查": "zha", "翟": "zhai", "覃": "qin", "乐": "yue", "折": "she",
        "缪": "miao", "种": "chong", "盖": "ge", "区": "ou", "秘": "bi",
        "都": "du", "繁": "po", "贲": "ben", "郇": "xun",
        "單": "shan", "樂": "yue", "繆": "miao", "種": "chong",
        "蓋": "ge", "區": "ou", "賁": "ben", "祕": "bi"
    ]

    private static func mandarinLatin(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        return mutable as String
    }

    private static func stripTonesAndCollapse(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func romanizedName(_ name: String) -> String {
        guard !name.isEmpty, containsHan(name) else { return name }
        var result = ""
        var run = ""
        var runIsHan: Bool?

        func appendRun() {
            guard let isHan = runIsHan else { return }
            let text: String
            if isHan {
                let raw: String
                // Only the first character of the original name is a surname.
                if result.isEmpty, let first = run.first, let reading = surnameReadings[first] {
                    let rest = run.dropFirst()
                    raw = rest.isEmpty ? reading : reading + " " + mandarinLatin(String(rest))
                } else {
                    raw = mandarinLatin(run)
                }
                let converted = stripTonesAndCollapse(raw)
                text = converted.isEmpty ? run : converted
            } else {
                // Never strip accents or normalize whitespace from the original Latin name.
                text = run
            }
            if let last = result.last, let first = text.first,
               (last.isLetter || last.isNumber), (first.isLetter || first.isNumber) {
                result += " "
            }
            result += text
        }

        for character in name {
            let isHan = containsHan(String(character))
            if runIsHan != isHan {
                appendRun()
                run = ""
                runIsHan = isHan
            }
            run.append(character)
        }
        appendRun()
        return result
    }

    /// 返回名字字段罗马化后的副本(leftTeamName/rightTeamName/serverName/winnerName/receiverName),其余字段原样保留。
    static func romanized(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementPayload {
        var copy = payload
        if !copy.leftTeamName.isEmpty { copy.leftTeamName = romanizedName(copy.leftTeamName) }
        if !copy.rightTeamName.isEmpty { copy.rightTeamName = romanizedName(copy.rightTeamName) }
        if let serverName = copy.serverName, !serverName.isEmpty { copy.serverName = romanizedName(serverName) }
        if let winnerName = copy.winnerName, !winnerName.isEmpty { copy.winnerName = romanizedName(winnerName) }
        if let receiverName = copy.receiverName, !receiverName.isEmpty { copy.receiverName = romanizedName(receiverName) }
        return copy
    }
}
