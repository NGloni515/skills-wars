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
    }
    for name, image in textures.items():
        image.save(os.path.join(OUT_DIR, name))
        print("wrote", name)


main()
