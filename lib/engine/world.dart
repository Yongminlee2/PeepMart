import 'dart:collection';
import 'dart:math';

import 'catalog.dart';
import 'game.dart';

/// 좌표는 칸 단위 소수. 정수 값이 칸의 한가운데다 (x=2 는 2번 칸 중앙).
class Walker {
  double x, y;
  double dx = 0, dy = 1; // 마지막으로 걸은 방향(그리기용)
  bool moving = false;
  List<Tile> path = [];
  Tile goal;
  final List<String> carry = [];
  Walker(Tile at)
      : x = at.$1.toDouble(),
        y = at.$2.toDouble(),
        goal = at;

  bool get arrived => path.isEmpty;
  Tile get tile => (x.round(), y.round());
  double distTo(Tile t) => sqrt(pow(x - t.$1, 2) + pow(y - t.$2, 2));
}

enum CState { toShelf, atShelf, toQueue, toSeat, sitting, leaving, gone }

class Customer extends Walker {
  final int look;
  final List<String> wants; // 사려는 상품, 차례대로
  int wantIndex = 0;
  int missed = 0;
  CState state = CState.toShelf;
  Item? shelf, register, seat;
  double timer = 0; // 진열대 앞·자리에서 보낸 시간
  double waited = 0; // 줄에서 기다린 시간
  int scanned = 0;
  int bonus = 0; // 앉아서 먹고 가면 +1
  double react = 0; // 남은 반응 시간. 반응하는 동안은 멈춰 선다
  bool happy = false;
  CustomerKind kind = CustomerKind.normal;
  Customer(this.look, super.at, this.wants);

  double get patience => kind == CustomerKind.hurry ? 0.5 : 1.0;

  String get want => wants[wantIndex];
}

enum StaffState { idle, toWork, working, toShelf, unloading }

class StaffAgent extends Walker {
  final Staff kind;
  StaffState state = StaffState.idle;
  Item? item; // 계산원: 맡은 계산대 / 진열원: 채울 진열대
  Tile? target; // 청소부: 치울 쓰레기
  double step = 0;
  StaffAgent(this.kind, super.at);
}

enum FxKind { pick, place, scan, cash, pay, angry, sad, levelUp, litter, clean, goal, event }

/// 화면 연출용 사건. 엔진은 쌓기만 하고 화면이 가져가 비운다.
class Fx {
  final FxKind kind;
  final double x, y;
  final double tx, ty;
  final String product;
  final int amount;
  Fx(this.kind, this.x, this.y, {double? tx, double? ty, this.product = '', this.amount = 0})
      : tx = tx ?? x,
        ty = ty ?? y;
}

class World {
  final Game game;
  final Random _rng;
  late Walker player;
  final List<Customer> customers = [];
  final List<StaffAgent> staff = [];
  final Map<Item, List<Customer>> queues = {};
  final List<Fx> fx = [];
  double input = 0, inputY = 0; // 조이스틱, 세계 방향, 크기 0~1
  double time = 0;
  final Map<Item, double> lastScan = {};
  double _spawnIn = 1, _playerStep = 0, _cashStep = 0, _wageIn = wagePeriod;
  EventKind? event; // 지금 벌어지는 행사
  double eventLeft = 0, _eventIn = eventGap.$1;
  int _vipQueue = 0; // VIP 방문 행사로 아직 올 VIP 수
  int _seenLayout = -1;

  World(this.game, {int? seed}) : _rng = Random(seed) {
    player = Walker(game.entrances.first.tile);
  }

  void tick(double dt) {
    time += dt;
    if (_seenLayout != game.layoutVersion) _layoutChanged();
    _movePlayer(dt);
    _playerWork(dt);
    _syncStaff();
    for (final s in [...staff]) {
      _staffWork(s, dt);
    }
    _events(dt);
    _spawnIn -= dt * (event == EventKind.rush ? rushFactor : 1);
    if (_spawnIn <= 0) {
      final cap = min(60, 3 + 2 * game.shelves.length);
      if (customers.length < cap) _spawn();
      _spawnIn = spawnInterval(game.shelves.length, game.rating, game.decorCount) * (0.7 + _rng.nextDouble() * 0.6);
    }
    for (final c in [...customers]) {
      _updateCustomer(c, dt);
    }
    customers.removeWhere((c) => c.state == CState.gone);
    _wageIn -= dt;
    if (_wageIn <= 0) {
      _wageIn = wagePeriod;
      game.money -= game.wages;
    }
    final done = game.checkGoal();
    if (done != null) fx.add(Fx(FxKind.goal, player.x, player.y, amount: done.reward));
  }

