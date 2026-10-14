// 스토어 스크린샷용 저장 만들기. 평소엔 건너뛰고, 켰을 때만 돈다:
//
//     SHOT_SAVE=120 flutter test test/shot_save_test.dart
//
// 밸런스 자동 플레이(Bot)로 숫자만큼 분 동안 가게를 키운 뒤 build/shot_save.json 에 쓴다.
// tool/ios_shots.py 가 이 파일을 시뮬레이터 앱의 Documents 에 넣고 `-shot` 으로 화면을 연다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';

import 'balance_test.dart' show Bot;

void main() {
  final minutes = int.tryParse(Platform.environment['SHOT_SAVE'] ?? '');
  test('스크린샷용 저장', () {
    final g = Game();
    final w = World(g, seed: 11);
    final bot = Bot(w);
    const dt = 0.1;
    // 정한 시간이 지나면 그날 장사가 끝날 때(닫힌 가게)까지만 더 돌린다
    for (var t = 0.0;; t += dt) {
      bot.tick(dt);
      w.tick(dt);
      w.fx.clear();
      final done = w.result != null;
      w.result = null;
      if (done && t >= minutes! * 60) break;
      if (w.phase == DayPhase.closed) w.openDay();
    }
    Directory('build').createSync(recursive: true);
    File('build/shot_save.json').writeAsStringSync(jsonEncode(g.toJson()));
    // ignore: avoid_print
    print('레벨 ${g.level}, 돈 ${g.money}, 진열대 ${g.shelves.length}, 땅 ${g.plots.length}, ${g.day}일째');
  }, skip: minutes == null, timeout: const Timeout(Duration(minutes: 30)));
}
