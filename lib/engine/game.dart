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
  int level = 1; // 가구 레벨 (진열대·계산대)
  bool broken = false; // 고장 (그날만, 저장 안 함)
  int price = defaultPrice; // 가격표 (priceLevels 의 번호)
  int units = boxSize; // 상자에 남은 물건
  double incoming = 0; // 주문한 상자가 도착하기까지 남은 초 (0 이면 주문 없음)
  Item(this.type, this.c, this.r, {this.rot = 0, this.product});

  ItemType get t => itemType(type);
  Tile get tile => (c, r);
  Tile get _d => rotations[rot];
  Tile get till => (c + _d.$1, r + _d.$2); // 계산하는 사람 자리
  Tile get front => (c - _d.$1, r - _d.$2); // 손님 맨 앞 자리
  int get capacity => levelCapacity(shelfCapacity[t.shelf]!, level);
  bool get levels => t.kind == ItemKind.shelf || t.kind == ItemKind.register;
}

enum PlaceResult { ok, locked, money, notOwned, occupied, blocksPath }

/// 지점끼리 함께 쓰는 것: 돈·레벨·목표·업그레이드·단골·처음 안내·지점들.
class Owner {
  int money = startMoney;
  int level = 1, xp = 0;
  int served = 0; // 지금까지 계산한 손님 (모든 지점)
  int goal = 0; // 지금 목표 (goals 의 번호, 다 하면 goals.length)
  final Map<Upgrade, int> upgrades = {};
  final Map<String, int> hearts = {}; // 단골 → 하트 수
  TutorialStep tutorial = TutorialStep.pickBox;
  int savedAt = 0; // 마지막 저장 시각(밀리초). 꺼 둔 동안 번 돈 계산용
  final Map<String, Game> branches = {}; // 연 지점들
  final Set<int> met = {}; // 만난 손님 (캐릭터 시트 번호)
  final Map<String, int> sold = {}; // 상품마다 지금까지 판 개수
  final Set<String> story = {}; // 본 이야기
  final Set<String> combosFound = {}; // 한 번이라도 만든 진열 세트
  int goalBase = 0; // 목표를 다 이룬 때의 손님 수(끝없는 목표의 출발점)
  String current = 'piyak';

  Owner() {
    Game._(this, 'piyak');
  }

  Game get game => branches[current]!;

  int heartsOf(String regular) => hearts[regular] ?? 0;

  int get rank => rankOf(level);

  /// 이야기를 열 때가 됐는가.
  bool chapterReady(String id) => switch (id) {
        'opening' => tutorial == TutorialStep.done,
        'rival' => rank >= 1,
        'mayor' => rank >= 2,
        'scheme' => rank >= 3,
        'festival' => rank >= 4,
        'finale' => rank >= 5,
        _ => branches.containsKey(id), // 지점 이름: 그 동네를 열면
      };

  /// 아직 안 본 다음 이야기 (차례대로).
  Chapter? get nextChapter => chapters.where((c) => !story.contains(c.id) && chapterReady(c.id)).firstOrNull;

  /// 손님을 만났다. 처음이면 true, [meetEvery] 명째마다 상금이 들어온다.
  (bool, int) meet(int sheet) {
    if (!met.add(sheet)) return (false, 0);
    final reward = met.length % meetEvery == 0 ? meetReward(met.length ~/ meetEvery) : 0;
    money += reward;
    return (true, reward);
  }

  /// 하나 팔았다. 딱 [stampAt] 개째면 도장 상금을 주고 그 값을 돌려준다.
  int addSold(String product) {
    final n = (sold[product] ?? 0) + 1;
    sold[product] = n;
    if (n != stampAt) return 0;
    final reward = productById(product).price * stampAt;
    money += reward;
    return reward;
  }

  /// 처음 안내가 [step] 에 있으면 다음으로 넘긴다.
  void advance(TutorialStep step) {
    if (tutorial == step) tutorial = TutorialStep.values[step.index + 1];
  }

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

  bool canOpen(String branch) {
    final b = branchById(branch);
    return !branches.containsKey(branch) && level >= b.level && money >= b.price;
  }

