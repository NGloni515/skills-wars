import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 128
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "game/fx/textures"


def radial(falloff):
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    c = (SIZE - 1) / 2
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x - c, y - c) / c
            pixels[x, y] = (255, 255, 255, int(255 * max(0.0, min(1.0, falloff(d)))))
    return image


def star(points=5, inner=0.42):
    image = Image.new("L", (SIZE * 4, SIZE * 4), 0)
    c = SIZE * 2
    outline = []
    for i in range(points * 2):
        r = (0.95 if i % 2 == 0 else 0.95 * inner) * c
        a = math.pi * i / points - math.pi / 2
        outline.append((c + r * math.cos(a), c + r * math.sin(a)))
    ImageDraw.Draw(image).polygon(outline, fill=255)
    alpha = image.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8))
    result = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    result.putalpha(alpha)
    return result


def spark():
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    c = (SIZE - 1) / 2
    for y in range(SIZE):
        for x in range(SIZE):
            along = abs(x - c) / c
            across = abs(y - c) / (c * 0.16)
            a = max(0.0, 1.0 - along ** 1.5) * max(0.0, 1.0 - across ** 2)
            pixels[x, y] = (255, 255, 255, int(255 * a))
    return image


OUTLINE = (18, 26, 44, 255)


def icon(draw_shape):
    scale = 4
    image = Image.new("RGBA", (SIZE * scale, SIZE * scale), (0, 0, 0, 0))
    draw_shape(ImageDraw.Draw(image), SIZE * scale)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def shield_icon(draw, s):
    outline = [(0.5, 0.06), (0.88, 0.2), (0.84, 0.55), (0.5, 0.95), (0.16, 0.55), (0.12, 0.2)]
    draw.polygon([(x * s, y * s) for x, y in outline], fill=(89, 204, 255, 255), outline=OUTLINE, width=int(s * 0.06))
    inner = [(0.5, 0.2), (0.74, 0.29), (0.71, 0.53), (0.5, 0.8)]
    draw.polygon([(x * s, y * s) for x, y in inner], fill=(190, 240, 255, 255))


def haste_icon(draw, s):
    bolt = [(0.58, 0.04), (0.2, 0.56), (0.47, 0.56), (0.38, 0.96), (0.82, 0.4), (0.54, 0.4), (0.66, 0.04)]
    draw.polygon([(x * s, y * s) for x, y in bolt], fill=(255, 214, 51, 255), outline=OUTLINE, width=int(s * 0.06))


def gold_icon(draw, s):
    draw.ellipse([0.08 * s, 0.08 * s, 0.92 * s, 0.92 * s], fill=(255, 178, 31, 255), outline=OUTLINE, width=int(s * 0.06))
    draw.ellipse([0.24 * s, 0.24 * s, 0.76 * s, 0.76 * s], outline=(255, 226, 120, 255), width=int(s * 0.06))
    draw.rectangle([0.45 * s, 0.32 * s, 0.55 * s, 0.68 * s], fill=(255, 226, 120, 255))


def big_hook_icon(draw, s):
    draw.ellipse([0.06 * s, 0.06 * s, 0.94 * s, 0.94 * s], fill=(242, 102, 242, 255), outline=OUTLINE, width=int(s * 0.05))
    w = int(s * 0.1)
    draw.line([(0.5 * s, 0.18 * s), (0.5 * s, 0.6 * s)], fill=(240, 244, 250, 255), width=w)
    draw.arc([0.26 * s, 0.4 * s, 0.74 * s, 0.84 * s], 0, 180, fill=(240, 244, 250, 255), width=w)
    draw.polygon([(0.66 * s, 0.62 * s), (0.82 * s, 0.62 * s), (0.74 * s, 0.44 * s)], fill=(240, 244, 250, 255))


HOOK_COLOR = (255, 150, 40, 255)
ARROW_COLOR = (60, 190, 240, 255)
TRAP_COLOR = (205, 105, 70, 255)
GLYPH = (250, 250, 255, 255)


def badge(color, glyph):
    def draw_badge(draw, s):
        draw.ellipse([0.05 * s, 0.05 * s, 0.95 * s, 0.95 * s], fill=color, outline=OUTLINE, width=int(s * 0.05))
        glyph(draw, s)
    return draw_badge


