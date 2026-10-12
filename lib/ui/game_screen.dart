import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../engine/world.dart';
import '../save.dart';
import '../settings.dart';
import '../strings.dart';
import 'build_panel.dart';
import 'hub_screens.dart';
import 'sprites.dart';
import 'title_screen.dart';
import 'settings_sheet.dart';
import 'sfx.dart';
import 'store_painter.dart';
import 'widgets.dart';

class GameScreen extends StatefulWidget {
  final Game game;
  final World? world; // 시험에서 넣어 준다
  final bool followCamera; // 시험에서는 끈다(누를 자리가 흔들리지 않게)
  const GameScreen(this.game, {super.key, this.world, this.followCamera = true});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final World world = widget.world ?? World(widget.game);
  late final Ticker _ticker = createTicker(_onTick);
  final List<Flight> flights = [];
  late final Camera camera = Camera(iso(world.player.x, world.player.y), 1.0);
  BuildView? building; // null = 장사 중, 아니면 건설 중
  Duration _last = Duration.zero;
  double clock = 0, _sinceSave = 0;
  String? _toast;
  double _toastLeft = 0;
  (String, int)? _regularNews; // (단골, 오른 하트) — 이야기 카드
  double _regularLeft = 0;

  // 손가락
  Offset? _stickBase, _lastFocal;
  Offset _stick = Offset.zero;
  double _startZoom = 1;
  bool _touched = false;
  bool _follow = true; // 카메라가 플레이어를 따라가나 (지도를 끌면 멈춘다)
  bool _dragGhost = false; // 미리보기를 끌고 있나
  Tile? _dest, _lastPaint;
  Size _size = Size.zero;