  void _events(double dt) {
    if (event != null) {
      eventLeft -= dt;
      if (eventLeft <= 0) event = null;
      return;
    }
    if (game.level < eventLevel) return;
    _eventIn -= dt;
    if (_eventIn > 0) return;
    _eventIn = eventGap.$1 + _rng.nextDouble() * (eventGap.$2 - eventGap.$1);
    startEvent(_rng.nextBool() ? EventKind.rush : EventKind.vip);
  }

  void startEvent(EventKind k) {
    event = k;
    eventLeft = k == EventKind.rush ? rushTime : 30;
    if (k == EventKind.vip) _vipQueue = vipVisitors;
    fx.add(Fx(FxKind.event, player.x, player.y, amount: k.index));
  }

  // ---------------------------------------------------------------- 짓기가 바뀌었을 때

  void _layoutChanged() {
    _seenLayout = game.layoutVersion;
    final regs = game.registers.toSet();
    queues.removeWhere((r, _) => !regs.contains(r));
    final items = game.items.toSet();
    for (final c in customers) {
      // 가던 진열대·계산대·의자가 없어졌거나 바뀌었으면 다시 고른다
      if (c.state == CState.toShelf || c.state == CState.atShelf) {
        if (c.shelf == null || !items.contains(c.shelf) || c.shelf!.product != c.want) _toShelf(c);
      } else if (c.state == CState.toQueue && !regs.contains(c.register)) {
        _toRegister(c);
      } else if ((c.state == CState.toSeat || c.state == CState.sitting) && !items.contains(c.seat)) {
        _leave(c);
      }
      if (c.path.isNotEmpty) _walkTo(c, c.goal);
    }
    for (final s in staff) {
      s
        ..state = StaffState.idle
        ..item = null
        ..target = null;
      s.carry.clear();
    }
    if (!_free(player.x, player.y)) _unstick(player);
    if (player.path.isNotEmpty) _walkTo(player, player.goal);
  }

  void _unstick(Walker w) {
    final a = _access(w.tile);
    w
      ..x = a.$1.toDouble()
      ..y = a.$2.toDouble();
  }

  // ---------------------------------------------------------------- 플레이어

  /// 누른 칸으로 걸어간다. 물건을 눌렀으면 그 일을 할 수 있는 자리로 간다:
  /// 상자·진열대·꾸미기는 앞 칸, 계산대는 계산 자리. 갈 곳(서는 칸)을 돌려주고, 못 가면 null.
  Tile? walkPlayerTo(Tile t) {
    Tile? stand;
    final item = game.at(t);
    final reg = game.registers.where((r) => r.tile == t || r.till == t).firstOrNull;
    if (reg != null) {
      stand = reg.till;
    } else if (item != null && !item.t.walkable) {
      stand = _access(t);
    } else if (game.walkable(t)) {
      stand = t;
    }
    if (stand == null || !game.walkable(stand)) return null;
    final path = _bfs(player.tile, stand);
    if (path == null) return null;
    player
      ..goal = stand
      ..path = path;
    return stand;
  }

  void _movePlayer(double dt) {
    final len = sqrt(input * input + inputY * inputY);
    if (len <= 0.05) {
      // 조이스틱을 안 쓰면 누른 곳으로 걸어가는 중일 수 있다
      _walk(player, dt, game.speed);
      return;
    }
    player
      ..moving = true
      ..path = [];
    final s = game.speed * dt * min(1.0, len);
    final ux = input / len, uy = inputY / len;
    player
      ..dx = ux
      ..dy = uy;
    // 축마다 따로 막아서 벽을 따라 미끄러지게 한다.
    final nx = player.x + ux * s;
    if (_free(nx, player.y)) player.x = nx;
    final ny = player.y + uy * s;
    if (_free(player.x, ny)) player.y = ny;
  }

