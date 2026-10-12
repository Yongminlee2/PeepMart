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

  test('셀프 계산대: 계산원 없이 손님이 찍고, 오류가 나면 점장이 고쳐야 다시 돈다', () {
    final g = shop(10);
    // 원래 계산대를 팔 수 없으니 셀프 계산대를 하나 더 놓고, 원래 것은 줄이 안 생기게 막는다
    expect(g.place('selfcheck', (4, 5)), isTrue);
    final self = g.at((4, 5))!;
    final w = World(g, seed: 9)..openDay();
    var paidAtSelf = 0, errors = 0;
    for (var i = 0; i < 3000; i++) {
      for (final s in g.shelves) {
        s.stock = s.capacity;
      }
      w.tick(0.05);
      errors += w.fx.where((e) => e.kind == FxKind.incident && e.amount == Incident.selfError.index).length;
      paidAtSelf += w.fx.where((e) => e.kind == FxKind.pay && e.x == 4 && e.y == 5).length;
      if (self.broken && i % 400 == 399) self.broken = false; // 가끔 점장이 고쳐 준 셈
      w.fx.clear();
    }
    expect(paidAtSelf, greaterThan(0));
    expect(errors, greaterThan(0));
    // 계산원은 셀프 계산대에 서지 않는다
    g.hire(Staff.cashier);
    g.hire(Staff.cashier);
    run(w, 3);
    expect(w.staff.where((s) => s.item == self), isEmpty);
  });

  test('동네 매출 순위: 7일마다 순위를 매기고, 1~3위는 상금, 순위표는 매출 순', () {
    final g = shop(3);
    final w = World(g, seed: 10);
    for (var d = 1; d <= 7; d++) {
      w.openDay();
      w.daySales = 500; // 매일 같은 매출
      close(w);
      if (d < 7) {
        expect(w.result!.weekRank, 0);
        expect(g.weekSales, 500 * d);
      }
      w.result = null;
    }
    // 같은 만큼만 벌면 평소보다 30% 더 버는 메가마트를 못 이긴다
    final last = g.lastWeekRank;
    expect(last, greaterThan(1));
    expect(g.weekSales, 0);
    final st = g.standings();
    expect(st.length, rivalShops.length + 1);
    for (var i = 1; i < st.length; i++) {
      expect(st[i - 1].$2, greaterThanOrEqualTo(st[i].$2));
    }
    // 한 주 동안 크게 벌면 1위
    for (var d = 1; d <= 7; d++) {
      w.openDay();
      w.daySales = 5000;
      close(w);
      if (d == 7) {
        expect(w.result!.weekRank, 1);
        expect(w.result!.weekPrize, greaterThan(0));
      }
      w.result = null;
    }
    final back = Game.fromJson(g.toJson());
    expect(back.lastWeekRank, 1);
  });

  test('검토에서 나온 것: 7일째에 나가도 순위 정산, 1+1 로 비워도 날짜 새로, 한정 상품은 그날만, 야간 일당은 그 결과에', () {
    // 7일째 장사 중에 나가면(abandonDay) 그 주 순위를 매긴다
    final g = shop(3)..day = 7;
    final w = World(g, seed: 13)..openDay();
    w.daySales = 300;
    w.abandonDay();
    expect(g.day, 8);
    expect(g.weekSales, 0);
    expect(g.lastWeekRank, greaterThan(0));
    // 1+1 로 진열대가 비면 날짜·스티커가 새로
    final g2 = shop(3)..owner.tutorial = TutorialStep.done;
    final fr = first(g2, 'fridge');
    g2.setProduct(fr, 'gimbap');
    fr
      ..stock = 2
      ..age = 1
      ..sticker = true;
    g2.setPromo(Promo.onePlusOne, product: 'gimbap');
    final w2 = World(g2, seed: 14)..openDay();
    for (var i = 0; i < 1200 && fr.stock > 0; i++) {
      w2.tick(0.05);
    }
    expect(fr.stock, 0);
    expect(fr.age, 0);
    expect(fr.sticker, isFalse);
    // 명절이 아닌 날엔 진열해 둔 한정 상품도 안 팔린다
    final g3 = shop(12)..day = 5;
    final rack = first(g3, 'rack');
    g3.setProduct(rack, 'lollipop');
    rack.stock = 8;
    final w3 = World(g3, seed: 15)..openDay();
    var bought = false;
    for (var i = 0; i < 1200; i++) {
      w3.tick(0.05);
      bought |= w3.customers.any((c) => c.kind != CustomerKind.thief && c.carry.contains('lollipop'));
    }
    expect(bought, isFalse); // (도둑은 아무거나 훔친다)
    // 야간 영업의 일당은 그 밤 결과에 나오고 다음 날로 안 넘어간다
    final g4 = shop(10);
    g4.hire(Staff.cashier);
    final w4 = World(g4, seed: 16)..openDay();
    close(w4);
    w4.result = null;
    w4.openNight();
    run(w4, nightLength + 1);
    for (var i = 0; i < 400 && w4.result == null; i++) {
      w4.customers.clear();
      w4.tick(0.05);
    }
    expect(w4.result!.night, isTrue);
    expect(w4.result!.wages, greaterThan(0));
    expect(g4.spentWages, 0);
  });
}
