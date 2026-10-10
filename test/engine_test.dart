import 'dart:convert';

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

/// 막힌 칸 바로 아래(앞) 칸.
Tile below(Tile t) => (t.$1, t.$2 + 1);

void main() {
  test('넓힌 가게는 이전 가게의 상자·진열대 자리를 전부 가진다', () {
    for (var i = 1; i < layouts.length; i++) {
      expect(layouts[i].crates.toSet().containsAll(layouts[i - 1].crates), isTrue);
      expect(layouts[i].shelves.toSet().containsAll(layouts[i - 1].shelves), isTrue);
    }
  });

  test('자리끼리 겹치지 않고, 진열대·상자 앞에 설 칸이 있다', () {
    for (final l in layouts) {
      final fixed = [l.register, l.till, l.cash, l.door, ...l.queue, ...l.pads];
      final all = [...fixed, ...l.crates, ...l.shelves];
      expect(all.toSet().length, all.length, reason: '겹침');
      for (final t in [...l.crates, ...l.shelves]) {
        final (x, y) = t;
        final open = [(x, y + 1), (x + 1, y), (x - 1, y), (x, y - 1)]
            .where((n) => n.$1 >= 0 && n.$2 >= 0 && n.$1 < l.w && n.$2 < l.h && !all.contains(n) || fixed.contains(n));
        expect(open, isNotEmpty, reason: '$t 앞에 설 칸이 없다');
      }
    }
  });

  test('모든 상품이 마지막 가게에 자리가 있고, 넓히기 전에 여는 상품은 첫 가게에 자리가 있다', () {
    expect(Game.slotOf.length, products.length);
    expect(Game.slotOf.values.every((s) => s < layouts.last.shelves.length && s < layouts.last.crates.length), isTrue);
    final beforeExpand = unlocks.takeWhile((u) => u is! Expand).whereType<NewProduct>();
    for (final u in beforeExpand) {
      expect(Game.slotOf[u.product]! < layouts.first.shelves.length, isTrue, reason: u.product);
    }
  });

  test('상자 옆에 서면 팔 개수만큼 들고, 진열대 옆에 서면 채운다', () {
    final g = Game()..stock['soda'] = 0;
    final w = World(g, seed: 1);
    stand(w, below(g.crateTile('soda')));
    run(w, 2);
    expect(w.player.carry, List.filled(g.arms, 'soda'));
    stand(w, below(g.shelfTile('soda')));
    run(w, 2);
    expect(w.player.carry, isEmpty);
    expect(g.stock['soda'], g.arms);
  });

  test('계산대 뒤에 서면 계산되고, 돈은 옆에 쌓였다가 주워야 들어온다', () {
    final g = Game();
    final w = World(g, seed: 2);
    stand(w, g.layout.till);
    for (var i = 0; i < 2000 && g.cash == 0; i++) {
      w.tick(0.05);
    }
    expect(g.cash, greaterThan(0));
    expect(g.money, 0);
    final cash = g.cash;
    stand(w, g.layout.cash);
    run(w, 1);
    expect(g.cash, 0);
    expect(g.money, greaterThanOrEqualTo(cash));
  });

  test('구매 칸에 서면 돈이 조금씩 빠지고, 다 채우면 열린다', () {
    final g = Game()..money = 100;
    final w = World(g, seed: 3);
    final (first, tile) = g.pads.first;
    final price = unlocks[first].price;
    stand(w, tile);
    run(w, 0.2);
    expect(g.money, inExclusiveRange(100 - price, 100), reason: '한 번에 다 빠지면 안 된다');
    run(w, 3);
    expect(g.bought, contains(first));
    expect(g.money, 100 - price);
    expect(g.openProducts, contains('ramen'));
    // 진열대가 생긴 자리에 갇히지 않는다
    final x = w.player.x;
    w.input = -1;
    run(w, 0.5);
    expect(w.player.x, isNot(x));
  });

  test('돈이 모자라면 낸 만큼만 남고, 다음에 이어서 낸다', () {
    final g = Game()..money = 10;
    final w = World(g, seed: 4);
    final (first, tile) = g.pads.first;
    stand(w, tile);
    run(w, 2);
    expect(g.money, 0);
    expect(g.paid[first], 10);
    expect(g.bought, isNot(contains(first)));
  });

  test('손님은 빈 진열대 앞에서 기다렸다가 채워지면 집는다', () {
    final g = Game()
      ..stock['soda'] = 0
      ..stock['chips'] = 0;
    final w = World(g, seed: 5);
    stand(w, g.layout.door);
    for (var i = 0; i < 400 && !w.customers.any((c) => c.state == CState.atShelf); i++) {
      w.tick(0.05);
    }
    final c = w.customers.firstWhere((c) => c.state == CState.atShelf);
    g.stock[c.want] = 3;
    run(w, 1);
    expect(c.carry, isNotEmpty);
  });

  test('너무 오래 비어 있으면 손님은 포기한다', () {
    final g = Game()
      ..stock['soda'] = 0
      ..stock['chips'] = 0;
    final w = World(g, seed: 6);
    stand(w, g.layout.door);
    run(w, shelfPatience * 2 + 15); // 두 개를 사러 왔으면 두 진열대에서 다 기다린다
    expect(g.recent, contains(1));
    expect(w.queue, isEmpty);
  });

  test('계산 알바가 있으면 사람이 없어도 계산된다', () {
    final g = Game()..bought.add(unlocks.indexWhere((u) => u is HireCashier));
    final w = World(g, seed: 7);
    stand(w, g.layout.door);
    run(w, 60);
    expect(g.cash, greaterThan(0));
  });

  test('진열 알바는 반 넘게 빈 진열대를 상자에서 날라 채운다', () {
    final g = Game()..bought.add(unlocks.indexWhere((u) => u is HireStocker));
    g.stock['soda'] = 0;
    g.stock['chips'] = 8;
    final w = World(g, seed: 8);
    stand(w, g.layout.door);
    run(w, 15);
    expect(g.stock['soda'], greaterThanOrEqualTo(startArms - 2)); // 그새 손님이 집어갈 수 있다
  });

  test('가게를 넓혀도 상품과 재고가 그대로다', () {
    final g = Game()..money = 100000;
    final w = World(g, seed: 9);
    for (var i = 0; i < 50 && g.level == 0; i++) {
      final (_, tile) = g.pads.first;
      stand(w, tile);
      run(w, 10);
    }
    expect(g.level, 1);
    expect(g.openProducts, containsAll(['soda', 'chips', 'ramen', 'sandwich', 'icecream', 'fruit']));
    expect(g.pads.map((p) => unlocks[p.$1]).whereType<NewProduct>().map((u) => u.product), contains('bento'));
  });

  test('별점이 높으면 손님이 더 많이 온다', () {
    int visitors(int score) {
      final g = Game()..recent.addAll(List.filled(20, score));
      final w = World(g, seed: 10);
      var count = 0;
      final seen = <Customer>{};
      for (var i = 0; i < 2400; i++) {
        w.tick(0.05);
        for (final c in w.customers) {
          if (seen.add(c)) count++;
        }
      }
      return count;
    }

    expect(visitors(5), greaterThan(visitors(0)));
  });

  test('저장했다 불러오면 그대로다', () {
    final g = Game()
      ..money = 777
      ..cash = 12
      ..level = 1;
    g.bought.addAll([0, 1]);
    g.paid[2] = 5;
    g.stock['ramen'] = 3;
    g.rate(4);
    final back = Game.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(g.toJson()));
  });
}
