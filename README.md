# 삐약마트 (Peep Mart)

편의점을 운영하는 귀여운 타이쿤. 방 하나에서 시작해 넓은 땅에 마음대로 지어 키운다. Flutter 로 안드로이드·아이폰을 함께 낸다.

설계: `docs/설계/2026-10-11-peepmart-design.md`

## 빌드 (Windows, 한글 사용자 폴더 우회)

```bash
export TEMP=/c/workAndroid/tmp-ascii TMP=/c/workAndroid/tmp-ascii PUB_CACHE=/c/flutter/.pub-cache GRADLE_USER_HOME=/c/workAndroid/gradle-home-ascii
flutter test
flutter build apk --release
```

밸런스 자동 플레이(6시간, 몇 분 걸림): `BALANCE=1 flutter test test/balance_test.dart`

같은 와이파이의 폰에서 웹으로 해 보기: `flutter build web --release` 후 `python tool/serve_web.py` → `http://<PC 주소>:8762`

## 그림 다시 만들기

Kenney 묶음(CC0)을 받아 둔 폴더를 넘긴다. 블렌더가 찍은 뒤 `pack_assets.py` 로 256색으로 줄인다
(블렌더 안의 파이썬에는 PIL 이 없어서 따로 돌린다).

```bash
blender -b -P tool/render_chars.py -- "<Mini Characters GLB 폴더>" build/chars
python tool/pack_assets.py build/chars assets/characters
blender -b -P tool/render_props.py -- "<Food Kit GLB 폴더>" "<Furniture Kit Models 폴더>" build/props
python tool/pack_assets.py build/props assets/props
```

효과음은 Kenney Interface Sounds 의 ogg 를 ffmpeg 로 모노 22kHz wav 로 바꿔 `assets/audio/` 에 둔다
(아이폰은 ogg 를 못 튼다).

## 문장

원본은 `i18n/*.json`. `lib/l10n/` 은 `python ../common/i18n/gen.py i18n/ --to flutter --out lib/l10n` 로 만든다.

## 그림 출처

- 캐릭터: Kenney "Mini Characters 1" (CC0) — www.kenney.nl
- 음식·가구: Kenney "Food Kit", "Furniture Kit" (CC0)
- 효과음: Kenney "Interface Sounds" (CC0)
- 글꼴: Jua (SIL OFL)
