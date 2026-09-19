import Foundation

/// Shared plumbing for the three-language localization gates
/// (LocalizationIntegrityTests, ScoreboardRecordV4Tests, …).
enum LocalizationTestSupport {
    struct Entry: Equatable {
        let key: String
        let value: String
    }

    static let localizablePaths: [String: String] = [
        "en": "jifen/Resources/en.lproj/Localizable.strings",
        "zh-Hans": "jifen/Resources/zh-Hans.lproj/Localizable.strings",
        "zh-Hant": "jifen/Resources/zh-Hant.lproj/Localizable.strings",
    ]

    static let infoPlistPaths: [String: String] = [
        "en": "jifen/Resources/en.lproj/InfoPlist.strings",
        "zh-Hans": "jifen/Resources/zh-Hans.lproj/InfoPlist.strings",
        "zh-Hant": "jifen/Resources/zh-Hant.lproj/InfoPlist.strings",
    ]

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // jifenTests
            .deletingLastPathComponent()   // repo root
    }

    /// Simplified-only glyphs observed in the zh-Hans table (opencc cn->tw changes them).
    /// Excludes 台 (measure word stays 台 in Traditional). 占 is included:
    /// the unified term is 佔先 (matches 無佔先 in this table and the voice map).
    static let simplifiedOnlyCharacters: Set<Character> = Set("万与专业丢两个临为举么义买于云仅从仪们优会传伤体余侧储儿兑关内册写农决况净准减凭击刘则刚创删别办务动势区医协单占历参双发变号后吗启员响团围国图场坏块声处备复头实审宽对将尝尽属币帅带干并广庄庆应开异弃张弹强当录态总戏战户执扩扫扰抛抢报择损换据掷掼摄摇数斗断无旧时昵显暂术机权条来标样检横气没浅测游滚满滩点状独环现电疗盖盘码确离种积称稳竖笔筛简篮类纠红约级线练组细终经绑结给络绝统继绩绪续维绿编网罚胜节范荐获蓝补见观规视览触计订认让训议记许论设访证评识试话该详语误说请诺读调谢负责败账购费资赖赛赢趋转轮软轻载辅辑输边达迁过运这进违连迟适选邮采里钟钥钮铅链销锁错键镜长闭问间阅队际随隐静页顶项须预领频颗题颜额风飞馆馈骂验骚骤鸣鸿麦黄")

    static func entries(relativePath: String) throws -> [Entry] {
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
        let pattern = #"(?m)^\s*\"((?:\\.|[^\"])*)\"\s*=\s*\"((?:\\.|[^\"])*)\"\s*;"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard
                let keyRange = Range(match.range(at: 1), in: content),
                let valueRange = Range(match.range(at: 2), in: content)
            else { return nil }
            return Entry(key: String(content[keyRange]), value: String(content[valueRange]))
        }
    }

    static func valuesByKey(relativePath: String) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try entries(relativePath: relativePath).map { ($0.key, $0.value) })
    }

    static func formatTokens(in value: String) -> [String] {
        let pattern = #"%(?:%|(?:\d+\$)?[-+0 #']*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|L|z|t|j)?[@dDuUxXoOfFeEgGcCsSpaAi])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).map { match in
            String(value[Range(match.range, in: value)!])
                .replacingOccurrences(of: #"%\d+\$"#, with: "%", options: .regularExpression)
        }.sorted()
    }
}
