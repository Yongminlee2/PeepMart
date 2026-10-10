# 삐약마트 (Peep Mart)

편의점을 운영하는 귀여운 아케이드 타이쿤. Flutter 로 안드로이드·아이폰을 함께 낸다.

설계: `docs/설계/2026-10-11-peepmart-design.md`

## 빌드 (Windows, 한글 사용자 폴더 우회)

```bash
export TEMP=/c/workAndroid/tmp-ascii TMP=/c/workAndroid/tmp-ascii PUB_CACHE=/c/flutter/.pub-cache GRADLE_USER_HOME=/c/workAndroid/gradle-home-ascii
flutter test
flutter build apk --release
```

## 캐릭터 그림 다시 만들기

Kenney Mini Characters 1(CC0)의 GLB 를 받아 둔 폴더를 넘긴다. 시트가 나오면 256색으로 줄인다.

```bash
blender -b -P tool/render_chars.py -- "<GLB 폴더>" assets/characters
```

## 문장

원본은 `i18n/*.json`. `lib/l10n/` 은 `python ../common/i18n/gen.py i18n/ --to flutter --out lib/l10n` 로 만든다.

## 그림 출처

- 캐릭터: Kenney "Mini Characters 1" (CC0) — www.kenney.nl
- 글꼴: Jua (SIL OFL)
