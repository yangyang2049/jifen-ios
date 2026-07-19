import SwiftUI

private struct SetupDialogContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 内容较少时按实际高度收紧，内容较多时限制到可用高度并保持滚动。
struct AdaptiveSetupDialogScrollView<Content: View>: View {
    let maxHeight: CGFloat
    private let content: Content

    @State private var measuredContentHeight: CGFloat = 0

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    private var resolvedHeight: CGFloat? {
        guard measuredContentHeight > 0 else { return nil }
        return min(measuredContentHeight, maxHeight)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SetupDialogContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .frame(height: resolvedHeight)
        .frame(maxHeight: maxHeight)
        .onPreferenceChange(SetupDialogContentHeightPreferenceKey.self) { height in
            let roundedHeight = ceil(height)
            guard abs(measuredContentHeight - roundedHeight) > 0.5 else { return }
            measuredContentHeight = roundedHeight
        }
    }
}

/// 居中 Setup Dialog 壳：遮罩独立淡入，卡片 scale-up。
/// 用 overlay 展示，避免 fullScreenCover 自下而上的系统动画。
struct CenteredSetupDialogContainer<Content: View>: View {
    var allowsBackdropDismiss: Bool = true
    var onBackdropTap: () -> Void
    @ViewBuilder var content: (_ maxContentHeight: CGFloat) -> Content

    @State private var appeared = false

    private let animation = Animation.easeOut(duration: 0.2)
    private let headerAndActionsReserve: CGFloat = 160

    var body: some View {
        GeometryReader { proxy in
            let cardMaxHeight = max(280, proxy.size.height - 48)
            let maxContentHeight = max(120, cardMaxHeight - headerAndActionsReserve)

            ZStack {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard allowsBackdropDismiss else { return }
                        onBackdropTap()
                    }

                content(maxContentHeight)
                    .frame(width: min(340, proxy.size.width - 32))
                    .frame(maxHeight: cardMaxHeight)
                    .background(Theme.homeDialogBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(animation) {
                appeared = true
            }
        }
    }
}

/// 托管 binding：打开时 scale-up，关闭时先播退出动画再清空 item。
struct CenteredSetupDialogPresenter<Item: Identifiable, Content: View>: View {
    @Binding var item: Item?
    var allowsBackdropDismiss: Bool = true
    @ViewBuilder var content: (_ item: Item, _ dismiss: @escaping () -> Void, _ maxContentHeight: CGFloat) -> Content

    @State private var visibleItem: Item?
    @State private var appeared = false

    private let animation = Animation.easeOut(duration: 0.2)
    private let dismissDuration: TimeInterval = 0.18
    private let headerAndActionsReserve: CGFloat = 160

    var body: some View {
        GeometryReader { proxy in
            let cardMaxHeight = max(280, proxy.size.height - 48)
            let maxContentHeight = max(120, cardMaxHeight - headerAndActionsReserve)

            ZStack {
                if let visibleItem {
                    Color.black.opacity(0.48)
                        .ignoresSafeArea()
                        .opacity(appeared ? 1 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard allowsBackdropDismiss else { return }
                            requestDismiss()
                        }

                    content(visibleItem, requestDismiss, maxContentHeight)
                        .frame(width: min(340, proxy.size.width - 32))
                        .frame(maxHeight: cardMaxHeight)
                        .background(Theme.homeDialogBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
                        .scaleEffect(appeared ? 1 : 0.92)
                        .opacity(appeared ? 1 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture { }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(visibleItem != nil)
        .onAppear {
            if let item {
                present(item)
            }
        }
        .onChange(of: item?.id) { _, newId in
            if let item, newId != nil {
                present(item)
            } else if newId == nil, visibleItem != nil, appeared {
                animateOutThenClearVisible()
            }
        }
    }

    private func present(_ newItem: Item) {
        visibleItem = newItem
        appeared = false
        withAnimation(animation) {
            appeared = true
        }
    }

    private func requestDismiss() {
        guard appeared else {
            visibleItem = nil
            item = nil
            return
        }
        withAnimation(.easeOut(duration: dismissDuration)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDuration) {
            visibleItem = nil
            item = nil
        }
    }

    private func animateOutThenClearVisible() {
        withAnimation(.easeOut(duration: dismissDuration)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDuration) {
            visibleItem = nil
        }
    }
}
