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

/// 가게 문: 닫힘(짓는 시간) → 엶 → 마감(남은 손님만) → 닫힘.
enum DayPhase { closed, open, closing }

/// 막 끝난 하루. 화면이 결과 창으로 보여 준다.
class DayResult {
  final int day, sales, target, served, upset, stars, bonus, taskReward;
  final bool best;
  final List<(DayTask, bool)> tasks;
  const DayResult(this.day, this.sales, this.target, this.served, this.upset, this.stars, this.bonus,
      this.taskReward, this.best, this.tasks);
}

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
  final List<int> prices = []; // 집은 물건마다 낼 값 (집을 때 정해진다)
  String? regular; // 단골이면 그 이름
  bool fleeing = false; // 도둑: 물건을 들고 도망치는 중
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

enum FxKind { pick, place, scan, cash, pay, angry, sad, levelUp, litter, clean, goal, event, regular, day, incident, stamp }

/// FxKind.day 의 amount.
const dayLastCall = 0, dayClosing = 1, dayClosed = 2;

/// FxKind.incident 의 amount (돈이 걸린 건 product 에 금액 문자열).
/// 도장을 받았을 때 FxKind.stamp (product = 상품, amount = 상금).
enum Incident { thiefFlee, thiefCaught, thiefEscaped, kidLost, kidFound, kidGone, orderIn, orderDone, orderLate }

