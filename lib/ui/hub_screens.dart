import 'package:flutter/material.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../strings.dart';
import 'settings_sheet.dart';
import 'sprites.dart';
import 'store_painter.dart';
import 'widgets.dart';

/// 화면 위쪽 제목 줄이 있는 기본 틀.
class _Page extends StatelessWidget {
  final String title;
  final Widget body;
  const _Page(this.title, this.body);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          foregroundColor: inkColor,
          title: Text(title, style: const TextStyle(color: inkColor)),
        ),
        body: SafeArea(child: body),
      );
}

BoxDecoration _card([Color color = Colors.white]) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: inkColor, width: 2),
    );

// ------------------------------------------------------------------ 동네 지도

/// 지점 고르기. 열린 곳은 들어가고, 닫힌 곳은 레벨·값을 보여 주고 연다.
class MapScreen extends StatefulWidget {
  final Owner owner;
  final void Function(Game) onEnter;
  const MapScreen(this.owner, {super.key, required this.onEnter});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Owner get o => widget.owner;

  Future<void> _tap(Branch b) async {
    final open = o.branches.containsKey(b.id);
    if (!open) {
      if (o.level < b.level) return;
      if (o.money < b.price) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('no_money'))));
        return;
      }
      if (!await confirm(context, S.tn('open_branch', {'name': S.t('b_${b.id}'), 'n': b.price}))) return;
    }
    if (o.open(b.id) && mounted) widget.onEnter(o.game);
  }

  @override
  Widget build(BuildContext context) => _Page(
        S.t('btn_map'),
        ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [Text(S.tn('level_n', {'n': o.level}), style: const TextStyle(fontSize: 18, color: inkColor)), const Spacer(), Coins(o.money)]),
          const SizedBox(height: 12),
          for (final b in branches) _branchCard(b),
        ]),
      );

  Widget _branchCard(Branch b) {
    final th = themeOf(b.id);
    final open = o.branches.containsKey(b.id);
    final here = o.current == b.id;
    final locked = !open && o.level < b.level;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: locked ? null : () => _tap(b),
        child: Container(
          decoration: _card(locked ? const Color(0xFFEEEEEE) : Colors.white),
          clipBehavior: Clip.antiAlias,
          child: Row(children: [
            // 동네 색 미리보기
            Container(
              width: 92,
              height: 100,
              color: th.sky,
              child: Stack(alignment: Alignment.center, children: [
                Positioned(bottom: 10, child: Container(width: 70, height: 28, decoration: BoxDecoration(color: th.floorB, borderRadius: BorderRadius.circular(6)))),
                Positioned(top: 18, child: Container(width: 70, height: 34, decoration: BoxDecoration(color: th.wallR, border: Border(bottom: BorderSide(color: th.band, width: 6))))),
                if (locked) const Icon(Icons.lock_rounded, color: Colors.black45, size: 34),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.t('b_${b.id}'), style: const TextStyle(fontSize: 19, color: inkColor)),
                  Text(S.t('b_${b.id}_desc'), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 2, children: [
                    for (final p in b.featured.take(5)) SizedBox(width: 22, height: 22, child: CustomPaint(painter: FoodPreview(p))),
                  ]),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: here
                  ? Text(S.t('here'), style: const TextStyle(color: Color(0xFF43A047), fontSize: 15))
                  : open
                      ? const Icon(Icons.chevron_right_rounded, color: inkColor, size: 30)
                      : locked
                          ? Text(S.tn('level_n', {'n': b.level}), style: const TextStyle(color: Colors.black45))
                          : Coins(b.price, size: 15),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 단골 수첩

class RegularsScreen extends StatelessWidget {
  final Owner owner;
  const RegularsScreen(this.owner, {super.key});

  @override
  Widget build(BuildContext context) => _Page(
        S.t('btn_regulars'),
        ListView(padding: const EdgeInsets.all(16), children: [
          Text(S.t('regulars_hint'), style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 10),
          for (final r in regulars) _regularCard(context, r),
        ]),
      );

  Widget _regularCard(BuildContext context, Regular r) {
    final hearts = owner.heartsOf(r.id);
    final met = owner.level >= r.level && owner.branches.containsKey(r.branch);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: _card(met ? Colors.white : const Color(0xFFEEEEEE)),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 56, height: 56, child: CustomPaint(painter: Portrait(r.look, hidden: !met))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(met ? S.t('reg_${r.id}_name') : '???', style: const TextStyle(fontSize: 18, color: inkColor)),
                Text(met ? S.t('reg_${r.id}_intro') : S.tn('regular_where', {'name': S.t('b_${r.branch}'), 'n': r.level}),
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ]),
            ),
            Column(children: [
              Text('♥' * hearts + '♡' * (maxHearts - hearts), style: const TextStyle(color: Color(0xFFEC407A), fontSize: 15)),
              if (met) SizedBox(width: 26, height: 26, child: CustomPaint(painter: FoodPreview(r.favorite))),
            ]),
          ]),
          if (met) ...[
            const SizedBox(height: 8),
            for (var h = 1; h <= maxHearts; h++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h <= hearts ? '♥ ' : '♡ ', style: const TextStyle(color: Color(0xFFEC407A))),
                  Expanded(
                    child: Text(h <= hearts ? S.t('reg_${r.id}_h$h') : S.t('regular_locked'),
                        style: TextStyle(fontSize: 14, color: h <= hearts ? inkColor : Colors.black38)),
                  ),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}

/// 캐릭터 얼굴 그림. [hidden] 이면 까만 그림자.
class Portrait extends CustomPainter {
  final int look;
  final bool hidden;
  final Anim anim;
  Portrait(this.look, {this.hidden = false, this.anim = Anim.idle}) : super(repaint: Sprites.loaded);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height * 0.98)
      ..scale(size.width / 50);
    if (hidden) canvas.saveLayer(null, Paint()..colorFilter = const ColorFilter.mode(Colors.black54, BlendMode.srcIn));
    Sprites.draw(canvas, look, Offset.zero, anim, Facing.downLeft, 0.2);
    if (hidden) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(Portrait old) => old.look != look || old.hidden != hidden;
}

// ------------------------------------------------------------------ 게임 방법

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _topics = [
    ('move', Icons.touch_app_rounded),
    ('day', Icons.wb_sunny_rounded),
    ('rank', Icons.storefront_rounded),
    ('stock', Icons.inventory_2_rounded),
    ('checkout', Icons.point_of_sale_rounded),
    ('build', Icons.handyman_rounded),
    ('customers', Icons.star_rounded),
    ('staff', Icons.groups_rounded),
    ('levelup', Icons.keyboard_double_arrow_up_rounded),
    ('regulars', Icons.favorite_rounded),
    ('branches', Icons.map_rounded),
    ('goals', Icons.flag_rounded),
  ];

  @override
  Widget build(BuildContext context) => _Page(
        S.t('btn_help'),
        ListView(padding: const EdgeInsets.all(16), children: [
          for (final (key, icon) in _topics)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: _card(),
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: const Color(0xFFFF9800), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(S.t('help_${key}_t'), style: const TextStyle(fontSize: 17, color: inkColor)),
                      const SizedBox(height: 4),
                      Text(S.t('help_${key}_b'), style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.45)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      );
}

// ------------------------------------------------------------------ 게임 중 메뉴

enum MenuChoice { map, regulars, help, settings, title }

Future<MenuChoice?> showGameMenu(BuildContext context) => showModalBottomSheet<MenuChoice>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (m, icon, key) in const [
              (MenuChoice.map, Icons.map_rounded, 'btn_map'),
              (MenuChoice.regulars, Icons.favorite_rounded, 'btn_regulars'),
              (MenuChoice.help, Icons.help_rounded, 'btn_help'),
              (MenuChoice.settings, Icons.settings_rounded, 'settings_title'),
              (MenuChoice.title, Icons.home_rounded, 'btn_title'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: BubbleButton(S.t(key), color: Colors.white, trailing: Icon(icon, color: inkColor), onTap: () => Navigator.pop(c, m)),
                ),
              ),
          ]),
        ),
      ),
    );
