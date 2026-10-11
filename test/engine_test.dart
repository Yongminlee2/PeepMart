import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/catalog.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';

void run(World w, double seconds) {
  for (var t = 0.0; t < seconds; t += 0.05) {
    w.tick(0.05);
  }
}

void stand(World w, Tile t) => w.player
  ..x = t.$1.toDouble()
  ..y = t.$2.toDouble();

Item first(Game g, String type) => g.items.firstWhere((i) => i.type == type);

void main() {
  group('짓기', () {
    test('처음 가게: 빈 자리에 놓을 수 있고 계산대 줄이 있다', () {
      final g = Game();
      expect(g.canPlace('plant', (5, 5)), PlaceResult.ok);
      expect(g.queueTiles(first(g, 'register')), isNotEmpty);
    });

    test('잠긴 것·돈 모자람·남의 땅·겹침은 못 놓는다', () {
      final g = Game()..money = 100000;
      expect(g.canPlace('freezer', (5, 5)), PlaceResult.locked);
      expect(g.canPlace('rack', (9, 1)), PlaceResult.notOwned);
      expect(g.canPlace('rack', (2, 3)), PlaceResult.occupied); // 냉장고 자리
      final reg = first(g, 'register');
      expect(g.canPlace('rack', reg.till), PlaceResult.occupied);
      expect(g.canPlace('rack', reg.front), PlaceResult.occupied);
      g.money = 10;
      expect(g.canPlace('rack', (5, 5)), PlaceResult.money);
    });

    test('입구를 막아 가게가 갇히게는 못 짓는다', () {
      final g = Game()..money = 100000;
      final e = first(g, 'entrance').tile; // (7,7) 구석
      expect(g.place('plant', (e.$1 - 1, e.$2)), isTrue);
      expect(g.canPlace('plant', (e.$1, e.$2 - 1)), PlaceResult.blocksPath);
    });

    test('놓으면 돈이 빠지고, 팔면 절반을 돌려받는다. 마지막 계산대·입구는 못 판다', () {
      final g = Game()..money = 1000;
      expect(g.place('rack', (5, 5), product: 'donut'), isTrue);
      expect(g.money, 1000 - 40);
      final rack = g.at((5, 5))!;
      expect(rack.stock, rack.capacity);
      expect(g.sell(rack), isTrue);
      expect(g.money, 1000 - 40 + 20);
      expect(g.sell(first(g, 'register')), isFalse);
      expect(g.sell(first(g, 'entrance')), isFalse);
    });

    test('계산대를 돌리면 계산 자리가 바뀌고 줄이 남는다', () {
      final g = Game();
      final reg = first(g, 'register');
      final till = reg.till;
      expect(g.rotate(reg), isTrue);
      expect(reg.till, isNot(till));
      expect(g.queueTiles(reg), isNotEmpty);
    });

    test('상품 바꾸기: 맞는 진열대·열린 상품만, 바꾸면 비워진다', () {
      final g = Game();
      final rack = first(g, 'rack');
      expect(g.setProduct(rack, 'soda'), isFalse); // 냉장 상품
      expect(g.setProduct(rack, 'noodles'), isFalse); // 레벨 2
      g.level = 2;
      expect(g.setProduct(rack, 'noodles'), isTrue);
      expect(rack.stock, 0);
    });

    test('땅은 맞닿은 필지만 살 수 있고, 사면 그 칸들이 내 땅이 된다', () {
      final g = Game()..money = 100000;
      expect(g.plotsForSale, {(1, 0), (0, 1)});
      expect(g.buyPlot((2, 0)), isFalse);
      final price = g.nextPlotPrice;
      expect(g.buyPlot((1, 0)), isTrue);
      expect(g.money, 100000 - price);
      expect(g.owns((9, 3)), isTrue);
      expect(g.nextPlotPrice, greaterThan(price));
      expect(g.plotsForSale, containsAll([(2, 0), (1, 1), (0, 1)]));
    });

    test('땅을 전부 사면 지도 전체가 내 것이 된다', () {
      final g = Game()..money = 1 << 40;
      while (g.plotsForSale.isNotEmpty) {
        expect(g.buyPlot(g.plotsForSale.first), isTrue);
      }
      expect(g.plots.length, plotCols * plotRows);
      expect(g.owns((mapW - 1, mapH - 1)), isTrue);
    });

    test('바닥 칠하기는 진열대 밑에도 된다', () {
      final g = Game();
      expect(g.place('floor-pink', (2, 3)), isTrue);
      expect(g.floors[(2, 3)], 'floor-pink');
    });
  });

  group('레벨·직원·업그레이드', () {
    test('경험치가 차면 레벨이 오르고 남은 경험치는 이월된다', () {
      final g = Game();
      final need = xpToNext(1) + xpToNext(2);
      expect(g.addXp(need + 3), 2);
      expect(g.level, 3);
      expect(g.xp, 3);
    });

    test('모든 상품·가구는 최고 레벨 안에서 열린다', () {
      expect(products.every((p) => p.level <= maxLevel), isTrue);
      expect(itemTypes.every((t) => t.level <= maxLevel), isTrue);
      for (final k in ShelfKind.values) {
        expect(itemTypes.any((t) => t.shelf == k), isTrue, reason: '$k 진열대가 없다');
        expect(products.any((p) => p.kind == k), isTrue, reason: '$k 상품이 없다');
      }
    });

    test('직원은 레벨이 되고 돈이 있어야 고용하고, 일당이 매겨진다', () {
      final g = Game()..money = 1000;
      expect(g.hire(Staff.cashier), isFalse); // 레벨 2부터
      g.level = 2;
      expect(g.hire(Staff.cashier), isTrue);
      expect(g.money, 1000 - staffSpecs[Staff.cashier]!.hire);
      expect(g.wages, staffSpecs[Staff.cashier]!.wage);
    });

    test('일당은 주기마다 빠진다', () {
      final g = Game()..staff[Staff.janitor] = 2;
      g.items.removeWhere((i) => i.t.kind == ItemKind.shelf); // 손님이 안 오게
      final w = World(g, seed: 1);
      final m = g.money;
      run(w, wagePeriod + 0.1);
      expect(g.money, m - 2 * staffSpecs[Staff.janitor]!.wage);
    });

    test('업그레이드는 단계마다 레벨·값이 필요하고 끝이 있다', () {
      final g = Game()..money = 100000;
      expect(g.buyUpgrade(Upgrade.shoes), isFalse);
      g.level = 30;
      for (var i = 0; i < upgradeSteps[Upgrade.shoes]!.length; i++) {
        expect(g.buyUpgrade(Upgrade.shoes), isTrue);
      }
      expect(g.buyUpgrade(Upgrade.shoes), isFalse);
      expect(g.speed, playerSpeed * 1.75);
    });
  });

  group('손님과 일', () {
    test('상자 옆에 서면 들고, 진열대 옆에 서면 채운다', () {
      final g = Game();
      final fridge = first(g, 'fridge')..stock = 0;
      final w = World(g, seed: 2);
      stand(w, (1, 1)); // 콜라 상자 (1,0) 앞
      run(w, 2);
      expect(w.player.carry, List.filled(g.arms, 'soda'));
      stand(w, (2, 4)); // 냉장고 (2,3) 앞
      run(w, 2);
      expect(fridge.stock, greaterThanOrEqualTo(g.arms - 1)); // 그새 손님이 하나 집을 수 있다
    });

    test('내가 계산하면 돈이 계산대 옆에 쌓였다 들어오고, 경험치가 오른다', () {
      final g = Game();
      final reg = first(g, 'register');
      final w = World(g, seed: 3);
      stand(w, reg.till);
      final m = g.money;
      for (var i = 0; i < 3000 && g.served == 0; i++) {
        w.tick(0.05);
      }
      expect(g.served, 1);
      run(w, 1);
      expect(reg.cash, 0);
      expect(g.money, greaterThan(m));
      expect(g.level > 1 || g.xp > 0, isTrue);
    });

    test('계산원이 서 있으면 돈이 바로 들어온다', () {
      final g = Game()..staff[Staff.cashier] = 1;
      final w = World(g, seed: 4);
      stand(w, (0, 7));
      run(w, 50);
      expect(g.served, greaterThan(0));
      expect(first(g, 'register').cash, 0);
    });

    test('진열원은 상자가 있는 상품만 채운다', () {
      final g = Game()..staff[Staff.stocker] = 1;
      final fridge = first(g, 'fridge')..stock = 0;
      final rack = first(g, 'rack')..stock = 0;
      g.sell(g.items.firstWhere((i) => i.type == 'box' && i.product == 'donut'));
      final w = World(g, seed: 5);
      stand(w, (0, 7));
      run(w, 12);
      expect(fridge.stock, greaterThan(0));
      expect(rack.stock, 0);
    });

    test('휴지통이 멀면 쓰레기가 생기고, 플레이어와 청소부가 치운다', () {
      final g = Game()..staff[Staff.cashier] = 1;
      g.sell(first(g, 'bin'));
      final w = World(g, seed: 6);
      stand(w, (0, 7));
      for (var i = 0; i < 40000 && g.trash.isEmpty; i++) {
        w.tick(0.05);
        for (final s in g.shelves) {
          s.stock = s.capacity; // 손님이 계속 사게
        }
      }
      expect(g.trash, isNotEmpty);
      final t = g.trash.first;
      stand(w, t);
      run(w, 0.1);
      expect(g.trash.contains(t), isFalse);
      stand(w, (0, 7));
      g.trash.add((5, 6));
      g.staff[Staff.janitor] = 1;
      run(w, 15);
      expect(g.trash.contains((5, 6)), isFalse);
    });

    test('빈 진열대 앞에서 기다리다 포기한다', () {
      final g = Game();
      first(g, 'fridge').stock = 0;
      first(g, 'rack').stock = 0;
      final w = World(g, seed: 7);
      stand(w, (0, 7));
      run(w, shelfPatience * 3 + 20);
      expect(g.recent, contains(1));
    });

    test('앉아 먹는 상품을 사면 빈 의자에 앉았다 간다', () {
      final g = Game()
        ..level = 7
        ..money = 10000
        ..staff[Staff.cashier] = 1;
      g.sell(first(g, 'fridge'));
      expect(g.place('coffeemachine', (2, 3), product: 'coffee'), isTrue);
      expect(g.place('chair', (1, 5)), isTrue);
      final w = World(g, seed: 8);
      stand(w, (0, 7));
      var sat = false;
      for (var i = 0; i < 6000 && !sat; i++) {
        w.tick(0.05);
        sat = w.customers.any((c) => c.state == CState.sitting);
        for (final s in g.shelves) {
          s.stock = s.capacity;
        }
      }
      expect(sat, isTrue);
    });

    test('계산대가 둘이면 손님이 짧은 줄로 나뉜다', () {
      final g = Game()..money = 10000;
      expect(g.place('register', (6, 5)), isTrue);
      g.place('rack', (4, 5), product: 'donut');
      g.place('fridge', (2, 5), product: 'soda');
      final w = World(g, seed: 9);
      stand(w, (0, 7));
      var both = false;
      for (var i = 0; i < 6000 && !both; i++) {
        w.tick(0.05);
        both = w.queues.values.where((q) => q.isNotEmpty).length >= 2;
      }
      expect(both, isTrue);
    });

    test('짓고 팔기를 마구 해도 멈추지 않고, 가게가 갇히지 않는다', () {
      final rng = Random(42);
      final g = Game()
        ..money = 1 << 30
        ..level = 30;
      for (final p in [(1, 0), (0, 1), (1, 1)]) {
        g.buyPlot(p);
      }
      g.staff
        ..[Staff.cashier] = 2
        ..[Staff.stocker] = 2
        ..[Staff.janitor] = 1;
      final w = World(g, seed: 10);
      final types = itemTypes.map((t) => t.id).toList();
      for (var step = 0; step < 400; step++) {
        final t = (rng.nextInt(16), rng.nextInt(16));
        final type = itemType(types[rng.nextInt(types.length)]);
        final fits = products.where((p) => type.kind == ItemKind.box || p.kind == type.shelf).toList();
        final product = type.needsProduct ? fits[rng.nextInt(fits.length)].id : null;
        if (rng.nextBool()) {
          g.place(type.id, t, rot: rng.nextInt(4), product: product);
        } else if (g.at(t) case final i?) {
          g.sell(i);
        }
        run(w, 0.5);
      }
      run(w, 30);
      expect(g.entrances, isNotEmpty);
      expect(g.registers, isNotEmpty);
      for (final r in g.registers) {
        expect(g.queueTiles(r), isNotEmpty);
      }
    });
  });

  test('꺼 둔 동안 번 돈: 계산원이 있어야 하고 두 시간까지만', () {
    final g = Game();
    expect(g.offlineEarnings(3600), 0);
    g.staff[Staff.cashier] = 1;
    final hour = g.offlineEarnings(3600);
    expect(hour, greaterThan(0));
    expect(g.offlineEarnings(100000), g.offlineEarnings(7200));
  });

  test('저장했다 불러오면 그대로다', () {
    final g = Game()
      ..money = 5000
      ..level = 5
      ..xp = 12;
    g.buyPlot((1, 0));
    g.place('rug', (5, 5));
    g.place('floor-mint', (4, 4));
    g.staff[Staff.stocker] = 2;
    g.upgrades[Upgrade.arms] = 1;
    g.trash.add((6, 6));
    first(g, 'register').cash = 9;
    g.rate(4);
    final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(g.toJson()));
    expect(back.at((5, 5))?.type, 'rug');
  });
}
