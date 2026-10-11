// 밸런스 확인용 자동 플레이. 평소엔 건너뛰고, 아래처럼 켰을 때만 돈다:
//
//     BALANCE=1 flutter test test/balance_test.dart
//
// 사람처럼(눌러서 걷기로) 계산·돈 줍기·진열을 하고, 돈이 생기면 진열대·계산대·직원·땅을 산다.
// 몇 분마다 레벨·돈·땅을 찍어서 성장 속도가 알맞은지 본다.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/catalog.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';

class Bot {
  final World w;
  Bot(this.w);
  Game get g => w.game;
  double _thinkIn = 0;

  void tick(double dt) {
    if (w.player.path.isEmpty) _work();
    _thinkIn -= dt;
    if (_thinkIn <= 0) {
      _thinkIn = 5;
      _build();
    }
  }

  // ---------------------------------------------------------------- 손으로 하는 일

  void _work() {
    for (final r in g.registers) {
      final q = w.queues[r];
      if (q != null && q.isNotEmpty && !w.staffedAt(r)) {
        if (w.player.distTo(r.till) >= standRadius) w.walkPlayerTo(r.tile);
        return;
      }
    }
    final rich = g.registers.where((r) => r.cash > 15).toList();
    if (rich.isNotEmpty) {
      w.walkPlayerTo(rich.first.tile);
      return;
    }
    for (final s in g.shelves) {
      if (w.player.carry.contains(s.product) && s.stock < s.capacity) {
        w.walkPlayerTo(s.tile);
        return;
      }
    }
    if (g.count(Staff.stocker) * 6 < g.shelves.length) {
      final boxes = {for (final b in g.ofKind(ItemKind.box)) b.product: b};
      final low = g.shelves.where((s) => s.stock * 2 < s.capacity && boxes.containsKey(s.product)).toList()
        ..sort((a, b) => a.stock.compareTo(b.stock));
      if (low.isNotEmpty && w.player.carry.isEmpty) {
        w.walkPlayerTo(boxes[low.first.product]!.tile);
        return;
      }
    }
    if (g.trash.isNotEmpty && g.count(Staff.janitor) == 0) w.walkPlayerTo(g.trash.first);
  }

  // ---------------------------------------------------------------- 사기

  Tile? _spot(String type, {int rot = 0}) {
    for (final p in g.plots) {
      for (var y = p.$2 * plotSize; y < (p.$2 + 1) * plotSize; y++) {
        for (var x = p.$1 * plotSize; x < (p.$1 + 1) * plotSize; x++) {
          // 진열대끼리 붙지 않게 홀수 줄만 쓴다(통로가 생긴다)
          if (type != 'register' && y.isEven) continue;
          if (g.canPlace(type, (x, y), rot: rot) == PlaceResult.ok) return (x, y);
        }
      }
    }
    return null;
  }

  bool _place(String type, {String? product, int reserve = 0}) {
    if (g.money < itemType(type).price + reserve) return false;
    for (var rot = 0; rot < 4; rot++) {
      final t = _spot(type, rot: rot);
      if (t != null) return g.place(type, t, rot: rot, product: product);
      if (!itemType(type).rotates) break;
    }
    return false;
  }

