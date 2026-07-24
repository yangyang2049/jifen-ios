import SwiftUI

struct FirstLaunchLegalScreen: View {
    let onAccept: () -> Void

    @State private var isChecked = false
    @State private var showDeclineMessage = false

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            GeometryReader { geometry in
                let isPad = UIDevice.current.userInterfaceIdiom == .pad

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        summaryCard
                        consentRow
                        actions
                    }
                    .frame(maxWidth: isPad ? 560 : 680)
                    .padding(.horizontal, isPad ? 32 : 22)
                    .padding(.vertical, isPad ? 40 : 28)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
        .alert(
            NSLocalizedString("legal_decline_title", comment: "Legal consent declined title"),
            isPresented: $showDeclineMessage
        ) {
            Button(NSLocalizedString("legal_decline_acknowledge", comment: "Legal consent declined acknowledgement")) { }
        } message: {
            Text(NSLocalizedString("legal_decline_message", comment: "Legal consent declined message"))
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(NSLocalizedString("legal_consent_title", comment: "First-launch legal title"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("legal_consent_subtitle", comment: "First-launch legal subtitle"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("legal_summary_title", comment: "Legal data summary title"))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text(NSLocalizedString("legal_summary_body", comment: "Legal data summary body"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var consentRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                isChecked.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isChecked ? Theme.accentColor : Theme.textSecondary, lineWidth: 1.5)
                        .frame(width: 22, height: 22)

                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("legal_consent_toggle", comment: "Legal consent checkbox"))
            .accessibilityValue(isChecked ? "1" : "0")

            Text(agreementAttributedText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .tint(Theme.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                showDeclineMessage = true
            } label: {
                Text(NSLocalizedString("legal_decline", comment: "Decline legal consent"))
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
            .tint(Theme.textSecondary)

            Button {
                onAccept()
            } label: {
                Text(NSLocalizedString("legal_agree_continue", comment: "Accept legal consent"))
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentColor)
            .disabled(!isChecked)
        }
    }

    private var agreementAttributedText: AttributedString {
        let format = NSLocalizedString(
            "legal_consent_checkbox_markdown",
            comment: "Legal consent text with terms and privacy links"
        )
        let markdown = String(
            format: format,
            LegalDocuments.termsURL.absoluteString,
            LegalDocuments.privacyURL.absoluteString
        )
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}

#Preview {
    FirstLaunchLegalScreen(onAccept: { })
}
