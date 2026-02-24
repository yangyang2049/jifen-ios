import Foundation

enum CommonNamesBatchParser {
    static func parse(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(
            of: "[,，、;；\\n\\r]+",
            with: "\n",
            options: .regularExpression
        )

        var result: [String] = []
        var keys = Set<String>()

        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(raw)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !value.isEmpty else { continue }
            let key = value.lowercased()
            if keys.insert(key).inserted {
                result.append(value)
            }
        }

        return result
    }
}
