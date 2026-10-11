"""앱 아이콘 전부 만들기: 노란 바탕 + 편의점 차양 줄무늬 + 캐릭터(tool/render_icon.py 결과).

    python tool/make_icons.py build/icon_char.png

- 안드로이드: 적응형(배경·전경 따로, 전경은 가운데 66% 안전 구역 안) + 옛 정사각 아이콘
- 아이폰: AppIcon.appiconset 의 파일 이름 그대로, 투명 없이
- 스토어: store/play-icon-512.png
"""
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YELLOW, PINK, WHITE = (255, 224, 130, 255), (244, 143, 177, 255), (255, 253, 247, 255)


def background(size):
    im = Image.new("RGBA", (size, size), YELLOW)
    d = ImageDraw.Draw(im)
    band, n = int(size * 0.2), 7
    w = size / n
    for i in range(n):
        x0 = i * w
        col = PINK if i % 2 == 0 else WHITE
        d.rectangle([x0, 0, x0 + w, band], fill=col)
        d.ellipse([x0, band - w / 2, x0 + w, band + w / 2], fill=col)  # 차양 끝 물결
    return im


def character(src, box):
    ch = Image.open(src).convert("RGBA")
    ch = ch.crop(ch.getbbox())
    k = min(box / ch.width, box / ch.height)
    return ch.resize((round(ch.width * k), round(ch.height * k)), Image.LANCZOS)


def full(src, size):
    im = background(size)
    ch = character(src, int(size * 0.74))
    im.alpha_composite(ch, ((size - ch.width) // 2, size - ch.height - int(size * 0.04)))
    return im


def main():
    src = sys.argv[1]
    big = full(src, 1024)

    res = os.path.join(ROOT, "android/app/src/main/res")
    for d, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        big.resize((px, px), Image.LANCZOS).save(os.path.join(res, f"mipmap-{d}", "ic_launcher.png"))
    for d, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        background(px).save(os.path.join(res, f"mipmap-{d}", "ic_launcher_background.png"))
        fg = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        ch = character(src, int(px * 0.6))
        fg.alpha_composite(ch, ((px - ch.width) // 2, (px - ch.height) // 2 + int(px * 0.04)))
        fg.save(os.path.join(res, f"mipmap-{d}", "ic_launcher_foreground.png"))
    os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
    with open(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                '</adaptive-icon>\n')

    ios = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    flat = big.convert("RGB")  # 앱스토어는 투명 아이콘을 거부한다
    for name in os.listdir(ios):
        m = re.match(r"Icon-App-([\d.]+)x[\d.]+@(\d)x\.png", name)
        if m:
            px = round(float(m.group(1)) * int(m.group(2)))
            flat.resize((px, px), Image.LANCZOS).save(os.path.join(ios, name))

    os.makedirs(os.path.join(ROOT, "store"), exist_ok=True)
    big.convert("RGB").resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "store", "play-icon-512.png"))
    print("ok")


main()