def range_glyph(draw, s):
    w = int(s * 0.08)
    draw.line([(0.26 * s, 0.5 * s), (0.74 * s, 0.5 * s)], fill=GLYPH, width=w)
    draw.polygon([(0.16 * s, 0.5 * s), (0.34 * s, 0.36 * s), (0.34 * s, 0.64 * s)], fill=GLYPH)
    draw.polygon([(0.84 * s, 0.5 * s), (0.66 * s, 0.36 * s), (0.66 * s, 0.64 * s)], fill=GLYPH)


def speed_glyph(draw, s):
    w = int(s * 0.09)
    for x in (0.28, 0.5):
        draw.line([(x * s, 0.28 * s), ((x + 0.2) * s, 0.5 * s), (x * s, 0.72 * s)], fill=GLYPH, width=w, joint="curve")


def size_glyph(draw, s):
    draw.ellipse([0.22 * s, 0.22 * s, 0.78 * s, 0.78 * s], outline=GLYPH, width=int(s * 0.07))
    draw.ellipse([0.39 * s, 0.39 * s, 0.61 * s, 0.61 * s], fill=GLYPH)


def cooldown_glyph(draw, s):
    w = int(s * 0.07)
    draw.ellipse([0.22 * s, 0.22 * s, 0.78 * s, 0.78 * s], outline=GLYPH, width=w)
    draw.line([(0.5 * s, 0.5 * s), (0.5 * s, 0.32 * s)], fill=GLYPH, width=w)
    draw.line([(0.5 * s, 0.5 * s), (0.64 * s, 0.58 * s)], fill=GLYPH, width=w)


def stun_glyph(draw, s):
    outline = []
    for i in range(10):
        r = (0.33 if i % 2 == 0 else 0.14) * s
        a = math.pi * i / 5 - math.pi / 2
        outline.append((0.5 * s + r * math.cos(a), 0.52 * s + r * math.sin(a)))
    draw.polygon(outline, fill=GLYPH)


def spread_glyph(draw, s):
    draw.ellipse([0.36 * s, 0.36 * s, 0.64 * s, 0.64 * s], outline=GLYPH, width=int(s * 0.06))
    for a in range(4):
        angle = math.pi / 4 + a * math.pi / 2
        tip = (0.5 * s + 0.33 * s * math.cos(angle), 0.5 * s + 0.33 * s * math.sin(angle))
        side = (math.cos(angle + math.pi / 2) * 0.07 * s, math.sin(angle + math.pi / 2) * 0.07 * s)
        base = (0.5 * s + 0.2 * s * math.cos(angle), 0.5 * s + 0.2 * s * math.sin(angle))
        draw.polygon([tip, (base[0] + side[0], base[1] + side[1]), (base[0] - side[0], base[1] - side[1])], fill=GLYPH)


def outlined(draw, s, shape):
    shape(draw, s, OUTLINE, 0.05)
    shape(draw, s, None, 0.0)


def hook_skill(draw, s):
    def shape(draw, s, color, grow):
        fill = color or HOOK_COLOR
        w = int(s * (0.1 + grow))
        draw.ellipse([(0.55 - grow) * s, (0.06 - grow) * s, (0.75 + grow) * s, (0.26 + grow) * s], outline=fill, width=int(s * (0.06 + grow)))
        draw.line([(0.65 * s, 0.25 * s), (0.65 * s, 0.6 * s)], fill=fill, width=w)
        draw.arc([0.25 * s, 0.36 * s, 0.73 * s, 0.84 * s], 0, 180, fill=fill, width=w)
        draw.line([(0.29 * s, 0.6 * s), (0.29 * s, 0.5 * s)], fill=fill, width=w)
        tip = [(0.2 - grow) * s, (0.54 + grow * 0.5) * s], [(0.4 + grow) * s, (0.54 + grow * 0.5) * s], [0.29 * s, (0.3 - grow * 1.6) * s]
        draw.polygon([tuple(p) for p in tip], fill=fill)
    outlined(draw, s, shape)


