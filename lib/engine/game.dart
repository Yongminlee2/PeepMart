import 'dart:collection';
import 'dart:math';

import 'catalog.dart';

/// 바닥에 놓인 것 하나.
class Item {
  final String type;
  final int c, r;
  int rot; // 계산대 방향 (rotations 의 번호)
  String? product; // 진열대·상자에 든 상품
  int stock = 0; // 진열대 재고
  int cash = 0; // 계산대 옆에 쌓인 돈
  Item(this.type, this.c, this.r, {this.rot = 0, this.product});

  ItemType get t => itemType(type);
  Tile get tile => (c, r);
  Tile get _d => rotations[rot];
  Tile get till => (c + _d.$1, r + _d.$2); // 계산하는 사람 자리
  Tile get front => (c - _d.$1, r - _d.$2); // 손님 맨 앞 자리
  int get capacity => shelfCapacity[t.shelf]!;
}

enum PlaceResult { ok, locked, money, notOwned, occupied, blocksPath }

/// 꺼도 남는 상태와 짓기 규칙. 화면은 이걸 고치고, 움직이는 건 [World] 가 맡는다.
class Game {
  int money = startMoney;
  int level = 1, xp = 0;
  int served = 0; // 지금까지 계산한 손님
  final Set<Tile> plots = {(0, 0)}; // 가진 땅 (필지 좌표)
  final List<Item> items = [];
  final Map<Tile, String> floors = {}; // 칠한 바닥
  final Map<Staff, int> staff = {};
  final Map<Upgrade, int> upgrades = {};
  final Set<Tile> trash = {};
  final List<int> recent = []; // 최근 손님 만족도 0~5
  int savedAt = 0; // 마지막 저장 시각(밀리초). 꺼 둔 동안 번 돈 계산용

  /// 바뀔 때마다 1씩 오른다. [World] 가 길을 다시 찾을지 보는 데 쓴다.
  int layoutVersion = 0;
  final Map<Tile, Item> _at = {};

  Game() {
    for (final i in [
      Item('box', 1, 0, product: 'soda'),
      Item('box', 2, 0, product: 'donut'),
      Item('fridge', 2, 3, product: 'soda'),
      Item('rack', 3, 3, product: 'donut'),
      Item('register', 6, 2),
      Item('entrance', 7, 7),
      Item('plant', 0, 0),
      Item('bin', 7, 0),
    ]) {
      if (i.t.kind == ItemKind.shelf) i.stock = i.capacity;
      items.add(i);
    }
    _reindex();
  }

  // ---------------------------------------------------------------- 조회

  bool owns(Tile t) =>
      t.$1 >= 0 && t.$2 >= 0 && t.$1 < mapW && t.$2 < mapH && plots.contains((t.$1 ~/ plotSize, t.$2 ~/ plotSize));

  Item? at(Tile t) => _at[t];

  bool walkable(Tile t) => owns(t) && (_at[t]?.t.walkable ?? true);

  Iterable<Item> ofKind(ItemKind k) => items.where((i) => i.t.kind == k);
  Iterable<Item> get shelves => ofKind(ItemKind.shelf).where((i) => i.product != null);
  Iterable<Item> get registers => ofKind(ItemKind.register);
  Iterable<Item> get entrances => ofKind(ItemKind.entrance);

  /// 진열대에 올라 있는 상품들 (손님이 사러 올 수 있는 것).
  Set<String> get onSale => {for (final s in shelves) s.product!};

  int count(Staff s) => staff[s] ?? 0;
  int step(Upgrade u) => upgrades[u] ?? 0;
  int get arms => startArms + 2 * step(Upgrade.arms);
  double get speed => playerSpeed * (1 + 0.25 * step(Upgrade.shoes));
  int get wages => Staff.values.fold(0, (s, k) => s + count(k) * staffSpecs[k]!.wage);
  int get decorCount => ofKind(ItemKind.decor).length + ofKind(ItemKind.seat).length;

