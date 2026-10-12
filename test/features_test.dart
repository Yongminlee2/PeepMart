import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/catalog.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';

void run(World w, double seconds) {
  for (var t = 0.0; t < seconds; t += 0.05) {
    w.tick(0.05);
  }
}

Game shop(int level) {
  final g = Game()
    ..money = 50000
    ..level = level;
  g.owner.tutorial = TutorialStep.done;
  return g;
}

/// 문 닫기: 시간을 다 쓰고 손님을 내보낸다.
void close(World w) {
  w.dayTime = dayLength;
  w.customers.clear();
  w.tick(0.01);
  w.customers.clear();
  w.tick(0.01);
}

Item first(Game g, String type) => g.items.firstWhere((i) => i.type == type);

void main() {
  test('유통기한: 신선 진열대는 밤마다 늙고 기한이 되면 버린다, 임박이면 반값 스티커', () {
    final g = shop(3);
    final fridge = first(g, 'fridge');
    expect(g.setProduct(fridge, 'gimbap'), isTrue);
    fridge.stock = 4;
    final w = World(g, seed: 1);
    expect(g.expiring(fridge), isFalse);
    w.openDay();
    close(w);
    expect(fridge.age, 1);
    expect(g.expiring(fridge), isTrue);
    final full = g.salePrice(fridge, 'gimbap');
    expect(g.toggleSticker(fridge), isTrue);
    expect(g.salePrice(fridge, 'gimbap'), (full * stickerPrice).round());
    w.result = null;
    w.openDay();
    close(w);
    expect(fridge.stock, 0);
    expect(fridge.sticker, isFalse);
    expect(w.result!.wasted, 4);
    // 신선하지 않은 상품은 늙지 않는다
    expect(first(g, 'rack').age, 0);
  });

  test('명절: 8일마다 돌아오고, 그날만 한정 상품을 찾고, 손님이 더 온다', () {
    final g = shop(12);
    final days = [for (var d = 1; d <= 40; d++) if ((g..day = d).todayHoliday != null) d];
    expect(days, [4, 12, 20, 28, 36]);
    g.day = 4;
    final h = g.todayHoliday!;
    expect(g.demand, contains(holidayProduct(h).id));
    g.day = 5;
    expect(g.demand.where((p) => productById(p).holiday != null), isEmpty);
    // 레벨이 낮아 한정 상품을 못 들이면 명절도 없다
    final low = shop(4)..day = 4;
    expect(low.todayHoliday, isNull);
    // 명절 날 열면 손님이 한정 상품을 찾는다(없으면 못 판 것으로 센다)
    g.day = 4;
    final w = World(g, seed: 2)..openDay();
    expect(w.holiday, h);
    run(w, 60);
    expect(w.dayMissing.keys, contains(holidayProduct(h).id));
  });
}
