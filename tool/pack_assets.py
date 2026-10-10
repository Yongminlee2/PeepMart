"""블렌더가 찍은 PNG 를 앱에 넣을 모양으로 줄인다.

    python tool/pack_assets.py <렌더 폴더> assets/<넣을 폴더>

- prop-*: 가구 재질이 바래 보여서 채도·밝기를 올린다.
- 전부: 256색으로 줄인다 (캐릭터 시트 11MB → 1.3MB, 눈으로는 차이 없음).
"""
import glob
import os
import sys

from PIL import Image, ImageEnhance

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for f in sorted(glob.glob(os.path.join(src, "*.png"))):
    name = os.path.basename(f)
    if name.startswith("_"):
        continue
    im = Image.open(f).convert("RGBA")
    if name.startswith("prop-"):
        a = im.getchannel("A")
        im = ImageEnhance.Brightness(ImageEnhance.Color(im).enhance(1.6)).enhance(1.12)
        im.putalpha(a)
    im.quantize(colors=256, method=Image.Quantize.FASTOCTREE).save(os.path.join(dst, name), optimize=True)
    print(name)