  bool unlockedItem(ItemType t) => level >= t.level;
  bool unlockedProduct(Product p) => level >= p.level;

  double get rating => recent.isEmpty ? startRating : recent.reduce((a, b) => a + b) / recent.length;

  void rate(int satisfaction) {
    recent.add(satisfaction.clamp(0, 5));
    if (recent.length > 30) recent.removeAt(0);
  }

  /// 계산대 앞으로 이어지는 줄 자리 (맨 앞부터). 막히면 거기서 끝난다.
  List<Tile> queueTiles(Item reg) {
    final d = rotations[reg.rot];
    final out = <Tile>[];
    var t = reg.front;
    while (out.length < 6 && walkable(t) && !_reserved(t, except: reg)) {
      out.add(t);
      t = (t.$1 - d.$1, t.$2 - d.$2);
    }
    return out;
  }

  /// 다른 계산대의 계산 자리·맨 앞 자리인가 (거기엔 아무것도 못 놓는다).
  bool _reserved(Tile t, {Item? except}) =>
      registers.any((r) => r != except && (r.till == t || r.front == t));

  // ---------------------------------------------------------------- 레벨

  /// 경험치를 더한다. 오른 레벨 수를 돌려준다.
  int addXp(int n) {
    var ups = 0;
    xp += n;
    while (level < maxLevel && xp >= xpToNext(level)) {
      xp -= xpToNext(level);
      level++;
      ups++;
    }
    return ups;
  }

  // ---------------------------------------------------------------- 짓기

  /// [free] 면 레벨·돈은 안 본다(이미 산 것을 옮길 때).
  PlaceResult canPlace(String typeId, Tile t, {int rot = 0, bool free = false}) {
    final type = itemType(typeId);
    if (!free && !unlockedItem(type)) return PlaceResult.locked;
    if (!free && money < type.price) return PlaceResult.money;
    if (!owns(t)) return PlaceResult.notOwned;
    if (type.kind == ItemKind.floor) return floors[t] == typeId ? PlaceResult.occupied : PlaceResult.ok;
    if (_at.containsKey(t) || _reserved(t) || trash.contains(t)) return PlaceResult.occupied;
    final probe = Item(typeId, t.$1, t.$2, rot: rot);
    if (type.kind == ItemKind.register) {
      for (final s in [probe.till, probe.front]) {
        if (!owns(s) || _at[s]?.t.walkable == false || _reserved(s)) return PlaceResult.occupied;
      }
    }
    if (!type.walkable && !_stillReachable(add: probe)) return PlaceResult.blocksPath;
    return PlaceResult.ok;
  }

  bool place(String typeId, Tile t, {int rot = 0, String? product}) {
    if (canPlace(typeId, t, rot: rot) != PlaceResult.ok) return false;
    final type = itemType(typeId);
    money -= type.price;
    if (type.kind == ItemKind.floor) {
      floors[t] = typeId;
    } else {
      final i = Item(typeId, t.$1, t.$2, rot: rot, product: product);
      if (type.kind == ItemKind.shelf && product != null) i.stock = i.capacity;
      items.add(i);
    }
    _changed();
    return true;
  }

  /// 옮길 수 있는가 (바꾸지 않고 보기만).
  PlaceResult canMove(Item i, Tile t, {int? rot}) {
    items.remove(i);
    _reindex();
    final res = canPlace(i.type, t, rot: rot ?? i.rot, free: true);
    items.add(i);
    _reindex();
    return res;
  }

  /// 이미 놓은 것을 다른 칸으로 옮긴다(공짜). 못 옮기면 그대로 두고 그 까닭을 돌려준다.
  PlaceResult move(Item i, Tile t, {int? rot}) {
    items.remove(i);
    _reindex();
    final r = rot ?? i.rot;
    final res = canPlace(i.type, t, rot: r, free: true);
    if (res == PlaceResult.ok) {
      items.add(Item(i.type, t.$1, t.$2, rot: r, product: i.product)
        ..stock = i.stock
        ..cash = i.cash);
    } else {
      items.add(i);
    }
    _changed();
    return res;
  }

