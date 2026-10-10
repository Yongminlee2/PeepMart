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
  double distTo(Tile t) => sqrt(pow(x - t.$1, 2) + pow(y - t.$2, 2));
}

enum CState { toShelf, atShelf, toQueue, leaving, gone }

class Customer extends Walker {
  final int look;
  final List<String> wants; // 사려는 상품, 차례대로
  int wantIndex = 0;
  int missed = 0;
  CState state = CState.toShelf;
  double timer = 0; // 진열대 앞에서 기다린 시간 / 줄에서 기다린 시간
  int scanned = 0;
  double react = 0; // 남은 반응 시간. 반응하는 동안은 멈춰 선다
  bool happy = false;
  Customer(this.look, super.at, this.wants);

  String get want => wants[wantIndex];
}

enum StockerState { idle, toCrate, loading, toShelf, unloading }

class Stocker extends Walker {
  StockerState state = StockerState.idle;
  String? product;
  Stocker(super.at);
}

enum FxKind { pick, place, scan, cash, pay, unlock, angry, sad }

/// 화면 연출용 사건. 엔진은 쌓기만 하고 화면이 가져가 비운다.
class Fx {
  final FxKind kind;
  final double x, y; // 시작점
  final double tx, ty; // 날아갈 곳 (item·cash)
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
  Stocker? stocker;
  final List<Customer> customers = [];
  final List<Customer> queue = [];
  final List<Fx> fx = [];
  double input = 0, inputY = 0; // 조이스틱, 세계 방향, 크기 0~1
  double time = 0;
  double lastScan = -9;
  double _spawnIn = 1, _playerStep = 0, _cashierStep = 0, _cashStep = 0, _payCarry = 0;

  World(this.game, {int? seed}) : _rng = Random(seed) {
    final d = layout.door;
    player = Walker((d.$1 - 2, d.$2));
  }

  Layout get layout => game.layout;

  void tick(double dt) {
    time += dt;
    _movePlayer(dt);
    _playerWork(dt);
    if (game.hasCashier) {
      _cashierStep += dt;
      if (_cashierStep >= scanStepCashier) {
        _cashierStep = 0;
        _scan();
      }
    }
    if (game.hasStocker) _stockerWork(dt);
    _spawnIn -= dt;
    if (_spawnIn <= 0) {
      if (customers.length < 3 + game.openProducts.length) _spawn();
      // 가게가 작을 땐 천천히, 상품이 늘수록 자주 온다. 별점도 손님을 부른다.
      _spawnIn = 9 / (1 + game.rating * 0.25) / (0.6 + 0.1 * game.openProducts.length) * (0.7 + _rng.nextDouble() * 0.6);
    }
    for (final c in [...customers]) {
      _updateCustomer(c, dt);
    }
    customers.removeWhere((c) => c.state == CState.gone);
  }

  // ---------------------------------------------------------------- 플레이어

