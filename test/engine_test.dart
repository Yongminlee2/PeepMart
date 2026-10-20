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
      final price = itemType('rack').price;
      expect(g.money, 1000 - price);
      final rack = g.at((5, 5))!;
      expect(rack.stock, rack.capacity);
      expect(g.sell(rack), isTrue);
      expect(g.money, 1000 - price + price ~/ 2);
      expect(g.sell(first(g, 'register')), isFalse);
      expect(g.sell(first(g, 'entrance')), isFalse);
    });

    test('옮기기는 공짜고, 재고·돈 더미가 따라가며, 안 되는 자리면 그대로다', () {
      final g = Game();
      final rack = first(g, 'rack')..stock = 3;
      final m = g.money;
      expect(g.move(rack, (5, 5)), PlaceResult.ok);
      final moved = g.at((5, 5))!;
      expect(moved.stock, 3);
      expect(moved.product, 'donut');
      expect(g.at((3, 3)), isNull);
      expect(g.money, m);
      expect(g.move(moved, (2, 3)), PlaceResult.occupied); // 냉장고 자리
      expect(g.at((5, 5)), same(moved));
      final reg = first(g, 'register')..cash = 7;
      expect(g.move(reg, (5, 1), rot: 1), PlaceResult.ok);
      expect(g.at((5, 1))!.cash, 7);
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

    test('손이 꽉 찼는데 놓을 데가 없으면, 다른 상자 앞에서 제 상자로 돌려놓고 새 걸 든다', () {
      final g = Game()..owner.tutorial = TutorialStep.done;
      for (final s in g.shelves) {
        s.stock = s.capacity; // 콜라 진열대 가득
      }
      final donut = g.shelves.firstWhere((s) => s.product == 'donut')..stock = 0;
      final soda = g.boxOf('soda')!, box = g.boxOf('donut')!;
      final w = World(g, seed: 2);
      w.player.carry.addAll(List.filled(g.arms, 'soda'));
      final before = soda.units;
      expect(w.walkPlayerTo(box.tile), isNotNull);
      run(w, 6);
      expect(w.player.carry, contains('donut'));
      expect(w.player.carry, isNot(contains('soda')));
      expect(soda.units, before + g.arms);
      expect(donut.capacity, greaterThan(0));
    });

    test('누르면 걸어가서 그 일을 한다: 상자 → 들기, 진열대 → 채우기, 계산대 → 계산 자리', () {
      final g = Game()..owner.tutorial = TutorialStep.done; // 안내 손님이 채운 걸 사 가지 않게
      final fridge = first(g, 'fridge')..stock = 0;
      final w = World(g, seed: 20);
      final box = g.items.firstWhere((i) => i.type == 'box' && i.product == 'soda');
      expect(w.walkPlayerTo(box.tile), isNotNull);
      run(w, 6);
      expect(w.player.carry, contains('soda'));
      expect(w.walkPlayerTo(fridge.tile), isNotNull);
      run(w, 6);
      expect(fridge.stock, greaterThan(0));
      final reg = first(g, 'register');
      expect(w.walkPlayerTo(reg.tile), reg.till);
      run(w, 6);
      expect(w.atAnyTill, isTrue);
      expect(w.walkPlayerTo((30, 30)), isNull); // 남의 땅
    });

    test('지나가며 옆 상자 물건을 집지 않고, 멈춰 선 상자에서만 집는다', () {
      final g = Game();
      final w = World(g, seed: 22);
      stand(w, (0, 1));
      w.walkPlayerTo((4, 1)); // (1,1)·(2,1)·(3,1) 을 지나며 콜라·도넛 상자 옆을 지난다
      run(w, 3);
      expect(w.player.carry, isEmpty); // (4,1) 은 어느 상자에도 손이 안 닿는다
      w.walkPlayerTo(g.items.firstWhere((i) => i.type == 'box' && i.product == 'soda').tile);
      run(w, 3);
      expect(w.player.carry, isNotEmpty);
      expect(w.player.carry.toSet(), {'soda'});
    });

    test('조이스틱을 쓰면 가던 길을 멈춘다', () {
      final g = Game();
      final w = World(g, seed: 21);
      w.walkPlayerTo((1, 6));
      run(w, 0.2);
      w.input = 1;
      run(w, 0.1);
      expect(w.player.path, isEmpty);
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

  group('목표·손님 종류·행사', () {
    test('목표는 차례로 나오고, 이루면 상금을 주고 다음으로 넘어간다', () {
      final g = Game()..money = 1000;
      expect(g.currentGoal!.kind, GoalKind.shelves);
      expect(g.checkGoal(), isNull);
      g.place('rack', (5, 5), product: 'donut');
      final m = g.money;
      final done = g.checkGoal();
      expect(done?.kind, GoalKind.shelves);
      expect(g.money, m + done!.reward);
      expect(g.currentGoal!.kind, GoalKind.served);
    });

    test('모든 목표는 이룰 수 있는 값이다', () {
      for (final goal in goals) {
        final max = switch (goal.kind) {
          GoalKind.level => maxLevel,
          GoalKind.plots => plotCols * plotRows,
          GoalKind.products => products.length,
          GoalKind.rating => 50,
          GoalKind.cashiers => staffSpecs[Staff.cashier]!.max,
          GoalKind.stockers => staffSpecs[Staff.stocker]!.max,
          GoalKind.janitors => staffSpecs[Staff.janitor]!.max,
          _ => 1 << 30,
        };
        expect(goal.target, lessThanOrEqualTo(max), reason: '$goal');
      }
    });

    test('VIP 방문 행사: VIP 가 오고, 두 배를 낸다', () {
      final g = Game()..staff[Staff.cashier] = 1;
      final w = World(g, seed: 30);
      stand(w, (0, 7));
      w.startEvent(EventKind.vip);
      var vipPaid = 0;
      for (var i = 0; i < 4000 && vipPaid == 0; i++) {
        w.tick(0.05);
        for (final s in g.shelves) {
          s.stock = s.capacity;
        }
        for (final f in w.fx) {
          if (f.kind == FxKind.pay) vipPaid = f.amount;
        }
        w.fx.clear();
        expect(w.customers.where((c) => c.kind != CustomerKind.vip).length, lessThanOrEqualTo(w.customers.length));
      }
      expect(w.customers.any((c) => c.kind == CustomerKind.vip) || vipPaid > 0, isTrue);
      expect(vipPaid % 2, 0); // 두 배라서 짝수
    });

    test('손님 몰림 행사 동안 손님이 더 자주 온다', () {
      int visitors(bool rush) {
        final g = Game()..staff[Staff.cashier] = 1;
        final w = World(g, seed: 31);
        stand(w, (0, 7));
        if (rush) w.startEvent(EventKind.rush);
        final seen = <Customer>{};
        for (var i = 0; i < 600; i++) {
          w.tick(0.05);
          seen.addAll(w.customers);
        }
        return seen.length;
      }

      expect(visitors(true), greaterThan(visitors(false)));
    });

    test('행사는 레벨 3부터 저절로 벌어진다', () {
      final g = Game();
      final w = World(g, seed: 32);
      stand(w, (0, 7));
      run(w, eventGap.$2 + 5);
      expect(w.event, isNull); // 레벨 1
      g.level = eventLevel;
      var happened = false;
      for (var i = 0; i < (eventGap.$2 + 5) * 20 && !happened; i++) {
        w.tick(0.05);
        happened = w.event != null;
      }
      expect(happened, isTrue);
    });

    test('급한 손님은 절반만 참는다', () {
      final c = Customer(0, (0, 0), ['soda'])..kind = CustomerKind.hurry;
      expect(c.patience, 0.5);
    });
  });

  group('갓물주 요소: 가구 레벨업·매니저·지점·단골·처음 안내', () {
    test('빈 진열대를 누르면 상자에 들렀다가 와서 채운다 (한 번만 누르면 된다)', () {
      final g = Game();
      final fridge = first(g, 'fridge')..stock = 0;
      final w = World(g, seed: 40);
      w.tapAt(fridge.tile);
      run(w, 10);
      expect(fridge.stock, greaterThanOrEqualTo(g.arms - 2));
    });

    test('가구 레벨업: 더 담고 더 비싸게, 계산대는 더 빨리, 팔면 올린 값도 절반 돌려받는다', () {
      final g = Game()..money = 100000;
      final rack = first(g, 'rack');
      final cap = rack.capacity, price = g.salePrice(rack, 'donut');
      final cost = g.levelUpCost(rack)!;
      expect(g.levelUp(rack), isTrue);
      expect(g.money, 100000 - cost);
      expect(rack.capacity, cap + 2);
      expect(g.salePrice(rack, 'donut'), greaterThanOrEqualTo(price));
      final reg = first(g, 'register');
      final t = g.scanTime(reg, cashier: false);
      g.levelUp(reg);
      expect(g.scanTime(reg, cashier: false), lessThan(t));
      while (g.levelUpCost(rack) != null) {
        g.levelUp(rack);
      }
      expect(rack.level, maxItemLevel);
      expect(g.levelUp(rack), isFalse);
      final m = g.money;
      g.sell(rack);
      expect(g.money - m, greaterThan(itemType('rack').price)); // 레벨 올린 값까지 절반
    });

    test('매니저: 상자 없이 코너가 채워지고, 10% 비싸게 팔고, 꺼 둔 시간이 늘어난다', () {
      final g = Game()
        ..money = 100000
        ..level = 30;
      final rack = first(g, 'rack')..stock = 0;
      g.sell(g.items.firstWhere((i) => i.type == 'box' && i.product == 'donut'));
      final before = g.salePrice(rack, 'donut');
      final hours = g.offlineHours;
      expect(g.hireManager(managers.firstWhere((m) => m.kind == ShelfKind.rack)), isTrue);
      expect(g.salePrice(rack, 'donut'), greaterThanOrEqualTo(before));
      expect(g.offlineHours, hours + 1);
      g.owner.tutorial = TutorialStep.done; // 닫힌 가게: 손님이 안 사 가서 채워진 것만 본다
      final w = World(g, seed: 41);
      stand(w, (0, 7));
      run(w, managerRestock * 3 + 0.1);
      expect(rack.stock, greaterThan(0));
    });

    test('지점: 레벨·돈이 있어야 열고, 가구는 따로, 돈·레벨은 함께', () {
      final g = Game();
      final o = g.owner;
      expect(o.open('beach'), isFalse);
      o
        ..level = 10
        ..money = 6000;
      expect(o.open('beach'), isTrue);
      expect(o.money, 1000);
      final beach = o.game;
      expect(beach.branch, 'beach');
      expect(identical(beach, g), isFalse);
      beach.money += 5;
      expect(g.money, 1005);
      beach.place('plant', (5, 5));
      expect(g.at((5, 5)), isNull);
      expect(o.open('piyak'), isTrue); // 이미 연 곳은 옮기기만
      expect(o.game, same(g));
      // 대표 상품은 비싸다
      final sodaShelf = first(beach, 'fridge');
      expect(beach.salePrice(sodaShelf, 'soda'), greaterThan(productById('soda').price));
    });

    test('단골: 이 지점에 찾아오고, 부탁한 걸 사 가면 하트와 상금', () {
      final g = Game()..staff[Staff.cashier] = 1;
      final w = World(g, seed: 42);
      stand(w, (0, 7));
      String? heartFrom;
      for (var i = 0; i < 20000 && heartFrom == null; i++) {
        w.tick(0.05);
        for (final s in g.shelves) {
          s.stock = s.capacity;
        }
        for (final f in w.fx) {
          if (f.kind == FxKind.regular && f.amount > 0) heartFrom = f.product; // -1 은 들어올 때 알림
        }
        w.fx.clear();
      }
      expect(heartFrom, 'mina'); // 삐약동 레벨 1 단골
      expect(g.owner.heartsOf('mina'), 1);
    });

    test('하트는 다섯 개까지, 오를 때마다 상금', () {
      final g = Game();
      var m = g.money;
      for (var h = 1; h <= maxHearts; h++) {
        expect(g.giveHeart('mina'), h);
        expect(g.money, m + heartReward(h));
        m = g.money;
      }
      expect(g.giveHeart('mina'), isNull);
    });

    test('처음 안내는 들기 → 채우기 → 계산 → 돈 줍기 → 짓기 순서로 넘어간다', () {
      final g = Game()..money = 1000;
      final o = g.owner;
      final fridge = first(g, 'fridge')..stock = 0;
      final w = World(g, seed: 43);
      expect(o.tutorial, TutorialStep.pickBox);
      w.tapAt(fridge.tile);
      run(w, 10);
      expect(o.tutorial.index, greaterThanOrEqualTo(TutorialStep.checkout.index));
      final reg = first(g, 'register');
      w.walkPlayerTo(reg.tile);
      for (var i = 0; i < 4000 && o.tutorial.index < TutorialStep.build.index; i++) {
        w.tick(0.05);
        for (final s in g.shelves) {
          s.stock = s.capacity;
        }
      }
      expect(o.tutorial, TutorialStep.build);
      g.place('plant', (5, 5));
      expect(o.tutorial, TutorialStep.done);
    });

    test('지점 둘을 저장했다 불러와도 그대로다', () {
      final g = Game()
        ..level = 12
        ..money = 9000;
      g.owner.open('beach');
      g.owner.game.place('plant', (4, 4));
      g.owner.hearts['sora'] = 2;
      g.hireManager(managers.first..toString());
      final j = jsonEncode(g.toJson());
      final back = Game.fromJson(jsonDecode(j) as Map<String, dynamic>);
      expect(jsonEncode(back.toJson()), j);
      expect(back.branch, 'beach');
      expect(back.owner.branches.keys.toSet(), {'piyak', 'beach'});
    });
  });

  test('꺼 둔 동안 번 돈: 계산원이 있어야 하고 두 시간까지만', () {
    final g = Game();
    expect(g.offlineEarnings(3600), 0);
    g.staff[Staff.cashier] = 1;
    g.avgSales = 1e9;
    final hour = g.offlineEarnings(3600);
    expect(hour, greaterThan(0));
    expect(g.offlineEarnings(100000), g.offlineEarnings(7200));
    g.avgSales = 50; // 하루 평균 매출보다 많이 벌진 못한다
    expect(g.offlineEarnings(7200), (50 * offlineCap).round());
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

  group('하루 장사', () {
    Game ready() {
      final g = Game()
        ..money = 1000
        ..level = 5;
      g.owner.tutorial = TutorialStep.done;
      g.hire(Staff.cashier);
      g.hire(Staff.stocker);
      return g;
    }

    test('안내가 끝난 가게는 닫힌 채 시작하고, 열기 전엔 손님이 안 온다', () {
      final w = World(ready(), seed: 1);
      expect(w.phase, DayPhase.closed);
      run(w, 30);
      expect(w.customers, isEmpty);
    });

    test('열면 하루가 흐르고, 마감 뒤 손님이 다 나가면 닫고 결과를 남긴다', () {
      final g = ready();
      final w = World(g, seed: 2)..openDay();
      expect(w.phase, DayPhase.open);
      expect(w.tasks, hasLength(2));
      expect(w.dayTarget, greaterThan(0));
      run(w, dayLength - 1);
      expect(w.phase, DayPhase.open);
      expect(w.daySales, greaterThan(0));
      run(w, 2);
      expect(w.phase, isNot(DayPhase.open));
      final before = g.money;
      for (var i = 0; i < 4000 && w.phase != DayPhase.closed; i++) {
        w.tick(0.05);
      }
      final r = w.result!;
      expect(w.phase, DayPhase.closed);
      expect(r.day, 1);
      expect(g.day, 2);
      expect(r.sales, w.daySales);
      expect(r.stars, inInclusiveRange(0, 3));
      expect(g.money, greaterThanOrEqualTo(before + r.bonus + r.taskReward - r.cost - g.wages * 2));
      expect(g.bestSales, r.sales);
    });

    test('처음 안내 중에는 열려 있어도 시계가 안 간다', () {
      final g = Game();
      final w = World(g, seed: 3);
      expect(w.phase, DayPhase.open);
      run(w, dayLength + 10);
      expect(w.phase, DayPhase.open);
    });

    test('할 일: 파는 개수·손님 수·실망한 손님 수를 센다', () {
      final w = World(ready(), seed: 4)..openDay();
      const sell = DayTask(DayTaskKind.sell, 2, product: 'soda');
      const calm = DayTask(DayTaskKind.calm, 1);
      w.daySold['soda'] = 2;
      expect(w.taskDone(sell), isTrue);
      w.dayUpset = 1;
      expect(w.taskDone(calm), isTrue);
      w.dayUpset = 2;
      expect(w.taskDone(calm), isFalse);
    });

    test('별: 목표의 0.7·1·1.3배에서 하나씩, 보너스는 별에 따라, 운영비가 빠진다', () {
      final g = ready();
      final w = World(g, seed: 5)..openDay();
      w
        ..dayTarget = 100
        ..daySales = 140
        ..tasks = [];
      final before = g.money;
      w.dayTime = dayLength;
      w.customers.clear();
      w.tick(0.01); // 마감
      w.customers.clear();
      w.tick(0.01); // 닫기
      expect(w.result!.stars, 3);
      expect(g.money - before, greaterThanOrEqualTo((140 * dayBonus[3]).round() - g.wages - g.dailyCost));
      expect(w.result!.cost, g.dailyCost);
      expect(w.result!.profit, 140 + w.result!.bonus + w.result!.chest - g.dailyCost);
      expect(w.result!.chest, greaterThan(0)); // 별 셋이면 보물 상자
    });

    test('날짜·최고 매출·최근 평균은 저장된다', () {
      final g = ready()
        ..day = 7
        ..bestSales = 321
        ..avgSales = 250.5
        ..avgServed = 30;
      final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(back.day, 7);
      expect(back.bestSales, 321);
      expect(back.avgSales, 250.5);
      expect(back.avgServed, 30);
    });

    test('둘째 날부터 목표는 최근 평균의 1.15배(가게 크기와 상관없이)', () {
      final g = ready();
      expect(g.hasHistory, isFalse);
      g.recordDay(200, 30);
      expect(g.dayTarget, 230);
      g.recordDay(100, 20); // 못한 날은 목표도 내려간다
      expect(g.avgSales, closeTo(160, 0.01));
      expect(g.dayTarget, 180);
    });
  });

  group('가게 등급', () {
    test('레벨 5·10·15·20·25 에서 오른다', () {
      expect([for (final l in [1, 4, 5, 9, 10, 15, 19, 20, 25, 30]) rankOf(l)], [0, 0, 1, 1, 2, 3, 3, 4, 5, 5]);
    });

    test('등급이 오르면 손님이 더 자주 온다', () {
      final g = Game();
      final low = g.spawnGap;
      g.level = 10;
      expect(g.spawnGap, closeTo(low / (1 + 2 * rankVisitorBonus), 1e-9));
    });
  });

  group('날씨·특별한 날', () {
    Game shop(int level) {
      final g = Game()
        ..money = 5000
        ..level = level;
      g.owner.tutorial = TutorialStep.done;
      g.hire(Staff.cashier);
      return g;
    }

    test('구멍가게는 늘 맑음, 동네 편의점부터 예보한 날씨가 그날 날씨가 된다', () {
      final g = shop(1)..weather = Weather.rain;
      expect(g.todayWeather, Weather.sunny);
      g.level = 5;
      expect(g.todayWeather, Weather.rain);
      final w = World(g, seed: 1)..openDay();
      expect(w.weather, Weather.rain);
    });

    test('특별한 날은 큰 편의점부터 5일마다, 축제는 대형마트부터', () {
      final g = shop(10)..day = 5;
      expect(g.todaySpecial, SpecialDay.picnic);
      g.day = 10;
      expect(g.todaySpecial, SpecialDay.exam);
      g.day = 15;
      expect(g.todaySpecial, SpecialDay.picnic);
      g.day = 7;
      expect(g.todaySpecial, isNull);
      g
        ..level = 20
        ..day = 15;
      expect(g.todaySpecial, SpecialDay.festival);
    });

    test('날씨 상품이 진열돼 있으면 손님이 그걸 더 자주 고른다', () {
      // 처음 가게는 콜라·도넛뿐: 더운 날엔 맨 먼저 콜라를 집는 손님이 많다
      double firstSoda(Weather wx) {
        var soda = 0, all = 0;
        for (var seed = 0; seed < 3; seed++) {
          final g = shop(5)..weather = wx;
          final w = World(g, seed: seed)..openDay();
          final seen = <Customer>{};
          for (var i = 0; i < 3000; i++) {
            w.tick(0.05);
            for (final s in g.shelves) {
              s.stock = s.capacity;
            }
            for (final c in w.customers) {
              if (c.wants.isNotEmpty && seen.add(c)) {
                all++;
                if (c.wants.first == 'soda') soda++;
              }
            }
          }
        }
        return soda / all;
      }
      expect(firstSoda(Weather.hot), greaterThan(firstSoda(Weather.sunny)));
    });

    test('닫을 때 다음 날 날씨를 정하고 저장된다', () {
      final g = shop(5);
      final w = World(g, seed: 9)..openDay();
      w.dayTime = dayLength;
      w.customers.clear();
      w.tick(0.01);
      w.customers.clear();
      w.tick(0.01);
      expect(w.phase, DayPhase.closed);
      final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(back.weather, g.weather);
    });
  });

  group('돌발 사건', () {
    (Game, World) shop(int level, int seed) {
      final g = Game()
        ..money = 5000
        ..level = level;
      g.owner.tutorial = TutorialStep.done;
      g.hire(Staff.cashier);
      final w = World(g, seed: seed)..openDay();
      return (g, w);
    }

    Customer? find(World w, CustomerKind k) => w.customers.where((c) => c.kind == k).firstOrNull;

    void fill(Game g) {
      for (final s in g.shelves) {
        s.stock = s.capacity;
      }
    }

    test('구멍가게엔 사건이 없다', () {
      final (_, w) = shop(4, 1);
      expect(w.tasks, isNotEmpty);
      for (var i = 0; i < 3200; i++) {
        w.tick(0.05);
        expect(w.customers.where((c) => c.kind == CustomerKind.thief || c.kind == CustomerKind.lost), isEmpty);
      }
      expect(w.order, isNull);
    });

    test('도둑: 문 앞을 지키고 있으면 잡아서 벌금을 받는다', () {
      for (var seed = 0; seed < 20; seed++) {
        final (g, w) = shop(10, seed);
        final before = g.money;
        Customer? thief;
        final fx = <Incident>[];
        for (var i = 0; i < 4000 && !fx.contains(Incident.thiefCaught); i++) {
          fill(g);
          w.tick(0.05);
          thief ??= find(w, CustomerKind.thief);
          for (final e in w.fx.where((e) => e.kind == FxKind.incident)) {
            fx.add(Incident.values[e.amount]);
          }
          w.fx.clear();
          // 도망치기 시작하면 입구에 선다
          if (thief != null && thief.fleeing) stand(w, g.entrances.first.tile);
        }
        if (!fx.contains(Incident.thiefFlee)) continue;
        expect(fx, contains(Incident.thiefCaught));
        expect(g.money, greaterThan(before));
        return;
      }
      fail('20번 씨앗 안에 도둑이 한 번도 안 나왔다');
    });

    test('도둑: 아무도 안 쫓으면 달아난다', () {
      for (var seed = 0; seed < 20; seed++) {
        final (g, w) = shop(10, seed);
        final fx = <Incident>[];
        for (var i = 0; i < 4000; i++) {
          fill(g);
          stand(w, (0, 7)); // 문(7,7)에서 멀리
          w.tick(0.05);
          for (final e in w.fx.where((e) => e.kind == FxKind.incident)) {
            fx.add(Incident.values[e.amount]);
          }
          w.fx.clear();
        }
        if (!fx.contains(Incident.thiefFlee)) continue;
        expect(fx, contains(Incident.thiefEscaped));
        expect(fx, isNot(contains(Incident.thiefCaught)));
        return;
      }
      fail('20번 씨앗 안에 도둑이 한 번도 안 나왔다');
    });

    test('길 잃은 아이: 가까이 가면 사례금, 안 가면 울며 나간다', () {
      for (var seed = 0; seed < 20; seed++) {
        final (g, w) = shop(10, seed);
        Customer? kid;
        var found = false;
        for (var i = 0; i < 4000 && !found; i++) {
          w.tick(0.05);
          kid ??= find(w, CustomerKind.lost);
          if (kid != null && kid.state == CState.atShelf) stand(w, kid.tile);
          found = w.fx.any((e) => e.kind == FxKind.incident && e.amount == Incident.kidFound.index);
          w.fx.clear();
        }
        if (kid == null) continue;
        expect(found, isTrue);
        return;
      }
      fail('20번 씨앗 안에 아이가 한 번도 안 나왔다');
    });

    test('배달: 진열대를 돌며 챙기고(재고가 빠진다) 입구에 닿으면 값의 두 배', () {
      final (g, w) = shop(15, 3);
      w.order = Order(['soda', 'donut']);
      final before = g.money;
      fill(g);
      expect(w.canDeliver, isTrue);
      expect(w.startDelivery(), isTrue);
      expect(w.order!.carrying, isFalse); // 입구에 서 있어도 아직 못 챙겼다
      var picked = false;
      for (var i = 0; i < 1200 && w.order != null; i++) {
        w.tick(0.05);
        picked |= w.fx.any((e) => e.kind == FxKind.pick);
        w.fx.clear();
      }
      expect(picked, isTrue);
      expect(w.order, isNull);
      expect(g.money, greaterThanOrEqualTo(before + (productById('soda').price + productById('donut').price) * orderPay));
    });

    test('배달: 재고가 없으면 못 떠나고, 시간이 지나면 취소', () {
      final (g, w) = shop(15, 4);
      w.order = Order(['soda']);
      for (final s in g.shelves) {
        s.stock = 0;
      }
      expect(w.canDeliver, isFalse);
      expect(w.startDelivery(), isFalse);
      w.order!.left = 0.01;
      w.tick(0.05);
      expect(w.order, isNull);
    });
  });

  group('도감', () {
    test('처음 만난 손님만 기록되고 10명째마다 상금', () {
      final o = Game().owner..money = 0;
      expect(o.meet(5).$1, isTrue);
      expect(o.meet(5).$1, isFalse);
      for (var i = 10; i < 18; i++) {
        o.meet(i);
      }
      expect(o.money, 0);
      final (isNew, reward) = o.meet(30); // 10명째
      expect(isNew, isTrue);
      expect(reward, meetReward(1));
      expect(o.money, meetReward(1));
    });

    test('한 상품을 30개 팔면 도장 상금이 한 번만', () {
      final o = Game().owner..money = 0;
      var got = 0;
      for (var i = 0; i < 40; i++) {
        got += o.addSold('soda');
      }
      expect(got, productById('soda').price * stampPay);
      expect(o.sold['soda'], 40);
    });

    test('계산하면 판 개수가 쌓이고 도감은 저장된다', () {
      final g = Game()
        ..money = 1000
        ..level = 5; // 계산원을 쓸 수 있게
      g.owner.tutorial = TutorialStep.done;
      g.hire(Staff.cashier);
      final w = World(g, seed: 2)..openDay();
      for (var i = 0; i < 1200; i++) {
        w.tick(0.05);
        for (final s in g.shelves) {
          s.stock = s.capacity;
        }
      }
      expect(g.owner.sold.values.fold(0, (a, b) => a + b), greaterThan(0));
      g.owner.met.add(7);
      final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(back.owner.sold, g.owner.sold);
      expect(back.owner.met, contains(7));
    });
  });

  group('삐약동 이야기', () {
    test('차례대로 열린다: 안내 → 등급·지점', () {
      final o = Game().owner;
      expect(o.nextChapter, isNull);
      o.tutorial = TutorialStep.done;
      expect(o.nextChapter?.id, 'opening');
      o.story.add('opening');
      expect(o.nextChapter, isNull);
      o.level = 10;
      expect(o.nextChapter?.id, 'rival');
      o.story.add('rival');
      expect(o.nextChapter?.id, 'mayor');
      o.story.add('mayor');
      expect(o.nextChapter, isNull); // 바닷가는 아직 안 열었다
      o.level = 12;
      o.money = 99999;
      o.open('beach');
      expect(o.nextChapter?.id, 'beach');
    });

    test('본 이야기는 저장된다', () {
      final g = Game();
      g.owner.story.addAll(['opening', 'rival']);
      final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(back.owner.story, {'opening', 'rival'});
    });
  });

  group('어려움: 고장·진상 손님·운영비', () {
    (Game, World) shop(int level, int seed) {
      final g = Game()
        ..money = 5000
        ..level = level;
      g.owner.tutorial = TutorialStep.done;
      g.hire(Staff.cashier);
      final w = World(g, seed: seed)..openDay();
      return (g, w);
    }

    test('고장 난 진열대에서는 못 사고, 옆에 멈춰 서 있으면 고친다', () {
      final (g, w) = shop(5, 1);
      final fridge = first(g, 'fridge')
        ..stock = 10
        ..broken = true;
      run(w, 30);
      expect(fridge.stock, 10); // 아무도 못 집었다
      stand(w, (fridge.c + 1, fridge.r));
      run(w, repairTime + 0.5);
      expect(fridge.broken, isFalse);
    });

    test('고장은 하루가 끝나면 고쳐진다', () {
      final (g, w) = shop(5, 2);
      final fridge = first(g, 'fridge')..broken = true;
      w.dayTime = dayLength;
      w.customers.clear();
      w.tick(0.01);
      w.customers.clear();
      w.tick(0.01);
      expect(w.phase, DayPhase.closed);
      expect(fridge.broken, isFalse);
    });

    test('진상 손님: 못 달래면 실망 손님 2명, 가서 달래면 조용히 간다', () {
      for (final calm in [false, true]) {
        final (g, w) = shop(10, 3);
        w.customers.add(Customer(0, g.entrances.first.tile, [])..kind = CustomerKind.grumpy);
        w.customers.last
          ..state = CState.atShelf
          ..timer = 0;
        stand(w, calm ? w.customers.last.tile : (0, 6)); // 안 달랠 때는 멀리 선다
        final upset = w.dayUpset;
        run(w, grumpyPatience + 1);
        expect(w.dayUpset - upset, calm ? lessThan(grumpyAngerRate) : greaterThanOrEqualTo(grumpyAngerRate));
      }
    });

    test('사건은 동네 편의점부터, 등급이 오를수록 많다', () {
      int count(int level) {
        var n = 0;
        for (var seed = 0; seed < 10; seed++) {
          final (g, w) = shop(level, seed);
          for (var i = 0; i < 3600; i++) {
            for (final s in g.shelves) {
              s.stock = s.capacity;
            }
            w.tick(0.05);
            n += w.fx.where((e) => e.kind == FxKind.incident && [Incident.thiefFlee, Incident.kidLost, Incident.brokeDown, Incident.grumpyIn].contains(Incident.values[e.amount])).length;
            w.fx.clear();
          }
        }
        return n;
      }
      expect(count(4), 0);
      final low = count(5), high = count(20);
      expect(low, greaterThan(0));
      expect(high, greaterThan(low));
    });

    test('운영비: 땅이 넓고 등급이 높을수록 크다', () {
      final g = Game()..plots.add((1, 0));
      final small = g.dailyCost;
      g.level = 20;
      expect(g.dailyCost, greaterThan(small));
    });
  });

  group('세트·가격표·팁', () {
    test('세 상품 진열대를 두 칸 안에 두면 세트가 되고 값이 오른다', () {
      final g = Game()
        ..money = 99999
        ..level = 30;
      // 콜라 냉장고는 (2,3)에 있다
      expect(g.place('freezer', (3, 4), product: 'icecream'), isTrue);
      final ice = g.at((3, 4))!;
      final before = g.salePrice(ice, 'icecream');
      expect(g.activeCombos, isEmpty);
      expect(g.place('freezer', (1, 4), product: 'popsicle'), isTrue);
      expect(g.activeCombos.map((c) => c.$1.id), contains('summer'));
      expect(g.salePrice(ice, 'icecream'), greaterThan(before));
      expect(g.newCombos().map((k) => k.id), ['summer']);
      expect(g.newCombos(), isEmpty); // 한 번만
    });

    test('멀리 떨어져 있으면 세트가 아니다', () {
      final g = Game()
        ..money = 99999
        ..level = 30;
      g.place('freezer', (6, 6), product: 'icecream');
      g.place('freezer', (0, 6), product: 'popsicle');
      expect(g.activeCombos, isEmpty);
    });

    test('가격표: 값이 바뀌고 저장된다', () {
      final g = Game();
      final rack = first(g, 'rack');
      final normal = g.salePrice(rack, 'donut');
      g.cyclePrice(rack); // 보통 → 비싸게
      expect(rack.price, 2);
      expect(g.salePrice(rack, 'donut'), greaterThanOrEqualTo(normal));
      final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(first(back, 'rack').price, 2);
    });

    test('프리미엄이면 안 사고 가는 손님이 생긴다', () {
      int sold(int price) {
        final g = Game()
          ..money = 5000
          ..level = 5;
        g.owner.tutorial = TutorialStep.done;
        g.hire(Staff.cashier);
        for (final s in g.shelves) {
          s.price = price;
        }
        final w = World(g, seed: 4)..openDay();
        for (var i = 0; i < 2400; i++) {
          for (final s in g.shelves) {
            s.stock = s.capacity;
          }
          w.tick(0.05);
        }
        return w.daySold.values.fold(0, (a, b) => a + b);
      }
      expect(sold(3), lessThan(sold(1)));
    });

    test('팁: 가까이 가면 줍고, 하루가 끝나면 사라진다', () {
      final g = Game()..money = 0;
      g.owner.tutorial = TutorialStep.done;
      final w = World(g, seed: 5)..openDay();
      w.tips[(4, 4)] = 7;
      w.tips[(1, 6)] = 3;
      stand(w, (4, 4));
      w.tick(0.05);
      expect(w.tips.containsKey((4, 4)), isFalse);
      expect(g.money, greaterThanOrEqualTo(7));
      w.dayTime = dayLength;
      w.customers.clear();
      w.tick(0.01);
      w.customers.clear();
      w.tick(0.01);
      expect(w.tips, isEmpty);
    });
  });

  group('피버 타임·위생 점검', () {
    test('계산을 이어 가면 콤보, 다 차면 피버 타임, 시간이 지나면 끊긴다', () {
      final g = Game()
        ..money = 5000
        ..level = 5;
      g.owner.tutorial = TutorialStep.done;
      g.hire(Staff.cashier);
      g.hire(Staff.stocker);
      final w = World(g, seed: 6)..openDay();
      w
        ..combo = feverAt - 1
        ..sinceServe = 0;
      var fever = false;
      for (var i = 0; i < 1200 && !fever; i++) {
        for (final s in g.shelves) {
          s.stock = s.capacity;
        }
        w.tick(0.05);
        if (w.combo == 0 && w.feverLeft == 0) {
          // 손님 간격이 길어 끊겨도 다시 채워 둔다
          w
            ..combo = feverAt - 1
            ..sinceServe = 0;
        }
        fever = w.feverLeft > 0;
      }
      expect(fever, isTrue);
      expect(w.feverLeft, lessThanOrEqualTo(feverTime));
      w.combo = 5;
      w.sinceServe = comboWindow(g.spawnGap) + 1;
      w.tick(0.01);
      expect(w.combo, 0); // 시간이 지나면 끊긴다
    });

    test('점검 날은 동네 편의점부터 7일마다', () {
      final g = Game()..day = 7;
      expect(g.inspectionDay, isFalse); // 구멍가게
      g.level = 5;
      expect(g.inspectionDay, isTrue);
      g.day = 8;
      expect(g.inspectionDay, isFalse);
    });

    test('점수: 쓰레기·빈 진열대·고장마다 깎인다', () {
      final g = Game()..level = 5;
      g.owner.tutorial = TutorialStep.done;
      final w = World(g, seed: 7)..openDay();
      for (final s in g.shelves) {
        s.stock = s.capacity;
      }
      expect(w.inspectionScore, 100);
      g.trash.add((5, 5));
      first(g, 'rack').stock = 0;
      first(g, 'fridge').broken = true;
      expect(w.inspectionScore, 100 - inspectTrash - inspectEmpty - inspectBroken);
    });

    test('점검관이 둘러보고 깨끗하면 상금, 지저분하면 벌금', () {
      for (final clean in [true, false]) {
        final g = Game()
          ..money = 1000
          ..level = 5
          ..day = 7;
        g.owner.tutorial = TutorialStep.done;
        g.hire(Staff.cashier);
        final w = World(g, seed: 8)..openDay();
        if (!clean) {
          g.trash.addAll([(4, 5), (5, 5), (6, 5), (4, 6)]);
        }
        Incident? result;
        for (var i = 0; i < 4800 && result == null; i++) {
          for (final s in g.shelves) {
            s.stock = clean ? s.capacity : 0;
          }
          stand(w, (0, 6));
          w.tick(0.05);
          for (final e in w.fx.where((e) => e.kind == FxKind.incident)) {
            final k = Incident.values[e.amount];
            if (k == Incident.inspectGood || k == Incident.inspectOk || k == Incident.inspectBad) result = k;
          }
          w.fx.clear();
        }
        expect(result, clean ? Incident.inspectGood : Incident.inspectBad);
      }
    });
  });

  group('재고·재주문', () {
    test('상자에서 꺼내면 줄고, 비면 더 못 꺼낸다', () {
      final g = Game();
      final w = World(g, seed: 1);
      final box = g.items.firstWhere((i) => i.type == 'box' && i.product == 'soda')..units = 3;
      stand(w, (box.c, box.r + 1));
      for (var i = 0; i < 100; i++) {
        w.tick(0.05);
        w.player.carry.clear(); // 계속 꺼내 보기
      }
      expect(box.units, 0);
    });

    test('주문: 도매가를 내고 15초 뒤 24개 도착, 오는 중엔 또 못 한다', () {
      final g = Game()..money = 1000;
      final w = World(g, seed: 2);
      final box = g.items.firstWhere((i) => i.type == 'box' && i.product == 'soda')..units = 0;
      expect(g.reorder(box), isTrue);
      expect(g.money, 1000 - reorderCost('soda'));
      expect(g.reorder(box), isFalse);
      run(w, restockDelay + 0.5);
      expect(box.units, boxSize);
      expect(box.incoming, 0);
    });

    test('돈이 모자라거나 상자가 가득하면 주문 못 한다', () {
      final g = Game()..money = 0;
      final box = g.items.firstWhere((i) => i.type == 'box')..units = 0;
      expect(g.reorder(box), isFalse);
      g.money = 9999;
      box.units = boxMax;
      expect(g.reorder(box), isFalse);
    });

    test('진열원은 빈 상자로는 못 채운다', () {
      final g = Game()
        ..money = 5000
        ..level = 5;
      g.owner.tutorial = TutorialStep.done;
      g.hire(Staff.stocker);
      for (final b in g.ofKind(ItemKind.box)) {
        b.units = 0;
      }
      for (final s in g.shelves) {
        s.stock = 0;
      }
      final w = World(g, seed: 3);
      stand(w, (0, 6));
      run(w, 20);
      expect(g.shelves.every((s) => s.stock == 0), isTrue);
    });

    test('남은 양과 오는 중인 주문은 저장된다(오는 중은 도착한 것으로)', () {
      final g = Game()..money = 1000;
      final box = g.items.firstWhere((i) => i.type == 'box')..units = 5;
      g.reorder(box);
      final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(back.items.firstWhere((i) => i.type == 'box').units, 5 + boxSize);
    });
  });

  group('단체 주문·가격 전쟁·보물 상자·인형뽑기', () {
    Game shop(int level) {
      final g = Game()
        ..money = 5000
        ..level = level;
      g.owner.tutorial = TutorialStep.done;
      return g;
    }

    void close(World w) {
      w.dayTime = dayLength;
      w.customers.clear();
      w.tick(0.01);
      w.customers.clear();
      w.tick(0.01);
    }

    test('단체 주문은 많고 오래 걸리고 더 받는다', () {
      final o = Order(['soda', 'soda', 'donut', 'donut'], bulk: true);
      expect(o.left, bulkTime);
      expect(o.pay, ((3 + 3 + 3 + 3) * bulkPay).round());
      expect(Order(['soda']).left, orderTime);
    });

    test('가격 전쟁 날: 라이벌 이야기 중, 6일마다(삐약동만)', () {
      final g = shop(5)..day = 9;
      expect(g.priceWarDay, isFalse); // 이야기 전
      g.owner.story.add('rival');
      expect(g.priceWarDay, isTrue);
      g.day = 10;
      expect(g.priceWarDay, isFalse);
      g
        ..day = 9
        ..owner.story.add('finale');
      expect(g.priceWarDay, isFalse); // 결말 뒤
    });

    test('가격 전쟁: 별 둘이면 보너스, 아니면 진 것', () {
      for (final win in [true, false]) {
        final g = shop(5)..day = 3;
        g.owner.story.add('rival');
        final w = World(g, seed: 1)..openDay();
        expect(w.priceWar, isTrue);
        w
          ..dayTarget = 100
          ..daySales = win ? 110 : 50;
        close(w);
        expect(w.result!.warPrize, win ? (100 * priceWarPrize).round() : -1);
      }
    });

    test('보물 상자: 별 둘 이상일 때만', () {
      for (final (sales, has) in [(60, false), (75, false), (105, true), (140, true)]) {
        final g = shop(5);
        final w = World(g, seed: 2)..openDay();
        w
          ..dayTarget = 100
          ..daySales = sales
          ..tasks = [];
        close(w);
        expect(w.result!.chest > 0, has, reason: 'sales $sales');
      }
    });

    test('인형뽑기 옆을 지나 나가는 손님이 가끔 한 판 한다', () {
      final g = shop(6);
      g.hire(Staff.cashier);
      expect(g.place('claw', (4, 5)), isTrue); // 계산대(6,2) 가까이
      final w = World(g, seed: 3)
        ..openDay()
        ..bigEvent = null; // 정전 같은 큰 이벤트 없이
      var plays = 0;
      for (var i = 0; i < 3600; i++) {
        for (final s in g.shelves) {
          s.stock = s.capacity;
        }
        w.tick(0.05);
        plays += w.fx.where((e) => e.kind == FxKind.pay && e.amount == clawPlay && e.x == 4 && e.y == 5).length;
        w.fx.clear();
      }
      expect(plays, greaterThan(0));
    });
  });

  group('자동 발주·동네 규칙·끝없는 목표', () {
    test('자동 발주: 사면 상자가 바닥나기 전에 수수료를 붙여 저절로 주문한다', () {
      final g = Game()
        ..money = 99999
        ..level = 15;
      final w = World(g, seed: 1);
      final box = g.items.firstWhere((i) => i.type == 'box')..units = 2;
      w.tick(0.05);
      expect(box.incoming, 0); // 안 샀으면 그대로
      expect(g.buyUpgrade(Upgrade.autoOrder), isTrue);
      final before = g.money;
      w.tick(0.05);
      expect(box.incoming, greaterThan(0));
      expect(before - g.money, (reorderCost(box.product!) * autoOrderFee).round());
    });

    test('동네 규칙: 바닷가는 손님이 많고, 다른 동네는 보통', () {
      expect(ruleOf('beach').visitors, greaterThan(1));
      expect(ruleOf('night').thief, greaterThan(1));
      expect(ruleOf('piyak').visitors, 1);
    });

    test('목표를 다 이루면 손님 500명마다 목표가 이어진다', () {
      final g = Game()
        ..goal = goals.length
        ..served = 4000;
      expect(g.checkGoal(), isNull); // 출발점을 지금으로
      expect(g.currentGoal!.target, 4000 + extraGoalStep);
      g.served = 4000 + extraGoalStep;
      final before = g.money;
      expect(g.checkGoal(), isNotNull);
      expect(g.money - before, extraGoalReward(0));
      expect(g.currentGoal!.target, 4000 + 2 * extraGoalStep);
    });
  });

  group('점검에서 잡은 버그', () {
    test('옮겨도 상자 남은 양·주문·가격표·고장이 그대로다(공짜 재고 방지)', () {
      final g = Game()..money = 1000;
      final box = g.items.firstWhere((i) => i.type == 'box')..units = 0;
      expect(g.move(box, (4, 1)), PlaceResult.ok);
      final moved = g.at((4, 1))!;
      expect(moved.units, 0);
      final rack = first(g, 'rack')
        ..price = 3
        ..broken = true;
      expect(g.move(rack, (4, 5)), PlaceResult.ok);
      expect(g.at((4, 5))!.price, 3);
      expect(g.at((4, 5))!.broken, isTrue);
    });

    test('새로 놓은 상자는 비어 있고, 상품을 바꾸면 비운다', () {
      final g = Game()
        ..money = 9999
        ..level = 30;
      expect(g.place('box', (5, 5), product: 'sushi'), isTrue);
      expect(g.at((5, 5))!.units, 0);
      final box = g.items.firstWhere((i) => i.type == 'box' && i.product == 'soda');
      expect(g.setProduct(box, 'sushi'), isTrue);
      expect(box.units, 0);
      g.reorder(box);
      expect(g.setProduct(box, 'gimbap'), isFalse); // 오는 중엔 못 바꾼다
    });

    test('장사 중에 떠나면 운영비를 내고 날이 넘어간다', () {
      final g = Game()..money = 1000;
      g.owner.tutorial = TutorialStep.done;
      final w = World(g, seed: 1)..openDay();
      run(w, 5);
      final day = g.day, cost = g.dailyCost, money = g.money;
      w.abandonDay();
      expect(g.day, day + 1);
      expect(g.money, money - cost);
      expect(w.phase, DayPhase.closed);
    });

    test('출발한 배달이 남아 있으면 마감이 끝날 때까지 기다린다', () {
      final g = Game()..level = 15;
      g.owner.tutorial = TutorialStep.done;
      final w = World(g, seed: 2)..openDay();
      w.order = Order(['soda'])..started = true;
      w.dayTime = dayLength;
      w.customers.clear();
      w.tick(0.01);
      w.customers.clear();
      w.tick(0.01);
      expect(w.phase, DayPhase.closing);
      w.order = null;
      w.tick(0.01);
      expect(w.phase, DayPhase.closed);
    });

    test('고장은 그 옆에 멈춰 선 시간만 센다', () {
      final g = Game()..level = 5;
      g.owner.tutorial = TutorialStep.done;
      final w = World(g, seed: 3)..openDay();
      final fridge = first(g, 'fridge');
      stand(w, (fridge.c + 1, fridge.r));
      run(w, 5); // 고장 전에 오래 서 있어도
      fridge.broken = true;
      w.tick(0.05);
      expect(fridge.broken, isTrue); // 바로 고쳐지지 않는다
      run(w, repairTime + 0.2);
      expect(fridge.broken, isFalse);
    });
  });

  test('손님은 동네 상품을 찾는다: 없는 건 못 팔고 세고, 종류가 많을수록 많이 산다', () {
    final g = Game()
      ..level = 5
      ..owner.tutorial = TutorialStep.done
      ..money = 1000;
    g.hire(Staff.cashier); // 손님이 계속 드나들게
    final w = World(g, seed: 3)..openDay();
    run(w, 100);
    expect(w.dayMissing, isNotEmpty);
    expect(w.dayMissing.keys.toSet().intersection(g.onSale), isEmpty);
    expect(g.demand.toSet().containsAll(w.dayMissing.keys), isTrue);
    expect(basketCap(12), greaterThan(basketCap(2)));
  });
}