  /// 판다(값의 절반을 돌려받는다). 마지막 입구·마지막 계산대는 못 판다.
  bool sell(Item i) {
    if (i.t.kind == ItemKind.entrance && entrances.length <= 1) return false;
    if (i.t.kind == ItemKind.register && registers.length <= 1) return false;
    items.remove(i);
    money += (i.t.price * sellRefund).round() + i.cash;
    _changed();
    return true;
  }

  bool sellFloor(Tile t) {
    final f = floors.remove(t);
    if (f == null) return false;
    _changed();
    return true;
  }

  bool rotate(Item i) {
    if (!i.t.rotates) return false;
    final old = i.rot;
    items.remove(i);
    _reindex();
    for (var k = 1; k <= 4; k++) {
      final n = (old + k) % 4;
      final probe = Item(i.type, i.c, i.r, rot: n);
      final ok = [probe.till, probe.front]
          .every((s) => owns(s) && _at[s]?.t.walkable != false && !_reserved(s));
      if (ok && _stillReachable(add: probe)) {
        i.rot = n;
        break;
      }
    }
    items.add(i);
    _changed();
    return i.rot != old;
  }

  /// 진열대·상자의 상품을 바꾼다. 진열대는 비워진다(새 상품은 날라 와야 한다).
  bool setProduct(Item i, String product) {
    final p = productById(product);
    if (!i.t.needsProduct || !unlockedProduct(p)) return false;
    if (i.t.kind == ItemKind.shelf && i.t.shelf != p.kind) return false;
    if (i.product == product) return false;
    i.product = product;
    i.stock = 0;
    _changed();
    return true;
  }

  // ---------------------------------------------------------------- 땅

