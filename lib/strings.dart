import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/l10n.dart'; // ../i18n/gen.py --to flutter 가 만든다

export 'l10n/l10n.dart' show kLanguageNames, kLanguageOrder, kStrings;

/// 지금 고른 언어로 문장을 찾는다.
///
/// 표 자체는 `../i18n/gen.py --to flutter` 가 만든다. 손으로 고치지 않는다 —
/// 원본은 `i18n/<code>.json` 이다.
class S {
  static const Map<String, Map<String, String>> strings = kStrings;

  /// 아무것도 못 찾을 때 쓸 언어. **절대 비워 두지 않는다.**
  static const String fallback = 'en';

  /// 열쇠로 문장을 찾는다.
  ///
  /// 못 찾으면 **열쇠 자체를 돌려준다.** 던지지 않는다 — 안 옮겨진 문장은
  /// 화면에 보이는 버그지 크래시가 아니고, 어차피 테스트가 출시 전에 잡는다
  /// (아래 [missingKeys]).
  ///
  /// 조각을 이어 붙여 만들지 않는다. 왜 그러면 안 되는지는
  /// `../traps/03-i18n.md`.
  static String t(String key) {
    final lang = _resolve(AppLang().value);
    return strings[lang]?[key] ?? strings[fallback]![key] ?? key;
  }

  /// 숫자를 끼우는 문장. **문장을 쪼개지 말고 `{n}` 자리를 둔다.**
  ///
  ///     'stage_n': '{n}단계'      ko
  ///     'stage_n': 'Stage {n}'    en
  ///
  /// 이렇게 두면 숫자가 앞에 오는 말도, 셈낱말을 쓰는 말도 그 언어 어순으로
  /// 남는다. `'{n}' + t('stage')` 로 만들면 영어에서 「7Stage」가 된다.
  static String tn(String key, Map<String, Object> slots) {
    var out = t(key);
    slots.forEach((name, value) => out = out.replaceAll('{$name}', '$value'));
    return out;
  }

  /// 저장된 설정을 실제 표로 바꾼다.
  ///
  /// 'system' 은 **찾을 때마다** 기기 로케일로 푼다. 그래야 기기 언어를 바꿔도
  /// 앱을 다시 켜지 않고 반영된다.
  static String _resolve(String lang) {
    if (strings.containsKey(lang)) return lang;
    for (final locale in PlatformDispatcher.instance.locales) {
      final code = codeForLocale(
        locale.languageCode,
        locale.scriptCode,
        locale.countryCode,
      );
      if (code != null) return code;
    }
    return fallback;
  }

  /// 기기 로케일 → 우리 표 하나. 가진 게 없으면 null.
  ///
  /// **중국어만 표가 둘이다.** 대만·홍콩·마카오는 번체를 읽는다. 간체로
  /// 보여 줘도 읽히기는 하지만 남의 나라 글자로 읽힌다. 안드로이드가 이걸
  /// `zh-Hant` 로 줄 때도 있고 그냥 `zh-TW` 로 줄 때도 있어서 둘 다 본다.
  static String? codeForLocale(String lang, String? script, String? country) {
    if (lang == 'zh') {
      final traditional = script == 'Hant' ||
          const {'TW', 'HK', 'MO'}.contains(country?.toUpperCase());
      return traditional ? 'zh_Hant' : 'zh';
    }
    return strings.containsKey(lang) ? lang : null;
  }

  /// 어느 언어에 어떤 열쇠가 빠졌는지. **테스트에서 쓴다.**
  ///
  /// ```dart
  /// test('모든 언어가 영어와 같은 열쇠를 가진다', () {
  ///   expect(S.missingKeys(), isEmpty);
  /// });
  /// ```
  ///
  /// 이 테스트가 없으면 언어를 추가할 때 반쯤 빠진 채로 출시된다.
  /// 화면에는 영어가 섞여 나오는데 아무도 안 본다.
  static Map<String, List<String>> missingKeys() {
    final want = strings[fallback]!.keys.toSet();
    final out = <String, List<String>>{};
    strings.forEach((code, table) {
      final missing = want.difference(table.keys.toSet()).toList()..sort();
      final empty = table.entries.where((e) => e.value.trim().isEmpty).map((e) => e.key);
      final all = [...missing, ...empty];
      if (all.isNotEmpty) out[code] = all;
    });
    return out;
  }
}

/// 고른 언어. 'system' 이거나 [kStrings] 의 열쇠.
class AppLang extends ValueNotifier<String> {
  AppLang._() : super('system');
  static final AppLang _instance = AppLang._();
  factory AppLang() => _instance;

  static const _key = 'app_language';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getString(_key) ?? 'system';
  }

  Future<void> set(String lang) async {
    value = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lang);
  }
}
