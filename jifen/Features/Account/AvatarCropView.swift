import SwiftUI
import UIKit

/// 1:1 头像裁剪的纯数学（视图与渲染共用，单元测试直接覆盖这层）。
nonisolated enum AvatarCropGeometry {
    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 5
    static let outputSide: CGFloat = 1024

    static func fillScale(imageSize: CGSize, side: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, side > 0 else { return 1 }
        return max(side / imageSize.width, side / imageSize.height)
    }

    /// zoom=1 时图片按 cover 适配裁剪框后的显示尺寸。
    static func baseDisplaySize(imageSize: CGSize, side: CGFloat) -> CGSize {
        let fill = fillScale(imageSize: imageSize, side: side)
        return CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
    }

    /// 拖拽偏移的单轴上限：保证缩放后的图片始终覆盖裁剪框。
    static func offsetLimit(imageSize: CGSize, side: CGFloat, zoom: CGFloat) -> CGSize {
        let base = baseDisplaySize(imageSize: imageSize, side: side)
        let clampedZoom = min(max(zoom, minZoom), maxZoom)
        return CGSize(
            width: max(0, (base.width * clampedZoom - side) / 2),
            height: max(0, (base.height * clampedZoom - side) / 2)
        )
    }

    static func clamp(offset: CGSize, limit: CGSize) -> CGSize {
        CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
    }

    static func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }

    /// 把当前「缩放+偏移」状态渲染成 outputSide×outputSide 的正方形图片。
    static func croppedImage(
        from source: UIImage,
        side: CGFloat,
        zoom: CGFloat,
        offset: CGSize,
        outputSide: CGFloat = outputSide
    ) -> UIImage? {
        guard side > 0, source.size.width > 0, source.size.height > 0 else { return nil }
        let base = baseDisplaySize(imageSize: source.size, side: side)
        let drawSize = CGSize(width: base.width * zoom, height: base.height * zoom)
        let scale = outputSide / side
        let origin = CGPoint(
            x: ((side - drawSize.width) / 2 + offset.width) * scale,
            y: ((side - drawSize.height) / 2 + offset.height) * scale
        )
        let pixelSize = CGSize(width: drawSize.width * scale, height: drawSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputSide, height: outputSide),
            format: format
        )
        return renderer.image { _ in
            source.draw(in: CGRect(origin: origin, size: pixelSize))
        }
    }
}

/// PhotosPicker/相机 → 裁剪 sheet 的呈现载体（sheet(item:) 需要 Identifiable）。
nonisolated struct AvatarCropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 黑底 55% 遮罩 + 正方形裁剪窗（圆形参考线），底部贴近「取消/完成」。
/// 手势：双指缩放 [1,5] + 拖拽，越界按 offsetLimit 钳制，手势结束即固化基线。
struct AvatarCropView: View {
    let source: UIImage
    /// 上传中：完成按钮转 loading 并锁按钮，sheet 保持打开直到结果返回。
    var isBusy: Bool = false
    var cancelButtonTitle: String = NSLocalizedString("cancel", value: "取消", comment: "")
    var confirmButtonTitle: String = NSLocalizedString(
        "me_profile_avatar_crop_confirm",
        value: "完成",
        comment: ""
    )
    var title: String = NSLocalizedString(
        "me_profile_avatar_crop_title",
        value: "调整头像",
        comment: ""
    )
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    @State private var zoom: CGFloat = AvatarCropGeometry.minZoom
    @State private var offset: CGSize = .zero
    @State private var zoomBaseline: CGFloat = AvatarCropGeometry.minZoom
    @State private var offsetBaseline: CGSize = .zero
    @State private var cropSide: CGFloat = 0

    var body: some View {
        ZStack {
            // 独立可测标识：直接打在根容器上会把 identifier 传染给全部子按钮
            //（XCUITest 反查 profile_avatar_crop_* 失效的实测教训）。
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier("profile_avatar_crop_root")
            mainContent
        }
        // 裁剪编辑器用不透明纯黑：半透明黑会叠出 sheet 系统材质的灰底
        .background(Color.black.ignoresSafeArea())
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            cropWindow
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
    }

    private var cropWindow: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - 32
            ZStack {
                Color.clear
                ZStack {
                    Image(uiImage: source)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .scaleEffect(zoom)
                        .offset(offset)
                }
                .frame(width: side, height: side)
                .clipped()
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                .overlay(Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .gesture(magnificationGesture.simultaneously(with: dragGesture))
            }
            .onAppear { cropSide = side }
            .onChange(of: geo.size) { _, _ in
                let newSide = min(geo.size.width, geo.size.height) - 32
                cropSide = newSide
                rebaseOffset(side: newSide)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button(action: onCancel) {
                Text(cancelButtonTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .disabled(isBusy)
            .accessibilityIdentifier("profile_avatar_crop_cancel")

            Spacer()

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            Spacer()

            Button {
                guard let cropped = AvatarCropGeometry.croppedImage(
                    from: source,
                    side: cropSide,
                    zoom: zoom,
                    offset: offset
                ) else {
                    onCancel()
                    return
                }
                onConfirm(cropped)
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(confirmButtonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white))
            }
            .disabled(isBusy)
            .accessibilityIdentifier("profile_avatar_crop_confirm")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = AvatarCropGeometry.clampZoom(zoomBaseline * value)
                clampCurrentOffset()
            }
            .onEnded { _ in
                zoomBaseline = zoom
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = AvatarCropGeometry.clamp(
                    offset: CGSize(
                        width: offsetBaseline.width + value.translation.width,
                        height: offsetBaseline.height + value.translation.height
                    ),
                    limit: AvatarCropGeometry.offsetLimit(
                        imageSize: source.size,
                        side: cropSide,
                        zoom: zoom
                    )
                )
            }
            .onEnded { _ in
                offsetBaseline = offset
            }
    }

    private func clampCurrentOffset() {
        offset = AvatarCropGeometry.clamp(
            offset: offset,
            limit: AvatarCropGeometry.offsetLimit(
                imageSize: source.size,
                side: cropSide,
                zoom: zoom
            )
        )
        offsetBaseline = offset
    }

    private func rebaseOffset(side: CGFloat) {
        guard side > 0 else { return }
        offset = AvatarCropGeometry.clamp(
            offset: offset,
            limit: AvatarCropGeometry.offsetLimit(imageSize: source.size, side: side, zoom: zoom)
        )
        offsetBaseline = offset
    }
}
