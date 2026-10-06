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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    textures = {
        "soft.png": radial(lambda d: max(0.0, 1.0 - d) ** 1.6),
        "drop.png": radial(lambda d: 1.0 if d < 0.72 else max(0.0, 1.0 - (d - 0.72) / 0.18)),
        "ring.png": radial(lambda d: max(0.0, 1.0 - abs(d - 0.8) / 0.12) ** 1.2),
        "star.png": star(),
        "spark.png": spark(),
    }
    for name, image in textures.items():
        image.save(os.path.join(OUT_DIR, name))
        print("wrote", name)


main()
