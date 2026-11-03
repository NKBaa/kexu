"""生成「课序」应用图标。

设计方向：暖白底 + 深墨色课表卡片 + 克制的雾蓝/杏色课程条，
呼应 App 的 Material 3 Expressive 新主题，小尺寸下也保持清晰。
运行：python tooling/make_icon.py
产物：
- docs/app-icon-1024.png（母版）
- app/android/app/src/main/res/mipmap-*/ic_launcher.png（Android 各密度）
- app/windows/runner/resources/app_icon.ico（Windows 多尺寸 ICO）
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
ANDROID_RES = os.path.join(ROOT, "app", "android", "app", "src", "main", "res")
WINDOWS_RES = os.path.join(ROOT, "app", "windows", "runner", "resources")

S = 1024
SS = 3  # 超采样倍率

CREAM = (248, 246, 238, 255)
CREAM_DEEP = (239, 232, 218, 255)
INK = (27, 27, 31, 255)
MIST = (205, 217, 243, 255)
BLUE = (133, 157, 214, 255)
PEACH = (235, 205, 178, 255)


def lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        color = (lerp(top[0], bottom[0], t), lerp(top[1], bottom[1], t), lerp(top[2], bottom[2], t))
        for x in range(size):
            px[x, y] = color
    return img


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_icon(size: int) -> Image.Image:
    s = size * SS
    scale = s / S

    def p(v: float) -> float:
        return v * scale

    # 暖白渐变底，四角透明
    bg = vertical_gradient(s, (251, 249, 243), (238, 231, 217)).convert("RGBA")
    bg.putalpha(rounded_mask(s, int(p(224))))
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # 卡片柔和阴影
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (p(198), p(252), p(826), p(840)),
        radius=p(128),
        fill=(27, 27, 31, 58),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(p(24)))
    layer.alpha_composite(shadow)

    # 深墨色课表卡片
    d.rounded_rectangle(
        (p(194), p(246), p(830), p(828)),
        radius=p(126),
        fill=INK,
    )

    # 顶部装订环（暖白色，与背景呼应）
    for cx in (p(354), p(670)):
        d.rounded_rectangle(
            (cx - p(18), p(188), cx + p(18), p(286)),
            radius=p(18),
            fill=CREAM,
        )

    # 课程条：时间轴 + 课程块，粗细在小图标下仍清晰
    def bar(x0: float, y0: float, x1: float, color: tuple[int, int, int, int]) -> None:
        d.rounded_rectangle(
            (p(x0), p(y0), p(x1), p(y0 + 46)),
            radius=p(23),
            fill=color,
        )

    # 第 1 行
    d.ellipse((p(286), p(382), p(310), p(406)), fill=MIST)
    bar(332, 382, 724, MIST)
    # 第 2 行：暖白 + 雾蓝
    d.ellipse((p(286), p(492), p(310), p(516)), fill=PEACH)
    bar(332, 492, 542, CREAM)
    bar(570, 492, 724, BLUE)
    # 第 3 行
    d.ellipse((p(286), p(602), p(310), p(626)), fill=MIST)
    bar(332, 602, 652, CREAM)

    result = Image.alpha_composite(bg, layer)
    return result.resize((size, size), Image.LANCZOS)


def main() -> None:
    os.makedirs(DOCS, exist_ok=True)
    master = draw_icon(S)
    master.save(os.path.join(DOCS, "app-icon-1024.png"))

    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, px in sizes.items():
        out_dir = os.path.join(ANDROID_RES, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)
        draw_icon(px).save(os.path.join(out_dir, "ic_launcher.png"))

    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    icons = [draw_icon(px) for px in ico_sizes]
    icons[-1].save(
        os.path.join(WINDOWS_RES, "app_icon.ico"),
        format="ICO",
        sizes=[(px, px) for px in ico_sizes],
        append_images=icons[:-1],
    )

    print("icon generated:")
    print(" ", os.path.join(DOCS, "app-icon-1024.png"))
    print(" ", os.path.join(ANDROID_RES, "mipmap-xxxhdpi", "ic_launcher.png"))
    print(" ", os.path.join(WINDOWS_RES, "app_icon.ico"))


if __name__ == "__main__":
    main()
