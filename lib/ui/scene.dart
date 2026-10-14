import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../strings.dart';
import 'hub_screens.dart' show Portrait;
import 'sprites.dart';
import 'widgets.dart';

/// 대화 장면의 배경.
enum SceneBg { store, cafe, beach, amusement, concert, ceremony }

/// 장면 대본이 부르는 것: 말하기와 묻기(고른 번호).
class SceneController {
  final _SceneScreenState _s;
  SceneController._(this._s);

  Future<void> say(int look, String name, String text, {bool smile = false}) => _s._show(look, name, text, smile, const []);

  Future<int> ask(int look, String name, String text, List<String> choices, {bool smile = false}) =>
      _s._show(look, name, text, smile, choices).then((v) => v ?? 0);
}

/// 연애 게임처럼: 배경 그림 + 큰 초상화 + 이름표와 대사 상자(한 글자씩), 선택지. 대본이 끝나면 닫힌다.
Future<void> playScene(BuildContext context, SceneBg bg, Future<void> Function(SceneController c) script) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, _, _) => _SceneScreen(bg, script),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));

class _SceneScreen extends StatefulWidget {
  final SceneBg bg;
  final Future<void> Function(SceneController c) script;
  const _SceneScreen(this.bg, this.script);

  @override
  State<_SceneScreen> createState() => _SceneScreenState();
}

class _SceneScreenState extends State<_SceneScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  int? _look;
  String _name = '', _text = '';
  bool _smile = false;
  List<String> _choices = const [];
  Completer<int?>? _wait;
  double _shown = 0; // 지금까지 보인 글자 수(한 글자씩)
  Timer? _type;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.script(SceneController._(this));
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _type?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<int?> _show(int look, String name, String text, bool smile, List<String> choices) {
    _type?.cancel();
    setState(() {
      _look = look;
      _name = name;
      _text = text;
      _smile = smile;
      _choices = choices;
      _shown = 0;
    });
    _type = Timer.periodic(const Duration(milliseconds: 28), (t) {
      if (!mounted) return t.cancel();
      setState(() => _shown += 1);
      if (_shown >= _text.length) t.cancel();
    });
    _wait = Completer<int?>();
    return _wait!.future;
  }

  bool get _typing => _shown < _text.length;

  void _tap() {
    if (_typing) {
      setState(() => _shown = _text.length.toDouble());
      return;
    }
    if (_choices.isEmpty) _done(null);
  }

  void _done(int? v) {
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.complete(v);
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, _) => CustomPaint(painter: _BgPainter(widget.bg, _anim.value * 60)),
              ),
            ),
            if (look != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 150,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('$look$_name'),
                    tween: Tween(begin: 0.9, end: 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    builder: (_, k, child) => Transform.scale(scale: k, alignment: Alignment.bottomCenter, child: child),
                    child: SizedBox(
                      width: 300,
                      height: 300,
                      child: CustomPaint(painter: Portrait(look, anim: _smile ? Anim.yes : Anim.idle)),
                    ),
                  ),
                ),
              ),
            Positioned(left: 12, right: 12, bottom: 16, child: SafeArea(top: false, child: _box())),
          ]),
        ),
      ),
    );
  }

  Widget _box() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_name.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 14, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFEC407A), borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
            child: Text(_name, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 110),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF48FB1), width: 3),
            boxShadow: softShadow,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_text.substring(0, min(_text.length, _shown.floor())),
                style: const TextStyle(fontSize: 17, color: inkColor, height: 1.5)),
            if (!_typing && _choices.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < _choices.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: const Color(0xFFFFF0F6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFEC407A), width: 1.5)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _done(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Text(_choices[i], style: const TextStyle(fontSize: 15, color: inkColor)),
                        ),
                      ),
                    ),
                  ),
                ),
            ] else if (!_typing)
              Align(
                alignment: Alignment.centerRight,
                child: Text('${S.t('scene_tap')} ▼', style: const TextStyle(fontSize: 12, color: Colors.black38)),
              ),
          ]),
        ),
      ]);
}

/// 장면 배경 그림(움직이는 것: 파도·관람차·조명·빛가루).
class _BgPainter extends CustomPainter {
  final SceneBg bg;
  final double t;
  _BgPainter(this.bg, this.t);

