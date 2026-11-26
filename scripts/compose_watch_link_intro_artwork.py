#!/usr/bin/env python3
"""合成手表联动介绍弹层的原版设备 hero 图（Apple Design Resources 官方机身）。

素材来自 Apple Design Resources 的官方机身 PNG（iPhone 17 Landscape / Apple Watch Ultra 4），
屏幕内容是 App 自身在模拟器上的真实截图（手机端乒乓球计分板、手表端同一计分板）。
脚本只做像素级合成：把截图嵌在官方机身透明屏口之下，再将完整官方机身（含灵动岛、圆角抗锯齿与表冠表带）
alpha_composite 叠回上层，不做任何外壳重绘。

用法：
    python3 scripts/compose_watch_link_intro_artwork.py \
        --phone-bezel "/Volumes/Bezel-iPhone-17/PNG/iPhone 17/iPhone 17 - Sage - Landscape.png" \
        --watch-bezel "/Volumes/Bezel-Apple-Watch-Ultra-4-2026/PNG/AW Ultra 4 - Natural + Ocean Band Translucent Gray.png" \
        --phone-screen <phone.png> --watch-screen <watch.png> \
        --output <out@3x.png> [--output-2x <out@2x.png>]

输出：1068x798（356x266 pt @3x）透明 PNG（及可选 712x532 @2x），供 Assets.xcassets 使用。
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

CANVAS_WIDTH = 1068
CANVAS_HEIGHT = 798
CANVAS_2X_SIZE = (712, 532)
SUPERSAMPLE = 2

# Option A 版面参数（以最终 1068x798 画布为基准，脚本内自动乘 SUPERSAMPLE）。
PHONE_WIDTH = 830.0
PHONE_ANGLE = 5.5          # PIL 正角度为逆时针旋转（对应 CSS -5.5deg）
PHONE_X = 36.0
PHONE_Y = 32.0
PHONE_SHADOW_BLUR = 14.0
PHONE_SHADOW_OPACITY = 0.18
PHONE_SHADOW_OFFSET = (0.0, 8.0)

WATCH_WIDTH = 296.0
WATCH_ANGLE = -8.5         # PIL 负角度为顺时针旋转（对应 CSS +8.5deg）
WATCH_X = 682.0
WATCH_Y = 282.0
WATCH_SHADOW_BLUR = 16.0
WATCH_SHADOW_OPACITY = 0.26
WATCH_SHADOW_OFFSET = (-4.0, 10.0)


def screen_mask(bezel: Image.Image) -> Image.Image:
    """机身 PNG 中间的透明屏口，用中心洪水填充取出精确形状（含圆角，绕过灵动岛）。"""
    alpha = np.array(bezel)[:, :, 3]
    height, width = alpha.shape
    open_area = alpha < 8
    seen = np.zeros_like(open_area)
    stack = [(height // 2, width // 2)]
    seen[height // 2, width // 2] = True
    while stack:
        y, x = stack.pop()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < height and 0 <= nx < width and open_area[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                stack.append((ny, nx))
    mask = (seen * 255).astype(np.uint8)
    return Image.fromarray(mask)


def mask_bbox(mask: Image.Image) -> tuple[int, int, int, int]:
    arr = np.array(mask)
    ys, xs = np.where(arr > 0)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def fit_bezel(bezel: Image.Image, screen: Image.Image, target_width: float) -> Image.Image:
    """将真实截图精确嵌入官方机身透明屏口之下，再用官方机身 alpha_composite 叠回上层。"""
    mask = screen_mask(bezel)
    left, top, right, bottom = mask_bbox(mask)
    slot_w, slot_h = right - left, bottom - top

    shot = screen.convert("RGBA")
    if (shot.width < shot.height) != (slot_w < slot_h):
        shot = shot.transpose(Image.Transpose.ROTATE_90)
    if shot.size != (slot_w, slot_h):
        shot = shot.resize((slot_w, slot_h), Image.LANCZOS)

    # 外扩 2px 让屏幕边缘稳妥压入不透明黑边下方，彻底消除抗锯齿白边或漏缝。
    dilated_mask = mask.filter(ImageFilter.MaxFilter(5))
    screen_canvas = Image.new("RGBA", bezel.size, (0, 0, 0, 0))
    screen_canvas.paste(shot, (left, top))

    layer = Image.new("RGBA", bezel.size, (0, 0, 0, 0))
    layer.paste(screen_canvas, (0, 0), dilated_mask)
    layer.alpha_composite(bezel)

    scale = target_width / layer.width
    size = (max(1, round(layer.width * scale)), max(1, round(layer.height * scale)))
    return layer.resize(size, Image.LANCZOS)


def drop_shadow(alpha: Image.Image, blur: float, opacity: float) -> Image.Image:
    pad = int(np.ceil(blur * 3))
    padded = Image.new("L", (alpha.width + pad * 2, alpha.height + pad * 2), 0)
    padded.paste(alpha, (pad, pad))
    shadow = padded.filter(ImageFilter.GaussianBlur(blur))
    shadow = shadow.point(lambda value: int(value * opacity))
    layer = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    layer.putalpha(shadow)
    return layer, pad


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phone-bezel", required=True)
    parser.add_argument("--watch-bezel", required=True)
    parser.add_argument("--phone-screen", required=True)
    parser.add_argument("--watch-screen", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--output-2x")
    args = parser.parse_args()

    k = SUPERSAMPLE
    canvas = Image.new("RGBA", (CANVAS_WIDTH * k, CANVAS_HEIGHT * k), (0, 0, 0, 0))

    phone = fit_bezel(
        Image.open(args.phone_bezel).convert("RGBA"),
        Image.open(args.phone_screen),
        PHONE_WIDTH * k,
    ).rotate(PHONE_ANGLE, resample=Image.BICUBIC, expand=True)

    watch = fit_bezel(
        Image.open(args.watch_bezel).convert("RGBA"),
        Image.open(args.watch_screen),
        WATCH_WIDTH * k,
    ).rotate(WATCH_ANGLE, resample=Image.BICUBIC, expand=True)

    phone_x, phone_y = round(PHONE_X * k), round(PHONE_Y * k)
    watch_x, watch_y = round(WATCH_X * k), round(WATCH_Y * k)

    phone_shadow, phone_pad = drop_shadow(phone.getchannel("A"), PHONE_SHADOW_BLUR * k, PHONE_SHADOW_OPACITY)
    canvas.alpha_composite(
        phone_shadow,
        (phone_x - phone_pad + round(PHONE_SHADOW_OFFSET[0] * k), phone_y - phone_pad + round(PHONE_SHADOW_OFFSET[1] * k)),
    )
    canvas.alpha_composite(phone, (phone_x, phone_y))

    watch_shadow, watch_pad = drop_shadow(watch.getchannel("A"), WATCH_SHADOW_BLUR * k, WATCH_SHADOW_OPACITY)
    canvas.alpha_composite(
        watch_shadow,
        (watch_x - watch_pad + round(WATCH_SHADOW_OFFSET[0] * k), watch_y - watch_pad + round(WATCH_SHADOW_OFFSET[1] * k)),
    )
    canvas.alpha_composite(watch, (watch_x, watch_y))

    final_3x = canvas.resize((CANVAS_WIDTH, CANVAS_HEIGHT), Image.LANCZOS)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    final_3x.save(output)

    if args.output_2x:
        out_2x = Path(args.output_2x)
        out_2x.parent.mkdir(parents=True, exist_ok=True)
        final_3x.resize(CANVAS_2X_SIZE, Image.LANCZOS).save(out_2x)

    alpha = np.array(final_3x.getchannel("A"))
    ys, xs = np.where(alpha > 8)
    margin = min(int(xs.min()), int(ys.min()), CANVAS_WIDTH - 1 - int(xs.max()), CANVAS_HEIGHT - 1 - int(ys.max()))
    print(
        f"phone {phone.size} at ({phone_x},{phone_y}); "
        f"watch {watch.size} at ({watch_x},{watch_y}); "
        f"bbox=({xs.min()},{ys.min()})..({xs.max()},{ys.max()}) min_margin={margin}px -> {output}"
    )


if __name__ == "__main__":
    main()