  void _build() {
    final cashiers = g.count(Staff.cashier);
    if (cashiers < g.registers.length && g.money > staffSpecs[Staff.cashier]!.hire + 40) g.hire(Staff.cashier);
    final queued = w.queues.values.fold(0, (s, q) => s + q.length);
    if (queued > 3 * g.registers.length) _place('register', reserve: 50);
    if (g.count(Staff.stocker) < (g.shelves.length / 6).ceil() && g.money > 200) g.hire(Staff.stocker);
    if (g.trash.length > 3 && g.count(Staff.janitor) < 1 + g.plots.length ~/ 4 && g.money > 150) g.hire(Staff.janitor);

    // 새 상품: 진열대 + 상자
    final sale = g.onSale;
    for (final p in products) {
      if (!g.unlockedProduct(p) || sale.contains(p.id)) continue;
      final shelf = itemTypes.firstWhere((t) => t.shelf == p.kind);
      if (!g.unlockedItem(shelf) || g.money < shelf.price + itemType('box').price + 30) break;
      if (_place(shelf.id, product: p.id)) _place('box', product: p.id);
      break;
    }
    // 잘 팔리는 가게: 진열대를 하나씩 더 (상품마다 최대 둘)
    if (g.money > 400) {
      final counts = <String, int>{};
      for (final s in g.shelves) {
        counts[s.product!] = (counts[s.product!] ?? 0) + 1;
      }
      final fewest = counts.entries.where((e) => e.value < 2).toList();
      if (fewest.isNotEmpty) {
        final p = productById(fewest.first.key);
        _place(itemTypes.firstWhere((t) => t.shelf == p.kind).id, product: p.id, reserve: 200);
      }
    }
    if (g.decorCount * 2 < g.shelves.length) _place(g.level >= 3 ? 'flowers' : 'plant', reserve: 100);
    if (sale.any((p) => productById(p).eatIn) && g.ofKind(ItemKind.seat).length < 2 + g.plots.length) {
      _place('chair', reserve: 150);
    }
    if (g.ofKind(ItemKind.bin).length < g.plots.length) _place('bin', reserve: 100);
    for (final u in Upgrade.values) {
      final n = g.nextUpgrade(u);
      if (n != null && g.money > n.$1 * 1.5) g.buyUpgrade(u);
    }
    // 빈 자리가 모자라면 땅
    final free = _spot('rack') == null;
    if ((free || g.money > g.nextPlotPrice * 2) && g.plotsForSale.isNotEmpty && g.money >= g.nextPlotPrice) {
      g.buyPlot(g.plotsForSale.reduce((a, b) => a.$1 + a.$2 <= b.$1 + b.$2 ? a : b));
    }
  }
}

void main() {
  test('자동 플레이로 성장 속도 보기', () {
    final g = Game();
    final w = World(g, seed: 7);
    final bot = Bot(w);
    const dt = 0.1;
    final out = StringBuffer('분  레벨  돈      땅  진열대 상품 계산대 직원(계/진/청) 별점 목표 손님\n');
    var lastLevel = 1;
    final levelAt = <int, double>{};
    final stars = <int>[];
    for (var t = 0.0; t < 6 * 3600; t += dt) {
      bot.tick(dt);
      w.tick(dt);
      w.fx.clear();
      // 하루가 끝나면 별을 적고 바로 다음 날을 연다(사람은 닫힌 동안 좀 쉬니 실제로는 더 느리다)
      final r = w.result;
      if (r != null) {
        stars.add(r.stars);
        w.result = null;
      }
      if (w.phase == DayPhase.closed) w.openDay();
      if (g.level != lastLevel) {
        lastLevel = g.level;
        levelAt[g.level] = t / 60;
      }
      if ((t / 60) % 15 < dt / 60) {
        final head = '${(t / 60).round().toString().padLeft(3)}  ${g.level.toString().padLeft(4)}  '
            '${g.money.toString().padLeft(6)}  ${g.plots.length.toString().padLeft(2)}  '
            '${g.shelves.length.toString().padLeft(5)}  ${g.onSale.length.toString().padLeft(4)}  '
            '${g.registers.length.toString().padLeft(5)}  '
            '${g.count(Staff.cashier)}/${g.count(Staff.stocker)}/${g.count(Staff.janitor)}';
        out.writeln('${head.padRight(56)}${g.rating.toStringAsFixed(1)}  ${g.goal.toString().padLeft(3)}  ${g.served}');
      }
    }
    out.writeln('\n하루 ${stars.length}번, 별 0~3개 횟수: ${[for (var i = 0; i <= 3; i++) stars.where((x) => x == i).length]}');
    out.writeln('\n레벨 도달(분): ${levelAt.entries.map((e) => '${e.key}:${e.value.round()}').join('  ')}');
    // ignore: avoid_print
    print(out);
    expect(g.level, greaterThan(1));
  }, skip: !Platform.environment.containsKey('BALANCE'), timeout: const Timeout(Duration(minutes: 30)));

  test('무작위 최소값', () => expect(Random(1).nextInt(2), lessThan(2)));
}
