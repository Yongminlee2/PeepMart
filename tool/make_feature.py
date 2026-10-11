"""플레이 스토어 그래픽 이미지(1024×500): 차양 줄무늬 + "Peep Mart" + 캐릭터·음식.

    python tool/make_feature.py build/icon_char.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1024, 500
YELLOW, PINK, WHITE, INK = (255, 224, 130), (244, 143, 177), (255, 253, 247), (93, 64, 55)

im = Image.new("RGBA", (W, H), YELLOW + (255,))
d = ImageDraw.Draw(im)
n, band = 12, 92
w = W / n
for i in range(n):
    col = PINK if i % 2 == 0 else WHITE
    d.rectangle([i * w, 0, (i + 1) * w, band], fill=col)
    d.ellipse([i * w, band - w / 2, (i + 1) * w, band + w / 2], fill=col)
# 바닥 체크무늬 띠
for i in range(0, W, 48):
    d.rectangle([i, H - 70, i + 48, H], fill=(255, 248, 225) if (i // 48) % 2 == 0 else (255, 236, 179))

font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/Jua-Regular.ttf"), 116)
text, x, y = "Peep Mart", 56, 180
d.text((x, y), text, font=font, fill=INK, stroke_width=10, stroke_fill=WHITE)

ch = Image.open(sys.argv[1]).convert("RGBA")
ch = ch.crop(ch.getbbox())
k = 340 / ch.height
ch = ch.resize((round(ch.width * k), 340), Image.LANCZOS)
im.alpha_composite(ch, (W - ch.width - 10, H - ch.height - 24))

for name, pos, size in (("donut", (90, 360), 92), ("icecream", (230, 380), 86), ("cake", (370, 372), 96),
                        ("sandwich", (505, 382), 92), ("fruit", (630, 378), 84)):
    f = Image.open(os.path.join(ROOT, f"assets/props/food-{name}.png")).convert("RGBA")
    f = f.crop(f.getbbox())
    k = size / max(f.size)
    f = f.resize((round(f.width * k), round(f.height * k)), Image.LANCZOS)
    im.alpha_composite(f, pos)

im.convert("RGB").save(os.path.join(ROOT, "store", "play-feature-1024x500.png"))
print("ok")
