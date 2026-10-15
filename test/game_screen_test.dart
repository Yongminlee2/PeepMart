import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/catalog.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';
import 'package:peep_mart/strings.dart';
import 'package:peep_mart/ui/game_screen.dart';
import 'package:peep_mart/ui/store_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final mapFinder = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is StorePainter);

/// 카메라는 시험에서 처음 자리(= 시작할 때 플레이어 = 입구)에 멈춰 있다. [t] 칸의 화면 위치.
Offset screenOf(WidgetTester tester, World w, (int, int) t) {
  final center = tester.getCenter(mapFinder);
  final start = w.game.entrances.first.tile;
  return center + iso(t.$1 + 0.0, t.$2 + 0.0) - iso(start.$1 + 0.0, start.$2 + 0.0);
}

Future<void> runFor(WidgetTester tester, double seconds) async {
  for (var i = 0; i < seconds * 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('상자를 누르면 걸어가서 들고, 진열대를 누르면 채운다', (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game();
    final fridge = g.items.firstWhere((i) => i.type == 'fridge')..stock = 0;
    final w = World(g, seed: 1);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
    await tester.pump();

    final box = g.items.firstWhere((i) => i.type == 'box' && i.product == 'soda');
    await tester.tapAt(screenOf(tester, w, box.tile));
    await runFor(tester, 5);
    expect(w.player.carry, contains('soda'));

    await tester.tapAt(screenOf(tester, w, fridge.tile));
    await runFor(tester, 5);
    expect(fridge.stock, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('한 손가락으로 끌면 지도가 움직이고, 그동안 플레이어는 가만히 있다', (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game();
    final w = World(g, seed: 2);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
    await tester.pump();
    final before = (w.player.x, w.player.y);
    await tester.dragFrom(const Offset(206, 500), const Offset(-120, -80));
    await runFor(tester, 1);
    expect((w.player.x, w.player.y), before);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [412.0, 360.0]) {
    testWidgets('건설: 진열대 고르기 → 상품 → 미리보기 → 옮기고 ✓ 로 놓기 (폭 $width)', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = Game()..money = 1000;
      final w = World(g, seed: 3);
      await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.handyman_rounded));
      await tester.pump();
      await tester.tap(find.text(S.t('i_rack')).hitTestable().first);
      await runFor(tester, 1); // 게임이 계속 움직여서 pumpAndSettle 은 끝나지 않는다
      await tester.tap(find.text(S.t('p_donut')).last);
      await runFor(tester, 1); // 게임이 계속 움직여서 pumpAndSettle 은 끝나지 않는다
      final before = g.items.length;
      // 미리보기가 생겼다 → 빈 칸을 눌러 옮기고 ✓
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final center = tester.getCenter(mapFinder);
      await tester.tapAt(center + iso(5, 5) - iso(w.player.x, w.player.y));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      expect(g.items.length, before + 1);
      expect(g.at((5, 5))?.type, 'rack');
      expect(g.at((5, 5))?.product, 'donut');
      // 놓으면 놓기가 끝나서, 방금 놓은 걸 바로 눌러 팔 수 있다 (실기기에서 받은 제보)
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      final m = g.money;
      await tester.tapAt(center + iso(5, 5) - iso(w.player.x, w.player.y) + const Offset(0, -20));
      await runFor(tester, 0.3);
      await tester.tap(find.byIcon(Icons.sell_rounded));
      await runFor(tester, 0.3);
      expect(g.at((5, 5)), isNull);
      expect(g.money, greaterThan(m));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('건설: 놓인 물건을 눌러 옮기기 → 새 자리 → ✓ (공짜)', (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game();
    final w = World(g, seed: 4);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.handyman_rounded));
    await runFor(tester, 0.5);
    final money = g.money;
    final center = tester.getCenter(mapFinder);
    Offset at((int, int) t) => center + iso(t.$1 + 0.0, t.$2 + 0.0) - iso(w.player.x, w.player.y);
    await tester.tapAt(at((3, 3))); // 도넛 선반
    await runFor(tester, 0.3);
    await tester.tap(find.byIcon(Icons.open_with_rounded));
    await runFor(tester, 0.3);
    await tester.tapAt(at((4, 5)));
    await runFor(tester, 0.3);
    await tester.tap(find.byIcon(Icons.check_rounded));
    await runFor(tester, 0.3);
    expect(g.at((3, 3)), isNull);
    expect(g.at((4, 5))?.type, 'rack');
    expect(g.money, money);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('계산대 몸통(바닥 칸보다 위)을 눌러도 계산 자리로 간다 — 실기기에서 잡힌 문제', (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game();
    final w = World(g, seed: 5);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
    await tester.pump();
    final reg = g.registers.first;
    // 계산대 그림의 위쪽(기계 부분)을 누른다
    await tester.tapAt(screenOf(tester, w, reg.tile) + const Offset(0, -38));
    await runFor(tester, 5);
    expect(w.atAnyTill, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('하루 장사: 문 열기 → 마감 → 결과 창 → 다음 날 단추', (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game();
    g.owner.tutorial = TutorialStep.done;
    g.owner.story.addAll(chapters.map((c) => c.id)); // 이야기 창이 가리지 않게
    final w = World(g, seed: 6);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
    await tester.pump();
    expect(w.phase, DayPhase.closed);

    await tester.tap(find.text(S.tn('day_open', {'n': 1})));
    await tester.pump();
    expect(w.phase, DayPhase.open);
    expect(find.text(S.tn('day_n', {'n': 1})), findsOneWidget);

    w.dayTime = dayLength - 0.01;
    w.customers.clear();
    await runFor(tester, 1);
    expect(w.phase, DayPhase.closed);
    expect(find.text(S.tn('day_result', {'n': 1})), findsOneWidget);

    await tester.tap(find.text(S.t('btn_nice')));
    await runFor(tester, 1);
    expect(find.text(S.tn('day_result', {'n': 1})), findsNothing);
    expect(w.result, isNull);
    expect(find.text(S.tn('day_open', {'n': 2})), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('배달 주문 카드: 배달 가기 → 문 앞으로', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game()..level = 15;
    g.owner.tutorial = TutorialStep.done;
    g.owner.story.addAll(chapters.map((c) => c.id)); // 이야기 창이 가리지 않게
    final w = World(g, seed: 7)..openDay();
    w.order = Order(['soda', 'donut']);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
    await tester.pump();
    await tester.tap(find.text(S.t('order_go')));
    await tester.pump();
    expect(w.order!.started, isTrue);
    expect(find.text(S.t('order_picking')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('이야기: 안내를 마치면 첫 이야기가 뜨고, 읽는 동안 시간이 멈춘다', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game();
    g.owner.tutorial = TutorialStep.done;
    final w = World(g, seed: 8);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w, followCamera: false)));
    // 대사는 한 글자씩 나온다: 충분히 기다린 뒤 본다
    await runFor(tester, 4);
    expect(find.text(S.t('story_opening_0')), findsOneWidget);
    final t = w.time;
    await runFor(tester, 1);
    expect(w.time, t); // 멈춤
    for (var i = 0; i < 4; i++) {
      await tester.tapAt(const Offset(180, 300)); // 눌러서 다음 줄
      await runFor(tester, 4);
    }
    expect(find.text(S.t('story_opening_4')), findsOneWidget);
    await tester.tapAt(const Offset(180, 300));
    await runFor(tester, 1);
    expect(g.owner.story, contains('opening'));
    expect(w.time, greaterThan(t));
    await tester.pumpWidget(const SizedBox());
  });
}
