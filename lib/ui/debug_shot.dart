import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/game.dart';
import '../engine/world.dart';
import '../save.dart';
import '../strings.dart';
import 'game_screen.dart';
import 'hub_screens.dart';
import 'more_games_screen.dart';
import 'title_screen.dart';

/// 시뮬레이터 화면 확인·스토어 스크린샷용(아이폰 디버그 빌드만). 이 맥의 시뮬레이터는
/// 탭이 앱에 닿지 않아서 실행 인자로 열 화면을 정한다:
///
///     xcrun simctl launch <기기> com.peep.mart -shot game -lang en
///
/// 앱 Documents 에 shot_save.json(test/shot_save_test.dart 가 만든다)이 있으면 그 가게로 연다.
/// 실행 인자는 AppDelegate 의 `peep/debug` 채널이 주는데 그것도 DEBUG 에서만 있다 —
/// 정식 빌드에선 [kDebugMode] 가 상수 false 라 여기는 통째로 빠진다.
const shotNames = ['title', 'game', 'closed', 'build', 'map', 'regulars', 'dex', 'story', 'help', 'more'];

Future<Widget?> debugShotHome() async {
  if (!kDebugMode || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  List<String> args;
  try {
    args = await const MethodChannel('peep/debug').invokeListMethod<String>('args') ?? const [];
  } catch (_) {
    return null;
  }
  String? arg(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final shot = arg('-shot');
  if (shot == null || !shotNames.contains(shot)) return null;
  final lang = arg('-lang');
  if (lang != null && S.strings.containsKey(lang)) AppLang().value = lang; // 저장하지 않는다

  Game? g;
  try {
    final f = File('${(await getApplicationDocumentsDirectory()).path}/shot_save.json');
    if (f.existsSync()) g = Game.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  } catch (_) {}
  if (g != null) {
    // 자동 플레이는 이야기를 안 읽는다 — 이야기 창이 화면을 가리지 않게 읽은 것으로
    if (shot != 'story') {
      for (var ch = g.owner.nextChapter; ch != null; ch = g.owner.nextChapter) {
        g.owner.story.add(ch.id);
      }
    }
    await saveGame(g); // 첫 화면에 「이어서 하기」
    g.savedAt = 0; // 「자리 비운 동안 번 돈」 창도 안 띄운다
  }
  final game = g ?? Game();

  return switch (shot) {
    'game' => GameScreen(game, world: _busy(game)),
    'closed' => GameScreen(game),
    'build' => GameScreen(game, debugBuild: true),
    'map' => MapScreen(game.owner, onEnter: (_) {}),
    'regulars' => RegularsScreen(game.owner),
    'dex' => DexScreen(game.owner),
    'story' => StoryScreen(game.owner),
    'help' => const HelpScreen(),
    'more' => const MoreGamesScreen(),
    _ => const TitleScreen(),
  };
}

/// 문을 열고 잠깐 돌려 손님이 들어와 있는 가게.
World _busy(Game g) {
  final w = World(g, seed: 5)..openDay();
  for (var i = 0; i < 25 * 20; i++) {
    w.tick(0.05);
    w.fx.clear();
  }
  return w;
}
