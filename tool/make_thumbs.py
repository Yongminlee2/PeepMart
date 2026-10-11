"""캐릭터 시트에서 초상화용 한 프레임(서기·좋아요)을 잘라 작은 그림으로 둔다.

    python tool/make_thumbs.py

도감처럼 초상화를 수십 개 그리는 화면에서 시트(한 장 풀면 6.8MB)를 전부 올리지 않게.
프레임은 lib/ui/sprites.dart 의 drawPortrait 와 맞춘다(열 2, 줄 0=서기·6=좋아요).
"""
import glob
import os

from PIL import Image

FR, COL, ROWS = 128, 2, {"idle": 0, "yes": 6}
src = os.path.join(os.path.dirname(__file__), "..", "assets", "characters")
dst = os.path.join(src, "thumbs")
os.makedirs(dst, exist_ok=True)
for f in sorted(glob.glob(os.path.join(src, "character-*.png"))):
    name = os.path.basename(f)[len("character-"):-4]
    sheet = Image.open(f).convert("RGBA")
    for anim, row in ROWS.items():
        im = sheet.crop((COL * FR, row * FR, COL * FR + FR, row * FR + FR))
        im.quantize(colors=256, method=Image.Quantize.FASTOCTREE).save(os.path.join(dst, f"{name}-{anim}.png"), optimize=True)
print("ok")
