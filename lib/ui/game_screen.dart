import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../engine/world.dart';
import '../save.dart';
import '../settings.dart';
import '../strings.dart';
import 'build_panel.dart';
import 'settings_sheet.dart';
import 'sfx.dart';
import 'store_painter.dart';
import 'widgets.dart';

class GameScreen extends StatefulWidget {
  final Game game;
  final World? world; // 시험에서 넣어 준다
  const GameScreen(this.game, {super.key, this.world});

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
    world.tick(dt);
    if (building == null && _follow) {
      final target = iso(world.player.x, world.player.y);
      camera.center = Offset.lerp(camera.center, target, (dt * 5).clamp(0.0, 1.0))!;
    }
    for (final e in world.fx) {
      if (e.kind == FxKind.goal) {
        toast(S.tn('goal_done', {'n': e.amount}));
        Sfx.play(FxKind.levelUp, clock);
      } else if (e.kind == FxKind.event) {
        toast(S.t(EventKind.values[e.amount] == EventKind.rush ? 'event_rush' : 'event_vip'));
        Sfx.play(FxKind.levelUp, clock);
      } else if (e.kind == FxKind.levelUp) {
        _levelUp(e.amount);
      } else {
        Sfx.play(e.kind, clock);
      }
      if (e.kind != FxKind.scan) flights.add(Flight(e));
    }
    world.fx.clear();
    for (final f in flights) {
      f.age += dt;
    }
    flights.removeWhere((f) => f.age > f.life);
    _toastLeft -= dt;
    _sinceSave += dt;
    if (_sinceSave > 5) {
      _sinceSave = 0;
      saveGame(game);
    }
    setState(() {});
  }

  void _levelUp(int level) {
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

  void toast(String text) {
    _toast = text;
    _toastLeft = 3;
  }

  // ---------------------------------------------------------------- 손가락

  bool get _useStick => Settings.i.joystick;

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
    final t = tileOf(camera.toWorld(local, _size));
    final b = building;
    if (b == null) {
      // 누른 곳으로 걸어가서 그 일을 한다
      _touched = true;
      _dest = world.walkPlayerTo(t);
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
      backgroundColor: const Color(0xFFDCEDC8),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: LayoutBuilder(builder: (context, c) {
                  _size = Size(c.maxWidth, c.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: (_) => _onScaleEnd(),
                    onTapUp: (d) => _onTap(d.localPosition),
                    child: CustomPaint(size: _size, painter: StorePainter(world, flights, clock, camera, b, dest: _dest)),
                  );
                }),
              ),
              Positioned(left: 8, right: 8, top: 6, child: _hud()),
              if (b == null) Positioned(left: 8, top: 58, child: _goalCard()),
              if (_toast != null && _toastLeft > 0)
                Align(
                  alignment: const Alignment(0, -0.62),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: inkColor, width: 2),
                      ),
                      child: Text(_toast!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: inkColor)),
                    ),
                  ),
                ),
              if (b == null && !_touched)
                Align(
                  alignment: const Alignment(0, 0.9),
                  child: Text(S.t(_useStick ? 'hint_move' : 'hint_tap'),
                      style: const TextStyle(fontSize: 16, color: Colors.black45)),
                ),
              if (b != null && b.ghostType != null && b.hover != null) Positioned(left: 0, right: 0, bottom: 14, child: _ghostButtons(b)),
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
              if (b == null || b.ghostType == null || b.hover == null) // 미리보기 단추와 겹치지 않게
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
                    Flexible(child: Text(label(g), style: style, overflow: TextOverflow.ellipsis)),
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
        icon: const Icon(Icons.settings_rounded, color: inkColor),
        onPressed: () => showSettings(context),
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
