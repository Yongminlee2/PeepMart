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

  test('홍보: 전단지는 돈을 내고 내일 하루만, 1+1 은 하나 사면 하나 더 가져간다', () {
    final g = shop(3)..avgSales = 400;
    final money = g.money;
    expect(g.setPromo(Promo.flyer), isTrue);
    expect(g.money, money - g.flyerCost);
    expect(g.setPromo(Promo.flyer), isFalse); // 하루에 하나
    final w = World(g, seed: 4)..openDay();
    expect(w.promo, Promo.flyer);
    expect(g.promo, isNull);
    close(w);
    expect(w.promo, isNull);
    // 1+1: 진열된 상품만
    expect(g.setPromo(Promo.onePlusOne, product: 'gimbap'), isFalse);
    expect(g.setPromo(Promo.onePlusOne, product: 'donut'), isTrue);
    final rack = first(g, 'rack')..stock = 8;
    w.result = null;
    w.openDay();
    run(w, 40); // 계산할 사람이 없으니 손님은 물건을 든 채 줄을 선다
    expect(rack.stock, lessThan(7));
    expect(w.customers.any((c) => c.carry.where((p) => p == 'donut').length >= 2), isTrue);
    // 저장했다 불러와도 남는다
    g.promo = null;
    g.setPromo(Promo.onePlusOne, product: 'soda');
    final back = Game.fromJson(g.toJson());
    expect(back.promo, Promo.onePlusOne);
    expect(back.promoProduct, 'soda');
  });

  test('즉석 조리: 온장 진열대에 채운 건 날것이고, 점장이 옆에 서 있어야 익는다', () {
    final g = shop(9);
    expect(g.place('hotcounter', (4, 5), product: 'cupramen'), isTrue);
    final hot = g.at((4, 5))!..stock = 0;
    final w = World(g, seed: 5);
    w.player
      ..x = 4
      ..y = 6
      ..carry.addAll(['cupramen', 'cupramen', 'cupramen']);
    run(w, 0.5);
    expect(hot.raw, 3);
    expect(hot.stock, 0);
    run(w, cookTime + 0.2);
    expect(hot.stock, cookBatch);
    run(w, cookTime + 0.2);
    expect(hot.raw, 0);
    expect(hot.stock, 3);
    // 멀리 있으면 안 익는다
    hot.raw = 2;
    w.player
      ..x = 1
      ..y = 6;
    run(w, cookTime * 2);
    expect(hot.raw, 2);
  });

  test('수익 기계: 나가는 손님이 쓰면 돈, 고장 나면 못 쓰고 점장이 옆에 서면 고친다', () {
    final g = shop(12);
    g.hire(Staff.cashier);
    expect(g.place('vending', (4, 5)), isTrue);
    final m = g.at((4, 5))!;
    final w = World(g, seed: 3)..openDay();
    var paid = 0, broke = false;
    for (var i = 0; i < 3600 && !broke; i++) {
      for (final s in g.shelves) {
        s.stock = s.capacity;
      }
      w.tick(0.05);
      paid += w.fx.where((e) => e.kind == FxKind.pay && e.amount == machineSpecs['vending']!.$2 && e.x == 4 && e.y == 5).length;
      broke = m.broken;
      w.fx.clear();
    }
    expect(paid, greaterThan(0));
    m.broken = true;
    w.player
      ..x = 4
      ..y = 6
      ..path = [];
    run(w, repairTime + 0.3);
    expect(m.broken, isFalse);
  });

  test('서비스 카운터: 택배·복권 손님이 오고, 점장이 옆에 서 있으면 처리해 수수료를 받는다', () {
    final g = shop(6);
    expect(g.place('service', (4, 5)), isTrue);
    final w = World(g, seed: 6)..openDay();
    // 점장은 카운터 옆에 서 있는다
    w.player
      ..x = 4
      ..y = 6;
    var fees = 0, seen = false;
    for (var i = 0; i < 2400; i++) {
      for (final s in g.shelves) {
        s.stock = s.capacity;
      }
      w.tick(0.05);
      seen |= w.customers.any((c) => c.kind == CustomerKind.service);
      fees += w.fx.where((e) => e.kind == FxKind.pay && e.x == 4 && e.y == 5).length;
      w.fx.clear();
    }
    expect(seen, isTrue);
    expect(fees, greaterThan(0));
    // 카운터를 팔면 기다리던 서비스 손님은 그냥 간다(멈추지 않는다)
    g.sell(g.at((4, 5))!);
    run(w, 30);
    expect(w.customers.where((c) => c.kind == CustomerKind.service && c.state == CState.atShelf), isEmpty);
  });

  test('알바 성장·성격: 뽑을 때 성격이 붙고, 일하면 숙련도가 오르고, 조는 알바는 점장이 깨운다', () {
    final g = shop(6);
    for (var i = 0; i < 3; i++) {
      expect(g.hire(Staff.cashier), isTrue);
    }
    expect(g.traitsOf(Staff.cashier).length, 3);
    g.fire(Staff.cashier);
    expect(g.traitsOf(Staff.cashier).length, 2);
    expect(staffLevel(0), 1);
    expect(staffLevel(staffXpUnit * 4), 3);
    // 저장 왕복
    g.addStaffXp(Staff.cashier, 100);
    final back = Game.fromJson(g.toJson());
    expect(back.traitsOf(Staff.cashier), g.traitsOf(Staff.cashier));
    expect(back.staffLevelOf(Staff.cashier), g.staffLevelOf(Staff.cashier));
    // 졸음: 조는 동안 일 안 하고, 점장이 다가가면 깬다
    g.traits[Staff.cashier] = [Trait.sleepy, Trait.sleepy];
    final w = World(g, seed: 7)..openDay();
    run(w, 1);
    final s = w.staff.firstWhere((s) => s.kind == Staff.cashier)..asleep = true;
    w.player
      ..x = s.x
      ..y = s.y;
    run(w, 0.1);
    expect(s.asleep, isFalse);
    // 계산하면 숙련도가 쌓인다
    final xp = g.staffXp[Staff.cashier] ?? 0;
    for (var i = 0; i < 1200; i++) {
      for (final sh in g.shelves) {
        sh.stock = sh.capacity;
      }
      for (final a in w.staff) {
        a.asleep = false;
      }
      w.tick(0.05);
    }
    expect(g.staffXp[Staff.cashier]!, greaterThan(xp));
  });

  test('야간 영업: 낮 장사를 끝낸 뒤 하루 한 번, 1분, 값을 더 받고 날짜는 안 넘어간다', () {
    final g = shop(10);
    g.hire(Staff.cashier);
    final w = World(g, seed: 8);
    expect(w.canOpenNight, isFalse); // 낮 장사 전
    w.openDay();
    close(w);
    expect(w.canOpenNight, isFalse); // 결과 창을 보는 동안
    w.result = null;
    expect(w.canOpenNight, isTrue);
    final day = g.day;
    w.openNight();
    expect(w.night, isTrue);
    expect(w.dayLeft, nightLength);
    for (var i = 0; i < 2000 && w.phase != DayPhase.closed; i++) {
      for (final s in g.shelves) {
        s.stock = s.capacity;
      }
      w.tick(0.05);
    }
    for (var i = 0; i < 400 && w.result == null; i++) {
      w.customers.clear();
      w.tick(0.05);
    }
    expect(w.result!.night, isTrue);
    expect(g.day, day);
    expect(w.night, isFalse);
    w.result = null;
    expect(w.canOpenNight, isFalse); // 하루 한 번
    // 낮은 등급은 못 연다
    final low = World(shop(5)..owner.tutorial = TutorialStep.done, seed: 1)..openDay();
    close(low);
    low.result = null;
    expect(low.canOpenNight, isFalse);
  });
}