  static const _knobMax = 56.0;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
    _welcomeBack();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    world.abandonDay(); // 장사 중에 나가도 하루는 지나간다
    saveGame(game);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    Music.background(away);
    if (away) saveGame(game);
  }

  /// 꺼 둔 동안 계산원이 번 돈을 알려 준다.
  void _welcomeBack() {
    if (game.savedAt == 0) return;
    final away = (DateTime.now().millisecondsSinceEpoch - game.savedAt) / 1000;
    final earned = game.offlineEarnings(away);
    if (earned <= 0) return;
    game.money += earned;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: bg,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(S.tn('welcome_back', {'n': earned}),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, color: inkColor)),
            const SizedBox(height: 12),
            Coins(earned, size: 28),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(S.t('btn_ok')))],
        ),
      );
    });
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    clock += dt;
    if (_storyOpen) return; // 이야기를 읽는 동안은 시간이 멈춘다
    world.tick(dt);
    if (building == null && _follow && widget.followCamera) {
      // 플레이어 쪽 60%, 가게 가운데 쪽 40%: 가게가 화면에 더 많이 들어온다
      final target = Offset.lerp(_storeCenter(), iso(world.player.x, world.player.y), 0.6)!;
      camera.center = Offset.lerp(camera.center, target, (dt * 5).clamp(0.0, 1.0))!;
    }
    for (final e in world.fx) {
      if (e.kind == FxKind.goal) {
        toast(S.tn('goal_done', {'n': e.amount}));
        Sfx.play(FxKind.levelUp, clock);
      } else if (e.kind == FxKind.event) {
        toast(S.t(EventKind.values[e.amount] == EventKind.rush ? 'event_rush' : 'event_vip'));
        Sfx.play(FxKind.levelUp, clock);
      } else if (e.kind == FxKind.regular) {
        if (e.amount > 0) {
          _regularNews = (e.product, e.amount);
          _regularLeft = 7;
          Sfx.play(FxKind.levelUp, clock);
        } else if (e.amount < 0) {
          final want = world.customers.where((c) => c.regular == e.product).firstOrNull?.wants.first;
          toast(S.tn('regular_arrive', {'name': regularName(e.product), 'item': want == null ? '' : S.t('p_$want')}));
        }
      } else if (e.kind == FxKind.combo) {
        toast(S.tn('combo_made', {'name': S.t('combo_${e.product}'), 'n': ((comboPrice - 1) * 100).round()}));
        Sfx.play(FxKind.levelUp, clock);
      } else if (e.kind == FxKind.sleep) {
        toast(S.t('staff_doze'));
        Sfx.cue('alarm', clock);
      } else if (e.kind == FxKind.tip) {
        Sfx.play(FxKind.cash, clock);
      } else if (e.kind == FxKind.stamp) {
        toast(S.tn('stamp_got', {'item': S.t('p_${e.product}'), 'n': stampAt, 'r': e.amount}));
        Sfx.play(FxKind.levelUp, clock);
      } else if (e.kind == FxKind.incident) {
        final k = Incident.values[e.amount];
        if (k == Incident.boxEmpty || k == Incident.boxArrived) {
          toast(S.tn('inc_${k.name}', {'item': S.t('p_${e.product}')}));
        } else if (k == Incident.inspectGood || k == Incident.inspectOk || k == Incident.inspectBad) {
          final parts = e.product.split('|');
          toast(S.tn('inc_${k.name}', {'s': parts[0], 'n': parts.length > 1 ? parts[1] : ''}));
        } else {
          toast(S.tn('inc_${k.name}', {'n': e.product}));
        }
        Sfx.cue(
            switch (k) {
              Incident.thiefFlee || Incident.brokeDown || Incident.grumpyIn || Incident.boxEmpty || Incident.kidLost ||
                Incident.selfError => 'alarm',
              Incident.thiefCaught || Incident.kidFound || Incident.orderDone || Incident.repaired || Incident.grumpyCalmed ||
                Incident.inspectGood => 'good',
              Incident.thiefEscaped || Incident.kidGone || Incident.orderLate || Incident.grumpyLeft || Incident.inspectBad => 'bad',
              Incident.fever => 'fever',
              Incident.clawPlay => 'chest',
              _ => 'bell', // 주문·단체 주문·도착·점검관·보통
            },
            clock);
      } else if (e.kind == FxKind.day) {
        if (e.amount == dayClosed) {
          final r = world.result;
          if (r != null) _dayResult(r);
        } else {
          toast(S.t(e.amount == dayLastCall ? 'day_last_call' : 'day_closing'));
          Sfx.play(FxKind.levelUp, clock);
        }
      } else if (e.kind == FxKind.levelUp) {
        _levelUp(e.amount);
      } else {
        Sfx.play(e.kind, clock);
      }
      if (e.kind != FxKind.scan) flights.add(Flight(e));
    }
    world.fx.clear();
    // 손님 도감: 처음 보는 손님
    for (final c in world.customers) {
      final (isNew, reward) = game.owner.meet(customerSheet(c));
      if (!isNew || game.owner.met.length < 2) continue; // 첫 손님은 그냥 넘어간다(시작하자마자 알림이 뜨지 않게)
      flights.add(Flight(Fx(FxKind.goal, c.x, c.y, product: 'new')));
      toast(reward > 0
          ? S.tn('dex_milestone', {'n': game.owner.met.length, 'r': reward})
          : S.tn('dex_new', {'n': game.owner.met.length, 'm': customerChars.length}));
    }
    for (final f in flights) {
      f.age += dt;
    }
    flights.removeWhere((f) => f.age > f.life);
    // 온장 코너에 날것이 처음 들어오면 굽는 법을 알려 준다(한 번만)
    if (!_cookHinted && world.cooking == null && game.shelves.any((s) => s.raw > 0)) {
      _cookHinted = true;
      toast(S.t('cook_hint'));
    }
    if (!_serviceHinted && world.customers.any((c) => c.kind == CustomerKind.service)) {
      _serviceHinted = true;
      toast(S.t('service_hint'));
    }
    _toastLeft -= dt;
    _regularLeft -= dt;
    _maybeStory();
    Music.fast(world.feverLeft > 0);
    _sinceSave += dt;
    if (_sinceSave > 5) {
      _sinceSave = 0;
      saveGame(game);
    }
    setState(() {});
  }

  void _levelUp(int level) {
    if (level > 1 && rankLevels.contains(level)) _rankUp(rankOf(level));
    final news = [
      for (final t in itemTypes)
        if (t.level == level) S.t('i_${t.id}'),
      for (final p in products)
        if (p.level == level) S.t('p_${p.id}'),
    ];
    final head = S.tn('level_up', {'n': level});
    toast(news.isEmpty ? head : '$head\n${S.tn('unlocked', {'list': news.join(', ')})}');
    Sfx.play(FxKind.levelUp, clock);
  }

  bool _storyOpen = false;
  bool _cookHinted = false, _serviceHinted = false;

  /// 다음 이야기가 열렸으면 보여 준다. 장사 중에는 끝날 때까지 기다린다(첫 이야기만 바로).
  void _maybeStory() {
    if (_storyOpen || building != null || world.result != null) return;
    final ch = game.owner.nextChapter;
    if (ch == null || (world.phase != DayPhase.closed && ch.id != 'opening')) return;
    if (ModalRoute.of(context)?.isCurrent != true) return; // 다른 창이 떠 있으면 나중에
    _storyOpen = true;
    _release();
    showChapter(context, ch).then((_) {
      game.owner.story.add(ch.id);
      saveGame(game);
      _storyOpen = false;
      _last = Duration.zero;
    });
  }

  /// 가게 등급이 올랐다: 간판과 새로 열린 것을 크게 보여 준다.
  Future<void> _rankUp(int rank) async {
    Sfx.play(FxKind.levelUp, clock);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: bg,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 90, height: 90, child: CustomPaint(painter: Portrait(playerChar, anim: Anim.yes))),
          const SizedBox(height: 6),
          Text(S.t('rank_up'), style: const TextStyle(fontSize: 15, color: Colors.black54)),
          const SizedBox(height: 6),
          SizedBox(width: 240, height: 54, child: CustomPaint(painter: RankSign(rank))),
          const SizedBox(height: 12),
          Text(S.t('rank_${rank}_new'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: inkColor, height: 1.45)),
          const SizedBox(height: 6),
          Text(S.tn('rank_visitors', {'n': (rankVisitorBonus * rank * 100).round()}),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ]),
        actions: [
          Center(child: BubbleButton(S.t('btn_nice'), color: const Color(0xFF81C784), onTap: () => Navigator.pop(c))),
        ],
      ),
    );
  }

  void toast(String text) {
    _toast = text;
    _toastLeft = 3;
  }

  // ---------------------------------------------------------------- 손가락

  bool get _useStick => Settings.i.joystick;

  Offset _storeCenter() {
    var sum = Offset.zero;
    for (final (px, py) in game.plots) {
      sum += iso((px + 0.5) * plotSize - 0.5, (py + 0.5) * plotSize - 0.5);
    }
    return sum / game.plots.length.toDouble();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.localFocalPoint;
    _startZoom = camera.zoom;
    _lastPaint = null;
    final b = building;
    _dragGhost = false;
    if (b != null && b.ghostType != null && b.hover != null && d.pointerCount == 1) {
      // 미리보기(또는 그 아래 손잡이) 근처를 잡으면 끌어서 옮긴다
      final g = camera.toScreen(iso(b.hover!.$1 + 0.0, b.hover!.$2 + 0.0), _size);
      _dragGhost = (d.localFocalPoint - g).distance < 70 * camera.zoom.clamp(0.8, 1.5) ||
          (d.localFocalPoint - (g + Offset(0, 26 * camera.zoom))).distance < 40;
    }
    if (b == null && _useStick && d.pointerCount == 1) {
      _stickBase = d.localFocalPoint;
      _touched = true;
      _setStick(Offset.zero);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final b = building;
    if (d.pointerCount >= 2) {
      // 두 손가락: 확대·축소하며 옮기기
      _release();
      _dragGhost = false;
      camera.zoom = (_startZoom * d.scale).clamp(0.35, 2.2);
      if (_lastFocal != null) camera.center -= (d.localFocalPoint - _lastFocal!) / camera.zoom;
      _follow = false;
    } else if (_stickBase != null) {
      _setStick(d.localFocalPoint - _stickBase!);
    } else if (_dragGhost && b != null) {
      // 손가락보다 조금 위에 놓이게 해서 손가락에 가리지 않는다
      b.hover = tileOf(camera.toWorld(d.localFocalPoint - const Offset(0, 40), _size));
    } else if (b != null && _paintTool(b)) {
      _paint(b, tileOf(camera.toWorld(d.localFocalPoint, _size)));
    } else if (_lastFocal != null) {
      camera.center -= (d.localFocalPoint - _lastFocal!) / camera.zoom;
      _follow = false;
    }
    _lastFocal = d.localFocalPoint;
    final m = mapBounds;
    camera.center = Offset(camera.center.dx.clamp(m.left, m.right), camera.center.dy.clamp(m.top, m.bottom));
  }

  void _onScaleEnd() {
    _release();
    _dragGhost = false;
  }

  bool _paintTool(BuildView b) => b.place == 'eraser' || (b.place?.startsWith('floor-') ?? false);

  /// 바닥 칠하기·지우기는 실수해도 싸서 누르거나 끄는 대로 바로 한다.
  void _paint(BuildView b, Tile t) {
    if (t == _lastPaint) return;
    _lastPaint = t;
    if (b.place == 'eraser') {
      if (game.sellFloor(t)) Sfx.play(FxKind.clean, clock);
    } else if (game.canPlace(b.place!, t) == PlaceResult.ok) {
      game.place(b.place!, t);
      Sfx.play(FxKind.place, clock);
    }
  }

  void _setStick(Offset d) {
    if (d.distance > _knobMax) d = d / d.distance * _knobMax;
    _stick = d;
    final (x, y) = screenToWorld(d.dx, d.dy);
    final len = Offset(x, y).distance;
    final k = len == 0 ? 0.0 : (d.distance / _knobMax) / len;
    world
      ..input = x * k
      ..inputY = y * k;
    if (d != Offset.zero) _follow = true;
  }

  void _release() {
    _stickBase = null;
    _setStick(Offset.zero);
  }

  void _onTap(Offset local) {
    final b0 = building;
    // 물건 놓을 자리를 고를 때는 바닥 칸, 그 밖에는 눈에 보이는 물건을 누른 것으로 친다
    final placing = b0 != null && (b0.ghostType != null || _paintTool(b0) || b0.land);
    final w = camera.toWorld(local, _size);
    final t = placing ? tileOf(w) : tileAtPoint(game, w);
    final b = building;
    if (b == null) {
      // 빈 상자를 누르면 주문 창
      final box = game.at(t);
      if (box != null && box.t.kind == ItemKind.box && box.product != null && box.units == 0 && box.incoming <= 0) {
        _reorder(box);
        return;
      }
      // 누른 곳으로 걸어가서 그 일을 한다
      _touched = true;
      _dest = world.tapAt(t);
      if (_dest != null) _follow = true;
      return;
    }
    if (b.land) {
      final plot = (t.$1 ~/ plotSize, t.$2 ~/ plotSize);
      if (t.$1 >= 0 && t.$2 >= 0 && game.plotsForSale.contains(plot)) _buyPlot(plot);
      return;
    }
    if (_paintTool(b)) {
      _lastPaint = null;
      _paint(b, t);
      return;
    }
    if (b.ghostType != null) {
      b.hover = t; // 누르면 미리보기가 그리로 간다. 놓기는 ✓ 단추로
      return;
    }
    b.selected = game.at(t);
  }

  /// ✓ 단추: 미리보기 자리에 놓거나 옮긴다.
  void _confirm() {
    final b = building!;
    final t = b.hover;
    if (t == null) return;
    final mv = b.moving;
    if (mv != null) {
      final res = game.move(mv, t, rot: b.rot);
      if (res == PlaceResult.ok) {
        b.moving = null;
        b.hover = null;
        Sfx.play(FxKind.place, clock);
      } else {
        toast(_reason(res, mv.type));
      }
    } else {
      final res = game.canPlace(b.place!, t, rot: b.rot);
      if (res == PlaceResult.ok) {
        game.place(b.place!, t, rot: b.rot, product: b.product);
        Sfx.play(FxKind.place, clock);
        // 하나 놓으면 놓기를 끝낸다: 그래야 방금 놓은 것을 눌러 옮기거나 팔 수 있다
        b
          ..place = null
          ..hover = null;
        toast(S.t('placed_hint'));
      } else {
        toast(_reason(res, b.place!));
      }
    }
    setState(() {});
  }

  void _cancelGhost() => setState(() {
        building!
          ..place = null
          ..moving = null
          ..hover = null;
      });

  /// 놓을 것을 고르면 미리보기를 화면 가운데에 띄운다.
  void _panelChanged() {
    final b = building;
    if (b != null && b.ghostType != null && b.hover == null) b.hover = tileOf(camera.center);
    setState(() {});
  }

  String _reason(PlaceResult r, String type) => switch (r) {
        PlaceResult.locked => S.tn('need_level', {'n': itemType(type).level}),
        PlaceResult.money => S.t('no_money'),
        PlaceResult.notOwned => S.t('not_owned'),
        PlaceResult.occupied => S.t('occupied'),
        PlaceResult.blocksPath => S.t('blocks_path'),
        PlaceResult.ok => '',
      };

  Future<void> _buyPlot(Tile plot) async {
    final price = game.nextPlotPrice;
    if (game.money < price) {
      toast(S.t('no_money'));
      return;
    }
    if (await confirm(context, S.tn('buy_plot', {'n': price})) && game.buyPlot(plot)) {
      Sfx.play(FxKind.levelUp, clock);
    }
  }

  void _toggleBuild() => setState(() {
        building = building == null ? BuildView() : null;
        _release();
      });

  // ---------------------------------------------------------------- 화면

  @override
  Widget build(BuildContext context) {
    final b = building;
    return Scaffold(
      backgroundColor: themeOf(game.branch).sky,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: LayoutBuilder(builder: (context, c) {
                  _size = Size(c.maxWidth, c.maxHeight);
                  // 손가락을 떼면 무조건 조이스틱을 놓는다(제스처가 끊겨 끝 소식이 안 와도 계속 걷지 않게)
                  return Listener(
                    onPointerUp: (_) => _release(),
                    onPointerCancel: (_) => _release(),
                    child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: (_) => _onScaleEnd(),
                    onTapUp: (d) => _onTap(d.localPosition),
                    child: CustomPaint(
                        size: _size,
                        painter: StorePainter(world, flights, clock, camera, b,
                            dest: _dest, guide: b == null ? _guideTile() : null)),
                  ));
                }),
              ),
              Positioned(left: 8, right: 8, top: 6, child: _hud()),
              if (b == null && game.owner.tutorial == TutorialStep.done)
                Positioned(
                    left: 8,
                    top: 58,
                    child: world.phase == DayPhase.closed
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_goalCard(), _rankChip()])
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _dayCard(),
                            if (world.order != null) _orderCard(world.order!),
                          ])),
              if (game.owner.tutorial != TutorialStep.done && (b == null || game.owner.tutorial == TutorialStep.build))
                Positioned(left: 0, right: 0, top: 58, child: _tutorialCard(game.owner.tutorial)),
              if (_regularNews != null && _regularLeft > 0)
                Positioned(left: 0, right: 0, top: 150, child: _regularCard(_regularNews!)),
              if (world.feverLeft > 0) Positioned.fill(child: IgnorePointer(child: _feverGlow())),
              if (b == null && game.owner.tutorial == TutorialStep.done && world.phase != DayPhase.closed && (world.combo >= 2 || world.feverLeft > 0))
                Positioned(right: 8, top: 58, child: _comboChip()),
              if (_toast != null && _toastLeft > 0)
                Align(
                  // 위에 안내·단골 카드가 떠 있으면 그 아래로
                  alignment: Alignment(
                      0, game.owner.tutorial != TutorialStep.done || (_regularNews != null && _regularLeft > 0) ? -0.2 : -0.62),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(

                        boxShadow: softShadow,
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: inkColor, width: 2),
                      ),
                      child: Text(_toast!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: inkColor)),
                    ),
                  ),
                ),
              if (b == null && game.owner.tutorial == TutorialStep.done && world.phase == DayPhase.closed)
                Align(alignment: const Alignment(0, 0.86), child: _openButton()),
              if (b == null && !_touched && world.phase != DayPhase.closed)
                Align(
                  alignment: const Alignment(0, 0.9),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(16), boxShadow: softShadow),
                    child: Text(S.t(_useStick ? 'hint_move' : 'hint_tap'), style: const TextStyle(fontSize: 15, color: inkColor)),
                  ),
                ),
              if (b != null && b.ghostType != null && b.hover != null) Positioned(left: 0, right: 0, bottom: 14, child: _ghostButtons(b)),
              if (b != null && b.selected != null && b.ghostType == null)
                Positioned(left: 0, right: 0, bottom: 10, child: _selectedButtons(b, b.selected!)),
              if (_stickBase != null) ..._joystick(),
              if (b == null && !_follow)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'me',
                    backgroundColor: Colors.white,
                    foregroundColor: inkColor,
                    onPressed: () => setState(() => _follow = true),
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ),
              if (b == null || ((b.ghostType == null || b.hover == null) && b.selected == null)) // 단추끼리 겹치지 않게
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton(
                  heroTag: 'build',
                  backgroundColor: b == null ? const Color(0xFFFFB74D) : const Color(0xFF81C784),
                  foregroundColor: inkColor,
                  onPressed: _toggleBuild,
                  child: Icon(b == null ? Icons.handyman_rounded : Icons.storefront_rounded, size: 30),
                ),
              ),
            ]),
          ),
          if (b != null) BuildPanel(game: game, view: b, onChanged: _panelChanged, toast: toast),
        ]),
      ),
    );
  }

  Future<void> _menu() async {
    final choice = await showGameMenu(context);
    if (!mounted || choice == null) return;
    final nav = Navigator.of(context);
    switch (choice) {
      case MenuChoice.map:
        await saveGame(game);
        nav.push(MaterialPageRoute(
            builder: (_) => MapScreen(game.owner, onEnter: (g) {
                  saveGame(g);
                  nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => GameScreen(g)), (_) => false);
                })));
      case MenuChoice.regulars:
        nav.push(MaterialPageRoute(builder: (_) => RegularsScreen(game.owner)));
      case MenuChoice.help:
        nav.push(MaterialPageRoute(builder: (_) => const HelpScreen()));
      case MenuChoice.dex:
        nav.push(MaterialPageRoute(builder: (_) => DexScreen(game.owner)));
      case MenuChoice.story:
        nav.push(MaterialPageRoute(builder: (_) => StoryScreen(game.owner)));
      case MenuChoice.settings:
        showSettings(context);
      case MenuChoice.title:
        await saveGame(game);
        nav.pushReplacement(MaterialPageRoute(builder: (_) => const TitleScreen()));
    }
  }

  /// 처음 안내: 지금 단계에서 가리킬 칸 (짓기 단계는 망치 단추를 가리켜서 null).
  Tile? _guideTile() {
    final st = game.owner.tutorial;
    switch (st) {
      case TutorialStep.pickBox:
        final low = game.shelves.toList()..sort((a, b) => a.stock.compareTo(b.stock));
        for (final s in low) {
          final b = game.boxOf(s.product!);
          if (b != null) return b.tile;
        }
        return game.ofKind(ItemKind.box).firstOrNull?.tile;
      case TutorialStep.fillShelf:
        return game.shelves.where((s) => world.player.carry.contains(s.product) && s.stock < s.capacity).firstOrNull?.tile ??
            game.shelves.firstOrNull?.tile;
      case TutorialStep.checkout:
        return game.registers.firstOrNull?.till;
      case TutorialStep.collect:
        return (game.registers.where((r) => r.cash > 0).firstOrNull ?? game.registers.firstOrNull)?.tile;
      case TutorialStep.build || TutorialStep.done:
        return null;
    }
  }

  Widget _tutorialCard(TutorialStep st) => IgnorePointer(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
          decoration: BoxDecoration(

            boxShadow: softShadow,
            color: const Color(0xFFFFFDE7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFB300), width: 2.5),
          ),
          child: Row(children: [
            SizedBox(width: 54, height: 54, child: CustomPaint(painter: Portrait(stockerChar, anim: Anim.yes))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(S.tn('tut_step', {'n': st.index + 1, 'm': TutorialStep.values.length - 1}),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFFF8F00))),
                Text(S.t('tut_${st.name}'), style: const TextStyle(fontSize: 15, color: inkColor, height: 1.35)),
              ]),
            ),
          ]),
        ),
      );

  Widget _regularCard((String, int) news) {
    final (id, heart) = news;
    final r = regularById(id);
    return GestureDetector(
      onTap: () => setState(() => _regularLeft = 0),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(

          boxShadow: softShadow,
          color: const Color(0xFFFCE4EC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEC407A), width: 2.5),
        ),
        child: Row(children: [
          SizedBox(width: 64, height: 64, child: CustomPaint(painter: Portrait(r.look, anim: Anim.yes))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text(regularName(id), style: const TextStyle(fontSize: 17, color: Color(0xFFAD1457))),
                const SizedBox(width: 6),
                Text('♥' * heart, style: const TextStyle(color: Color(0xFFEC407A))),
                const Spacer(),
                Coins(heartReward(heart), size: 13),
              ]),
              const SizedBox(height: 2),
              Text(S.t('reg_${id}_h$heart'), style: const TextStyle(fontSize: 14, color: inkColor, height: 1.35)),
            ]),
          ),
        ]),
      ),
    );
  }

  /// 고른 물건으로 할 일: 옮기기 · 상품 · 돌리기 · 레벨업 · 팔기. 글자를 붙인 큰 단추.
  Widget _selectedButtons(BuildView b, Item i) {
    void done() => setState(() {});
    // 단추가 여섯 개까지 늘어도 좁은 폰(360)에서 다 보이게: 46 + 양옆 3
    Widget act(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white, Widget? extra}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Material(
              color: color,
              shape: const CircleBorder(side: BorderSide(color: inkColor, width: 2.5)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(width: 46, height: 46, child: Icon(icon, color: inkColor, size: 24)),
              ),
            ),
            const SizedBox(height: 2),
            // 글자가 길어도 단추 줄이 넓어지지 않게 줄여서 맞춘다
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 58),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8)),
                  child: extra ?? Text(label, style: const TextStyle(fontSize: 12, color: inkColor)),
                ),
              ),
            ),
          ]),
        );
    final cost = game.levelUpCost(i);
    var spent = i.t.price;
    for (var l = 1; l < i.level; l++) {
      spent += itemUpgradeCost(i.t, l);
    }
    final refund = (spent * sellRefund).round() + i.cash;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        act(Icons.open_with_rounded, S.t('act_move'), () {
          b
            ..moving = i
            ..place = null
            ..rot = i.rot
            ..hover = i.tile
            ..selected = null;
          toast(S.t('drag_hint'));
          done();
        }),
        if (i.t.needsProduct)
          act(Icons.swap_horiz_rounded, S.t('act_product'), () {
            showProductPicker(context, game, i.t, (p) {
              if (!game.setProduct(i, p)) toast(S.t('occupied'));
              done();
            }, toast);
          }),
        if (i.t.kind == ItemKind.box && i.product != null)
          act(Icons.local_shipping_rounded, S.t('act_reorder'), () => _reorder(i)),
        if (game.expiring(i))
          act(Icons.local_offer_rounded, S.t(i.sticker ? 'sticker_off' : 'act_sticker'), () {
            game.toggleSticker(i);
            toast(S.t(i.sticker ? 'sticker_on' : 'sticker_removed'));
            done();
          }, color: i.sticker ? const Color(0xFFFFF59D) : Colors.white),
        if (i.t.kind == ItemKind.shelf)
          act(Icons.price_change_rounded, S.t('price_${i.price}'), () {
            game.cyclePrice(i);
            toast(S.t('price_${i.price}_d'));
            done();
          }),
        if (i.t.rotates)
          act(Icons.rotate_right_rounded, S.t('act_rotate'), () {
            if (!game.rotate(i)) toast(S.t('occupied'));
            done();
          }),
        if (cost != null)
          act(Icons.keyboard_double_arrow_up_rounded, S.t('act_levelup'), () {
            if (game.levelUp(i)) {
              Sfx.play(FxKind.levelUp, clock);
            } else {
              toast(S.t('no_money'));
            }
            done();
          }, color: const Color(0xFFFFE0B2), extra: Coins(cost, size: 12)),
        act(Icons.sell_rounded, S.t('act_sell'), () {
          if (game.sell(i)) {
            b.selected = null;
            Sfx.play(FxKind.cash, clock);
          } else {
            toast(S.t('cant_sell'));
          }
          done();
        }, color: const Color(0xFFFFCDD2), extra: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${S.t('act_sell')} ', style: const TextStyle(fontSize: 12, color: inkColor)),
          Coins(refund, size: 12),
        ])),
      ]),
    );
  }

  /// 미리보기 아래 단추: 돌리기 · 놓기 · 그만.
  Widget _ghostButtons(BuildView b) {
    final mv = b.moving;
    final res = mv != null ? game.canMove(mv, b.hover!, rot: b.rot) : game.canPlace(b.place!, b.hover!, rot: b.rot);
    final ok = res == PlaceResult.ok;
    Widget round(IconData icon, Color color, VoidCallback onTap, {double size = 56}) => Material(
          color: color,
          shape: const CircleBorder(side: BorderSide(color: inkColor, width: 2.5)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, color: inkColor, size: size * 0.5)),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!ok)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10)),
          child: Text(_reason(res, mv?.type ?? b.place!), style: const TextStyle(fontSize: 14, color: Color(0xFFC62828))),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (itemType(b.ghostType!).rotates) ...[
          round(Icons.rotate_right_rounded, Colors.white, () => setState(() => b.rot = (b.rot + 1) % 4), size: 48),
          const SizedBox(width: 14),
        ],
        round(Icons.check_rounded, ok ? const Color(0xFF81C784) : const Color(0xFFE0E0E0), _confirm, size: 66),
        const SizedBox(width: 14),
        round(Icons.close_rounded, Colors.white, _cancelGhost, size: 48),
      ]),
    ]);
  }

  /// 지금 목표와 진행, 행사 중이면 남은 시간.
  /// 여는 동안: 날짜·남은 시간, 오늘 번 돈과 별 눈금, 할 일 두 개.
  Widget _dayCard() {
    final style = const TextStyle(fontSize: 13, color: inkColor);
    if (world.night) {
      // 야간 영업: 남은 시간과 번 돈만
      return IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: BoxDecoration(
            boxShadow: softShadow,
            color: const Color(0xFFE8EAF6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF5C6BC0), width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.nightlight_round, size: 16, color: Color(0xFF3949AB)),
            const SizedBox(width: 4),
            Text(S.t('night_title'), style: style.copyWith(fontSize: 14)),
            const SizedBox(width: 8),
            Coins(world.daySales, size: 13),
            const SizedBox(width: 8),
            Text(world.phase == DayPhase.closing ? S.t('day_closing_short') : '${world.dayLeft.ceil()}s',
                style: style.copyWith(color: Colors.black45, fontSize: 12)),
          ]),
        ),
      );
    }
    final ev = world.event;
    final closing = world.phase == DayPhase.closing;
    final full = world.dayTarget * dayStars.last; // 막대 끝 = 별 셋
    final stars = dayStars.where((r) => world.daySales >= world.dayTarget * r).length;
    Widget task(DayTask t) {
      final p = world.taskProgress(t);
      final done = world.taskDone(t);
      final calm = t.kind == DayTaskKind.calm;
      final text = switch (t.kind) {
        DayTaskKind.sell => S.tn('task_sell', {'item': S.t('p_${t.product}'), 'n': t.n}),
        DayTaskKind.serve => S.tn('task_serve', {'n': t.n}),
        DayTaskKind.calm => S.tn('task_calm', {'n': t.n}),
      };
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              calm
                  ? (done ? Icons.sentiment_satisfied_rounded : Icons.sentiment_dissatisfied_rounded)
                  : (done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
              size: 15,
              color: done ? const Color(0xFF43A047) : (calm ? const Color(0xFFE53935) : Colors.black38)),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: style, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          Text(calm ? '$p/${t.n}' : '${min(p, t.n)}/${t.n}', style: style.copyWith(color: Colors.black45, fontSize: 12)),
        ]),
      );
    }

    return IgnorePointer(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 250),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: BoxDecoration(

            boxShadow: softShadow,
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inkColor.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(closing ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  size: 16, color: closing ? const Color(0xFF5C6BC0) : const Color(0xFFFFA000)),
              const SizedBox(width: 4),
              Flexible(child: Text(S.tn('day_n', {'n': game.day}), style: style.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (game.rank >= rankWeather && world.weather != Weather.sunny) ...[
                const SizedBox(width: 4),
                Icon(weatherIcon(world.weather), size: 15, color: weatherColor(world.weather)),
              ],
              if (world.special != null) const Icon(Icons.celebration_rounded, size: 15, color: Color(0xFFE65100)),
              if (world.holiday != null) const Icon(Icons.redeem_rounded, size: 15, color: Color(0xFFD81B60)),
              if (world.promo != null) const Icon(Icons.campaign_rounded, size: 15, color: Color(0xFFE65100)),
              if (world.priceWar) const Icon(Icons.local_offer_rounded, size: 15, color: Color(0xFFC62828)),
              const SizedBox(width: 8),
              if (closing)
                Text(S.t('day_closing_short'), style: style.copyWith(color: const Color(0xFF5C6BC0)))
              else
                SizedBox(
                  width: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: world.dayLeft / dayLength,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFEEEEEE),
                      color: world.dayLeft < lastCall ? const Color(0xFFFF7043) : const Color(0xFFFFCA28),
                    ),
                  ),
                ),
              if (!closing) ...[
                const SizedBox(width: 6),
                Text('${world.dayLeft.ceil()}s', style: style.copyWith(fontSize: 12, color: Colors.black45)),
              ],
            ]),
            const SizedBox(height: 5),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Coins(world.daySales, size: 13),
              Text(' / ${world.dayTarget}', style: style.copyWith(color: Colors.black45, fontSize: 12)),
              const SizedBox(width: 6),
              for (var i = 0; i < 3; i++)
                Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 16, color: const Color(0xFFFFC107)),
            ]),
            const SizedBox(height: 3),
            SizedBox(
              width: 200,
              height: 8,
              child: Stack(children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: full <= 0 ? 0 : (world.daySales / full).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: const Color(0xFFEEEEEE),
                      color: const Color(0xFF66BB6A),
                    ),
                  ),
                ),
                for (final r in dayStars.take(2))
                  Positioned(left: 200 * r / dayStars.last - 1, top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
              ]),
            ),
            for (final t in world.tasks) task(t),
          ]),
        ),
        if (ev != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ev == EventKind.rush ? const Color(0xFFFFE0B2) : const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${S.t(ev == EventKind.rush ? 'event_rush' : 'event_vip')}  ${world.eventLeft.ceil()}s', style: style),
          ),
      ]),
    );
  }

  /// 상자 재주문: 값과 도착 시간을 보여 주고 주문한다.
  Future<void> _reorder(Item box) async {
    final p = box.product!;
    final cost = reorderCost(p);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: bg,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 56, height: 56, child: CustomPaint(painter: FoodPreview(p))),
          const SizedBox(height: 6),
          Text(S.tn('reorder_q', {'item': S.t('p_$p'), 'n': boxSize, 's': restockDelay.round()}),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: inkColor)),
          const SizedBox(height: 4),
          Text(S.tn('reorder_left', {'n': box.units}), style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 8),
          Coins(cost, size: 20),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.t('btn_cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(S.t('act_reorder'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (game.reorder(box)) {
      Sfx.play(FxKind.pay, clock);
      toast(S.tn('reorder_done', {'s': restockDelay.round()}));
    } else {
      toast(S.t(game.money < cost ? 'no_money' : 'reorder_busy'));
    }
    setState(() {});
  }

  /// 피버 타임: 화면 가장자리가 불꽃색으로 빛난다.
  Widget _feverGlow() {
    final a = 0.35 + 0.15 * sin(clock * 8);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFF6D00).withValues(alpha: a), width: 10),
        gradient: RadialGradient(
          radius: 1.2,
          colors: [Colors.transparent, const Color(0xFFFFAB00).withValues(alpha: a * 0.35)],
        ),
      ),
    );
  }

  /// 콤보 칩(오른쪽 위): 콤보 수와 피버까지 남은 칸, 피버 중이면 남은 시간.
  Widget _comboChip() {
    final fever = world.feverLeft > 0;
    final pulse = 1 + 0.06 * sin(clock * (fever ? 14 : 6));
    return IgnorePointer(
      child: Transform.scale(
        scale: pulse,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: fever ? const [Color(0xFFFF6D00), Color(0xFFFFD600)] : const [Colors.white, Colors.white]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFF6D00), width: 2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(fever ? S.tn('fever_left', {'n': world.feverLeft.ceil()}) : S.tn('combo_n', {'n': world.combo}),
                style: TextStyle(fontSize: fever ? 16 : 14, color: fever ? Colors.white : const Color(0xFFE65100))),
            if (!fever) ...[
              const SizedBox(height: 3),
              SizedBox(
                width: 70,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: world.combo / feverAt,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFFFE0B2),
                    color: const Color(0xFFFF6D00),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// 배달 주문: 상품·남은 시간, 출발 단추.
  Widget _orderCard(Order o) {
    const style = TextStyle(fontSize: 13, color: inkColor);
    final ok = world.canDeliver;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(

        boxShadow: softShadow,
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF42A5F5), width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.delivery_dining_rounded, color: Color(0xFF1E88E5), size: 22),
        const SizedBox(width: 4),
        if (o.bulk) Text(S.t('bulk_tag'), style: style.copyWith(color: const Color(0xFFE65100))),
        for (final p in o.items.toSet()) ...[
          SizedBox(width: 24, height: 24, child: CustomPaint(painter: FoodPreview(p))),
          if (o.items.where((x) => x == p).length > 1)
            Text('×${o.items.where((x) => x == p).length}', style: style.copyWith(fontSize: 12)),
        ],
        const SizedBox(width: 4),
        Text('${o.left.ceil()}s', style: style.copyWith(color: o.left < 20 ? const Color(0xFFE53935) : Colors.black54)),
        const SizedBox(width: 6),
        if (o.started)
          Text(S.t(o.carrying ? 'order_door' : 'order_picking'), style: style.copyWith(color: const Color(0xFF1E88E5)))
        else
          Material(
            color: ok ? const Color(0xFF64B5F6) : const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: ok
                  ? () {
                      if (world.startDelivery()) {
                        _dest = world.player.goal;
                        _follow = true;
                      }
                      setState(() {});
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(S.t(ok ? 'order_go' : 'order_short'), style: style.copyWith(color: ok ? Colors.white : Colors.black38)),
              ),
            ),
          ),
      ]),
    );
  }

  /// 닫힌 동안: 다음 날 예보와 문 열기.
  Widget _openButton() => Column(mainAxisSize: MainAxisSize.min, children: [
        if (game.rank >= rankWeather) _forecast(),
        _promoButton(),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
          child: Text(S.t('day_closed_hint'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
        const SizedBox(height: 8),
        if (world.canOpenNight) ...[
          SizedBox(
            width: 230,
            child: BubbleButton(
              S.t('night_open'),
              color: const Color(0xFF9FA8DA),
              trailing: const Icon(Icons.nightlight_round, color: inkColor),
              onTap: () {
                world.openNight();
                toast(S.tn('night_start', {'n': ((nightPay - 1) * 100).round()}));
                Sfx.play(FxKind.levelUp, clock);
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: 230,
          child: BubbleButton(
            S.tn('day_open', {'n': game.day}),
            color: const Color(0xFF81C784),
            trailing: const Icon(Icons.storefront_rounded, color: inkColor),
            onTap: () {
              world.openDay();
              Sfx.play(FxKind.levelUp, clock);
              setState(() {});
            },
          ),
        ),
      ]);

  /// 홍보: 정했으면 무엇인지, 아니면 고르는 단추.
  Widget _promoButton() {
    final p = game.promo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p == null ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: inkColor, width: 2)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: p == null ? _choosePromo : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(p == null ? Icons.campaign_rounded : Icons.check_circle_rounded, color: const Color(0xFFE65100), size: 20),
              const SizedBox(width: 6),
              Text(
                  p == null
                      ? S.t('promo_btn')
                      : p == Promo.flyer
                          ? S.t('promo_flyer_set')
                          : S.tn('promo_1p1_set', {'item': S.t('p_${game.promoProduct}')}),
                  style: const TextStyle(fontSize: 14, color: inkColor)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _choosePromo() async {
    final cost = game.flyerCost;
    final choice = await showModalBottomSheet<Promo>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) {
        Widget card(Promo p, IconData icon, String title, String desc, Widget price) => Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: inkColor, width: 1.5)),
              child: ListTile(
                leading: Icon(icon, color: const Color(0xFFE65100), size: 32),
                title: Text(title, style: const TextStyle(fontSize: 17, color: inkColor)),
                subtitle: Text(desc, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                trailing: price,
                onTap: () => Navigator.pop(c, p),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(S.t('promo_title'), style: const TextStyle(fontSize: 20, color: inkColor)),
              const SizedBox(height: 8),
              card(Promo.flyer, Icons.campaign_rounded, S.t('promo_flyer'),
                  S.tn('promo_flyer_d', {'n': ((flyerVisitors - 1) * 100).round()}), Coins(cost, size: 15)),
              card(Promo.onePlusOne, Icons.exposure_plus_1_rounded, S.t('promo_1p1'), S.t('promo_1p1_d'),
                  Text(S.t('promo_free'), style: const TextStyle(fontSize: 13, color: Color(0xFF2E7D32)))),
            ]),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice == Promo.flyer) {
      if (!game.setPromo(Promo.flyer)) toast(S.t('no_money'));
    } else {
      final sale = game.onSale.toList()..sort();
      if (sale.isEmpty) return;
      // 진열된 상품 중에서 고른다
      final kind = itemTypes.firstWhere((t) => t.kind == ItemKind.box);
      if (!mounted) return;
      showProductPicker(context, game, kind, (p) {
        if (!game.setPromo(Promo.onePlusOne, product: p)) toast(S.t('promo_need_shelf'));
        setState(() {});
      }, toast, only: sale.toSet());
    }
    setState(() {});
  }

  /// 다음 날 예보: 날씨·특별한 날, 잘 팔릴 상품.
  Widget _forecast() {
    final w = game.todayWeather;
    final sp = game.todaySpecial;
    final hol = game.todayHoliday;
    final goods = {...weatherGoods[w]!, ...?specialGoods[sp], ...?holidayGoods[hol]}
        .where((p) => productById(p).level <= game.level)
        .take(5)
        .map((p) => S.t('p_$p'))
        .toList();
    const style = TextStyle(fontSize: 14, color: inkColor);
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(

        boxShadow: softShadow,
        color: hol != null ? const Color(0xFFFCE4EC) : (sp == null ? Colors.white.withValues(alpha: 0.92) : const Color(0xFFFFF8E1)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sp == null ? inkColor.withValues(alpha: 0.5) : const Color(0xFFFFB300), width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(weatherIcon(w), color: weatherColor(w), size: 22),
          const SizedBox(width: 6),
          Flexible(child: Text(S.tn('forecast', {'n': game.day, 'w': S.t('weather_${w.name}')}), style: style)),
        ]),
        if (game.priceWarDay) ...[
          const SizedBox(height: 4),
          Text(S.t('war_forecast'), textAlign: TextAlign.center, style: style.copyWith(color: const Color(0xFFC62828), fontSize: 13)),
        ],
        if (game.inspectionDay) ...[
          const SizedBox(height: 4),
          Text(S.t('inspect_forecast'), textAlign: TextAlign.center, style: style.copyWith(color: const Color(0xFF1565C0), fontSize: 13)),
        ],
        if (hol != null) ...[
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 26, height: 26, child: CustomPaint(painter: FoodPreview(holidayProduct(hol).id))),
            const SizedBox(width: 4),
            Flexible(child: Text('${S.t('hol_${hol.name}')}!', style: style.copyWith(color: const Color(0xFFD81B60), fontSize: 16))),
          ]),
          Text(S.tn('hol_d', {'item': S.t('p_${holidayProduct(hol).id}')}),
              textAlign: TextAlign.center, style: style.copyWith(fontSize: 13)),
        ],
        if (sp != null) ...[
          const SizedBox(height: 4),
          Text('★ ${S.t('special_${sp.name}')}', style: style.copyWith(color: const Color(0xFFE65100), fontSize: 16)),
          Text(S.t('special_${sp.name}_d'), textAlign: TextAlign.center, style: style.copyWith(fontSize: 13)),
        ],
        if (goods.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(S.tn('sells_well', {'list': goods.join(', ')}),
              textAlign: TextAlign.center, style: style.copyWith(fontSize: 12, color: Colors.black54)),
        ],
      ]),
    );
  }

  Future<void> _dayResult(DayResult r) async {
    Sfx.play(FxKind.levelUp, clock);
    saveGame(game);
    if (r.night) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFFE8EAF6),
          title: Text(S.t('night_result'), textAlign: TextAlign.center, style: const TextStyle(color: inkColor)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.nightlight_round, size: 48, color: Color(0xFF3949AB)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${S.t('day_sales')}  ', style: const TextStyle(fontSize: 16, color: inkColor)),
              Coins(r.sales, size: 20),
            ]),
            Text('${S.t('day_served')} ${r.served}  ·  ${S.t('day_upset')} ${r.upset}',
                style: const TextStyle(fontSize: 14, color: Colors.black54)),
          ]),
          actions: [Center(child: BubbleButton(S.t('btn_nice'), color: const Color(0xFF9FA8DA), onTap: () => Navigator.pop(c)))],
        ),
      );
      world.result = null;
      return;
    }
    const style = TextStyle(fontSize: 15, color: inkColor);
    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(label, style: style)), const SizedBox(width: 8), value]),
        );
    String taskText(DayTask t) => switch (t.kind) {
          DayTaskKind.sell => S.tn('task_sell', {'item': S.t('p_${t.product}'), 'n': t.n}),
          DayTaskKind.serve => S.tn('task_serve', {'n': t.n}),
          DayTaskKind.calm => S.tn('task_calm', {'n': t.n}),
        };
    final perTask = (r.target * dayTaskReward).round();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: bg,
        title: Text(S.tn('day_result', {'n': r.day}), textAlign: TextAlign.center, style: const TextStyle(color: inkColor)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 3; i++)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 350 + 300 * i),
                  curve: Curves.elasticOut,
                  builder: (_, k, child) => Transform.scale(scale: i < r.stars ? k : 1, child: child),
                  child: Icon(i < r.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: i == 1 ? 58 : 46, color: const Color(0xFFFFC107)),
                ),
            ]),
            if (r.best)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFF7043), borderRadius: BorderRadius.circular(10)),
                child: Text(S.t('day_best'), style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            const SizedBox(height: 6),
            row(S.t('day_sales'), Coins(r.sales, size: 16)),
            row(S.t('day_target'), Text('${r.target}', style: style)),
            row(S.t('day_served'), Text('${r.served}', style: style)),
            row(S.t('day_upset'), Text('${r.upset}', style: style)),
            if (r.missing.isNotEmpty)
              row(
                  S.t('day_missing'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final (p, n) in r.missing) ...[
                      SizedBox(width: 22, height: 22, child: CustomPaint(painter: FoodPreview(p))),
                      Text('$n ', style: style.copyWith(fontSize: 13, color: const Color(0xFFE53935))),
                    ],
                  ])),
            const Divider(),
            Align(alignment: Alignment.centerLeft, child: Text(S.t('day_tasks'), style: style.copyWith(fontSize: 13, color: Colors.black54))),
            for (final (t, ok) in r.tasks)
              row(
                  taskText(t),
                  ok
                      ? Coins(perTask, size: 14)
                      : const Icon(Icons.close_rounded, size: 18, color: Color(0xFFE53935))),
            if (r.bonus > 0) row(S.t('day_bonus'), Coins(r.bonus, size: 14)),
            if (r.warPrize > 0) row(S.t('war_won'), Coins(r.warPrize, size: 14)),
            if (r.warPrize < 0) row(S.t('war_lost'), const Icon(Icons.close_rounded, size: 18, color: Color(0xFFE53935))),
            if (r.chest > 0) _Chest(r.chest, r.jackpot),
            if (r.weekRank > 0)
              row(S.tn('week_done', {'n': r.weekRank}),
                  r.weekPrize > 0 ? Coins(r.weekPrize, size: 14) : const Icon(Icons.emoji_events_outlined, size: 18, color: Colors.black38)),
            if (r.goods > 0) row(S.t('day_goods'), Coins(-r.goods, size: 14)),
            if (r.wages > 0) row(S.t('day_wages'), Coins(-r.wages, size: 14)),
            row(S.t('day_cost'), Coins(-r.cost, size: 14)),
            if (r.quit != null)
              Text(S.t('day_quit'), style: style.copyWith(fontSize: 13, color: const Color(0xFFE53935))),
            if (r.aid > 0) row(S.t('day_aid'), Coins(r.aid, size: 14)),
            if (r.wasted > 0)
              Text(S.tn('day_wasted', {'n': r.wasted, 'v': r.wasteValue}),
                  style: style.copyWith(fontSize: 13, color: const Color(0xFF8D6E63))),
            const Divider(),
            row(S.t('day_profit'), Coins(r.profit, size: 18)),
          ]),
        ),
        actions: [
          Center(
            child: BubbleButton(S.t('btn_nice'), color: const Color(0xFF81C784), onTap: () => Navigator.pop(c)),
          ),
        ],
      ),
    );
    world.result = null;
  }

  /// 이번 주 동네 순위: 누르면 순위표.
  Widget _rankChip() {
    final rank = game.weekRank;
    final left = weekLength - game.weekDone;
    return GestureDetector(
      onTap: _showStandings,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          boxShadow: softShadow,
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.emoji_events_rounded, size: 16, color: Color(0xFFFFA000)),
          const SizedBox(width: 4),
          Text(S.tn('week_rank', {'n': rank, 'd': left}), style: const TextStyle(fontSize: 13, color: inkColor)),
        ]),
      ),
    );
  }

  void _showStandings() {
    final list = game.standings();
    final top = list.first.$2 <= 0 ? 1 : list.first.$2;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Text(S.t('week_title'), style: const TextStyle(fontSize: 20, color: inkColor))),
            Center(
              child: Text(S.tn('week_desc', {'d': weekLength - game.weekDone, 'p': (game.weekBase * weekPrizes[0] / 10).round() * 10}),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < list.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(fontSize: 18, color: Color(0xFFFFA000)))),
                  SizedBox(
                    width: 104,
                    child: Text(list[i].$1 == 'me' ? S.t('week_me') : S.t(list[i].$1),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: list[i].$1 == 'me' ? const Color(0xFFE65100) : inkColor)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (list[i].$2 / top).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: const Color(0xFFEEEEEE),
                        color: list[i].$1 == 'me' ? const Color(0xFFFF7043) : const Color(0xFF90A4AE),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 64, child: Align(alignment: Alignment.centerRight, child: Coins(list[i].$2, size: 13))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _goalCard() {
    final g = game.currentGoal;
    final ev = world.event;
    final style = const TextStyle(fontSize: 13, color: inkColor);
    String label(Goal g) => S.tn('goal_${g.kind.name}',
        {'n': g.kind == GoalKind.rating ? (g.target / 10).toStringAsFixed(1) : g.target});
    return IgnorePointer(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 230),
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 7),
          decoration: BoxDecoration(

            boxShadow: softShadow,
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inkColor.withValues(alpha: 0.6), width: 1.5),
          ),
          child: g == null
              ? Text(S.t('goal_all'), style: style)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.flag_rounded, size: 16, color: Color(0xFFE53935)),
                    const SizedBox(width: 4),
                    Flexible(child: Text(label(g), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 110,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (game.progress(g.kind) / g.target).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: const Color(0xFFEEEEEE),
                          color: const Color(0xFF66BB6A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Coins(g.reward, size: 12),
                  ]),
                ]),
        ),
        if (ev != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ev == EventKind.rush ? const Color(0xFFFFE0B2) : const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${S.t(ev == EventKind.rush ? 'event_rush' : 'event_vip')}  ${world.eventLeft.ceil()}s', style: style),
          ),
      ]),
    );
  }

  Widget _hud() {
    final need = xpToNext(game.level);
    return Row(children: [
      // 좁은 폰·긴 언어에서도 넘치지 않게: 레벨·별점·돈은 줄어들 수 있다
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        decoration: BoxDecoration(

          boxShadow: softShadow,
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: inkColor, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.tn('level_n', {'n': game.level}), style: const TextStyle(fontSize: 15, color: inkColor)),
          const SizedBox(height: 2),
          SizedBox(
            width: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: game.level >= maxLevel ? 1 : game.xp / need,
                minHeight: 6,
                backgroundColor: const Color(0xFFEEEEEE),
                color: const Color(0xFFFF7043),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 24),
      Text(game.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 18, color: inkColor)),
      const SizedBox(width: 12),
      Coins(game.money, size: 22),
          ]),
        ),
      ),
      ListenableBuilder(
        listenable: Settings.i,
        builder: (context, _) => IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Settings.i.music || Settings.i.sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: inkColor),
          onPressed: () {
            final on = !(Settings.i.music || Settings.i.sound);
            Settings.i.set(music: on, sound: on);
          },
        ),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.menu_rounded, color: inkColor),
        onPressed: _menu,
      ),
    ]);
  }

  List<Widget> _joystick() => [
        Positioned(
          left: _stickBase!.dx - 52,
          top: _stickBase!.dy - 52,
          child: IgnorePointer(
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.45),
                border: Border.all(color: inkColor.withValues(alpha: 0.5), width: 2),
              ),
            ),
          ),
        ),
        Positioned(
          left: _stickBase!.dx + _stick.dx - 28,
          top: _stickBase!.dy + _stick.dy - 28,
          child: IgnorePointer(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFB74D),
                border: Border.all(color: inkColor, width: 2.5),
              ),
            ),
          ),
        ),
      ];
}

