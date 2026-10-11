import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/ui/hub_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> show(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: w));
    await tester.pump();
  }

  testWidgets('동네 지도: 넘치지 않고, 열 수 있는 지점은 돈을 내고 들어간다', (tester) async {
    final o = Game().owner
      ..level = 10
      ..money = 10000;
    Game? entered;
    await show(tester, MapScreen(o, onEnter: (g) => entered = g));
    await tester.tap(find.byType(InkWell).at(1)); // 두 번째 지점(바닷가)
    await tester.pump();
    await tester.tap(find.byType(TextButton).last); // 확인
    await tester.pump();
    expect(entered?.branch, 'beach');
    expect(o.money, 10000 - 5000);
  });

  testWidgets('단골 수첩과 게임 방법이 넘치지 않고 열린다', (tester) async {
    final o = Game().owner..hearts['mina'] = 2;
    await show(tester, RegularsScreen(o));
    expect(find.textContaining('♥'), findsWidgets);
    await show(tester, const HelpScreen());
    expect(find.byType(Icon), findsWidgets);
  });

  testWidgets('도감: 손님·도장·세트 세 칸이 넘치지 않고 열린다', (tester) async {
    final o = Game().owner
      ..met.addAll([0, 1, 2])
      ..sold['soda'] = 30
      ..sold['donut'] = 5;
    await show(tester, DexScreen(o));
    expect(find.byType(Tab), findsNWidgets(3));
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(find.text('30/30'), findsOneWidget);
    await tester.tap(find.byType(Tab).last);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_outline_rounded), findsWidgets);
  });
}
