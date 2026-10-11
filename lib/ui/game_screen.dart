import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/game.dart';
import '../engine/world.dart';
import '../save.dart';
import '../settings.dart';
import '../strings.dart';
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
  Duration _last = Duration.zero;
  double clock = 0, _sinceSave = 0;
  Offset? _stickBase;
  Offset _stick = Offset.zero;
  bool _touched = false;
  Offset? _camera;

  static const _knobMax = 56.0;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
    _welcomeBack();
  }

  /// 꺼 둔 동안 알바가 번 돈을 계산대 옆 돈 더미에 얹고 알려 준다.
  void _welcomeBack() {
    if (game.savedAt == 0) return;
    final away = (DateTime.now().millisecondsSinceEpoch - game.savedAt) / 1000;
    final earned = game.offlineEarnings(away);
    if (earned <= 0) return;
    game.cash += earned;
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

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    clock += dt;
    world.tick(dt);
    // 플레이어 쪽으로 60%, 가게 가운데 쪽으로 40%: 계산대처럼 중요한 곳이 화면 밖으로 덜 나간다.
    final l = game.layout;
    final target = Offset.lerp(storeBounds(l).center, iso(world.player.x, world.player.y), 0.6)!;
    _camera = _camera == null ? target : Offset.lerp(_camera, target, (dt * 5).clamp(0.0, 1.0));
    for (final e in world.fx) {
      Sfx.play(e.kind, clock);
      if (e.kind != FxKind.scan) flights.add(Flight(e));
    }
    world.fx.clear();
    for (final f in flights) {
      f.age += dt;
    }
    flights.removeWhere((f) => f.age > f.life);
    _sinceSave += dt;
    if (_sinceSave > 5) {
      _sinceSave = 0;
      saveGame(game);
    }
    setState(() {});
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (e) => setState(() {
                _stickBase = e.localPosition;
                _touched = true;
                _setStick(Offset.zero);
              }),
              onPanUpdate: (e) => _setStick(e.localPosition - _stickBase!),
              onPanEnd: (_) => _release(),
              onPanCancel: _release,
              child: CustomPaint(painter: StorePainter(world, flights, clock, _camera ?? Offset.zero)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 10,
            child: Row(children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 26),
              Text(game.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 20, color: inkColor)),
              const Spacer(),
              Coins(game.money, size: 24),
              const SizedBox(width: 4),
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
            ]),
          ),
          if (!_touched)
            Align(
              alignment: const Alignment(0, 0.9),
              child: Text(S.t('hint_move'), style: const TextStyle(fontSize: 16, color: Colors.black45)),
            ),
          if (_stickBase != null) ...[
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
          ],
        ]),
      ),
    );
  }
}
