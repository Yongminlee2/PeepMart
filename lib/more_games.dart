/// 개발자의 다른 게임 — 목록은 legal 저장소(github.io)의 `apps.json` 하나에서 받는다.
///
/// 새 앱을 내면 그 파일만 고치면 이미 깔린 모든 앱에 나온다(앱 업데이트 없이).
/// 받은 목록은 저장해 두고, 못 받으면 저장해 둔 걸 보여 준다 — 지하철에서 열어도
/// 비지 않게. 지금 이 앱도 목록에 두되 [MoreGame.self]로 표시해 「받기」 대신
/// 「지금 게임」을 보여 준다.
///
/// 출처: common/promo/flutter/more_games.dart (동작 규칙은 common/promo/README.md 2번).
///
/// 붙이는 법: [selfId] 를 앱 패키지로 바꾸고, 안드로이드 `MainActivity` 와 아이폰
/// `AppDelegate` 에 같은 이름의 채널을 단다(common/promo/README.md 「Flutter」). 화면은 앱
/// 디자인대로 그린다.
///
/// **아이폰은 구글 플레이로 보내지 않는다**(애플 심사 지침 2.3.10 — 다른 플랫폼
/// 언급 금지). 목록 항목에 앱스토어 번호(`"ios": "1234567890"`)가 있는 게임만
/// 보여 주고([visible]) 앱스토어로 연다. 아이폰에서 받을 다른 게임이 하나도 없으면
/// 메인 화면의 단추 자체를 숨긴다([hasOthers]) — 빈 목록으로 가는 단추는
/// "준비 안 된 기능"으로 반려된다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MoreGame {
  final String id;
  final String name;
  final String desc;

  /// https 주소. 없거나 https가 아니면 빈 문자열.
  final String icon;

  /// 지금 이 앱인가 — 「받기」 대신 「지금 게임」.
  final bool self;

  /// 앱스토어 번호(숫자만). 없으면 빈 문자열이고 아이폰 목록에 안 나온다.
  final String iosId;
  const MoreGame(
    this.id,
    this.name,
    this.desc,
    this.icon, {
    this.self = false,
    this.iosId = '',
  });
}

abstract final class MoreGames {
  static const listUrl = 'https://yongminlee2.github.io/legal/apps.json';
  static const selfId = 'com.peep.mart';
  static const _key = 'moreGames.json';
  static const _keyAt = 'moreGames.fetchedAt';

  /// 아이폰 메인 화면이 목록을 다시 받는 간격. 단추를 보일지 정하려고 받는
  /// 것이라 자주 받을 이유가 없다(게임은 인터넷 없이 돈다).
  static const refreshEvery = Duration(hours: 24);
  static const channel = 'app/store';
  static const _store = MethodChannel(channel);

  static final _pkg = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');
  static final _digits = RegExp(r'^[0-9]{5,12}$');

  static bool get onIos => Platform.isIOS;

  /// 받은 JSON을 목록으로. 밖에서 받은 글이라 모양이 이상한 항목은 건너뛰고,
  /// 통째로 깨졌으면 빈 목록 — 목록 파일이 깨져도 앱이 죽으면 안 된다.
  ///
  /// 이름·소개는 [lang] 칸 → 영어 칸 → 기본 칸(한국어) 순으로 고른다.
  static List<MoreGame> parse(String json,
      {String self = selfId, String lang = 'ko', String base = listUrl}) {
    Object? root;
    try {
      root = jsonDecode(json);
    } catch (_) {
      return const [];
    }
    final apps = root is Map ? root['apps'] : null;
    if (apps is! List) return const [];

    final out = <MoreGame>[];
    for (final o in apps) {
      if (o is! Map) continue;
      final id = o['id'];
      if (id is! String || !_pkg.hasMatch(id)) continue;
      final tr = o['i18n'];
      String pick(String key) {
        if (lang != 'ko' && tr is Map) {
          for (final l in [lang, 'en']) {
            final v = tr[l] is Map ? tr[l][key] : null;
            if (v is String && v.trim().isNotEmpty) return v;
          }
        }
        final v = o[key];
        return v is String ? v : '';
      }

      final name = pick('name').trim();
      if (name.isEmpty) continue;
      var icon = '';
      final rel = o['icon'];
      if (rel is String && rel.isNotEmpty) {
        final u = Uri.tryParse(base)?.resolve(rel).toString() ?? '';
        if (u.startsWith('https://')) icon = u;
      }
      final ios = o['ios'];
      out.add(MoreGame(id, _cut(name, 40), _cut(pick('desc').trim(), 120), icon,
          self: id == self,
          iosId: ios is String && _digits.hasMatch(ios) ? ios : ''));
    }
    return out;
  }

