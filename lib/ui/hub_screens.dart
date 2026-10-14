import 'dart:math';

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
          const SizedBox(height: 16),
          Text(S.t('chain_title'), style: const TextStyle(fontSize: 20, color: inkColor)),
          Text(S.tn('chain_desc', {'n': (chainVisitors * 100).round(), 'd': o.chainDaily}),
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 8),
          for (final s in chainSpots) _chainCard(s),
        ]),
      );

  static const _chainIcons = {
    'school': Icons.school_rounded,
    'station': Icons.train_rounded,
    'hospital': Icons.local_hospital_rounded,
    'campus': Icons.account_balance_rounded,
    'office': Icons.business_rounded,
    'park': Icons.attractions_rounded,
    'airport': Icons.flight_rounded,
    'tower': Icons.location_city_rounded,
  };

  Widget _chainCard(ChainSpot s) {
    final lv = o.chainLevel(s.id);
    final locked = lv == 0 && o.level < s.level;
    final up = o.chainUpgradePrice(s);
    Widget button(Widget child, bool ok, VoidCallback onTap) => FilledButton.tonal(onPressed: ok ? onTap : null, child: child);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: _card(lv > 0 ? const Color(0xFFFFF8E1) : (locked ? const Color(0xFFEEEEEE) : Colors.white)),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: [
          Icon(_chainIcons[s.id], size: 32, color: locked ? Colors.black26 : const Color(0xFFFF8F00)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lv > 0 ? '${S.t('chain_${s.id}')}  Lv.$lv' : S.t('chain_${s.id}'),
                  style: TextStyle(fontSize: 16, color: locked ? Colors.black38 : inkColor)),
              Text(
                  locked
                      ? S.tn('need_level', {'n': s.level})
                      : S.tn('chain_income', {'n': chainIncome(s, lv == 0 ? 1 : lv)}),
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
          if (lv == 0 && !locked)
            button(Row(mainAxisSize: MainAxisSize.min, children: [Text('${S.t('chain_open')} '), Coins(s.cost, size: 13)]),
                o.money >= s.cost, () async {
              if (await confirm(context, S.tn('chain_open_q', {'name': S.t('chain_${s.id}'), 'n': s.cost})) && o.openChain(s)) {
                setState(() {});
              }
            })
          else if (up != null)
            button(Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.arrow_upward_rounded, size: 16), Coins(up, size: 13)]),
                o.money >= up, () => setState(() => o.upgradeChain(s)))
          else if (lv >= chainMaxLevel)
            const Icon(Icons.star_rounded, color: Color(0xFFFFC107)),
        ]),
      ),
    );
  }

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
                Positioned.fill(child: CustomPaint(painter: BranchThumb(b.id))),
                if (locked)
                  Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const Icon(Icons.lock_rounded, color: Colors.white, size: 34),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.t('b_${b.id}'), style: const TextStyle(fontSize: 19, color: inkColor)),
                  Text(S.t('b_${b.id}_desc'), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  if (branchRules.containsKey(b.id))
                    Text(S.t('b_${b.id}_rule'), style: const TextStyle(fontSize: 12, color: Color(0xFFE65100))),
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
    Sprites.drawPortrait(canvas, look, anim);
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
    ('weather', Icons.umbrella_rounded),
    ('incident', Icons.local_police_rounded),
    ('dex', Icons.collections_bookmark_rounded),
    ('combo', Icons.auto_awesome_rounded),
    ('fever', Icons.local_fire_department_rounded),
    ('extra', Icons.card_giftcard_rounded),
    ('fresh', Icons.local_offer_rounded),
    ('holiday', Icons.redeem_rounded),
    ('promo', Icons.campaign_rounded),
    ('cook', Icons.outdoor_grill_rounded),
    ('machines', Icons.point_of_sale_rounded),
    ('night', Icons.nightlight_round),
    ('week', Icons.emoji_events_rounded),
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

enum MenuChoice { map, people, regulars, story, dex, help, settings, title }

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
              (MenuChoice.people, Icons.diversity_1_rounded, 'btn_people'),
              (MenuChoice.regulars, Icons.favorite_rounded, 'btn_regulars'),
              (MenuChoice.story, Icons.auto_stories_rounded, 'btn_story'),
              (MenuChoice.dex, Icons.collections_bookmark_rounded, 'btn_dex'),
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

// ------------------------------------------------------------------ 도감

/// 손님 도감(만난 손님)과 상품 도장(많이 판 상품).
class DexScreen extends StatelessWidget {
  final Owner owner;
  const DexScreen(this.owner, {super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: inkColor,
            title: Text(S.t('btn_dex'), style: const TextStyle(color: inkColor)),
            bottom: TabBar(
              labelColor: inkColor,
              indicatorColor: const Color(0xFFFF9800),
              tabs: [
                Tab(text: S.tn('dex_people', {'n': owner.met.where(customerChars.contains).length, 'm': customerChars.length})),
                Tab(text: S.tn('dex_stamps', {'n': products.where((p) => (owner.sold[p.id] ?? 0) >= stampAt).length, 'm': products.length})),
                Tab(text: S.tn('dex_combos', {'n': owner.combosFound.length, 'm': combos.length})),
              ],
            ),
          ),
          body: SafeArea(child: TabBarView(children: [_people(), _stamps(), _combos()])),
        ),
      );

  Widget _people() {
    final n = owner.met.where(customerChars.contains).length;
    final next = (n ~/ meetEvery + 1) * meetEvery;
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text(next <= customerChars.length ? S.tn('dex_people_hint', {'n': next, 'r': meetReward(next ~/ meetEvery)}) : S.t('dex_people_done'),
          style: const TextStyle(fontSize: 13, color: Colors.black54)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 5,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final who in customerChars)
            Container(
              decoration: _card(owner.met.contains(who) ? Colors.white : const Color(0xFFEEEEEE)),
              child: CustomPaint(painter: Portrait(who, hidden: !owner.met.contains(who))),
            ),
        ],
      ),
    ]);
  }

  /// 진열 세트: 무엇을 붙여 놓으면 되는지 다 보여 준다(목표가 되도록).
  Widget _combos() => ListView(padding: const EdgeInsets.all(14), children: [
        Text(S.tn('dex_combos_hint', {'n': ((comboPrice - 1) * 100).round()}), style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 10),
        for (final k in combos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: _card(owner.combosFound.contains(k.id) ? const Color(0xFFFFF8E1) : Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Icon(owner.combosFound.contains(k.id) ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFFFC107)),
                const SizedBox(width: 8),
                Expanded(child: Text(S.t('combo_${k.id}'), style: const TextStyle(fontSize: 15, color: inkColor))),
                for (final p in k.products)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: owner.level >= productById(p).level
                        ? SizedBox(width: 30, height: 30, child: CustomPaint(painter: FoodPreview(p)))
                        : const SizedBox(width: 30, child: Text('?', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: Colors.black26))),
                  ),
              ]),
            ),
          ),
      ]);

  Widget _stamps() => ListView(padding: const EdgeInsets.all(14), children: [
        Text(S.tn('dex_stamps_hint', {'n': stampAt, 'm': stampPay}), style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.8,
          children: [
            for (final p in products) _stamp(p),
          ],
        ),
      ]);

  Widget _stamp(Product p) {
    final open = owner.level >= p.level;
    final n = owner.sold[p.id] ?? 0;
    final done = n >= stampAt;
    return Container(
      decoration: _card(done ? const Color(0xFFF3E5F5) : (open ? Colors.white : const Color(0xFFEEEEEE))),
      padding: const EdgeInsets.all(6),
      child: Column(children: [
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            if (open) CustomPaint(size: const Size(44, 44), painter: FoodPreview(p.id)) else const Text('?', style: TextStyle(fontSize: 26, color: Colors.black26)),
            if (done)
              Transform.rotate(
                angle: -0.3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFF7E57C2), width: 2), borderRadius: BorderRadius.circular(6)),
                  child: const Text('★', style: TextStyle(color: Color(0xFF7E57C2), fontSize: 16)),
                ),
              ),
          ]),
        ),
        Text(open ? S.t('p_${p.id}') : '???', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: inkColor)),
        Text(done ? '$stampAt/$stampAt' : '${min(n, stampAt)}/$stampAt', style: const TextStyle(fontSize: 10, color: Colors.black45)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ 삐약동 이야기

/// 이야기 한 편을 말풍선으로 한 줄씩 보여 준다.
Future<void> showChapter(BuildContext context, Chapter ch) async {
  var i = 0;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final who = ch.lines[i];
      final last = i == ch.lines.length - 1;
      return AlertDialog(
        backgroundColor: bg,
        title: Text(S.t('story_${ch.id}_t'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Colors.black45)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CustomPaint(painter: Portrait(npcLooks[who]!, anim: who == Npc.rival && i < ch.lines.length - 2 ? Anim.idle : Anim.yes)),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: _npcColor(who), borderRadius: BorderRadius.circular(10)),
            child: Text(S.t('npc_${who.name}'), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          Text(S.t('story_${ch.id}_$i'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: inkColor, height: 1.5)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < ch.lines.length; k++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: k <= i ? inkColor : Colors.black12),
              ),
          ]),
        ]),
        actions: [
          if (!last) TextButton(onPressed: () => Navigator.pop(c), child: Text(S.t('btn_skip'))),
          TextButton(
            onPressed: () => last ? Navigator.pop(c) : set(() => i++),
            child: Text(S.t(last ? 'btn_ok' : 'btn_next')),
          ),
        ],
      );
    }),
  );
}