  /// 몸 반지름만큼 네 귀퉁이가 전부 걸을 수 있는 칸이어야 한다.
  bool _free(double x, double y) {
    const r = 0.22;
    for (final (ox, oy) in const [(-r, -r), (r, -r), (-r, r), (r, r)]) {
      if (!game.walkable(((x + ox).round(), (y + oy).round()))) return false;
    }
    return true;
  }

  void _playerWork(double dt) {
    _playerStep += dt;
    if (_playerStep >= moveStep) {
      _playerStep = 0;
      // 상자에서 집는 건 멈춰 섰을 때만: 지나가다 옆 상자 물건까지 집지 않게 (놓기는 지나가며 해도 좋다)
      _carryWork(player, game.arms, pick: !player.moving);
    }
    _cashStep += dt;
    for (final r in game.registers) {
      if (player.distTo(r.till) < standRadius && time - (lastScan[r] ?? -9) >= scanStepPlayer) {
        _scan(r, staffed: false);
      }
      if (r.cash > 0 && player.distTo(r.tile) < 1.5 && _cashStep >= 0.05) {
        _cashStep = 0;
        final take = min(r.cash, max(1, (r.cash * 0.25).ceil()));
        r.cash -= take;
        game.money += take;
        fx.add(Fx(FxKind.cash, r.c.toDouble(), r.r.toDouble(), tx: player.x, ty: player.y, amount: take));
      }
    }
    final t = player.tile;
    if (game.trash.remove(t)) fx.add(Fx(FxKind.clean, t.$1.toDouble(), t.$2.toDouble()));
  }

  bool get atAnyTill => game.registers.any((r) => player.distTo(r.till) < standRadius);

