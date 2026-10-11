import 'dart:io';

import 'package:flutter/material.dart';

import 'engine/catalog.dart';
import 'engine/game.dart';
import 'save.dart';
import 'settings.dart';
import 'strings.dart';
import 'ui/game_screen.dart';
import 'ui/more_games_screen.dart';
import 'ui/settings_sheet.dart';
import 'ui/sfx.dart';
import 'ui/sprites.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLang().load();
  await Settings.i.load();
  await Sprites.load();
  await Props.load(products.map((p) => p.id));
  await Sfx.load();
  await Music.init();
  runApp(const PeepMartApp());
}

class PeepMartApp extends StatelessWidget {
  const PeepMartApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: AppLang(),
        builder: (context, _, _) => MaterialApp(
          title: 'Peep Mart',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Jua', colorSchemeSeed: const Color(0xFFFFB74D)),
          home: const TitleScreen(),
        ),
      );
}

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  Game? saved;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    loadGame().then((g) => setState(() {
          saved = g;
          loaded = true;
        }));
  }

  void _go(Game g) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(g)));

  Future<void> _newGame() async {
    if (saved != null && !await confirm(context, S.t('reset_confirm'))) return;
    final g = Game();
    await saveGame(g);
    _go(g);
  }

  @override
  Widget build(BuildContext context) {
    final s = saved;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 240, height: 150, child: CustomPaint(painter: _TitleArt())),
              Text(S.t('app_name'), style: const TextStyle(fontSize: 52, color: inkColor)),
              const SizedBox(height: 32),
              if (!loaded)
                const SizedBox(height: 56)
              else if (s != null) ...[
                BubbleButton(S.t('btn_continue'), color: const Color(0xFF81C784), onTap: () => _go(s)),
                const SizedBox(height: 14),
                BubbleButton(S.t('btn_new_game'), onTap: _newGame),
              ] else
                BubbleButton(S.t('btn_start'), color: const Color(0xFF81C784), onTap: _newGame),
            ]),
          ),
          // 목록이 플레이 스토어 앱이라 안드로이드에서만 보인다.
          if (Platform.isAndroid)
            Align(
              alignment: const Alignment(0, 0.92),
              child: TextButton.icon(
                icon: const Icon(Icons.sports_esports_rounded, color: inkColor),
                label: Text(S.t('more_title'), style: const TextStyle(fontSize: 17, color: inkColor)),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoreGamesScreen())),
              ),
            ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              icon: const Icon(Icons.settings_rounded, color: inkColor, size: 30),
              onPressed: () => showSettings(context, onReset: _newGame),
            ),
          ),
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
    Props.food(canvas, 'donut', Offset(cx - 60, cy - 46), 16);
    Props.food(canvas, 'soda', Offset(cx + 62, cy - 50), 16);
  }

  @override
  bool shouldRepaint(_TitleArt old) => false;
}