  /// 새 지점을 연다(돈을 내고). 열려 있으면 그리로 옮기기만 한다.
  bool open(String branch) {
    if (branches.containsKey(branch)) {
      current = branch;
      return true;
    }
    if (!canOpen(branch)) return false;
    money -= branchById(branch).price;
    Game._(this, branch);
    current = branch;
    return true;
  }

  /// 꺼 둔 동안 모든 지점이 번 돈.
  int offlineEarnings(double seconds) => branches.values.fold(0, (s, g) => s + g.offlineEarnings(seconds));

  Map<String, Object> toJson() => {
        'money': money,
        'level': level,
        'xp': xp,
        'served': served,
        'goal': goal,
        'upgrades': {for (final e in upgrades.entries) e.key.name: e.value},
        'hearts': hearts,
        'tutorial': tutorial.name,
        'savedAt': savedAt,
        'current': current,
        'branches': {for (final e in branches.entries) e.key: e.value._toJson()},
        'met': met.toList()..sort(),
        'story': story.toList(),
        'combos': combosFound.toList(),
        'goalBase': goalBase,
        'sold': sold,
      };

  static Owner fromJson(Map<String, dynamic> j) {
    final o = Owner()
      ..money = j['money'] as int
      ..level = j['level'] as int
      ..xp = j['xp'] as int
      ..served = j['served'] as int
      ..goal = j['goal'] as int
      ..tutorial = TutorialStep.values.byName(j['tutorial'] as String)
      ..savedAt = j['savedAt'] as int? ?? 0;
    for (final e in (j['upgrades'] as Map).entries) {
      o.upgrades[Upgrade.values.byName(e.key as String)] = e.value as int;
    }
    o.hearts.addAll((j['hearts'] as Map).cast<String, int>());
    o.met.addAll(((j['met'] as List?) ?? const []).cast<int>());
    o.story.addAll(((j['story'] as List?) ?? const []).cast<String>());
    o.combosFound.addAll(((j['combos'] as List?) ?? const []).cast<String>());
    o.goalBase = j['goalBase'] as int? ?? 0;
    o.sold.addAll(((j['sold'] as Map?) ?? const {}).cast<String, int>());
    o.branches.clear();
    for (final e in (j['branches'] as Map).entries) {
      Game._(o, e.key as String)._fromJson(e.value as Map<String, dynamic>);
    }
    o.current = o.branches.containsKey(j['current']) ? j['current'] as String : 'piyak';
    return o;
  }
}

/// 지점 하나: 땅·가구·직원·매니저·쓰레기·별점과 짓기 규칙.
/// 움직이는 건 [World] 가 맡는다.
class Game {
  final Owner owner;
  final String branch;
  final Set<Tile> plots = {(0, 0)}; // 가진 땅 (필지 좌표)
  final List<Item> items = [];
  final Map<Tile, String> floors = {}; // 칠한 바닥
  final Map<Staff, int> staff = {};
  final Set<ShelfKind> managers = {};
  final Set<Tile> trash = {};
  final List<int> recent = []; // 최근 손님 만족도 0~5
  int day = 1; // 다음에 열 날
  int bestSales = 0; // 하루 최고 매출
  double avgSales = 0, avgServed = 0; // 최근 하루들의 평균. 목표·할 일을 내 가게 실력에 맞춘다
  Weather weather = Weather.sunny; // 다음에 여는 날의 날씨 (닫을 때 정해 둔다)

  /// 바뀔 때마다 1씩 오른다. [World] 가 길을 다시 찾을지 보는 데 쓴다.
  int layoutVersion = 0;
  final Map<Tile, Item> _at = {};

  /// 새 게임: 주인과 첫 지점(삐약동).
  factory Game() => Owner().game;