  /// 상품 상자 옆이면 하나 집고(pick), 그 상품 진열대 옆이면 하나 놓는다. 하나라도 옮겼으면 true.
  bool _carryWork(Walker w, int arms, {required bool pick}) {
    for (final s in game.shelves) {
      if (w.carry.contains(s.product) && s.stock < s.capacity && w.distTo(s.tile) <= reach + 0.25) {
        w.carry.remove(s.product);
        s.stock++;
        fx.add(Fx(FxKind.place, w.x, w.y, tx: s.c.toDouble(), ty: s.r.toDouble(), product: s.product!));
        return true;
      }
    }
    if (!pick) return false;
    for (final b in game.ofKind(ItemKind.box)) {
      if (b.product != null && w.carry.length < arms && w.distTo(b.tile) <= reach + 0.25) {
        w.carry.add(b.product!);
        fx.add(Fx(FxKind.pick, b.c.toDouble(), b.r.toDouble(), tx: w.x, ty: w.y, product: b.product!));
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- 계산

  /// 계산대 맨 앞 손님 물건 하나 찍기. 계산원이 찍으면 돈이 바로 들어오고,
  /// 내가 찍었으면 계산대 옆에 쌓인다(주우러 가야 한다).
  void _scan(Item reg, {required bool staffed}) {
    final q = queues[reg];
    if (q == null || q.isEmpty) return;
    final c = q.first;
    final tiles = game.queueTiles(reg);
    if (tiles.isEmpty || !c.arrived || c.goal != tiles.first) return;
    c.scanned++;
    lastScan[reg] = time;
    fx.add(Fx(FxKind.scan, c.x, c.y));
    if (c.scanned < c.carry.length) return;
    final base = c.carry.fold(0, (s, p) => s + productById(p).price);
    final paid = switch (c.kind) {
      CustomerKind.vip => base * 2,
      CustomerKind.hurry => (base * 1.5).round(),
      CustomerKind.normal => base,
    };
    if (staffed) {
      game.money += paid;
    } else {
      reg.cash += paid;
    }
    game.served++;
    final ups = game.addXp(paid);
    q.remove(c);
    fx.add(Fx(FxKind.pay, reg.c.toDouble(), reg.r.toDouble(), amount: paid));
    for (var i = 0; i < ups; i++) {
      fx.add(Fx(FxKind.levelUp, player.x, player.y, amount: game.level));
    }
    c
      ..react = 0.7
      ..happy = true;
    if (!_toSeat(c)) _leave(c);
  }

  // ---------------------------------------------------------------- 직원

  void _syncStaff() {
    for (final k in Staff.values) {
      final want = game.count(k);
      final have = staff.where((s) => s.kind == k).toList();
      for (var i = have.length; i < want; i++) {
        staff.add(StaffAgent(k, game.entrances.first.tile));
      }
      for (var i = want; i < have.length; i++) {
        staff.remove(have[i]);
      }
    }
  }

  void _staffWork(StaffAgent s, double dt) {
    _walk(s, dt, staffSpeed);
    switch (s.kind) {
      case Staff.cashier:
        _cashierWork(s, dt);
      case Staff.stocker:
        _stockerWork(s, dt);
      case Staff.janitor:
        _janitorWork(s);
    }
  }

  /// 계산원은 아무도 안 맡은 계산대로 가서 선다. 계산대보다 많으면 쉰다.
  void _cashierWork(StaffAgent s, double dt) {
    if (s.item == null) {
      final taken = {for (final o in staff) if (o.kind == Staff.cashier) o.item};
      final free = game.registers.where((r) => !taken.contains(r));
      if (free.isEmpty) return;
      s
        ..item = free.first
        ..state = StaffState.toWork;
      _walkTo(s, s.item!.till);
    }
    if (s.state == StaffState.toWork && s.arrived) s.state = StaffState.working;
    if (s.state == StaffState.working) {
      final d = rotations[s.item!.rot];
      s
        ..dx = -d.$1.toDouble()
        ..dy = -d.$2.toDouble();
      s.step += dt;
      if (s.step >= scanStepCashier) {
        s.step = 0;
        _scan(s.item!, staffed: true);
      }
    }
  }

  bool staffedAt(Item reg) => staff.any((s) => s.item == reg && s.state == StaffState.working);

  void _stockerWork(StaffAgent s, double dt) {
    switch (s.state) {
      case StaffState.idle:
        // 상자가 있고, 다른 진열원이 안 맡았고, 반 넘게 빈 진열대 중 제일 빈 것부터.
        final taken = {for (final o in staff) if (o != s && o.kind == Staff.stocker) o.item};
        final boxes = {for (final b in game.ofKind(ItemKind.box)) if (b.product != null) b.product!: b};
        Item? low;
        for (final sh in game.shelves) {
          if (taken.contains(sh) || !boxes.containsKey(sh.product)) continue;
          final ratio = sh.stock / sh.capacity;
          if (ratio < 0.5 && (low == null || ratio < low.stock / low.capacity)) low = sh;
        }
        if (low == null) return;
        s
          ..item = low
          ..state = StaffState.toWork;
        _walkTo(s, _access(boxes[low.product]!.tile));
      case StaffState.toWork:
        if (s.arrived) s.state = StaffState.working;
      case StaffState.working: // 상자에서 싣기
        if (!_tick(s, dt)) return;
        if (s.carry.length >= staffArms) {
          s.state = StaffState.toShelf;
          _walkTo(s, _access(s.item!.tile));
        } else {
          s.carry.add(s.item!.product!);
          fx.add(Fx(FxKind.pick, s.x, s.y, tx: s.x, ty: s.y, product: s.item!.product!));
        }
      case StaffState.toShelf:
        if (s.arrived) s.state = StaffState.unloading;
      case StaffState.unloading:
        if (_tick(s, dt) && !_carryWork(s, 0, pick: false)) {
          s.carry.clear();
          s
            ..item = null
            ..state = StaffState.idle;
        }
    }
  }

  void _janitorWork(StaffAgent s) {
    if (s.target != null && !game.trash.contains(s.target)) {
      s
        ..target = null
        ..state = StaffState.idle;
    }
    if (s.target == null) {
      final taken = {for (final o in staff) if (o != s) o.target};
      Tile? best;
      for (final t in game.trash) {
        if (!taken.contains(t) && (best == null || s.distTo(t) < s.distTo(best))) best = t;
      }
      if (best == null) return;
      s
        ..target = best
        ..state = StaffState.toWork;
      _walkTo(s, best);
    }
    if (s.arrived && game.trash.remove(s.target)) {
      fx.add(Fx(FxKind.clean, s.x, s.y));
      s
        ..target = null
        ..state = StaffState.idle;
    }
  }

  bool _tick(StaffAgent s, double dt) {
    s.step += dt;
    if (s.step < moveStep) return false;
    s.step = 0;
    return true;
  }

  // ---------------------------------------------------------------- 손님

  void _spawn() {
    final doors = game.entrances.toList();
    final sale = game.onSale.toList()..shuffle(_rng);
    if (doors.isEmpty || sale.isEmpty) return;
    final door = doors[_rng.nextInt(doors.length)].tile;
    final vip = _vipQueue > 0 || (game.rating >= vipMinRating && _rng.nextDouble() < vipChance);
    final n = vip ? min(sale.length, 2 + _rng.nextInt(2)) : 1 + _rng.nextInt(min(3, sale.length));
    final c = Customer(_rng.nextInt(10), door, sale.take(n).toList());
    if (vip) {
      c.kind = CustomerKind.vip;
      if (_vipQueue > 0) _vipQueue--;
    } else if (_rng.nextDouble() < hurryChance) {
      c.kind = CustomerKind.hurry;
    }
    customers.add(c);
    _toShelf(c);
  }

  void _toShelf(Customer c) {
    // 같은 상품 진열대가 여럿이면 제일 많이 남은 곳으로 간다.
    final options = game.shelves.where((s) => s.product == c.want).toList();
    if (options.isEmpty) {
      c.missed++;
      _nextWant(c);
      return;
    }
    c
      ..shelf = options.reduce((a, b) => b.stock > a.stock ? b : a)
      ..state = CState.toShelf
      ..timer = 0;
    _walkTo(c, _access(c.shelf!.tile));
  }

  void _toRegister(Customer c) {
    final regs = game.registers.where((r) => game.queueTiles(r).isNotEmpty).toList();
    if (regs.isEmpty) {
      game.rate(1);
      _leave(c, rated: true);
      return;
    }
    // 줄이 제일 짧은 계산대, 같으면 가까운 곳.
    regs.sort((a, b) {
      final q = (queues[a]?.length ?? 0).compareTo(queues[b]?.length ?? 0);
      return q != 0 ? q : c.distTo(a.front).compareTo(c.distTo(b.front));
    });
    c
      ..register = regs.first
      ..state = CState.toQueue;
    queues.putIfAbsent(regs.first, () => []).add(c);
  }

  /// 앉아서 먹는 상품을 샀고 빈 의자가 있으면 거기로 간다.
  bool _toSeat(Customer c) {
    if (!c.carry.any((p) => productById(p).eatIn)) return false;
    final taken = {for (final o in customers) if (o != c) o.seat};
    final free = game.ofKind(ItemKind.seat).where((s) => !taken.contains(s)).toList();
    if (free.isEmpty) return false;
    free.sort((a, b) => c.distTo(a.tile).compareTo(c.distTo(b.tile)));
    c
      ..seat = free.first
      ..state = CState.toSeat;
    _walkTo(c, free.first.tile);
    return true;
  }

  void _updateCustomer(Customer c, double dt) {
    if (c.react > 0) {
      c.react -= dt;
      if (c.state == CState.toQueue) c.waited += dt;
      return;
    }
    _walk(c, dt, customerSpeed);
    switch (c.state) {
      case CState.toShelf:
        if (c.arrived) c.state = CState.atShelf;
      case CState.atShelf:
        c.timer += dt;
        final s = c.shelf!;
        if (c.timer >= pickTime && s.stock > 0) {
          s.stock--;
          c.carry.add(c.want);
          _nextWant(c);
        } else if (c.timer > shelfPatience * c.patience) {
          c
            ..missed += 1
            ..react = 0.8
            ..happy = false;
          fx.add(Fx(FxKind.sad, c.x, c.y));
          _nextWant(c);
        }
      case CState.toQueue:
        c.waited += dt;
        final tiles = game.queueTiles(c.register!);
        if (tiles.isEmpty) {
          queues[c.register]?.remove(c);
          _toRegister(c);
          break;
        }
        final i = queues[c.register]!.indexOf(c);
        final spot = tiles[min(i, tiles.length - 1)];
        if (c.goal != spot) _walkTo(c, spot);
        if (c.waited > queuePatience * c.patience && c.scanned == 0) {
          queues[c.register]?.remove(c);
          game.rate(0);
          fx.add(Fx(FxKind.angry, c.x, c.y));
          c
            ..react = 0.8
            ..happy = false;
          _leave(c, rated: true);
        }
      case CState.toSeat:
        if (c.arrived) {
          c
            ..state = CState.sitting
            ..timer = 0;
        }
      case CState.sitting:
        c.timer += dt;
        if (c.timer >= sitTime) {
          c.bonus = 1;
          _leave(c);
        }
      case CState.leaving:
        if (c.arrived) c.state = CState.gone;
      case CState.gone:
        break;
    }
  }

  void _nextWant(Customer c) {
    c.wantIndex++;
    if (c.wantIndex < c.wants.length) {
      _toShelf(c);
    } else if (c.carry.isEmpty) {
      game.rate(1);
      _leave(c, rated: true);
    } else {
      _toRegister(c);
    }
  }

  /// 나간다. 산 손님은 이때 만족도를 매기고, 휴지통이 멀면 가끔 쓰레기를 버린다.
  void _leave(Customer c, {bool rated = false}) {
    if (!rated && c.carry.isNotEmpty && c.state != CState.leaving) {
      final sat = 5 - 2 * c.missed - (c.waited > queuePatience / 2 ? 1 : 0) - (game.trash.length > 3 ? 1 : 0) + c.bonus;
      game.rate(sat.clamp(1, 5));
      _litter(c);
    }
    c.state = CState.leaving;
    final doors = game.entrances.toList()..sort((a, b) => c.distTo(a.tile).compareTo(c.distTo(b.tile)));
    _walkTo(c, doors.first.tile);
  }

  void _litter(Customer c) {
    final t = c.tile;
    final nearBin = game.ofKind(ItemKind.bin).any((b) => (b.c - t.$1).abs() + (b.r - t.$2).abs() <= binRange);
    if (nearBin || _rng.nextDouble() > litterChance) return;
    if (game.at(t) != null || !game.owns(t) || game.registers.any((r) => r.till == t)) return;
    game.trash.add(t);
    fx.add(Fx(FxKind.litter, t.$1.toDouble(), t.$2.toDouble()));
  }

  // ---------------------------------------------------------------- 길

  void _walk(Walker w, double dt, double speed) {
    var budget = speed * dt;
    w.moving = w.path.isNotEmpty;
    while (budget > 0 && w.path.isNotEmpty) {
      if (!game.walkable(w.path.first) && w.path.first != w.goal) {
        _walkTo(w, w.goal); // 그새 뭔가 놓여 막혔다
        if (w.path.isEmpty) return;
      }
      final (tx, ty) = w.path.first;
      final dx = tx - w.x, dy = ty - w.y;
      final d = sqrt(dx * dx + dy * dy);
      if (d > 0) {
        w
          ..dx = dx / d
          ..dy = dy / d;
      }
      if (d <= budget) {
        w
          ..x = tx.toDouble()
          ..y = ty.toDouble();
        w.path.removeAt(0);
        budget -= d;
      } else {
        w
          ..x = w.x + dx / d * budget
          ..y = w.y + dy / d * budget;
        budget = 0;
      }
    }
  }

  /// 막힌 칸 앞에 서는 칸. 앞(아래)쪽을 먼저 본다.
  Tile _access(Tile t) {
    final (x, y) = t;
    for (final n in [(x, y + 1), (x + 1, y), (x - 1, y), (x, y - 1)]) {
      if (game.walkable(n)) return n;
    }
    return t;
  }

  void _walkTo(Walker w, Tile goal) {
    w.goal = goal;
    w.path = _bfs(w.tile, goal) ?? [goal];
  }

  List<Tile>? _bfs(Tile from, Tile to) {
    if (from == to) return [];
    final prev = <Tile, Tile>{from: from};
    final q = Queue<Tile>()..add(from);
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      final (x, y) = cur;
      for (final n in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]) {
        if (prev.containsKey(n) || (!game.walkable(n) && n != to)) continue;
        prev[n] = cur;
        if (n == to) {
          final path = <Tile>[n];
          for (var p = cur; p != from; p = prev[p]!) {
            path.insert(0, p);
          }
          return path;
        }
        q.add(n);
      }
    }
    return null;
  }
}
