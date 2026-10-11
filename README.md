# 삐약마트 (Peep Mart)

편의점을 운영하는 귀여운 타이쿤. 방 하나에서 시작해 넓은 땅에 마음대로 지어 키운다. Flutter 로 안드로이드·아이폰을 함께 낸다.

설계: `docs/설계/2026-10-11-peepmart-design.md`

## 놀이 한눈에

- **하루 장사**: 문을 열면 3분, 마감하면 별(1~3)·보너스·할 일 결과. 닫힌 동안 짓고 꾸민다. 목표는 최근 평균 × 1.15.
- **가게 등급** 6단계(레벨 5·10·15·20·25): 날씨 예보 → 특별한 날·진상 손님 → 배달·단체 주문 → 축제 → VIP.
- **알바가 못 하는 일**: 도둑·길 잃은 아이·고장·진상 손님·배달, 7일마다 위생 점검, 메가마트 가격 전쟁 날.
- **재고**: 상자 16개, 비면 도매가로 재주문(20초). 레벨 15부터 자동 발주(수수료). 결과 창 순이익엔 물건값·일당까지 빠진다.
- **짜릿함**: 연속 계산 콤보 → 피버 타임, 진열 세트 12종, 가격표, 바닥 팁, 보물 상자, 인형뽑기.
- **세계**: 동네 4곳(규칙이 다르다), 삐약동 이야기 9화, 가게 밖 동네(찻길·차·사람·건물), 단골 8명, 손님·상품·세트 도감.

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
blender -b -P tool/render_chars.py -- "<Ultimate Animated Character Pack FBX 폴더>" build/chars
python tool/pack_assets.py build/chars assets/characters
python tool/make_thumbs.py   # 초상화용 작은 그림
blender -b -P tool/render_props.py -- "<Food Kit GLB 폴더>" "<Furniture Kit Models 폴더>" build/props
python tool/pack_assets.py build/props assets/props
```

효과음은 Kenney Interface Sounds 의 ogg 를 ffmpeg 로 모노 22kHz wav 로 바꿔 `assets/audio/` 에 둔다
(아이폰은 ogg 를 못 튼다). 사건 소리: alarm=error_004, good=confirmation_002, bad=error_007, bell=glass_002,
fever=maximize_006, chest=maximize_008. (Kenney 블록형 캐릭터 시트는 커밋 1a997eb 의 render_chars.py 로 만든 것.)

## 문장

원본은 `i18n/*.json`. `lib/l10n/` 은 `python ../common/i18n/gen.py i18n/ --to flutter --out lib/l10n` 로 만든다.
새 문장은 한국어·영어만 쓰고 다른 언어에는 영어를 넣어 둔다. 앱이 거의 완성되면 영어와 같은 값인 키를 모아 한꺼번에 번역한다.

## 그림 출처

- 캐릭터: Quaternius "Ultimate Animated Character Pack" (CC0) — quaternius.com, Kenney "Mini Characters 1" (CC0) — www.kenney.nl
- 음식·가구: Kenney "Food Kit", "Furniture Kit" (CC0)
- 효과음: Kenney "Interface Sounds" (CC0)
- 글꼴: Jua (SIL OFL)
