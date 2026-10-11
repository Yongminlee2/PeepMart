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
  const GameScreen(this.game, {super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final World world = World(widget.game);
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
    if (building == null) {
      final target = iso(world.player.x, world.player.y);
      camera.center = Offset.lerp(camera.center, target, (dt * 5).clamp(0.0, 1.0))!;
    }
    for (final e in world.fx) {
      if (e.kind == FxKind.levelUp) {
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

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.localFocalPoint;
    _startZoom = camera.zoom;
    if (building == null && d.pointerCount == 1) {
      _stickBase = d.localFocalPoint;
      _touched = true;
      _setStick(Offset.zero);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      // 두 손가락: 확대·축소, 건설 중이면 옮기기도
      _release();
      camera.zoom = (_startZoom * d.scale).clamp(0.35, 2.2);
      if (building != null && _lastFocal != null) camera.center -= (d.localFocalPoint - _lastFocal!) / camera.zoom;
    } else if (building == null) {
      if (_stickBase != null) _setStick(d.localFocalPoint - _stickBase!);
    } else if (_lastFocal != null) {
      camera.center -= (d.localFocalPoint - _lastFocal!) / camera.zoom;
    }
    _lastFocal = d.localFocalPoint;
    final b = mapBounds;
    camera.center = Offset(camera.center.dx.clamp(b.left, b.right), camera.center.dy.clamp(b.top, b.bottom));
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
  }

  void _release() {
    _stickBase = null;
    _setStick(Offset.zero);
  }

  void _onTap(Offset local, Size size) {
    final b = building;
    if (b == null) return;
    final t = tileOf(camera.toWorld(local, size));
    if (b.land) {
      final plot = (t.$1 ~/ plotSize, t.$2 ~/ plotSize);
      if (t.$1 >= 0 && t.$2 >= 0 && game.plotsForSale.contains(plot)) _buyPlot(plot);
      return;
    }
    if (b.place != null) {
      b.hover = t;
      if (b.place == 'eraser') {
        if (game.sellFloor(t)) Sfx.play(FxKind.clean, clock);
        return;
      }
      final res = game.canPlace(b.place!, t, rot: b.rot);
      if (res == PlaceResult.ok) {
        game.place(b.place!, t, rot: b.rot, product: b.product);
        b.hover = null; // 놓았으면 미리보기는 지운다(그 칸은 이제 차 있어 빨갛게 보인다)
        Sfx.play(FxKind.place, clock);
      } else {
        toast(_reason(res, b.place!));
      }
      return;
    }
    b.selected = game.at(t);
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
                  final size = Size(c.maxWidth, c.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: (_) => _release(),
                    onTapUp: (d) => _onTap(d.localPosition, size),
                    child: CustomPaint(size: size, painter: StorePainter(world, flights, clock, camera, b)),
                  );
                }),
              ),
              Positioned(left: 8, right: 8, top: 6, child: _hud()),
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
                  child: Text(S.t('hint_move'), style: const TextStyle(fontSize: 16, color: Colors.black45)),
                ),
              if (_stickBase != null) ..._joystick(),
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton(
                  heroTag: 'build',
                  backgroundColor: b == null ? const Color(0xFFFFB74D) : const Color(0xFF81C784),
                  foregroundColor: inkColor,
                  onPressed: _toggleBuild,
                  child: Icon(b == null ? Icons.handyman_rounded : Icons.check_rounded, size: 30),
                ),
              ),
            ]),
          ),
          if (b != null) BuildPanel(game: game, view: b, onChanged: () => setState(() {}), toast: toast),
        ]),
      ),
    );
  }

  Widget _hud() {
    final need = xpToNext(game.level);
    return Row(children: [
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
      const Spacer(),
      Coins(game.money, size: 22),
      ListenableBuilder(
        listenable: Settings.i,
        builder: (context, _) => IconButton(
          icon: Icon(Settings.i.music || Settings.i.sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: inkColor),
          onPressed: () {
            final on = !(Settings.i.music || Settings.i.sound);
            Settings.i.set(music: on, sound: on);
          },
        ),
      ),
      IconButton(
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
