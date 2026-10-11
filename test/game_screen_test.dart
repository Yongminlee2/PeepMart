import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';
import 'package:peep_mart/strings.dart';
import 'package:peep_mart/ui/game_screen.dart';
import 'package:peep_mart/ui/store_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final mapFinder = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is StorePainter);

/// 화면 가운데 = 처음 카메라 = 플레이어 자리. 그 칸에서 [t] 칸까지의 화면 위치.
Offset screenOf(WidgetTester tester, World w, (int, int) t) {
  final center = tester.getCenter(mapFinder);
  return center + iso(t.$1 + 0.0, t.$2 + 0.0) - iso(w.player.x, w.player.y);
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
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w)));
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
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w)));
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
      await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w)));
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
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('건설: 놓인 물건을 눌러 옮기기 → 새 자리 → ✓ (공짜)', (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = Game();
    final w = World(g, seed: 4);
    await tester.pumpWidget(MaterialApp(home: GameScreen(g, world: w)));
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
}
