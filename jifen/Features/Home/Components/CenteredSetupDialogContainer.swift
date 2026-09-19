import SwiftUI

private struct SetupDialogContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SetupDialogHeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SetupDialogActionsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 高度贴内容，不超过 maxHeight；内容较多时封顶并保持滚动。
/// 宿主（CenteredSetupDialogContainer/Presenter）用 fixedSize(vertical: true) 提出空提案，
/// ScrollView 才会收缩到内容高度；若宿主给出具体高度提案，这里仍会占满提案。
struct AdaptiveSetupDialogScrollView<Content: View>: View {
    let maxHeight: CGFloat
    private let content: Content
    private let bottomClearance: CGFloat

    @State private var measuredContentHeight: CGFloat = 0

    init(
        maxHeight: CGFloat,
        bottomClearance: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.maxHeight = maxHeight
        self.bottomClearance = bottomClearance
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: measuredContentHeight > maxHeight + 1) {
            content
                // Keep the final setting comfortably above the fixed start actions.
                .padding(.bottom, bottomClearance)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SetupDialogContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .frame(maxHeight: maxHeight)
        .onPreferenceChange(SetupDialogContentHeightPreferenceKey.self) { height in
            let roundedHeight = ceil(height)
            guard abs(measuredContentHeight - roundedHeight) > 0.5 else { return }
            measuredContentHeight = roundedHeight
        }
    }
}

/// 分别测量标题和操作区，剩余高度才交给可滚动内容，避免用固定预留值猜测高度。
struct AdaptiveSetupDialogLayout<Header: View, DialogContent: View, Actions: View>: View {
    let maxHeight: CGFloat
    private let header: Header
    private let dialogContent: (CGFloat) -> DialogContent
    private let actions: Actions

    @State private var measuredHeaderHeight: CGFloat = 56
    @State private var measuredActionsHeight: CGFloat = 88

    init(
        maxHeight: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: @escaping (CGFloat) -> DialogContent,
        @ViewBuilder actions: () -> Actions
    ) {
        self.maxHeight = maxHeight
        self.header = header()
        self.dialogContent = content
        self.actions = actions()
    }

    private var maxScrollableContentHeight: CGFloat {
        max(80, maxHeight - measuredHeaderHeight - measuredActionsHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SetupDialogHeaderHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }

            dialogContent(maxScrollableContentHeight)

            actions
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SetupDialogActionsHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .onPreferenceChange(SetupDialogHeaderHeightPreferenceKey.self) { height in
            updateMeasuredHeight(height, current: measuredHeaderHeight) {
                measuredHeaderHeight = $0
            }
        }
        .onPreferenceChange(SetupDialogActionsHeightPreferenceKey.self) { height in
            updateMeasuredHeight(height, current: measuredActionsHeight) {
                measuredActionsHeight = $0
            }
        }
    }

    private func updateMeasuredHeight(
        _ height: CGFloat,
        current: CGFloat,
        update: (CGFloat) -> Void
    ) {
        guard height > 0 else { return }
        let roundedHeight = ceil(height)
        guard abs(current - roundedHeight) > 0.5 else { return }
        update(roundedHeight)
    }
}

/// 居中 Setup Dialog 壳：与计分板操作菜单一致，遮罩和卡片直接出现、直接消失。
struct CenteredSetupDialogContainer<Content: View>: View {
    var allowsBackdropDismiss: Bool = true
    var onBackdropTap: () -> Void
    @ViewBuilder var content: (_ maxDialogHeight: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            let cardMaxHeight = max(280, proxy.size.height - 48)
            let cardWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                role: .setup
            )

            ZStack {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard allowsBackdropDismiss else { return }
                        onBackdropTap()
                    }

                content(cardMaxHeight)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: cardWidth)
                    .background(Theme.homeDialogBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
                    .contentShape(Rectangle())
                    .onTapGesture { }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 托管 binding：直接根据 item 插入或移除整块遮罩与 Dialog。
struct CenteredSetupDialogPresenter<Item: Identifiable, Content: View>: View {
    @Binding var item: Item?
    var allowsBackdropDismiss: Bool = true
    @ViewBuilder var content: (_ item: Item, _ dismiss: @escaping () -> Void, _ maxDialogHeight: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            let cardMaxHeight = max(280, proxy.size.height - 48)
            let cardWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                role: .setup
            )

            ZStack {
                if let item {
                    Color.black.opacity(0.48)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .transition(.opacity)
                        .onTapGesture {
                            guard allowsBackdropDismiss else { return }
                            requestDismiss()
                        }

                    content(item, requestDismiss, cardMaxHeight)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: cardWidth)
                        .background(Theme.homeDialogBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
                        .contentShape(Rectangle())
                        .onTapGesture { }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: item?.id)
        }
        .allowsHitTesting(item != nil)
    }

    private func requestDismiss() {
        item = nil
    }
}