/// 배달 주문: 진열대를 돌며 상품을 챙기고(진열대에서 빠진다) 입구까지 들고 가면 끝.
class Order {
  final List<String> items;
  final List<String> toPick; // 아직 못 챙긴 것
  double left = orderTime;
  bool started = false;
  Order(this.items) : toPick = [...items];
  bool get carrying => started && toPick.isEmpty;
  int get pay => items.fold(0, (s, p) => s + productById(p).price) * orderPay;
}

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
  final List<Tile> plan = []; // 플레이어가 이어서 갈 곳 (빈 진열대를 누르면 상자 → 진열대)
  double _still = 0; // 플레이어가 멈춰 선 지 몇 초
  final Map<String, double> _regularSeen = {}; // 단골이 마지막으로 다녀간 시각
  final Map<ShelfKind, double> _managerStep = {};
  int _seenLayout = -1;

  DayPhase phase = DayPhase.closed;
  double dayTime = 0;
  int daySales = 0, dayServed = 0, dayUpset = 0, dayTarget = 0;
  final Map<String, int> daySold = {};
  List<DayTask> tasks = [];
  Weather weather = Weather.sunny; // 오늘(연 날) 날씨
  SpecialDay? special; // 오늘이 특별한 날이면
  Order? order; // 들어온 배달 주문
  Customer? chase; // 쫓고 있는 도둑
  double _chaseStep = 0;
  final List<(double, Incident)> _incidents = []; // 오늘 일어날 일 (시각, 종류)
  DayResult? result; // 방금 끝난 하루. 화면이 보여 주고 null 로 지운다

  World(this.game, {int? seed}) : _rng = Random(seed) {
    player = Walker(game.entrances.first.tile);
    // 처음 안내 중에는 바로 열고, 시계는 안내가 끝나야 간다
    if (game.owner.tutorial != TutorialStep.done) openDay();
  }

  bool get _clockRuns => game.owner.tutorial == TutorialStep.done;
  double get dayLeft => max(0, dayLength - dayTime);

  /// 문을 연다. 오늘 목표와 할 일 두 개를 정한다.
  void openDay() {
    if (phase != DayPhase.closed) return;
    phase = DayPhase.open;
    dayTime = 0;
    daySales = dayServed = dayUpset = 0;
    daySold.clear();
    result = null;
    weather = game.todayWeather;
    special = game.todaySpecial;
    dayTarget = game.dayTarget;
    if (special == SpecialDay.festival) dayTarget = (dayTarget * festivalVisitors / 10).round() * 10;
    tasks = _makeTasks();
    _spawnIn = 1;
    _planIncidents();
  }

  void _planIncidents() {
    _incidents.clear();
    order = null;
    double at() => incidentWindow.$1 + _rng.nextDouble() * (incidentWindow.$2 - incidentWindow.$1);
    if (game.rank >= rankIncidents) {
      for (var i = 0, n = 1 + _rng.nextInt(2); i < n; i++) {
        _incidents.add((at(), _rng.nextBool() ? Incident.thiefFlee : Incident.kidLost));
      }
    }
    if (game.rank >= rankDelivery) {
      for (var i = 0, n = 1 + _rng.nextInt(2); i < n; i++) {
        _incidents.add((at(), Incident.orderIn));
      }
    }
  }

  void _fx(Incident k, {int money = 0}) =>
      fx.add(Fx(FxKind.incident, player.x, player.y, amount: k.index, product: money > 0 ? '$money' : ''));

  /// 지금 일어날 일을 일으키고, 도둑·아이·배달을 돌본다.
  void _incidentsTick(double dt) {
    if (phase == DayPhase.open && _clockRuns) {
      for (final e in _incidents.where((e) => e.$1 <= dayTime).toList()) {
        _incidents.remove(e);
        switch (e.$2) {
          case Incident.thiefFlee:
            _spawnSpecial(CustomerKind.thief);
          case Incident.kidLost:
            _spawnSpecial(CustomerKind.lost);
          default:
            final sale = game.onSale.toList()..sort();
            if (order == null && sale.isNotEmpty) {
              sale.shuffle(_rng);
              order = Order(sale.take(min(sale.length, 2 + _rng.nextInt(2))).toList());
              _fx(Incident.orderIn);
            }
        }
      }
    }
    // 도둑: 가까이 가면 잡는다. 누른 도둑은 계속 쫓아간다.
    for (final c in customers) {
      if (!c.fleeing) continue;
      if (sqrt(pow(player.x - c.x, 2) + pow(player.y - c.y, 2)) < catchRange) {
        final fine = c.prices.fold(0, (s, p) => s + p) * thiefFine;
        game.money += fine;
        daySales += fine;
        c
          ..fleeing = false
          ..react = 0.8
          ..happy = false;
        c.carry.clear();
        _fx(Incident.thiefCaught, money: fine);
      }
    }
    final ch = chase;
    if (ch != null) {
      if (!ch.fleeing || ch.state == CState.gone) {
        chase = null;
      } else if ((_chaseStep -= dt) <= 0) {
        _chaseStep = 0.3;
        walkPlayerTo(ch.tile);
      }
    }
    final o = order;
    if (o != null) {
      o.left -= dt;
      _pickForOrder(o);
      if (o.carrying && game.entrances.any((e) => player.distTo(e.tile) < 0.6)) {
        game.money += o.pay;
        daySales += o.pay;
        order = null;
        _fx(Incident.orderDone, money: o.pay);
      } else if (o.left <= 0) {
        order = null;
        dayUpset++;
        _fx(Incident.orderLate);
      }
    }
  }

  /// 도둑이나 길 잃은 아이가 들어온다.
  void _spawnSpecial(CustomerKind kind) {
    final doors = game.entrances.toList();
    final sale = game.onSale.toList()..shuffle(_rng);
    if (doors.isEmpty || sale.isEmpty) return;
    final door = doors[_rng.nextInt(doors.length)].tile;
    final c = Customer(_rng.nextInt(1024), door, kind == CustomerKind.thief ? sale.take(1 + _rng.nextInt(2)).toList() : [])
      ..kind = kind;
    customers.add(c);
    if (kind == CustomerKind.thief) {
      _toShelf(c);
      return;
    }
    // 아이: 가게 안 빈 칸 아무 데나 가서 운다
    final spots = [
      for (var y = 0; y < mapH; y++)
        for (var x = 0; x < mapW; x++)
          if (game.walkable((x, y)) && game.at((x, y)) == null && !game.trash.contains((x, y))) (x, y)
    ];
    if (spots.isEmpty) {
      customers.remove(c);
      return;
    }
    c.state = CState.toShelf;
    _walkTo(c, spots[_rng.nextInt(spots.length)]);
    _fx(Incident.kidLost);
  }

  void _updateLost(Customer c, double dt) {
    if (c.react > 0) {
      c.react -= dt;
      return;
    }
    _walk(c, dt, customerSpeed * 0.8);
    switch (c.state) {
      case CState.toShelf:
        if (c.arrived) {
          c
            ..state = CState.atShelf
            ..timer = 0;
        }
      case CState.atShelf:
        c.timer += dt;
        if (sqrt(pow(player.x - c.x, 2) + pow(player.y - c.y, 2)) < catchRange) {
          final reward = max(20, (dayTarget * lostReward).round());
          game.money += reward;
          game.rate(5);
          c
            ..happy = true
            ..react = 1.0
            ..state = CState.leaving;
          _walkTo(c, game.entrances.first.tile);
          _fx(Incident.kidFound, money: reward);
        } else if (c.timer > lostPatience) {
          dayUpset++;
          c
            ..happy = false
            ..react = 0.8
            ..state = CState.leaving;
          _walkTo(c, game.entrances.first.tile);
          _fx(Incident.kidGone);
        }
      case CState.leaving:
        if (c.arrived) c.state = CState.gone;
      default:
        break;
    }
  }

  /// 남은 배달 물건이 진열대에 다 있는가.
  bool get canDeliver {
    final o = order;
    if (o == null || o.carrying) return false;
    final need = <String, int>{};
    for (final p in o.toPick) {
      need[p] = (need[p] ?? 0) + 1;
    }
    return need.entries.every((e) => game.shelves.where((s) => s.product == e.key).fold(0, (n, s) => n + s.stock) >= e.value);
  }

  /// 배달 출발: 남은 상품 진열대를 차례로 들렀다가 입구로 간다(진열대 앞에 서면 챙긴다).
  bool startDelivery() {
    if (!canDeliver) return false;
    final o = order!..started = true;
    plan.clear();
    chase = null;
    final stops = <Tile>[];
    for (final p in o.toPick.toSet()) {
      final s = game.shelves.where((s) => s.product == p && s.stock > 0).reduce((a, b) => b.stock > a.stock ? b : a);
      stops.add(s.tile);
    }
    final door = game.entrances.toList()..sort((a, b) => player.distTo(a.tile).compareTo(player.distTo(b.tile)));
    stops.add(door.first.tile);
    walkPlayerTo(stops.first);
    plan.addAll(stops.skip(1));
    return true;
  }

  /// 배달 중: 멈춰 선 자리 옆 진열대에서 남은 상품을 챙긴다.
  void _pickForOrder(Order o) {
    if (!o.started || o.carrying || player.moving) return;
    for (final s in game.shelves) {
      final p = s.product!;
      if (s.stock <= 0 || !o.toPick.contains(p) || player.distTo(s.tile) > 1.6) continue;
      while (s.stock > 0 && o.toPick.remove(p)) {
        s.stock--;
        fx.add(Fx(FxKind.pick, s.c.toDouble(), s.r.toDouble(), tx: player.x, ty: player.y, product: p));
      }
    }
  }

  List<DayTask> _makeTasks() {
    final sale = game.onSale.toList()..sort();
    if (sale.isEmpty) return [];
    // 오늘 올 손님 어림: 해 본 날이 있으면 최근 평균(조금 더), 없으면 가게 크기로 어림한 것의 60%
    final visitors = game.hasHistory ? game.avgServed * 1.05 : game.fullDay.$1 * 0.6;
    final p = sale[_rng.nextInt(sale.length)];
    final sell = DayTask(DayTaskKind.sell, max(3, (visitors * 1.5 / sale.length).round()), product: p);
    final other = _rng.nextBool()
        ? DayTask(DayTaskKind.serve, max(5, visitors.round()))
        : const DayTask(DayTaskKind.calm, calmLimit);
    return [sell, other];
  }

  /// 할 일이 어디까지 왔나 (calm 은 실망한 손님 수).
  int taskProgress(DayTask t) => switch (t.kind) {
        DayTaskKind.sell => daySold[t.product] ?? 0,
        DayTaskKind.serve => dayServed,
        DayTaskKind.calm => dayUpset,
      };

  bool taskDone(DayTask t) => t.kind == DayTaskKind.calm ? dayUpset <= t.n : taskProgress(t) >= t.n;

  void _closeDay() {
    final stars = dayStars.where((r) => daySales >= dayTarget * r).length;
    final bonus = (daySales * dayBonus[stars] * (special == SpecialDay.festival ? festivalBonus : 1)).round();
    final done = [for (final t in tasks) (t, taskDone(t))];
    final taskReward = done.where((d) => d.$2).length * (dayTarget * dayTaskReward).round();
    final best = daySales > game.bestSales;
    if (best) game.bestSales = daySales;
    game.recordDay(daySales, dayServed);
    game.money += bonus + taskReward;
    result = DayResult(game.day, daySales, dayTarget, dayServed, dayUpset, stars, bonus, taskReward, best, done);
    game.day++;
    game.weather = _pickWeather();
    order = null;
    phase = DayPhase.closed;
    fx.add(Fx(FxKind.day, player.x, player.y, amount: dayClosed));
  }

  Weather _pickWeather() {
    final odds = weatherOdds(game.branch);
    var r = _rng.nextInt(odds.reduce((a, b) => a + b));
    for (var i = 0; i < odds.length; i++) {
      r -= odds[i];
      if (r < 0) return Weather.values[i];
    }
    return Weather.sunny;
  }

  /// 날씨·특별한 날에 따라 손님이 오는 빠르기.
  double get _visitorFactor =>
      (weather == Weather.rain ? rainVisitors : 1.0) * (special == SpecialDay.festival ? festivalVisitors : 1.0);

  void _rate(int satisfaction) {
    game.rate(satisfaction);
    if (satisfaction <= 2 && phase != DayPhase.closed) dayUpset++;
  }

  void tick(double dt) {
    time += dt;
    if (_seenLayout != game.layoutVersion) _layoutChanged();
    _movePlayer(dt);
    _playerWork(dt);
    _followPlan(dt);
    _managersWork(dt);
    _syncStaff();
    for (final s in [...staff]) {
      _staffWork(s, dt);
    }
    _day(dt);
    _incidentsTick(dt);
    if (phase == DayPhase.open) _events(dt);
    final last = _clockRuns && dayLeft < lastCall ? lastCallFactor : 1.0;
    _spawnIn -= dt * (event == EventKind.rush ? rushFactor : 1) * last * _visitorFactor;
    if (_spawnIn <= 0 && phase == DayPhase.open) {
      final cap = min(60, 3 + 2 * game.shelves.length);
      if (customers.length < cap) _spawn();
      // 소풍날: 단체 손님이 줄줄이 들어온다
      if (special == SpecialDay.picnic && _rng.nextDouble() < 0.3) {
        final extra = picnicGroup.$1 - 1 + _rng.nextInt(picnicGroup.$2 - picnicGroup.$1 + 1);
        for (var i = 0; i < extra && customers.length < cap; i++) {
          _spawn();
        }
      }
      _spawnIn = game.spawnGap * (0.7 + _rng.nextDouble() * 0.6);
    }
    for (final c in [...customers]) {
      _updateCustomer(c, dt);
    }
    customers.removeWhere((c) => c.state == CState.gone);
    if (phase != DayPhase.closed) _wageIn -= dt;
    if (_wageIn <= 0) {
      _wageIn = wagePeriod;
      game.money -= game.wages;
    }
    final done = game.checkGoal();
    if (done != null) fx.add(Fx(FxKind.goal, player.x, player.y, amount: done.reward));
  }

  void _day(double dt) {
    if (phase == DayPhase.open && _clockRuns) {
      final before = dayLeft;
      dayTime += dt;
      if (before >= lastCall && dayLeft < lastCall) fx.add(Fx(FxKind.day, player.x, player.y, amount: dayLastCall));
      if (dayTime >= dayLength) {
        phase = DayPhase.closing;
        fx.add(Fx(FxKind.day, player.x, player.y, amount: dayClosing));
      }
    }
    if (phase == DayPhase.closing && customers.isEmpty) _closeDay();
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
      if (c.kind == CustomerKind.lost) {
        // 아이는 진열대와 상관없다
      } else if (c.state == CState.toShelf || c.state == CState.atShelf) {
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

  /// 화면에서 누른 칸. 진열대를 눌렀는데 그 상품을 안 들고 있으면 상자에 먼저 들렀다 간다.
  Tile? tapAt(Tile t) {
    plan.clear();
    chase = null;
    final thief = customers
        .where((c) => c.fleeing && sqrt(pow(c.x - t.$1, 2) + pow(c.y - t.$2, 2)) < 1.6)
        .firstOrNull;
    if (thief != null) {
      chase = thief;
      _chaseStep = 0.3;
      return walkPlayerTo(thief.tile);
    }
    final item = game.at(t);
    final p = item?.product;
    if (item != null && item.t.kind == ItemKind.shelf && p != null && !player.carry.contains(p)) {
      final box = game.boxOf(p);
      if (box != null && walkPlayerTo(box.tile) != null) {
        plan.add(t);
        return _access(box.tile);
      }
    }
    return walkPlayerTo(t);
  }

  void _followPlan(double dt) {
    if (player.moving) {
      _still = 0;
      return;
    }
    _still += dt;
    // 상자 앞에서 다 들었거나(팔이 꽉 참) 잠시 기다렸으면 다음 곳으로
    if (plan.isNotEmpty && (player.carry.length >= game.arms || _still > 0.9)) {
      walkPlayerTo(plan.removeAt(0));
      _still = 0;
    }
  }

  /// 매니저가 있는 코너는 상자 없이 저절로 채워진다.
  void _managersWork(double dt) {
    for (final k in game.managers) {
      final t = (_managerStep[k] ?? 0) + dt;
      if (t < managerRestock) {
        _managerStep[k] = t;
        continue;
      }
      _managerStep[k] = 0;
      Item? low;
      for (final s in game.shelves) {
        if (s.t.shelf == k && s.stock < s.capacity && (low == null || s.stock < low.stock)) low = s;
      }
      if (low != null) {
        low.stock++;
        fx.add(Fx(FxKind.place, low.c + 0.0, low.r - 1.0, tx: low.c + 0.0, ty: low.r + 0.0, product: low.product!));
      }
    }
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
      if (player.carry.isNotEmpty) game.owner.advance(TutorialStep.pickBox);
    }
    _cashStep += dt;
    for (final r in game.registers) {
      if (player.distTo(r.till) < standRadius && time - (lastScan[r] ?? -9) >= game.scanTime(r, cashier: false)) {
        _scan(r, staffed: false);
      }
      if (r.cash > 0 && player.distTo(r.tile) < 1.5 && _cashStep >= 0.05) {
        _cashStep = 0;
        final take = min(r.cash, max(1, (r.cash * 0.25).ceil()));
        r.cash -= take;
        game.money += take;
        game.owner.advance(TutorialStep.collect);
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
        if (w == player) game.owner.advance(TutorialStep.fillShelf);
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
    final base = c.prices.fold(0, (s, p) => s + p);
    final paid = switch (c.kind) {
      CustomerKind.vip => base * 2,
      CustomerKind.hurry => (base * 1.5).round(),
      CustomerKind.normal || CustomerKind.thief || CustomerKind.lost => base,
    };
    if (staffed) {
      game.money += paid;
    } else {
      reg.cash += paid;
      game.owner.advance(TutorialStep.checkout);
    }
    final reg0 = c.regular;
    if (reg0 != null && c.carry.contains(c.wants.first)) {
      final h = game.giveHeart(reg0);
      fx.add(Fx(FxKind.regular, c.x, c.y, product: reg0, amount: h ?? 0));
    }
    game.served++;
    daySales += paid;
    dayServed++;
    for (final p in c.carry) {
      daySold[p] = (daySold[p] ?? 0) + 1;
      final stamp = game.owner.addSold(p);
      if (stamp > 0) fx.add(Fx(FxKind.stamp, c.x, c.y, product: p, amount: stamp));
    }
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
      if (s.step >= game.scanTime(s.item!, cashier: true)) {
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
    // 단골: 이 지점에 올 수 있고, 지금 가게에 없고, 한동안 안 왔던 사람
    if (_rng.nextDouble() < regularChance) {
      final here = {for (final o in customers) o.regular};
      final cands = game.regularsHere
          .where((r) => !here.contains(r.id) && time - (_regularSeen[r.id] ?? -999) > regularCooldown)
          .toList();
      if (cands.isNotEmpty) {
        final r = cands[_rng.nextInt(cands.length)];
        final want = sale.contains(r.favorite) ? r.favorite : sale.first;
        final c = Customer(r.look, door, [want])..regular = r.id;
        _regularSeen[r.id] = time;
        customers.add(c);
        fx.add(Fx(FxKind.regular, door.$1 + 0.0, door.$2 + 0.0, product: r.id, amount: -1));
        _toShelf(c);
        return;
      }
    }
    final vip = _vipQueue > 0 ||
        (game.rating >= vipMinRating && _rng.nextDouble() < vipChance * (game.rank >= rankVip ? 2 : 1));
    final n = vip ? min(sale.length, 2 + _rng.nextInt(2)) : 1 + _rng.nextInt(min(3, sale.length));
    final wants = sale.take(n).toList();
    final fav = game.favored.toList()..sort();
    if (fav.isNotEmpty && _rng.nextDouble() < favoredPull) {
      final f = fav[_rng.nextInt(fav.length)];
      wants
        ..remove(f)
        ..insert(0, f);
      if (wants.length > n) wants.removeLast();
    }
    final c = Customer(_rng.nextInt(1024), door, wants);
    if (vip) {
      c.kind = CustomerKind.vip;
      if (_vipQueue > 0) _vipQueue--;
    } else if (_rng.nextDouble() < hurryChance * (special == SpecialDay.exam ? examHurry : 1)) {
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
      _rate(1);
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
    if (c.kind == CustomerKind.lost) {
      _updateLost(c, dt);
      return;
    }
    if (c.react > 0) {
      c.react -= dt;
      if (c.state == CState.toQueue) c.waited += dt;
      return;
    }
    _walk(c, dt, customerSpeed * (c.fleeing ? thiefSpeed : 1));
    switch (c.state) {
      case CState.toShelf:
        if (c.arrived) c.state = CState.atShelf;
      case CState.atShelf:
        c.timer += dt;
        final s = c.shelf!;
        if (c.timer >= pickTime && s.stock > 0) {
          s.stock--;
          c.carry.add(c.want);
          c.prices.add(game.salePrice(s, c.want));
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
          _rate(0);
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
        if (c.arrived) {
          c.state = CState.gone;
          if (c.fleeing) {
            c.fleeing = false;
            _fx(Incident.thiefEscaped);
          }
        }
      case CState.gone:
        break;
    }
  }

  void _nextWant(Customer c) {
    c.wantIndex++;
    if (c.wantIndex < c.wants.length) {
      _toShelf(c);
    } else if (c.kind == CustomerKind.thief) {
      // 도둑: 계산대에 안 가고 문으로 달아난다
      c.state = CState.leaving;
      final doors = game.entrances.toList()..sort((a, b) => c.distTo(a.tile).compareTo(c.distTo(b.tile)));
      _walkTo(c, doors.first.tile);
      if (c.carry.isNotEmpty) {
        c.fleeing = true;
        _fx(Incident.thiefFlee);
      }
    } else if (c.carry.isEmpty) {
      _rate(1);
      _leave(c, rated: true);
    } else {
      _toRegister(c);
    }
  }

  /// 나간다. 산 손님은 이때 만족도를 매기고, 휴지통이 멀면 가끔 쓰레기를 버린다.
  void _leave(Customer c, {bool rated = false}) {
    if (!rated && c.carry.isNotEmpty && c.state != CState.leaving) {
      final sat = 5 - 2 * c.missed - (c.waited > queuePatience / 2 ? 1 : 0) - (game.trash.length > 3 ? 1 : 0) + c.bonus;
      _rate(sat.clamp(1, 5));
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
