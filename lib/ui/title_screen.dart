import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/game.dart';
import '../more_games.dart';
import '../save.dart';
import '../strings.dart';
import 'game_screen.dart';
import 'hub_screens.dart';
import 'more_games_screen.dart';
import 'settings_sheet.dart';
import 'sprites.dart';
import 'store_painter.dart';
import 'widgets.dart';

/// 첫 화면: 이어서 하기·새로 시작·동네 지도·단골 수첩·게임 방법·설정.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  Game? saved;
  bool loaded = false;

  bool _iosMoreGames = false;

  @override
  void initState() {
    super.initState();
    loadGame().then((g) => setState(() {
          saved = g;
          loaded = true;
        }));
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) _decideMoreGames();
  }

  /// 아이폰: 저장해 둔 목록으로 먼저 정하고, 하루에 한 번 새로 받아 다시 정한다.
  Future<void> _decideMoreGames() async {
    void apply(String? json) {
      if (json == null || !mounted) return;
      setState(() => _iosMoreGames = MoreGames.hasOthers(MoreGames.parse(json), ios: true));
    }

    apply(await MoreGames.cached());
    apply(await MoreGames.refreshIfStale());
  }

  void _go(Game g) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(g)));

  Future<void> _newGame() async {
    if (saved != null && !await confirm(context, S.t('reset_confirm'))) return;
    final g = Game();
    await saveGame(g);
    if (!mounted) return;
    await showIntro(context);
    _go(g);
  }

  /// 저장이 없으면 새 주인으로 연다(지도·수첩을 처음부터 볼 수 있게).
  Owner get _owner => (saved ?? Game()).owner;

  @override
  Widget build(BuildContext context) {
    final s = saved;
    Widget small(String key, IconData icon, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16), side: const BorderSide(color: inkColor, width: 2)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Icon(icon, color: const Color(0xFFFF9800)),
                    const SizedBox(height: 2),
                    Text(S.t(key), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: inkColor)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(children: [
          // 하늘에서 크림색으로, 아래엔 작은 동네
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0xFFDDF1FF), bg])),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, height: 320, child: CustomPaint(painter: TitleTown())),
          Align(
            alignment: const Alignment(0, -0.5),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 240, height: 150, child: CustomPaint(painter: _TitleArt())),
                Text(S.t('app_name'), style: const TextStyle(fontSize: 52, color: inkColor)),
                Text(S.t('tagline'), style: const TextStyle(fontSize: 15, color: Colors.black54)),
                const SizedBox(height: 26),
                if (!loaded)
                  const SizedBox(height: 56)
                else if (s != null) ...[
                  SizedBox(
                      width: 240,
                      child: BubbleButton(S.t('btn_continue'), color: const Color(0xFF81C784), onTap: () => _go(s))),
                  const SizedBox(height: 12),
                  SizedBox(width: 240, child: BubbleButton(S.t('btn_new_game'), onTap: _newGame)),
                ] else
                  SizedBox(
                      width: 240,
                      child: BubbleButton(S.t('btn_start'), color: const Color(0xFF81C784), onTap: _newGame)),
                const SizedBox(height: 20),
                Row(children: [
                  small('btn_map', Icons.map_rounded, () {
                    final o = _owner;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MapScreen(o, onEnter: (g) {
                              saveGame(g);
                              Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => GameScreen(g)), (_) => false);
                            })));
                  }),
                  small('btn_regulars', Icons.favorite_rounded,
                      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegularsScreen(_owner)))),
                  small('btn_dex', Icons.collections_bookmark_rounded,
                      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DexScreen(_owner)))),
                  small('btn_help', Icons.help_rounded,
                      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()))),
                ]),
              ]),
            ),
          ),
          // 안드로이드는 늘, 아이폰은 앱스토어에서 받을 다른 게임이 있을 때만(심사 지침 2.3.10). 웹은 없음.
          if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || _iosMoreGames))
            Align(
              alignment: const Alignment(0, 0.97),
              child: TextButton.icon(
                style: TextButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.9), elevation: 2),
                icon: const Icon(Icons.sports_esports_rounded, color: inkColor),
                label: Text(S.t('more_title'), style: const TextStyle(fontSize: 16, color: inkColor)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoreGamesScreen())),
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

/// 새 게임 첫 이야기: 점장이 된 사연 세 장.
Future<void> showIntro(BuildContext context) async {
  for (var page = 1; page <= 3; page++) {
    if (!context.mounted) return;
    final more = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: bg,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 90, height: 90, child: CustomPaint(painter: Portrait(playerChar, anim: page == 3 ? Anim.yes : Anim.idle))),
          const SizedBox(height: 10),
          Text(S.t('intro_$page'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: inkColor, height: 1.5)),
        ]),
        actions: [
          if (page < 3) TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.t('btn_skip'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(S.t(page < 3 ? 'btn_next' : 'btn_lets_go'))),
        ],
      ),
    );
    if (more != true) return;
  }
}

class _TitleArt extends CustomPainter {
  _TitleArt() : super(repaint: Sprites.loaded);

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