def arrow_skill(draw, s):
    def shape(draw, s, color, grow):
        fill = color or ARROW_COLOR
        w = int(s * (0.08 + grow))
        draw.line([(0.24 * s, 0.76 * s), (0.66 * s, 0.34 * s)], fill=fill, width=w)
        g = grow * 1.4
        draw.polygon([((0.84 + g) * s, (0.16 - g) * s), ((0.5 - g) * s, (0.3 - g * 0.3) * s), ((0.7 + g * 0.3) * s, (0.5 + g) * s)], fill=fill)
        for dx, dy in ((0.0, 0.0), (0.08, 0.08)):
            draw.line([((0.18 + dx) * s, (0.62 + dy) * s), ((0.3 + dx) * s, (0.74 + dy) * s)], fill=fill, width=int(s * (0.07 + grow)))
            draw.line([((0.3 + dx) * s, (0.74 + dy) * s), ((0.22 + dx) * s, (0.86 + dy) * s)], fill=fill, width=int(s * (0.07 + grow)))
    outlined(draw, s, shape)


def trap_skill(draw, s):
    def shape(draw, s, color, grow):
        fill = color or TRAP_COLOR
        steel = color or (232, 226, 214, 255)
        band = int(s * (0.08 + grow))
        draw.arc([0.14 * s, 0.14 * s, 0.86 * s, 0.7 * s], 180, 360, fill=fill, width=band)
        draw.arc([0.14 * s, 0.34 * s, 0.86 * s, 0.9 * s], 0, 180, fill=fill, width=band)
        for x in (0.12, 0.82):
            draw.rectangle([(x - grow) * s, (0.4 - grow) * s, (x + 0.06 + grow) * s, (0.64 + grow) * s], fill=fill)
        g = grow * 1.2
        for x in (0.27, 0.39, 0.51, 0.63, 0.75):
            draw.polygon([((x - 0.05 - g) * s, (0.41 - g) * s), ((x + 0.05 + g) * s, (0.41 - g) * s), (x * s, (0.53 + g) * s)], fill=steel)
        for x in (0.33, 0.45, 0.57, 0.69):
            draw.polygon([((x - 0.05 - g) * s, (0.63 + g) * s), ((x + 0.05 + g) * s, (0.63 + g) * s), (x * s, (0.51 - g) * s)], fill=steel)
    outlined(draw, s, shape)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    textures = {
        "soft.png": radial(lambda d: max(0.0, 1.0 - d) ** 1.6),
        "drop.png": radial(lambda d: 1.0 if d < 0.72 else max(0.0, 1.0 - (d - 0.72) / 0.18)),
        "ring.png": radial(lambda d: max(0.0, 1.0 - abs(d - 0.8) / 0.12) ** 1.2),
        "star.png": star(),
        "spark.png": spark(),
        "icon_shield.png": icon(shield_icon),
        "icon_haste.png": icon(haste_icon),
        "icon_gold.png": icon(gold_icon),
        "icon_big_hook.png": icon(big_hook_icon),
        "skill_hook.png": icon(hook_skill),
        "skill_arrow.png": icon(arrow_skill),
        "skill_trap.png": icon(trap_skill),
        "upgrade_hook_range.png": icon(badge(HOOK_COLOR, range_glyph)),
        "upgrade_hook_speed.png": icon(badge(HOOK_COLOR, speed_glyph)),
        "upgrade_hook_size.png": icon(badge(HOOK_COLOR, size_glyph)),
        "upgrade_hook_cooldown.png": icon(badge(HOOK_COLOR, cooldown_glyph)),
        "upgrade_arrow_speed.png": icon(badge(ARROW_COLOR, speed_glyph)),
        "upgrade_arrow_stun.png": icon(badge(ARROW_COLOR, stun_glyph)),
        "upgrade_trap_size.png": icon(badge(TRAP_COLOR, spread_glyph)),
        "upgrade_trap_cooldown.png": icon(badge(TRAP_COLOR, cooldown_glyph)),
    }
    for name, image in textures.items():
        image.save(os.path.join(OUT_DIR, name))
        print("wrote", name)


main()
