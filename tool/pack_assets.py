"""블렌더가 찍은 PNG 를 앱에 넣을 모양으로 줄인다.

    python tool/pack_assets.py <렌더 폴더> assets/<넣을 폴더>

- prop-*: 가구 재질이 바래 보여서 채도·밝기를 올린다.
- RECOLOR: 원본 모델 색을 바꿔 다른 상품으로 쓴다(분홍 우유갑 → 바나나우유 등).
- 전부: 256색으로 줄인다 (캐릭터 시트 11MB → 1.3MB, 눈으로는 차이 없음).
"""
import glob
import os
import sys

from PIL import Image, ImageEnhance

# 파일 이름: (바꿀 색상 범위 0~255, 새 색상, 채도 배율, 밝기 더하기)
RECOLOR = {
    "food-bananamilk.png": ((200, 245), 32, 1.9, 10),   # 분홍 → 노랑
    "food-hoppang.png": ((5, 30), 24, 0.35, 35),        # 주황 찐빵 → 하얀 호빵
    "food-pear.png": ((50, 120), 34, 0.85, 15),          # 초록 서양배 → 누런 한국 배
}


def recolor(im, rule):
    (lo, hi), hue, sat, add = rule
    h, s, v = im.convert("RGB").convert("HSV").split()
    hp, sp, vp = h.load(), s.load(), v.load()
    for y in range(im.height):
        for x in range(im.width):
            if lo <= hp[x, y] <= hi and sp[x, y] > 40:
                hp[x, y] = hue
                sp[x, y] = int(sp[x, y] * sat)
                vp[x, y] = min(255, vp[x, y] + add)
    out = Image.merge("HSV", (h, s, v)).convert("RGBA")
    out.putalpha(im.getchannel("A"))
    return out


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
    if name in RECOLOR:
        im = recolor(im, RECOLOR[name])
    im.quantize(colors=256, method=Image.Quantize.FASTOCTREE).save(os.path.join(dst, name), optimize=True)
    print(name)
