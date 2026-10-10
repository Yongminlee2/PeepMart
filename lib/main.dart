import 'package:flutter/material.dart';

import 'engine/game.dart';
import 'save.dart';
import 'strings.dart';
import 'ui/game_screen.dart';
import 'ui/sprites.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLang().load();
  await Sprites.load();
  final saved = await loadGame();
  runApp(PeepMartApp(saved));
}

class PeepMartApp extends StatelessWidget {
  final Game? saved;
  const PeepMartApp(this.saved, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Peep Mart',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Jua', colorSchemeSeed: const Color(0xFFFFB74D)),
        home: TitleScreen(saved),
      );
}

class TitleScreen extends StatelessWidget {
  final Game? saved;
  const TitleScreen(this.saved, {super.key});

  void _go(BuildContext context, Game g) =>
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(g)));

  @override
  Widget build(BuildContext context) {
    final s = saved;
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 220, height: 140, child: CustomPaint(painter: _TitleArt())),
          Text(S.t('app_name'), style: const TextStyle(fontSize: 52, color: inkColor)),
          const SizedBox(height: 32),
          if (s != null) ...[
            BubbleButton(S.t('btn_continue'), color: const Color(0xFF81C784), onTap: () => _go(context, s)),
            const SizedBox(height: 14),
            BubbleButton(S.t('btn_new_game'), onTap: () => _go(context, Game())),
          ] else
            BubbleButton(S.t('btn_start'), color: const Color(0xFF81C784), onTap: () => _go(context, Game())),
        ]),
      ),
    );
  }
}

class _TitleArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 4;
    canvas.scale(1.6);
    final cx = size.width / 2 / 1.6, cy = y / 1.6;
    Sprites.draw(canvas, customerChars[0], Offset(cx - 44, cy), Anim.idle, Facing.downRight, 0.3);
    Sprites.draw(canvas, playerChar, Offset(cx, cy + 4), Anim.yes, Facing.downLeft, 0.2);
    Sprites.draw(canvas, customerChars[3], Offset(cx + 44, cy), Anim.idle, Facing.downLeft, 0.6);
  }

  @override
  bool shouldRepaint(_TitleArt old) => false;
}
