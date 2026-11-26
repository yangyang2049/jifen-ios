#!/usr/bin/env python3
"""合成手表端竖屏宣传片（1080x1920，30fps，15 秒）。

素材全部来自真实 App：
- 屏幕内容：`WatchPromoVideoCaptureUITests` 在 Apple Watch Ultra 4 模拟器上的真实截图；
- 机身：Apple Design Resources 官方 Ultra 4 机身 PNG；
- 联动镜头：`WatchLinkIntroArtwork-zh-Hans`（手机 + 手表真实计分板合成图）；
- 项目图标：App 自带 3D 运动图标。

脚本只做逐帧合成、文字动效与配乐合成，不重绘任何 App 界面。

用法：
    python3 scripts/compose_watch_promo_video.py \\
        --shots-dir <导出的截图附件目录> \\
        --output marketing/watch-promo-2026-11-26/watch-promo-zh-Hans.mp4
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compose_watch_link_intro_artwork import mask_bbox, screen_mask  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
W, H, FPS, DURATION = 1080, 1920, 30, 15.0
SAMPLE_RATE = 48000
BPM = 120
BEAT = 60.0 / BPM

FONT_PATH = (
    "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/"
    "86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"
)
FONT_SC = {"regular": 3, "medium": 7, "semibold": 11, "light": 15}

DEFAULT_BEZEL = "/Volumes/Bezel-Apple-Watch-Ultra-4-2026/PNG/AW Ultra 4 - Natural + Ocean Band Translucent Gray.png"
DEFAULT_LINK_ART = ROOT / "jifen/Assets.xcassets/WatchLinkIntroArtwork-zh-Hans.imageset/WatchLinkIntroArtwork-zh-Hans@3x.png"
DEFAULT_APP_ICON = ROOT / "jifenWatch Watch App/Assets.xcassets/watch_app_icon.imageset/watch_app_icon.png"
ICON_DIR = ROOT / "jifen/Assets.xcassets"
ORBIT_ICONS = [
    "icon_3d_badminton", "icon_3d_tennis", "icon_3d_pingpong", "icon_3d_eight_ball",
    "icon_3d_archery", "icon_3d_football", "icon_3d_pickleball", "icon_3d_basketball",
]

RED = (229, 57, 53)
BLUE = (30, 136, 229)
GREEN = (48, 209, 88)
TEXT_DIM = (178, 186, 194)

# 时间线（秒，均落在 120 BPM 的拍点上）。
T_SPORTS = 2.5
T_SCORE = 5.0
TAPS = [(6.0, True), (6.5, False), (7.0, True), (7.5, False), (8.0, True)]
T_GAME_END = 8.45
T_MONTAGE = 9.0
MONTAGE_STEP = 0.5
T_LINK = 11.0
T_END = 13.0


# ---------------------------------------------------------------- 工具函数

def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def progress(t: float, start: float, length: float) -> float:
    return clamp((t - start) / length)


def ease_out_cubic(x: float) -> float:
    return 1 - (1 - x) ** 3


def ease_in_out_cubic(x: float) -> float:
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def ease_out_back(x: float, s: float = 1.7) -> float:
    x -= 1
    return 1 + (s + 1) * x ** 3 + s * x ** 2


def lerp(a: float, b: float, x: float) -> float:
    return a + (b - a) * x


_font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    key = (weight, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(FONT_PATH, size, index=FONT_SC[weight])
    return _font_cache[key]


def with_alpha(img: Image.Image, alpha: float) -> Image.Image:
    if alpha >= 0.999:
        return img
    out = img.copy()
    a = out.getchannel("A").point(lambda v: int(v * alpha))
    out.putalpha(a)
    return out


def paste_center(canvas: Image.Image, sprite: Image.Image, cx: float, cy: float, alpha: float = 1.0) -> None:
    if alpha <= 0.001:
        return
    sprite = with_alpha(sprite, alpha)
    canvas.alpha_composite(sprite, (int(round(cx - sprite.width / 2)), int(round(cy - sprite.height / 2))))


def transform(sprite: Image.Image, scale: float, angle: float = 0.0) -> Image.Image:
    size = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
    out = sprite.resize(size, Image.LANCZOS)
    if abs(angle) > 0.01:
        out = out.rotate(angle, resample=Image.BICUBIC, expand=True)
    return out


def text_sprite(text: str, weight: str, size: int, color: tuple[int, int, int]) -> Image.Image:
    f = font(weight, size)
    left, top, right, bottom = f.getbbox(text)
    pad = 8
    img = Image.new("RGBA", (right - left + pad * 2, bottom - top + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((pad - left, pad - top), text, font=f, fill=color + (255,))
    return img


# ---------------------------------------------------------------- 素材

class Watch:
    """官方 Ultra 4 机身 + 真实屏幕截图的叠层（屏幕压在机身透明屏口之下）。"""

    def __init__(self, bezel_path: str) -> None:
        self.bezel = Image.open(bezel_path).convert("RGBA")
        mask = screen_mask(self.bezel)
        self.left, self.top, right, bottom = mask_bbox(mask)
        self.slot = (right - self.left, bottom - self.top)
        self.mask = mask.filter(ImageFilter.MaxFilter(5))
        alpha = self.bezel.getchannel("A")
        pad = 60
        padded = Image.new("L", (self.bezel.width + pad * 2, self.bezel.height + pad * 2), 0)
        padded.paste(alpha, (pad, pad))
        shadow = padded.filter(ImageFilter.GaussianBlur(26)).point(lambda v: int(v * 0.55))
        self.shadow = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
        self.shadow.putalpha(shadow)
        self.shadow_pad = pad

    def compose(self, screen: Image.Image) -> Image.Image:
        shot = screen.convert("RGBA")
        if shot.size != self.slot:
            shot = shot.resize(self.slot, Image.LANCZOS)
        under = Image.new("RGBA", self.bezel.size, (0, 0, 0, 0))
        under.paste(shot, (self.left, self.top))
        layer = Image.new("RGBA", self.bezel.size, (0, 0, 0, 0))
        layer.paste(under, (0, 0), self.mask)
        layer.alpha_composite(self.bezel)
        # 合入投影，保证缩放旋转时投影与机身一致。
        full = self.shadow.copy()
        full.alpha_composite(layer, (self.shadow_pad, self.shadow_pad + 0))
        return full

    @property
    def screen_center_offset(self) -> tuple[float, float]:
        """屏幕中心相对整张叠层中心的偏移（未缩放）。"""
        full_w = self.bezel.width + self.shadow_pad * 2
        full_h = self.bezel.height + self.shadow_pad * 2
        sx = self.shadow_pad + self.left + self.slot[0] / 2
        sy = self.shadow_pad + self.top + self.slot[1] / 2
        return sx - full_w / 2, sy - full_h / 2


def load_shots(shots_dir: Path) -> dict[str, Image.Image]:
    shots: dict[str, Image.Image] = {}
    for path in sorted(shots_dir.glob("promo_*.png")):
        name = path.stem.split("_", 2)[2]
        shots[name] = Image.open(path).convert("RGBA")
    return shots


def find_shift(upper: np.ndarray, lower: np.ndarray, top: int = 170, bottom: int = 470) -> int:
    """lower 相对 upper 向上滚动的像素数（两张真实截图的列表区逐行比对）。"""
    best, best_err = 0, float("inf")
    ys = np.arange(top, bottom)
    for shift in range(0, bottom - top - 60):
        src = ys + shift
        ok = src < bottom
        err = float(np.abs(lower[ys[ok]] - upper[src[ok]]).mean())
        if err < best_err:
            best, best_err = shift, err
    return best


class ScrollStrip:
    """把首页逐步滚动的真实截图按精确偏移拼成长条，生成平滑滚动画面。

    录屏工具在数码表冠滚动时只写入少量关键帧，无法直接使用；这里所有像素仍来自真实截图，
    顶部用模糊渐隐模拟列表滑入标题下方，标题与分页点取自首页截图原样叠回。
    """

    LIST_TOP, LIST_BOTTOM, HEADER_BOTTOM = 150, 480, 120

    def __init__(self, shots: list[Image.Image]) -> None:
        arrays = [np.asarray(img.convert("RGB"), dtype=np.float32) for img in shots]
        gray = [a.mean(axis=2) for a in arrays]
        offsets = [0]
        for upper, lower in zip(gray, gray[1:]):
            offsets.append(offsets[-1] + find_shift(upper, lower))
        self.total = offsets[-1]
        h, w = arrays[0].shape[:2]
        self.size = (w, h)
        strip = np.zeros((h + self.total, w, 3), dtype=np.float32)
        for arr, off in zip(arrays, offsets):
            strip[self.LIST_TOP + off:h + off] = arr[self.LIST_TOP:h]
        self.strip = strip
        top = arrays[0]
        self.header = top[: self.HEADER_BOTTOM]
        dots = top[485:]
        lum = dots.mean(axis=2)
        spread = dots.max(axis=2) - dots.min(axis=2)
        mask = np.zeros_like(lum)
        mask[:, w // 2 - 70: w // 2 + 70] = 1
        self.dots_mask = ((lum > 55) & (spread < 25) * 1 > 0) * mask
        self.dots = dots
        ramp = np.clip((np.arange(self.LIST_TOP) - 20) / (self.LIST_TOP - 20), 0, 1)
        self.fade = (0.12 + 0.88 * ramp ** 1.6)[:, None, None]
        self.blur_mix = (1 - ramp)[:, None, None]

    def render(self, offset: float) -> Image.Image:
        w, h = self.size
        o = int(round(clamp(offset, 0, self.total)))
        view = self.strip[o:o + h].copy()
        top = view[: self.LIST_TOP]
        blurred = np.asarray(Image.fromarray(top.astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)), np.float32)
        view[: self.LIST_TOP] = (top * (1 - self.blur_mix) + blurred * self.blur_mix) * self.fade
        view[: self.HEADER_BOTTOM] = np.maximum(view[: self.HEADER_BOTTOM], self.header)
        bottom = view[485:]
        m = self.dots_mask[..., None]
        view[485:] = bottom * (1 - m) + self.dots * m
        return Image.fromarray(np.clip(view, 0, 255).astype(np.uint8)).convert("RGBA")


def rounded_icon(path: Path, size: int) -> Image.Image:
    icon = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * 0.225), fill=255)
    icon.putalpha(mask.resize((size, size), Image.LANCZOS))
    return icon


def pill(text: str, color: tuple[int, int, int], size: int = 54,
         text_color: tuple[int, int, int] = (255, 255, 255)) -> Image.Image:
    label = text_sprite(text, "semibold", size, text_color)
    w, h = label.width + 44, label.height + 18
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=color + (255,))
    img.alpha_composite(label, ((w - label.width) // 2, (h - label.height) // 2))
    return img


# ---------------------------------------------------------------- 背景

def radial(cx: float, cy: float, radius: float, color: tuple[int, int, int], strength: float,
           xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / radius
    falloff = np.clip(1 - d, 0, 1) ** 2 * strength
    return falloff[..., None] * np.array(color, dtype=np.float32)[None, None, :]


def background(t: float, xs: np.ndarray, ys: np.ndarray, scale: int) -> Image.Image:
    base = np.full(xs.shape + (3,), (6, 8, 11), dtype=np.float32)
    drift = math.sin(t * 0.6) * 40
    end_mix = progress(t, T_END - 0.3, 0.6)
    red_strength = 0.34 * (1 - 0.4 * end_mix)
    blue_strength = 0.34 * (1 - 0.4 * end_mix)
    base += radial((180 + drift) / scale, (420 - drift) / scale, 980 / scale, RED, red_strength, xs, ys)
    base += radial((900 - drift) / scale, (1500 + drift) / scale, 980 / scale, BLUE, blue_strength, xs, ys)
    base += radial(540 / scale, 1000 / scale, 700 / scale, GREEN, 0.10 * end_mix, xs, ys)
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    return img.convert("RGBA")


# ---------------------------------------------------------------- 文案

class Caption:
    def __init__(self, title: str, subtitle: str, start: float, end: float, title_size: int = 88) -> None:
        self.title = text_sprite(title, "semibold", title_size, (255, 255, 255))
        self.subtitle = text_sprite(subtitle, "regular", 46, TEXT_DIM) if subtitle else None
        self.start, self.end = start, end

    def draw(self, canvas: Image.Image, t: float, y: float = 300) -> None:
        if t < self.start or t > self.end + 0.35:
            return
        enter = ease_out_cubic(progress(t, self.start, 0.45))
        sub_enter = ease_out_cubic(progress(t, self.start + 0.12, 0.45))
        leave = ease_in_out_cubic(progress(t, self.end, 0.3))
        alpha = enter * (1 - leave)
        offset = (1 - enter) * 46 - leave * 30
        paste_center(canvas, self.title, W / 2, y + offset, alpha)
        if self.subtitle is not None:
            sub_alpha = sub_enter * (1 - leave)
            paste_center(canvas, self.subtitle, W / 2, y + 100 + (1 - sub_enter) * 46 - leave * 30, sub_alpha)


# ---------------------------------------------------------------- 主合成

class Promo:
    def __init__(self, args: argparse.Namespace) -> None:
        self.watch = Watch(args.watch_bezel)
        self.shots = load_shots(Path(args.shots_dir))
        scroll_keys = ["home_top"] + sorted(
            (k for k in self.shots if k.startswith("home_scroll_")), key=lambda k: int(k.rsplit("_", 1)[1]))
        self.scroll = ScrollStrip([self.shots[k] for k in scroll_keys])
        self.link_art = Image.open(args.link_artwork).convert("RGBA")
        self.app_icon = rounded_icon(Path(args.app_icon), 288)
        self.orbit = []
        for name in ORBIT_ICONS:
            files = sorted((ICON_DIR / f"{name}.imageset").glob("*@3x.png"))
            if files:
                self.orbit.append(Image.open(files[0]).convert("RGBA").resize((168, 168), Image.LANCZOS))
        self.montage = [(label, self.shots[key]) for label, key in args.montage if key in self.shots]
        self.tap_screens = [self.shots[f"pp_step_{i}"] for i in range(len(TAPS))]
        self.cache: dict[int, Image.Image] = {}
        scale = 4
        ys, xs = np.mgrid[0:H // scale, 0:W // scale].astype(np.float32)
        self.bg_grid = (xs, ys, scale)

        self.captions = [
            Caption("比分，戴在手腕上", "全能计分器 · Apple Watch 版", 0.35, T_SPORTS - 0.3),
            Caption("多项运动，抬腕即开赛", "羽毛球 · 网球 · 乒乓球 · 台球 · 射箭 · 足球", T_SPORTS + 0.05, T_SCORE - 0.3),
            Caption("轻点一下，比分 +1", "左右半屏各管一方，单手也能记", T_SCORE + 0.15, TAPS[-1][0] - 0.3),
            Caption("自动判局，专心比赛", "拿下一局，自动进入局间休息", TAPS[-1][0] + 0.05, T_MONTAGE - 0.3),
            Caption("每项运动，专属计分板", "", T_MONTAGE + 0.05, T_LINK - 0.3),
            Caption("与 iPhone 实时同步", "手腕上记分，手机上同步显示", T_LINK + 0.05, T_END - 0.3),
        ]
        self.end_title = text_sprite("全能计分器", "semibold", 96, (255, 255, 255))
        self.end_sub = text_sprite("现已支持 Apple Watch", "medium", 46, GREEN)
        self.hide_store_hint = args.hide_store_hint
        self.end_hint = text_sprite("App Store 搜索「全能计分器」", "regular", 38, TEXT_DIM)
        self.plus_left = pill("+1", (255, 255, 255), 58, RED)
        self.plus_right = pill("+1", (255, 255, 255), 58, BLUE)
        self.labels = {label: pill(label, (58, 63, 72), 42) for label, _ in self.montage}

    # 屏幕内容 -----------------------------------------------------------
    def screen_at(self, t: float) -> tuple[Image.Image, str]:
        if t < T_SPORTS:
            return self.shots["home_top"], "home_top"
        if t < T_SCORE:
            x = ease_in_out_cubic(progress(t, T_SPORTS + 0.2, T_SCORE - T_SPORTS - 0.45))
            return self.scroll.render(x * self.scroll.total), f"scroll_{int(t * FPS)}"
        if t < T_MONTAGE:
            screen, key = self.shots["pp_8_7"], "pp_8_7"
            for i, (tap_t, _) in enumerate(TAPS):
                if t >= tap_t:
                    screen, key = self.tap_screens[i], f"pp_step_{i}"
            return screen, key
        index = min(len(self.montage) - 1, int((t - T_MONTAGE) / MONTAGE_STEP))
        return self.montage[index][1], f"montage_{index}"

    def screen_with_effects(self, t: float) -> tuple[Image.Image, str]:
        screen, key = self.screen_at(t)
        # 乒乓 → 首页切换的屏内交叉淡化。
        if T_SCORE <= t < T_SCORE + 0.2:
            prev, _ = self.screen_at(T_SCORE - 0.01)
            screen = Image.blend(prev.convert("RGBA"), screen.convert("RGBA"), progress(t, T_SCORE, 0.2))
            key = f"xfade_{int(t * FPS)}"
        # 快剪之间的屏内横推。
        if t >= T_MONTAGE:
            local = (t - T_MONTAGE) % MONTAGE_STEP
            index = int((t - T_MONTAGE) / MONTAGE_STEP)
            if 0 < index < len(self.montage) and local < 0.14:
                x = ease_in_out_cubic(local / 0.14)
                prev = self.montage[index - 1][1]
                width = screen.width
                pushed = Image.new("RGBA", screen.size, (0, 0, 0, 255))
                pushed.alpha_composite(prev, (int(-x * width), 0))
                pushed.alpha_composite(screen, (int((1 - x) * width), 0))
                screen, key = pushed, f"push_{int(t * FPS)}"
        # 点按涟漪。
        for tap_t, left in TAPS:
            p = progress(t, tap_t, 0.38)
            if 0 < p < 1:
                screen = screen.copy()
                overlay = Image.new("RGBA", screen.size, (0, 0, 0, 0))
                draw = ImageDraw.Draw(overlay)
                cx = screen.width * (0.25 if left else 0.75)
                cy = screen.height * 0.55
                r = 26 + ease_out_cubic(p) * 110
                alpha = int(150 * (1 - p))
                draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, alpha // 2),
                             outline=(255, 255, 255, alpha), width=5)
                dot = 30 * (1 - p)
                draw.ellipse((cx - dot, cy - dot, cx + dot, cy + dot), fill=(255, 255, 255, int(200 * (1 - p))))
                screen.alpha_composite(overlay)
                key = f"tap_{int(t * FPS)}"
        return screen, key

    def watch_layer(self, t: float) -> Image.Image:
        screen, key = self.screen_with_effects(t)
        if key.startswith(("home_top", "pp_", "montage_")) and key in self.cache:
            return self.cache[key]
        layer = self.watch.compose(screen)
        if key.startswith(("home_top", "pp_", "montage_")):
            self.cache[key] = layer
        return layer

    # 机位 -------------------------------------------------------------
    def watch_pose(self, t: float) -> tuple[float, float, float, float, float]:
        """返回 (cx, cy, scale, angle, alpha)。"""
        enter = ease_out_cubic(progress(t, 0.0, 1.1))
        cx, cy = W / 2, lerp(1600, 1140, enter)
        scale = lerp(0.95, 1.22, enter)
        angle = lerp(9, 0, enter)
        alpha = progress(t, 0.0, 0.35)
        # 运动项目：略微后退给图标让位。
        scale = lerp(scale, 1.10, ease_in_out_cubic(progress(t, T_SPORTS, 0.5)))
        # 计分：推近。
        push = ease_in_out_cubic(progress(t, T_SCORE - 0.1, 0.6))
        scale = lerp(scale, 1.52, push)
        cy = lerp(cy, 1190, push)
        # 快剪：回到中景。
        back = ease_in_out_cubic(progress(t, T_MONTAGE, 0.4))
        scale = lerp(scale, 1.30, back)
        # 联动：缩小淡出。
        leave = ease_in_out_cubic(progress(t, T_LINK - 0.1, 0.45))
        scale = lerp(scale, 0.85, leave)
        cy = lerp(cy, 1350, leave)
        alpha *= 1 - leave
        # 轻微呼吸浮动。
        cy += math.sin(t * 2.1) * 6
        angle += math.sin(t * 1.3) * 0.8
        return cx, cy, scale, angle, alpha

    # 单帧 -------------------------------------------------------------
    def frame(self, t: float) -> Image.Image:
        xs, ys, scale = self.bg_grid
        canvas = background(t, xs, ys, scale)

        self.draw_orbit(canvas, t)

        cx, cy, wscale, angle, alpha = self.watch_pose(t)
        if alpha > 0.001:
            layer = transform(self.watch_layer(t), wscale, angle)
            paste_center(canvas, layer, cx, cy, alpha)
            self.draw_plus(canvas, t, cx, cy, wscale)
            self.draw_label(canvas, t, cy, wscale)

        self.draw_link(canvas, t)
        for caption in self.captions:
            caption.draw(canvas, t)
        self.draw_end(canvas, t)
        return canvas

    def draw_orbit(self, canvas: Image.Image, t: float) -> None:
        if not (T_SPORTS <= t <= T_SCORE + 0.4):
            return
        spots = [(120, 640), (960, 610), (95, 1000), (985, 980), (115, 1380), (965, 1360), (230, 1730), (850, 1745)]
        for i, (icon, (x, y)) in enumerate(zip(self.orbit, spots)):
            p = progress(t, T_SPORTS + 0.1 + i * 0.1, 0.45)
            if p <= 0:
                continue
            s = max(0.0, ease_out_back(p)) * 0.86
            out = ease_in_out_cubic(progress(t, T_SCORE - 0.25, 0.45))
            dx, dy = x - W / 2, y - 1100
            x2, y2 = x + dx * out * 0.9, y + dy * out * 0.9
            y2 += math.sin(t * 2.4 + i) * 10
            sprite = transform(icon, max(0.01, s), math.sin(t * 1.6 + i * 0.7) * 8)
            paste_center(canvas, sprite, x2, y2, clamp(p * 2) * (1 - out))

    def draw_plus(self, canvas: Image.Image, t: float, cx: float, cy: float, wscale: float) -> None:
        ox, oy = self.watch.screen_center_offset
        sw, sh = self.watch.slot
        for tap_t, left in TAPS:
            p = progress(t, tap_t + 0.03, 0.7)
            if not 0 < p < 1:
                continue
            sprite = self.plus_left if left else self.plus_right
            pop = ease_out_back(clamp(p * 2.5))
            x = cx + (ox + (-0.25 if left else 0.25) * sw) * wscale
            y = cy + (oy - 0.36 * sh) * wscale - ease_out_cubic(p) * 170
            paste_center(canvas, transform(sprite, max(0.01, pop) * 1.15), x, y, 1 - progress(p, 0.6, 0.4))

    def draw_label(self, canvas: Image.Image, t: float, cy: float, wscale: float) -> None:
        if not (T_MONTAGE <= t < T_LINK):
            return
        index = min(len(self.montage) - 1, int((t - T_MONTAGE) / MONTAGE_STEP))
        label = self.labels[self.montage[index][0]]
        local = (t - T_MONTAGE) - index * MONTAGE_STEP
        pop = ease_out_back(clamp(local / 0.18))
        fade = 1 - progress(t, T_LINK - 0.3, 0.25)
        paste_center(canvas, transform(label, max(0.01, pop)), W / 2, 1810, fade)

    def draw_link(self, canvas: Image.Image, t: float) -> None:
        if not (T_LINK - 0.2 <= t <= T_END + 0.5):
            return
        enter = ease_out_cubic(progress(t, T_LINK, 0.6))
        leave = ease_in_out_cubic(progress(t, T_END - 0.15, 0.45))
        scale = lerp(0.85, 1.0, enter) * lerp(1, 0.9, leave)
        art = transform(self.link_art, scale, lerp(-4, 0, enter))
        cy = lerp(1250, 1080, enter) + math.sin(t * 2.0) * 6
        paste_center(canvas, art, W / 2 + 10, cy, enter * (1 - leave))

    def draw_end(self, canvas: Image.Image, t: float) -> None:
        if t < T_END:
            return
        icon_p = ease_out_back(progress(t, T_END + 0.1, 0.55))
        paste_center(canvas, transform(self.app_icon, max(0.01, icon_p)), W / 2, 760, clamp(icon_p * 2))
        items = [(self.end_title, 1030, 0.3), (self.end_sub, 1140, 0.45)]
        if not self.hide_store_hint:
            items.append((self.end_hint, 1600, 0.7))
        for sprite, y, start in items:
            p = ease_out_cubic(progress(t, T_END + start, 0.5))
            paste_center(canvas, sprite, W / 2, y + (1 - p) * 40, p)


# ---------------------------------------------------------------- 配乐

def synth_audio(path: Path) -> None:
    n = int(DURATION * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    mix = np.zeros(n, dtype=np.float64)
    rng = np.random.default_rng(7)

    def add(signal: np.ndarray, at: float, gain: float) -> None:
        start = int(at * SAMPLE_RATE)
        if start >= n:
            return
        end = min(n, start + len(signal))
        mix[start:end] += signal[: end - start] * gain

    def env(length: float, attack: float, decay: float) -> np.ndarray:
        tt = np.arange(int(length * SAMPLE_RATE)) / SAMPLE_RATE
        return np.minimum(1, tt / max(attack, 1e-4)) * np.exp(-tt / decay)

    def kick() -> np.ndarray:
        tt = np.arange(int(0.35 * SAMPLE_RATE)) / SAMPLE_RATE
        freq = 48 + 110 * np.exp(-tt * 28)
        phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
        return np.sin(phase) * np.exp(-tt * 9)

    def hat() -> np.ndarray:
        noise = rng.standard_normal(int(0.06 * SAMPLE_RATE))
        noise = np.diff(noise, prepend=0)
        return noise * env(0.06, 0.001, 0.015)

    def clap() -> np.ndarray:
        noise = rng.standard_normal(int(0.2 * SAMPLE_RATE))
        noise = noise - np.convolve(noise, np.ones(8) / 8, mode="same")
        return noise * env(0.2, 0.002, 0.05)

    def tone(freq: float, length: float, attack: float, decay: float, harmonics=(1.0, 0.35, 0.12)) -> np.ndarray:
        tt = np.arange(int(length * SAMPLE_RATE)) / SAMPLE_RATE
        wave_ = sum(a * np.sin(2 * np.pi * freq * (k + 1) * tt) for k, a in enumerate(harmonics))
        return wave_ * env(length, attack, decay)

    def note(semitones_from_a4: int) -> float:
        return 440.0 * 2 ** (semitones_from_a4 / 12)

    # 和弦进行 C – G – Am – F（每和弦 4 拍），16 分音符分解和弦 + 低音。
    chords = [[3, 7, 10, 15], [-2, 2, 5, 10], [0, 3, 7, 12], [-4, 0, 3, 8]]
    roots = [-21, -26, -24, -28]
    beats = int(DURATION / BEAT)
    for b in range(beats):
        at = b * BEAT
        chord = chords[(b // 4) % 4]
        root = roots[(b // 4) % 4]
        in_groove = at >= T_SPORTS - 0.01 and at < T_END + 0.01
        if in_groove:
            add(kick(), at, 0.85)
            add(hat(), at + BEAT / 2, 0.22)
            if b % 2 == 1:
                add(clap(), at, 0.17)
            add(tone(note(root), BEAT * 0.9, 0.005, 0.22, (1.0, 0.5, 0.2)), at, 0.32)
        for step in range(4 if at >= T_SPORTS - 0.01 else 2):
            sub = at + step * BEAT / (4 if at >= T_SPORTS - 0.01 else 2)
            if sub >= T_END + 1.6:
                continue
            freq = note(chord[(b * 4 + step) % 4] + 12)
            add(tone(freq, 0.3, 0.003, 0.09), sub, 0.10)

    # 片头铺底 + 上升音。
    pad_len = T_SPORTS
    pad_t = np.arange(int(pad_len * SAMPLE_RATE)) / SAMPLE_RATE
    pad = sum(np.sin(2 * np.pi * note(s) * pad_t) for s in (3, 7, 10, -9)) / 4
    add(pad * np.minimum(1, pad_t / 0.6) * 0.5, 0.0, 0.25)
    riser_t = np.arange(int(0.6 * SAMPLE_RATE)) / SAMPLE_RATE
    riser = rng.standard_normal(len(riser_t)) * (riser_t / 0.6) ** 2
    riser = np.convolve(riser, np.ones(6) / 6, mode="same")
    add(riser, T_SPORTS - 0.6, 0.12)

    # 转场嗖声。
    for at in (T_SCORE, T_MONTAGE, T_LINK, T_END):
        length = 0.35
        tt = np.arange(int(length * SAMPLE_RATE)) / SAMPLE_RATE
        noise = rng.standard_normal(len(tt))
        kernel = int(2 + 18 * 0.5)
        noise = np.convolve(noise, np.ones(kernel) / kernel, mode="same")
        add(noise * np.sin(np.pi * tt / length) ** 2, at - length * 0.6, 0.16)

    # 点按记分音：明亮短促的「哒」，最后一分加和弦。
    for i, (at, left) in enumerate(TAPS):
        base = note(15 if left else 12)
        add(tone(base * 2, 0.18, 0.001, 0.05, (1.0, 0.2)), at, 0.32)
        add(tone(base * 3, 0.12, 0.001, 0.03, (1.0,)), at, 0.12)
    for k, s in enumerate((15, 19, 22, 27)):
        add(tone(note(s), 0.9, 0.002, 0.35), T_GAME_END - 0.42 + k * 0.05, 0.14)

    # 快剪的「咔嚓」切换声。
    for k in range(1, 4):
        add(tone(note(24), 0.06, 0.001, 0.015, (1.0, 0.5)), T_MONTAGE + k * MONTAGE_STEP, 0.15)

    # 片尾重音 + 尾音。
    add(kick(), T_END, 1.0)
    for s in (3, 7, 10, 15, -9):
        add(tone(note(s), 2.0, 0.01, 0.8, (1.0, 0.25)), T_END, 0.11)

    # 简单混响（多抽头延迟）。
    wet = np.zeros_like(mix)
    for delay, gain in ((0.037, 0.35), (0.061, 0.28), (0.089, 0.22), (0.131, 0.16), (0.197, 0.1)):
        d = int(delay * SAMPLE_RATE)
        wet[d:] += mix[:-d] * gain
    mix = mix + wet * 0.5

    fade = np.ones(n)
    fade_len = int(0.9 * SAMPLE_RATE)
    fade[-fade_len:] = np.linspace(1, 0, fade_len) ** 1.5
    fade_in = int(0.05 * SAMPLE_RATE)
    fade[:fade_in] = np.linspace(0, 1, fade_in)
    mix *= fade
    mix = np.tanh(mix * 1.1)
    mix *= 0.72 / max(1e-6, np.max(np.abs(mix)))
    stereo = np.stack([mix, mix], axis=1)
    pcm = (stereo * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm.tobytes())


# ---------------------------------------------------------------- 入口

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shots-dir", required=True)
    parser.add_argument("--watch-bezel", default=DEFAULT_BEZEL)
    parser.add_argument("--link-artwork", default=str(DEFAULT_LINK_ART))
    parser.add_argument("--app-icon", default=str(DEFAULT_APP_ICON))
    parser.add_argument("--montage", nargs="*", default=["羽毛球=sport_羽毛球", "网球=sport_网球", "八球=sport_八球", "足球=sport_足球"])
    parser.add_argument("--output", required=True)
    parser.add_argument("--hide-store-hint", action="store_true", help="去掉片尾「App Store 搜索」一行（小红书版）")
    parser.add_argument("--poster", help="另存一帧封面 PNG")
    parser.add_argument("--poster-time", type=float, default=7.6)
    parser.add_argument("--preview", nargs="*", type=float, help="只导出这些时间点的帧到 output 同目录，便于检查")
    args = parser.parse_args()
    args.montage = [tuple(item.split("=", 1)) for item in args.montage]

    promo = Promo(args)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    if args.preview:
        for value in args.preview:
            promo.frame(value).convert("RGB").save(output.parent / f"preview_{value:05.2f}.png")
        return

    audio_path = output.with_suffix(".wav")
    synth_audio(audio_path)

    cmd = [
        "ffmpeg", "-y", "-v", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-i", str(audio_path),
        "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
        "-profile:v", "high", "-movflags", "+faststart",
        "-c:a", "aac", "-b:a", "192k", "-shortest", str(output),
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    total = int(DURATION * FPS)
    for i in range(total):
        img = promo.frame(i / FPS).convert("RGB")
        proc.stdin.write(img.tobytes())
        if args.poster and abs(i / FPS - args.poster_time) < 0.5 / FPS:
            img.save(args.poster)
        if i % 30 == 0:
            print(f"frame {i}/{total}", flush=True)
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit("ffmpeg 编码失败")
    audio_path.unlink(missing_ok=True)
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