/// 결과 창의 보물 상자: 누르면 열리며 상금을 보여 준다(돈은 하루가 끝날 때 이미 들어왔다).
class _Chest extends StatefulWidget {
  final int amount;
  final bool jackpot;
  const _Chest(this.amount, this.jackpot);

  @override
  State<_Chest> createState() => _ChestState();
}

class _ChestState extends State<_Chest> {
  bool open = false;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GestureDetector(
          onTap: () {
            if (open) return;
            setState(() => open = true);
            Sfx.cue(widget.jackpot ? 'fever' : 'chest', 0);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: open ? (widget.jackpot ? const Color(0xFFFFE082) : const Color(0xFFFFF8E1)) : const Color(0xFFFFECB3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFA000), width: 2),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TweenAnimationBuilder<double>(
                key: ValueKey(open),
                tween: Tween(begin: open ? 0.6 : 1, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, k, child) => Transform.scale(scale: k, child: child),
                child: Text(open ? (widget.jackpot ? '💎' : '🎁') : '🎁', style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: open
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                          child: Text(S.t(widget.jackpot ? 'chest_jackpot' : 'chest_open'),
                              style: const TextStyle(fontSize: 14, color: inkColor)),
                        ),
                        const SizedBox(width: 6),
                        Coins(widget.amount, size: 16),
                      ])
                    : Text(S.t('chest_tap'), style: const TextStyle(fontSize: 15, color: Color(0xFFE65100))),
              ),
            ]),
          ),
        ),
      );
}