  void _movePlayer(double dt) {
    final len = sqrt(input * input + inputY * inputY);
    player.moving = len > 0.05;
    if (!player.moving) return;
    final s = playerSpeed * dt * min(1.0, len);
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
      if (!_walkable(((x + ox).round(), (y + oy).round()))) return false;
    }
    return true;
  }

  void _playerWork(double dt) {
    _playerStep += dt;
    if (_playerStep >= moveStep) {
      _playerStep = 0;
      _carryWork(player, game.arms);
    }
    if (atTill && time - lastScan >= scanStepPlayer) _scan();
    if (game.cash > 0 && player.distTo(layout.cash) < 0.8) {
      _cashStep += dt;
      if (_cashStep >= 0.05) {
        _cashStep = 0;
        final take = min(game.cash, max(1, (game.cash * 0.25).ceil()));
        game.cash -= take;
        game.money += take;
        fx.add(Fx(FxKind.cash, layout.cash.$1.toDouble(), layout.cash.$2.toDouble(),
            tx: player.x, ty: player.y, amount: take));
      }
    }
    for (final (i, tile) in game.pads) {
      if (player.distTo(tile) > standRadius || game.money <= 0) continue;
      _payCarry += payPerSecond * dt;
      final n = _payCarry.floor();
      if (n == 0) break;
      _payCarry -= n;
      final before = game.level;
      if (game.pay(i, n)) {
        fx.add(Fx(FxKind.unlock, tile.$1.toDouble(), tile.$2.toDouble()));
        if (game.level != before) _resetForNewLayout();
        // 방금 생긴 진열대 위에 서 있었다면 앞으로 내보낸다.
        if (!_free(player.x, player.y)) {
          final a = _access((player.x.round(), player.y.round()));
          player
            ..x = a.$1.toDouble()
            ..y = a.$2.toDouble();
        }
      }
      break;
    }
  }

  /// 상자 옆이면 하나 집고, 그 상품 진열대 옆이면 하나 놓는다. 한 번에 하나.
  /// 하나라도 옮겼으면 true.
  bool _carryWork(Walker w, int arms) {
    for (final p in game.openProducts) {
      final shelf = game.shelfTile(p);
      if (w.carry.contains(p) && game.stock[p]! < game.capacity(p) && w.distTo(shelf) <= reach + 0.25) {
        w.carry.remove(p);
        game.stock[p] = game.stock[p]! + 1;
        fx.add(Fx(FxKind.place, w.x, w.y, tx: shelf.$1.toDouble(), ty: shelf.$2.toDouble(), product: p));
        return true;
      }
    }
    for (final p in game.openProducts) {
      final crate = game.crateTile(p);
      if (w.carry.length < arms && w.distTo(crate) <= reach + 0.25) {
        w.carry.add(p);
        fx.add(Fx(FxKind.pick, crate.$1.toDouble(), crate.$2.toDouble(), tx: w.x, ty: w.y, product: p));
        return true;
      }
    }
    return false;
  }

  bool get atTill => player.distTo(layout.till) < standRadius;

  /// 처음 하는 사람에게 다음에 갈 곳. 아무것도 할 게 없으면 null.
  /// 빈 진열대 채우기 → 계산 → 돈 줍기 → 살 수 있는 구매 칸 순서.
  Tile? guide() {
    final low = [
      for (final p in game.openProducts)
        if (game.stock[p]! < game.capacity(p) ~/ 2) p
    ];
    for (final p in low) {
      if (player.carry.contains(p)) return game.shelfTile(p);
    }
    final front = queue.isNotEmpty && queue.first.arrived ? queue.first : null;
    if (front != null && !game.hasCashier && !atTill) return layout.till;
    if (low.isNotEmpty && player.carry.isEmpty) return game.crateTile(low.first);
    if (game.cash > 0) return layout.cash;
    for (final (i, t) in game.pads) {
      if (game.money >= unlocks[i].price - (game.paid[i] ?? 0)) return t;
    }
    return null;
  }

  void _resetForNewLayout() {
    // 계산대·줄 위치가 바뀌니 손님은 새로 받는다.
    customers.clear();
    queue.clear();
    stocker = null;
  }

  // ---------------------------------------------------------------- 계산

  /// 맨 앞 손님 물건 하나 찍기. 다 찍으면 돈이 계산대 옆에 쌓인다.
  bool _scan() {
    if (queue.isEmpty) return false;
    final c = queue.first;
    if (!c.arrived || c.goal != layout.queue.first) return false;
    c.scanned++;
    lastScan = time;
    fx.add(Fx(FxKind.scan, c.x, c.y));
    if (c.scanned < c.carry.length) return true;
    final paid = c.carry.fold(0, (s, p) => s + productById(p).price);
    game.cash += paid;
    game.rate(5 - 2 * c.missed - (c.timer > queuePatience / 2 ? 1 : 0));
    queue.remove(c);
    fx.add(Fx(FxKind.pay, layout.register.$1.toDouble(), layout.register.$2.toDouble(), amount: paid));
    _leave(c);
    c
      ..react = 0.7
      ..happy = true;
    return true;
  }

  // ---------------------------------------------------------------- 진열 알바

  void _stockerWork(double dt) {
    final s = stocker ??= Stocker(layout.door);
    _walk(s, dt, stockerSpeed);
    switch (s.state) {
      case StockerState.idle:
        String? low;
        for (final p in game.openProducts) {
          final ratio = game.stock[p]! / game.capacity(p);
          if (ratio < 0.5 && (low == null || ratio < game.stock[low]! / game.capacity(low))) low = p;
        }
        if (low == null) return;
        s
          ..product = low
          ..state = StockerState.toCrate;
        _walkTo(s, _access(game.crateTile(low)));
      case StockerState.toCrate:
        if (s.arrived) s.state = StockerState.loading;
      case StockerState.loading:
        if (_tickStocker(dt)) {
          if (s.carry.length >= startArms) {
            s.state = StockerState.toShelf;
            _walkTo(s, _access(game.shelfTile(s.product!)));
          } else {
            s.carry.add(s.product!);
            final c = game.crateTile(s.product!);
            fx.add(Fx(FxKind.pick, c.$1.toDouble(), c.$2.toDouble(), tx: s.x, ty: s.y, product: s.product!));
          }
        }
      case StockerState.toShelf:
        if (s.arrived) s.state = StockerState.unloading;
      case StockerState.unloading:
        if (_tickStocker(dt) && !_carryWork(s, 0)) {
          s.carry.clear();
          s.state = StockerState.idle;
        }
    }
  }

  double _stockerStep = 0;
  bool _tickStocker(double dt) {
    _stockerStep += dt;
    if (_stockerStep < moveStep) return false;
    _stockerStep = 0;
    return true;
  }

  // ---------------------------------------------------------------- 손님

  void _spawn() {
    final open = [...game.openProducts]..shuffle(_rng);
    final c = Customer(_rng.nextInt(10), layout.door, open.take(1 + _rng.nextInt(min(2, open.length))).toList());
    customers.add(c);
    _toShelf(c);
  }

  void _toShelf(Customer c) {
    c
      ..state = CState.toShelf
      ..timer = 0;
    _walkTo(c, _access(game.shelfTile(c.want)));
  }

  void _updateCustomer(Customer c, double dt) {
    if (c.react > 0) {
      c.react -= dt;
      return;
    }
    _walk(c, dt, customerSpeed);
    switch (c.state) {
      case CState.toShelf:
        if (c.arrived) c.state = CState.atShelf;
      case CState.atShelf:
        c.timer += dt;
        final p = c.want;
        if (c.timer >= pickTime && game.stock[p]! > 0) {
          game.stock[p] = game.stock[p]! - 1;
          c.carry.add(p);
          _nextWant(c);
        } else if (c.timer > shelfPatience) {
          c
            ..missed += 1
            ..react = 0.8
            ..happy = false;
          fx.add(Fx(FxKind.sad, c.x, c.y));
          _nextWant(c);
        }
      case CState.toQueue:
        c.timer += dt;
        final i = queue.indexOf(c);
        final spot = layout.queue[min(i, layout.queue.length - 1)];
        if (c.goal != spot) _walkTo(c, spot);
        if (c.timer > queuePatience && c.scanned == 0) {
          queue.remove(c);
          game.rate(0);
          fx.add(Fx(FxKind.angry, c.x, c.y));
          _leave(c);
          c
            ..react = 0.8
            ..happy = false;
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
      _leave(c);
    } else {
      c
        ..state = CState.toQueue
        ..timer = 0;
      queue.add(c);
    }
  }

  void _leave(Customer c) {
    c.state = CState.leaving;
    _walkTo(c, layout.door);
  }

  // ---------------------------------------------------------------- 길

  void _walk(Walker w, double dt, double speed) {
    var budget = speed * dt;
    w.moving = w.path.isNotEmpty;
    while (budget > 0 && w.path.isNotEmpty) {
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

  Set<Tile> get _blocked => {
        layout.register,
        ...layout.decor.keys,
        for (final p in game.openProducts) ...[game.shelfTile(p), game.crateTile(p)],
      };

  bool _walkable(Tile t) {
    final (x, y) = t;
    if (x < 0 || y < 0 || x >= layout.w || y >= layout.h) return false;
    return !_blocked.contains(t);
  }

  /// 막힌 칸 앞에 서는 칸. 앞(아래)쪽을 먼저 본다.
  Tile _access(Tile t) {
    final (x, y) = t;
    for (final n in [(x, y + 1), (x + 1, y), (x - 1, y), (x, y - 1)]) {
      if (_walkable(n)) return n;
    }
    return t;
  }

  void _walkTo(Walker w, Tile goal) {
    w.goal = goal;
    w.path = _bfs((w.x.round(), w.y.round()), goal) ?? [goal];
  }

  List<Tile>? _bfs(Tile from, Tile to) {
    if (from == to) return [];
    final prev = <Tile, Tile>{from: from};
    final q = Queue<Tile>()..add(from);
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      final (x, y) = cur;
      for (final n in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]) {
        if (prev.containsKey(n) || (!_walkable(n) && n != to)) continue;
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