  Game._(this.owner, this.branch) {
    owner.branches[branch] = this;
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

  // 함께 쓰는 값은 주인에게서
  int get money => owner.money;
  set money(int v) => owner.money = v;
  int get level => owner.level;
  set level(int v) => owner.level = v;
  int get xp => owner.xp;
  set xp(int v) => owner.xp = v;
  int get served => owner.served;
  set served(int v) => owner.served = v;
  int get goal => owner.goal;
  set goal(int v) => owner.goal = v;
  int get savedAt => owner.savedAt;
  set savedAt(int v) => owner.savedAt = v;
  Map<Upgrade, int> get upgrades => owner.upgrades;
  int addXp(int n) => owner.addXp(n);

  Branch get info => branchById(branch);
  int get rank => owner.rank;

  /// 손님이 오는 평균 간격(초): 진열대·별점·꾸미기, 그리고 가게 등급.
  double get spawnGap => spawnInterval(shelves.length, rating, decorCount) / (1 + rankVisitorBonus * rank);

  // ---------------------------------------------------------------- 조회

  bool owns(Tile t) =>
      t.$1 >= 0 && t.$2 >= 0 && t.$1 < mapW && t.$2 < mapH && plots.contains((t.$1 ~/ plotSize, t.$2 ~/ plotSize));

  Item? at(Tile t) => _at[t];

  bool walkable(Tile t) => owns(t) && (_at[t]?.t.walkable ?? true);

  Iterable<Item> ofKind(ItemKind k) => items.where((i) => i.t.kind == k);
  Iterable<Item> get shelves => ofKind(ItemKind.shelf).where((i) => i.product != null);
  Iterable<Item> get registers => ofKind(ItemKind.register);
  Iterable<Item> get entrances => ofKind(ItemKind.entrance);
  Item? boxOf(String product) => ofKind(ItemKind.box).where((b) => b.product == product).firstOrNull;

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

  /// 이 진열대에서 이 상품 하나를 팔면 받는 값: 가구 레벨·지점 대표 상품·매니저가 올린다.
  int salePrice(Item shelf, String product) {
    final p = productById(product);
    var v = p.price * levelPrice(shelf.level);
    if (info.featured.contains(product)) v *= featuredPrice;
    if (managers.contains(p.kind)) v *= managerPrice;
    v *= priceLevels[shelf.price.clamp(0, priceLevels.length - 1)];
    if (inCombo(shelf)) v *= comboPrice;
    return max(1, v.round());
  }

  /// 상자를 다시 주문한다: 돈을 내고 [restockDelay] 초 뒤 도착. 이미 오는 중이거나 가득 찼거나 돈이 없으면 false.
  bool reorder(Item box) {
    final p = box.product;
    if (box.t.kind != ItemKind.box || p == null || box.incoming > 0 || box.units >= boxMax - boxSize + 1) return false;
    final cost = reorderCost(p);
    if (money < cost) return false;
    money -= cost;
    box.incoming = restockDelay;
    return true;
  }

  /// 가격표를 다음 단계로 (싸게 → 보통 → 비싸게 → 프리미엄 → 싸게).
  void cyclePrice(Item shelf) => shelf.price = (shelf.price + 1) % priceLevels.length;

  List<(Combo, List<Item>)>? _combos;
  int _combosAt = -1;

  /// 지금 이뤄진 진열 세트와 그 진열대들. 배치가 바뀔 때만 다시 센다.
  List<(Combo, List<Item>)> get activeCombos {
    if (_combos != null && _combosAt == layoutVersion) return _combos!;
    _combosAt = layoutVersion;
    final out = <(Combo, List<Item>)>[];
    bool close(Item a, Item b) => max((a.c - b.c).abs(), (a.r - b.r).abs()) <= comboRange;
    for (final k in combos) {
      final groups = [for (final p in k.products) shelves.where((s) => s.product == p).toList()];
      if (groups.any((g) => g.isEmpty)) continue;
      // 세 진열대가 서로 가까운 짝을 하나 찾는다
      List<Item>? found;
      for (final a in groups[0]) {
        for (final b in groups[1].where((b) => close(a, b))) {
          final c = groups[2].where((c) => close(a, c) && close(b, c)).firstOrNull;
          if (c != null) {
            found = [a, b, c];
            break;
          }
        }
        if (found != null) break;
      }
      if (found != null) out.add((k, found));
    }
    return _combos = out;
  }

  bool inCombo(Item shelf) => activeCombos.any((c) => c.$2.contains(shelf));

  /// 처음 만든 세트들을 기록하고 돌려준다.
  List<Combo> newCombos() => [
        for (final (k, _) in activeCombos)
          if (owner.combosFound.add(k.id)) k
      ];

  /// 계산대 맨 앞에서 물건 하나 찍는 데 걸리는 초.
  double scanTime(Item reg, {required bool cashier}) =>
      (cashier ? scanStepCashier : scanStepPlayer) / levelScan(reg.level);

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

  // ---------------------------------------------------------------- 단골

  /// 이 지점에 찾아올 수 있는 단골.
  Iterable<Regular> get regularsHere => regulars.where((r) => r.branch == branch && level >= r.level);

  /// 단골의 부탁을 들어줬다: 하트가 오르고 상금. 오른 하트 수(이미 가득이면 null).
  int? giveHeart(String regular) {
    final h = owner.heartsOf(regular);
    if (h >= maxHearts) return null;
    owner.hearts[regular] = h + 1;
    money += heartReward(h + 1);
    return h + 1;
  }

  // ---------------------------------------------------------------- 목표

  /// 지금 목표. 목록을 다 이루면 '손님 N명 받기'가 끝없이 이어진다.
  Goal? get currentGoal {
    if (goal < goals.length) return goals[goal];
    final i = goal - goals.length;
    return Goal(GoalKind.served, owner.goalBase + extraGoalStep * (i + 1), extraGoalReward(i));
  }

  /// 목표가 재는 지금 값.
  int progress(GoalKind k) => switch (k) {
        GoalKind.shelves => shelves.length,
        GoalKind.served => served,
        GoalKind.cashiers => count(Staff.cashier),
        GoalKind.registers => registers.length,
        GoalKind.level => level,
        GoalKind.plots => plots.length,
        GoalKind.decor => decorCount,
        GoalKind.stockers => count(Staff.stocker),
        GoalKind.products => onSale.length,
        GoalKind.rating => (rating * 10).floor(),
        GoalKind.seats => ofKind(ItemKind.seat).length,
        GoalKind.janitors => count(Staff.janitor),
      };

  /// 지금 목표를 이뤘으면 상금을 주고 다음으로 넘긴다. 이룬 목표를 돌려준다.
  Goal? checkGoal() {
    if (goal >= goals.length && owner.goalBase == 0) owner.goalBase = served; // 예전 저장: 지금부터 센다
    final g = currentGoal;
    if (g == null || progress(g.kind) < g.target) return null;
    money += g.reward;
    goal++;
    if (goal == goals.length) owner.goalBase = served;
    return g;
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
      if (type.kind == ItemKind.box) i.units = 0; // 상자 값엔 물건이 안 들었다: 주문해서 채운다
      items.add(i);
      owner.advance(TutorialStep.build);
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
        ..cash = i.cash
        ..level = i.level
        ..price = i.price
        ..units = i.units
        ..incoming = i.incoming
        ..broken = i.broken);
    } else {
      items.add(i);
    }
    _changed();
    return res;
  }

  /// 판다(값의 절반을 돌려받는다, 올린 레벨 값도 절반). 마지막 입구·마지막 계산대는 못 판다.
  bool sell(Item i) {
    if (i.t.kind == ItemKind.entrance && entrances.length <= 1) return false;
    if (i.t.kind == ItemKind.register && registers.length <= 1) return false;
    items.remove(i);
    var spent = i.t.price;
    for (var l = 1; l < i.level; l++) {
      spent += itemUpgradeCost(i.t, l);
    }
    money += (spent * sellRefund).round() + i.cash;
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
      final ok = [probe.till, probe.front].every((s) => owns(s) && _at[s]?.t.walkable != false && !_reserved(s));
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
    if (i.t.kind == ItemKind.box && i.incoming > 0) return false; // 오는 중인 주문이 있으면 못 바꾼다
    i.product = product;
    i.stock = 0;
    if (i.t.kind == ItemKind.box) i.units = 0;
    _changed();
    return true;
  }

  /// 가구 레벨업 값 (다 올렸거나 못 올리는 가구면 null).
  int? levelUpCost(Item i) => i.levels && i.level < maxItemLevel ? itemUpgradeCost(i.t, i.level) : null;

  bool levelUp(Item i) {
    final cost = levelUpCost(i);
    if (cost == null || money < cost) return false;
    money -= cost;
    i.level++;
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

  // ---------------------------------------------------------------- 직원·매니저·업그레이드

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

  bool canHireManager(ManagerSpec m) => !managers.contains(m.kind) && level >= m.level && money >= m.price;

  bool hireManager(ManagerSpec m) {
    if (!canHireManager(m)) return false;
    money -= m.price;
    managers.add(m.kind);
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

  // ---------------------------------------------------------------- 하루 장사

  /// 손님이 오는 대로 다 팔았을 때 하루에 오는 손님 수와 버는 돈.
  (double, double) get fullDay {
    final sale = onSale;
    if (sale.isEmpty) return (0, 0);
    final avg = sale.map((p) => productById(p).price).reduce((a, b) => a + b) / sale.length;
    // 마감 전 몰림까지 치면 손님이 15% 더 오고, 한 사람이 평균 두 개쯤 산다
    final visitors = dayLength / spawnGap * 1.15;
    return (visitors, visitors * avg * 2);
  }

  /// 다음에 여는 날의 날씨. 동네 편의점 전에는 늘 맑음.
  Weather get todayWeather => rank >= rankWeather ? weather : Weather.sunny;

  /// 다음에 여는 날이 위생 점검 날인가.
  bool get inspectionDay => rank >= rankInspection && day % inspectEvery == 0;

  /// 다음에 여는 날이 메가마트 가격 전쟁 날인가 (삐약동, 라이벌 이야기 중에만).
  bool get priceWarDay =>
      branch == 'piyak' && owner.story.contains('rival') && !owner.story.contains('finale') && day % priceWarEvery == 3;

  /// 다음에 여는 날이 특별한 날이면 그 종류.
  SpecialDay? get todaySpecial {
    if (rank < rankSpecialDay || day % specialEvery != 0) return null;
    final kinds = [SpecialDay.picnic, SpecialDay.exam, if (rank >= rankFestival) SpecialDay.festival];
    return kinds[(day ~/ specialEvery - 1) % kinds.length];
  }

  /// 오늘 잘 팔리는 상품(날씨 + 특별한 날) 중 지금 진열된 것.
  Set<String> get favored => {
        ...weatherGoods[todayWeather]!,
        ...?specialGoods[todaySpecial],
      }.intersection(onSale);

  /// 하루 운영비: 임대료 + 진열대 관리비.
  int get dailyCost => (plots.length * rentPerPlot * (1 + rentPerRank * rank)).round() + shelves.length * upkeepPerShelf;

  /// 해 본 날이 있는가. 있으면 목표·할 일을 최근 평균으로 정한다.
  /// (가게 크기로 어림하면 계산대·알바가 모자란 큰 가게에서 목표가 터무니없이 높아진다.)
  bool get hasHistory => avgServed > 0;

  /// 오늘 목표 매출. 첫날은 가게 크기로 어림해 낮게, 그다음부터는 최근 평균보다 조금 높게. 10 단위.
  int get dayTarget {
    final v = hasHistory ? avgSales * dayTargetGrowth : fullDay.$2 * dayTargetShare * min(1.0, 0.5 + 0.1 * day);
    return max(20, (v / 10).round() * 10);
  }

  /// 하루가 끝났을 때 평균에 넣는다.
  void recordDay(int sales, int served) {
    double mix(double avg, int today) => avg <= 0 ? today.toDouble() : avg * (1 - dayAverageWeight) + today * dayAverageWeight;
    avgSales = mix(avgSales, sales);
    avgServed = mix(avgServed, served);
  }

  // ---------------------------------------------------------------- 꺼 둔 동안

  /// 꺼 둔 동안 버는 시간 한계: 두 시간 + 매니저마다 한 시간 (최대 여덟 시간).
  double get offlineHours => min(offlineMaxHours, offlineBaseHours + offlineHoursPerManager * managers.length);

  /// 앱을 꺼 둔 동안 이 지점이 번 돈. 계산원이나 매니저가 있어야 번다.
  /// 켜 둔 것보다 덜 벌어야(대략 1/3) 들어와서 하는 맛이 남는다. 매니저마다 15% 더.
  int offlineEarnings(double seconds) {
    final tills = min(count(Staff.cashier), registers.length);
    final sale = onSale;
    if ((tills == 0 && managers.isEmpty) || sale.isEmpty || seconds <= 0) return 0;
    final avg = sale.map((p) => productById(p).price).reduce((a, b) => a + b) / sale.length;
    // 물건 원가(도매가)를 빼고 남는 만큼만
    final perSecond = avg * (1 - wholesaleRate) * 1.5 / spawnGap * (1 + 0.15 * managers.length);
    return (min(seconds, offlineHours * 3600) * perSecond / 3).floor();
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

  /// 저장: 주인(과 모든 지점)을 통째로.
  Map<String, Object> toJson() => owner.toJson();

  /// 불러오기: 마지막으로 있던 지점을 돌려준다.
  static Game fromJson(Map<String, dynamic> j) => Owner.fromJson(j).game;

  Map<String, Object> _toJson() => {
        'plots': [for (final p in plots) [p.$1, p.$2]],
        'items': [
          for (final i in items)
            // 오는 중인 주문은 저장할 때 도착한 것으로 친다
            [i.type, i.c, i.r, i.rot, i.product ?? '', i.stock, i.cash, i.level, i.price, min(boxMax, i.units + (i.incoming > 0 ? boxSize : 0))]
        ],
        'floors': [for (final e in floors.entries) [e.key.$1, e.key.$2, e.value]],
        'staff': {for (final e in staff.entries) e.key.name: e.value},
        'managers': [for (final m in managers) m.name],
        'trash': [for (final t in trash) [t.$1, t.$2]],
        'recent': recent,
        'day': day,
        'best': bestSales,
        'avg': [avgSales, avgServed],
        'weather': weather.name,
      };

  void _fromJson(Map<String, dynamic> j) {
    Tile tile(List l) => (l[0] as int, l[1] as int);
    plots
      ..clear()
      ..addAll([for (final p in j['plots'] as List) tile(p as List)]);
    items
      ..clear()
      ..addAll([
        for (final l in (j['items'] as List).cast<List>())
          Item(l[0] as String, l[1] as int, l[2] as int,
              rot: l[3] as int, product: (l[4] as String).isEmpty ? null : l[4] as String)
            ..stock = l[5] as int
            ..cash = l[6] as int
            ..level = l.length > 7 ? l[7] as int : 1
            ..price = l.length > 8 ? l[8] as int : defaultPrice
            ..units = l.length > 9 ? l[9] as int : boxSize
      ]);
    for (final l in (j['floors'] as List).cast<List>()) {
      floors[tile(l)] = l[2] as String;
    }
    for (final e in (j['staff'] as Map).entries) {
      staff[Staff.values.byName(e.key as String)] = e.value as int;
    }
    managers.addAll([for (final m in j['managers'] as List) ShelfKind.values.byName(m as String)]);
    trash.addAll([for (final t in j['trash'] as List) tile(t as List)]);
    recent.addAll((j['recent'] as List).cast<int>());
    day = j['day'] as int? ?? 1;
    bestSales = j['best'] as int? ?? 0;
    final avg = j['avg'] as List?;
    avgSales = (avg?[0] as num?)?.toDouble() ?? 0;
    avgServed = (avg?[1] as num?)?.toDouble() ?? 0;
    weather = Weather.values.asNameMap()[j['weather']] ?? Weather.sunny;
    _reindex();
  }
}

/// 손님이 오는 간격(초). 진열대가 많을수록·별점이 높을수록·꾸밀수록 자주 온다.
double spawnInterval(int shelves, double rating, int decor) =>
    6 / (1 + rating * 0.25) / (0.4 + 0.08 * shelves) / min(1.6, 1 + 0.02 * decor);
