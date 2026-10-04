import SwiftUI

enum ScoreAdditionTypography {
    static func plusFont(numberFontSize: CGFloat) -> Font {
        .system(size: max(1, numberFontSize - 2), weight: .bold)
    }

    /// Keep the plus two points smaller while preserving localized word order.
    static func attributedLabel(_ description: String, numberFontSize: CGFloat) -> AttributedString {
        var label = AttributedString(description)
        if let plusRange = label.range(of: "+") {
            label[plusRange].font = plusFont(numberFontSize: numberFontSize)
        }
        return label
    }
}

/// Keep the accompanying plus sign two points smaller than the amount.
struct AddValueLabel: View {
    let value: String
    let numberFontSize: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: "+")
                .font(ScoreAdditionTypography.plusFont(numberFontSize: numberFontSize))
            Text(verbatim: value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "+\(value)"))
    }
}
