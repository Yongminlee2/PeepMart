import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'engine/game.dart';

const _key = 'save_v4';

Future<Game?> loadGame() async {
  final raw = (await SharedPreferences.getInstance()).getString(_key);
  if (raw == null) return null;
  try {
    return Game.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null; // 형식이 바뀐 옛 저장은 버리고 새로 시작
  }
}

Future<void> saveGame(Game g) async {
  g.savedAt = DateTime.now().millisecondsSinceEpoch;
  await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(g.toJson()));
}