Color _npcColor(Npc n) => switch (n) {
      Npc.me => const Color(0xFFFF9800),
      Npc.grandma => const Color(0xFFAB47BC),
      Npc.rival => const Color(0xFF546E7A),
      Npc.mayor => const Color(0xFF8D6E63),
      Npc.bori => const Color(0xFF43A047),
    };

/// 본 이야기를 다시 본다. 아직 못 본 건 여는 조건만 보여 준다.
class StoryScreen extends StatelessWidget {
  final Owner owner;
  const StoryScreen(this.owner, {super.key});

  @override
  Widget build(BuildContext context) => _Page(
        S.t('btn_story'),
        ListView(padding: const EdgeInsets.all(16), children: [
          Text(S.t('story_hint'), style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 10),
          for (final (n, ch) in chapters.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: owner.story.contains(ch.id) ? Colors.white : const Color(0xFFEEEEEE),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: inkColor, width: 2)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: owner.story.contains(ch.id) ? () => showChapter(context, ch) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      SizedBox(
                          width: 48,
                          height: 48,
                          child: CustomPaint(painter: Portrait(npcLooks[ch.lines.first]!, hidden: !owner.story.contains(ch.id)))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(S.tn('story_no', {'n': n + 1}), style: const TextStyle(fontSize: 12, color: Colors.black45)),
                          Text(owner.story.contains(ch.id) ? S.t('story_${ch.id}_t') : '???',
                              style: const TextStyle(fontSize: 17, color: inkColor)),
                          if (!owner.story.contains(ch.id))
                            Text(S.t('story_${ch.id}_when'), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ]),
                      ),
                      if (owner.story.contains(ch.id)) const Icon(Icons.play_circle_rounded, color: Color(0xFFFF9800)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}