  /// 지금 살 수 있는 필지: 가진 땅과 맞닿은 것.
  Set<Tile> get plotsForSale => {
        for (final (x, y) in plots)
          for (final n in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
            if (n.$1 >= 0 && n.$2 >= 0 && n.$1 < plotCols && n.$2 < plotRows && !plots.contains(n)) n,
      };

  int get nextPlotPrice => plotPrice(plots.length);

  bool buyPlot(Tile p) {
    if (!plotsForSale.contains(p) || money < nextPlotPrice) return false;
    money -= nextPlotPrice;
    plots.add(p);
    _changed();
    return true;
  }

  // ---------------------------------------------------------------- 직원·업그레이드

  bool canHire(Staff s) {
    final spec = staffSpecs[s]!;
    return level >= spec.level && count(s) < spec.max && money >= spec.hire;
  }

  bool hire(Staff s) {
    if (!canHire(s)) return false;
    money -= staffSpecs[s]!.hire;
    staff[s] = count(s) + 1;
    return true;
  }

  bool fire(Staff s) {
    if (count(s) == 0) return false;
    staff[s] = count(s) - 1;
    return true;
  }

  /// 다음 단계 (값, 필요 레벨). 다 샀으면 null.
  (int, int)? nextUpgrade(Upgrade u) {
    final steps = upgradeSteps[u]!;
    return step(u) < steps.length ? steps[step(u)] : null;
  }

  bool buyUpgrade(Upgrade u) {
    final n = nextUpgrade(u);
    if (n == null || money < n.$1 || level < n.$2) return false;
    money -= n.$1;
    upgrades[u] = step(u) + 1;
    return true;
  }

  // ---------------------------------------------------------------- 꺼 둔 동안

  /// 앱을 꺼 둔 동안 번 돈. 계산원이 서 있는 계산대가 있어야 벌고, 두 시간까지만.
  /// 켜 둔 것보다 덜 벌어야(대략 1/3) 들어와서 하는 맛이 남는다.
  int offlineEarnings(double seconds) {
    final tills = min(count(Staff.cashier), registers.length);
    final sale = onSale;
    if (tills == 0 || sale.isEmpty || seconds <= 0) return 0;
    final avg = sale.map((p) => productById(p).price).reduce((a, b) => a + b) / sale.length;
    final perSecond = avg * 1.5 / spawnInterval(shelves.length, rating, decorCount);
    return (min(seconds, 7200) * perSecond / 3).floor();
  }

  // ---------------------------------------------------------------- 내부

  void _changed() {
    layoutVersion++;
    _reindex();
  }

  void _reindex() {
    _at
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.tile, i)));
  }

  /// 입구에서 걸어서 모든 진열대·상자·계산대 맨 앞에 닿을 수 있는가.
  /// [add] 를 놓았다고 치고 본다. 아무것도 갇히지 않게 짓기를 막는 데 쓴다.
  bool _stillReachable({Item? add}) {
    bool free(Tile t) => owns(t) && t != add?.tile && (_at[t]?.t.walkable ?? true);
    final start = entrances.map((e) => e.tile).where(free).toList();
    if (start.isEmpty) return false;
    final seen = <Tile>{...start};
    final q = Queue<Tile>.of(start);
    while (q.isNotEmpty) {
      final (x, y) = q.removeFirst();
      for (final n in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]) {
        if (free(n) && seen.add(n)) q.add(n);
      }
    }
    for (final i in [...items, ?add]) {
      final k = i.t.kind;
      if (k == ItemKind.register) {
        if (!seen.contains(i.front) || !seen.contains(i.till)) return false;
      } else if (k == ItemKind.shelf || k == ItemKind.box) {
        final (x, y) = i.tile;
        if (![(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)].any(seen.contains)) return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------- 저장

  Map<String, Object> toJson() => {
        'money': money,
        'level': level,
        'xp': xp,
        'served': served,
        'plots': [for (final p in plots) [p.$1, p.$2]],
        'items': [
          for (final i in items) [i.type, i.c, i.r, i.rot, i.product ?? '', i.stock, i.cash]
        ],
        'floors': [for (final e in floors.entries) [e.key.$1, e.key.$2, e.value]],
        'staff': {for (final e in staff.entries) e.key.name: e.value},
        'upgrades': {for (final e in upgrades.entries) e.key.name: e.value},
        'trash': [for (final t in trash) [t.$1, t.$2]],
        'recent': recent,
        'savedAt': savedAt,
      };

  static Game fromJson(Map<String, dynamic> j) {
    final g = Game()
      ..money = j['money'] as int
      ..level = j['level'] as int
      ..xp = j['xp'] as int
      ..served = j['served'] as int
      ..savedAt = j['savedAt'] as int? ?? 0;
    Tile tile(List l) => (l[0] as int, l[1] as int);
    g.plots
      ..clear()
      ..addAll([for (final p in j['plots'] as List) tile(p as List)]);
    g.items
      ..clear()
      ..addAll([
        for (final l in (j['items'] as List).cast<List>())
          Item(l[0] as String, l[1] as int, l[2] as int,
              rot: l[3] as int, product: (l[4] as String).isEmpty ? null : l[4] as String)
            ..stock = l[5] as int
            ..cash = l[6] as int
      ]);
    for (final l in (j['floors'] as List).cast<List>()) {
      g.floors[tile(l)] = l[2] as String;
    }
    for (final e in (j['staff'] as Map).entries) {
      g.staff[Staff.values.byName(e.key as String)] = e.value as int;
    }
    for (final e in (j['upgrades'] as Map).entries) {
      g.upgrades[Upgrade.values.byName(e.key as String)] = e.value as int;
    }
    g.trash.addAll([for (final t in j['trash'] as List) tile(t as List)]);
    g.recent.addAll((j['recent'] as List).cast<int>());
    g._reindex();
    return g;
  }
}

/// 손님이 오는 간격(초). 진열대가 많을수록·별점이 높을수록·꾸밀수록 자주 온다.
double spawnInterval(int shelves, double rating, int decor) =>
    6 / (1 + rating * 0.25) / (0.4 + 0.08 * shelves) / min(1.6, 1 + 0.02 * decor);