  void _sky(Canvas c, Size s, List<Color> cols, [double end = 0.7]) => c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: cols, stops: [0, end])
            .createShader(Offset.zero & s));

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    switch (bg) {
      case SceneBg.cafe:
        _sky(c, s, const [Color(0xFFFFE0B2), Color(0xFFD7A86E)]);
        // 창문과 하늘
        final win = Rect.fromLTWH(w * 0.12, h * 0.1, w * 0.76, h * 0.32);
        c.drawRRect(RRect.fromRectAndRadius(win, const Radius.circular(12)), Paint()..color = const Color(0xFF81D4FA));
        c.drawCircle(win.topRight + Offset(-w * 0.12, h * 0.08), 26, Paint()..color = const Color(0xFFFFF59D));
        for (var i = 0; i < 3; i++) {
          final x = (w * 0.2 + i * w * 0.25 + t * 6) % (win.width) + win.left;
          c.drawOval(Rect.fromCenter(center: Offset(x, win.top + h * (0.08 + 0.06 * i)), width: 70, height: 22),
              Paint()..color = Colors.white.withValues(alpha: 0.9));
        }
        c.drawRRect(RRect.fromRectAndRadius(win, const Radius.circular(12)),
            Paint()
              ..color = const Color(0xFF8D6E63)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8);
        c.drawLine(win.topCenter, win.bottomCenter, Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 6);
        // 매달린 전등
        for (final x in [0.25, 0.5, 0.75]) {
          final p = Offset(w * x, h * 0.05);
          c.drawLine(Offset(w * x, 0), p, Paint()..color = Colors.black54..strokeWidth = 2);
          c.drawCircle(p + const Offset(0, 8), 14, Paint()..color = const Color(0xFFFFCA28));
          c.drawCircle(p + const Offset(0, 8), 40, Paint()..color = const Color(0x33FFF59D));
        }
        // 나무 바닥과 탁자
        c.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.38), Paint()..color = const Color(0xFFA1887F));
        for (var i = 0; i < 8; i++) {
          c.drawLine(Offset(0, h * 0.62 + i * 40.0), Offset(w, h * 0.62 + i * 40.0), Paint()..color = const Color(0x22000000));
        }
        // (탁자·컵은 캐릭터 어깨에 걸려서 뺐다)
      case SceneBg.beach:
        _sky(c, s, const [Color(0xFF4FC3F7), Color(0xFFFFE0B2)], 0.55);
        c.drawCircle(Offset(w * 0.78, h * 0.18), 40, Paint()..color = const Color(0xFFFFF176));
        final sea = Path()..moveTo(0, h * 0.5);
        for (var x = 0.0; x <= w; x += 8) {
          sea.lineTo(x, h * 0.5 + sin(x / 30 + t * 1.5) * 5);
        }
        sea
          ..lineTo(w, h * 0.68)
          ..lineTo(0, h * 0.68)
          ..close();
        c.drawPath(sea, Paint()..color = const Color(0xFF0288D1));
        final foam = Path()..moveTo(0, h * 0.68);
        for (var x = 0.0; x <= w; x += 8) {
          foam.lineTo(x, h * 0.68 + sin(x / 22 + t * 2) * 6);
        }
        foam
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        c.drawPath(foam, Paint()..color = const Color(0xFFFFE9B0));
        // 파라솔
        final top = Offset(w * 0.15, h * 0.58);
        c.drawLine(top, top + const Offset(0, 90), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 4);
        for (var i = 0; i < 6; i++) {
          final a0 = pi + i * pi / 6, a1 = pi + (i + 1) * pi / 6;
          c.drawPath(
              Path()
                ..moveTo(top.dx, top.dy - 10)
                ..lineTo(top.dx + cos(a0) * 70, top.dy + 18 + sin(a0) * 6)
                ..lineTo(top.dx + cos(a1) * 70, top.dy + 18 + sin(a1) * 6)
                ..close(),
              Paint()..color = i.isEven ? const Color(0xFFEF5350) : Colors.white);
        }
      case SceneBg.amusement:
        _sky(c, s, const [Color(0xFF90CAF9), Color(0xFFE1F5FE)]);
        // 관람차
        final ctr = Offset(w * 0.68, h * 0.32);
        final r = min(w, h) * 0.26;
        final rim = Paint()
          ..color = const Color(0xFFEC407A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5;
        c.drawCircle(ctr, r, rim);
        const gond = [Color(0xFFFFCA28), Color(0xFF66BB6A), Color(0xFF42A5F5), Color(0xFFAB47BC)];
        for (var i = 0; i < 10; i++) {
          final a = t * 0.15 + i * 2 * pi / 10;
          final p = ctr + Offset(cos(a), sin(a)) * r;
          c.drawLine(ctr, p, Paint()..color = const Color(0xFFF8BBD0)..strokeWidth = 2);
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(0, 14), width: 22, height: 18), const Radius.circular(5)),
              Paint()..color = gond[i % gond.length]);
        }
        c.drawLine(ctr, ctr + Offset(-r * 0.6, h * 0.4), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 6);
        c.drawLine(ctr, ctr + Offset(r * 0.6, h * 0.4), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 6);
        // 롤러코스터 레일
        final rail = Path()..moveTo(0, h * 0.58);
        for (var x = 0.0; x <= w; x += 6) {
          rail.lineTo(x, h * 0.58 - sin(x / w * 2 * pi) * h * 0.1);
        }
        c.drawPath(rail, Paint()
          ..color = const Color(0xFFFF7043)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
        c.drawRect(Rect.fromLTWH(0, h * 0.66, w, h * 0.34), Paint()..color = const Color(0xFFA5D6A7));
        // 깃발 줄
        for (var i = 0; i < 12; i++) {
          final x = w * i / 11;
          c.drawPath(
              Path()
                ..moveTo(x - 10, h * 0.02)
                ..lineTo(x + 10, h * 0.02)
                ..lineTo(x, h * 0.02 + 18)
                ..close(),
              Paint()..color = gond[i % gond.length]);
        }
      case SceneBg.concert:
        _sky(c, s, const [Color(0xFF1A0033), Color(0xFF4A148C)]);
        // 무대 조명
        for (var i = 0; i < 4; i++) {
          final a = sin(t * 0.8 + i) * 0.35;
          final o = Offset(w * (0.15 + i * 0.23), 0);
          final beam = Path()
            ..moveTo(o.dx, o.dy)
            ..lineTo(o.dx + sin(a - 0.12) * h, h * 0.75)
            ..lineTo(o.dx + sin(a + 0.12) * h, h * 0.75)
            ..close();
          c.drawPath(beam, Paint()..color = [const Color(0x40F48FB1), const Color(0x4081D4FA), const Color(0x40FFF59D), const Color(0x40CE93D8)][i]);
        }
        c.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.06), Paint()..color = const Color(0xFF7B1FA2));
        // 관객 응원봉
        final rng = Random(3);
        for (var i = 0; i < 60; i++) {
          final x = rng.nextDouble() * w, y = h * (0.72 + rng.nextDouble() * 0.28);
          final bob = sin(t * 4 + i) * 4;
          c.drawLine(Offset(x, y + bob), Offset(x, y + 12 + bob), Paint()..color = Colors.white24..strokeWidth = 2);
          c.drawCircle(Offset(x, y + bob), 4,
              Paint()..color = [const Color(0xFFFF80AB), const Color(0xFF80D8FF), const Color(0xFFFFFF8D)][i % 3]);
        }
      case SceneBg.ceremony:
        _sky(c, s, const [Color(0xFFB71C1C), Color(0xFF880E4F)]);
        for (var i = 0; i < 10; i++) {
          c.drawRect(Rect.fromLTWH(w * i / 10, 0, w / 20, h * 0.7), Paint()..color = const Color(0x22000000));
        }
        c.drawRect(Rect.fromLTWH(0, h * 0.66, w, h * 0.34), Paint()..color = const Color(0xFF6D4C41));
        // 꽃가루
        final rng = Random(5);
        for (var i = 0; i < 70; i++) {
          final x = (rng.nextDouble() * w + sin(t + i) * 20) % w;
          final y = (rng.nextDouble() * h + t * 40 * (0.5 + rng.nextDouble())) % h;
          c.save();
          c.translate(x, y);
          c.rotate(t * 2 + i);
          c.drawRect(const Rect.fromLTWH(-4, -2, 8, 4),
              Paint()..color = [const Color(0xFFFFEB3B), const Color(0xFF81D4FA), const Color(0xFFF48FB1), Colors.white][i % 4]);
          c.restore();
        }
      case SceneBg.store:
        _sky(c, s, const [Color(0xFFFFF3E0), Color(0xFFFFE0B2)]);
        // 진열대 줄
        for (var row = 0; row < 3; row++) {
          final y = h * (0.12 + row * 0.15);
          c.drawRect(Rect.fromLTWH(0, y + 40, w, 8), Paint()..color = const Color(0xFFBC8A5F));
          final rng = Random(row);
          for (var x = 10.0; x < w; x += 26) {
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y + 14, 18, 26), const Radius.circular(4)),
                Paint()..color = [const Color(0xFFEF5350), const Color(0xFF66BB6A), const Color(0xFF42A5F5), const Color(0xFFFFCA28)][rng.nextInt(4)]);
          }
        }
        c.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.38), Paint()..color = const Color(0xFFFFF8E1));
        for (var i = 0; i < 12; i++) {
          for (var j = 0; j < 8; j++) {
            if ((i + j).isEven) {
              c.drawRect(Rect.fromLTWH(i * w / 12, h * 0.62 + j * 40.0, w / 12, 40), Paint()..color = const Color(0xFFFFECB3));
            }
          }
        }
    }
    // 은은한 빛가루
    final rng = Random(9);
    for (var i = 0; i < 18; i++) {
      final x = rng.nextDouble() * w, y = (rng.nextDouble() * h * 0.6 + sin(t * 0.7 + i) * 10);
      c.drawCircle(Offset(x, y), 2 + (i % 3).toDouble(), Paint()..color = Colors.white.withValues(alpha: 0.25 + 0.2 * sin(t * 2 + i)));
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t || old.bg != bg;
}