  /// 이 플랫폼에서 보여 줄 줄. 아이폰은 지금 게임 + 앱스토어 번호가 있는 게임만.
  static List<MoreGame> visible(List<MoreGame> apps, {required bool ios}) =>
      ios ? [for (final a in apps) if (a.self || a.iosId.isNotEmpty) a] : apps;

  /// 지금 게임 말고 받을 수 있는 게임이 하나라도 있는가.
  static bool hasOthers(List<MoreGame> apps, {required bool ios}) =>
      visible(apps, ios: ios).any((a) => !a.self);

  /// 「받기」가 스토어에 넘길 값 — 안드로이드는 패키지, 아이폰은 앱스토어 번호.
  static String storeKey(MoreGame a, {required bool ios}) =>
      ios ? a.iosId : a.id;

  static String iosStoreUrl(String iosId) =>
      'https://apps.apple.com/app/id$iosId';

  static String _cut(String s, int n) =>
      s.runes.length <= n ? s : String.fromCharCodes(s.runes.take(n));

  /// 저장해 둔 목록 (없으면 null).
  static Future<String?> cached() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  /// 새로 받아 저장한다. 실패하면 null.
  static Future<String?> fetch() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse(listUrl));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      // 깨진 걸 저장해 두면 다음에도 못 보여 준다
      if (parse(body).isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, body);
      await prefs.setInt(_keyAt, DateTime.now().millisecondsSinceEpoch);
      return body;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 마지막으로 받은 지 [refreshEvery]가 지났으면 다시 받는다. 받았으면 그 글, 아니면 null.
  static Future<String?> refreshIfStale() async {
    try {
      final at = (await SharedPreferences.getInstance()).getInt(_keyAt) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - at;
      if (age < refreshEvery.inMilliseconds) return null;
    } catch (_) {
      return null;
    }
    return fetch();
  }

  /// 아이콘 파일. 한 번 받으면 캐시 폴더에 둬서 오프라인에서도 보인다. 실패하면 null.
  static Future<File?> icon(String url) async {
    if (url.isEmpty) return null;
    try {
      final dir = await getApplicationCacheDirectory();
      final f = File('${dir.path}/more_games_${url.hashCode}.img');
      if (await f.exists() && await f.length() > 0) return f;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final res = await (await client.getUrl(Uri.parse(url)))
            .close()
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return null;
        final bytes = <int>[];
        await for (final c in res) {
          bytes.addAll(c);
        }
        await f.writeAsBytes(bytes, flush: true);
        return f;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  /// 스토어 주소 뒷부분. 어느 앱에서 넘어왔는지 플레이 콘솔 획득 보고서에 남도록
  /// utm을 붙인다.
  static String storeQuery(String id, {String from = selfId}) =>
      'details?id=$id&referrer='
      '${Uri.encodeQueryComponent('utm_source=$from&utm_medium=more_games')}';

  /// 스토어로 바로 연다. [key]는 [storeKey] — 안드로이드는 패키지, 아이폰은 앱스토어 번호.
  ///
  /// 안드로이드: 삼성 폰은 갤럭시 스토어도 market:// 을 받아서 패키지를 안 정하면
  /// "어느 앱으로 열까요" 창이 먼저 뜬다 — 그래서 MainActivity 에서 플레이 스토어를
  /// 정해서 연다. 아이폰: AppDelegate 가 앱스토어 주소만 연다.
  static Future<void> openStore(String key) async {
    try {
      if (onIos) {
        if (!_digits.hasMatch(key)) return;
        await _store.invokeMethod('openUrl', iosStoreUrl(key));
      } else {
        await _store.invokeMethod('open', storeQuery(key));
      }
    } catch (_) {
      // 스토어를 못 열어도 게임은 그대로.
    }
  }
}
