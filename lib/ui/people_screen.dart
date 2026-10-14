import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../engine/people.dart';
import '../strings.dart';
import 'hub_screens.dart' show Portrait;
import 'settings_sheet.dart' show confirm;
import 'sprites.dart';
import 'store_painter.dart' show FoodPreview;
import 'widgets.dart';

/// 사람들: 견습생 키우기(프린세스 메이커식)와 친해지기(연애).
class PeopleScreen extends StatefulWidget {
  final Owner owner;
  final int tab;
  const PeopleScreen(this.owner, {super.key, this.tab = 0});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

BoxDecoration _box([Color color = Colors.white]) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: inkColor, width: 2),
      boxShadow: softShadow,
    );

class _PeopleScreenState extends State<PeopleScreen> {
  Owner get o => widget.owner;
  final _rng = Random();

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: widget.tab,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: inkColor,
            title: Text(S.t('btn_people'), style: const TextStyle(color: inkColor)),
            bottom: TabBar(
              labelColor: inkColor,
              indicatorColor: const Color(0xFFFF9800),
              tabs: [Tab(text: S.t('ppl_tab_trainee')), Tab(text: S.t('ppl_tab_date'))],
            ),
          ),
          body: TabBarView(children: [_trainee(), _dating()]),
        ),
      );

  // ---------------------------------------------------------------- 견습생 키우기

  Widget _trainee() {
    if (!o.hasTrainee) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(S.tn('tr_locked', {'n': traineeLevel}),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: inkColor)),
        ),
      );
    }
    final t = o.trainee;
    final name = S.t('tr_${t.name}');
    const style = TextStyle(fontSize: 14, color: inkColor);
    Widget bar(String label, int v, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 70, child: Text(label, style: style)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(value: v / 100, minHeight: 10, backgroundColor: const Color(0xFFEEEEEE), color: c),
              ),
            ),
            SizedBox(width: 36, child: Text('$v', textAlign: TextAlign.right, style: style)),
          ]),
        );
    const statColors = {
      TStat.stamina: Color(0xFF66BB6A),
      TStat.cook: Color(0xFFFF7043),
      TStat.kind: Color(0xFFEC407A),
      TStat.sense: Color(0xFF42A5F5),
      TStat.charm: Color(0xFFAB47BC),
    };
    final done = o.lessonDone;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        decoration: _box(),
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            SizedBox(width: 92, height: 92, child: CustomPaint(painter: Portrait(t.look, anim: done ? Anim.yes : Anim.idle))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 22, color: inkColor)),
                Text('${S.tn('tr_gen', {'n': t.generation + 1})}  ${S.t('tr_stage_${t.stage}')}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFFFF8F00))),
                const SizedBox(height: 4),
                Text(S.tn('tr_lessons', {'n': t.lessonsTaken, 'm': graduateAt}), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: min(1, t.lessonsTaken / graduateAt), minHeight: 6, backgroundColor: const Color(0xFFEEEEEE), color: const Color(0xFFFFB300)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          for (final s in TStat.values) bar(S.t('stat_${s.name}'), t.stat(s), statColors[s]!),
          bar(S.t('stat_stress'), t.stress, t.stress >= stressTired ? const Color(0xFFE53935) : const Color(0xFF90A4AE)),
          const SizedBox(height: 6),
          Text(
              S.tn('tr_effects', {
                'v': (traineeVisitors(t) * 100).round(),
                's': (traineeSatisfy(t) * 100).round(),
                'd': (traineeDiscount(t) * 100).round(),
                'a': (traineeStaffSpeed(t) * 100).round(),
              }),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(S.t(traineeCookEvery(t) != null ? 'tr_cook_on' : 'tr_cook_off'),
              style: TextStyle(fontSize: 12, color: traineeCookEvery(t) != null ? const Color(0xFFE65100) : Colors.black45)),
        ]),
      ),
      const SizedBox(height: 12),
      if (t.canGraduate)
        BubbleButton(S.t('tr_graduate'), color: const Color(0xFFFFD54F), onTap: _graduate)
      else ...[
        if (done)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(S.t('tr_done_today'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          ),
        for (final l in lessons) _lessonCard(l, done),
      ],
      if (o.graduates.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(S.t('tr_history'), style: const TextStyle(fontSize: 17, color: inkColor)),
        for (final (gen, e) in o.graduates)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${S.tn('tr_gen', {'n': gen})} ${S.t('tr_${traineeNames[(gen - 1) % traineeNames.length]}')}: ${S.t('end_${e.name}')}',
                style: style),
          ),
      ],
    ]);
  }

  Widget _lessonCard(Lesson l, bool done) {
    final cost = lessonCost(l, o.trainee.generation);
    final sulk = l.id != 'rest' && o.trainee.stress >= stressSulk;
    final ok = !done && o.money >= cost && !sulk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: ok ? Colors.white : const Color(0xFFEEEEEE),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: inkColor, width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: done
              ? () => _snack(S.t('tr_done_today'))
              : sulk
                  ? () => _snack(S.tn('tr_sulk', {'name': S.t('tr_${o.trainee.name}')}))
                  : (ok ? () => _lesson(l) : () => _snack(S.t('no_money'))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.t('lesson_${l.id}'), style: const TextStyle(fontSize: 16, color: inkColor)),
                  Text(S.t('lesson_${l.id}_d'), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
              Coins(cost, size: 14),
            ]),
          ),
        ),
      ),
    );
  }

  void _lesson(Lesson l) {
    final stageBefore = o.trainee.stage;
    final got = o.giveLesson(l, rng: _rng);
    if (got == null) {
      _snack(S.tn('tr_sulk', {'name': S.t('tr_${o.trainee.name}')}));
      return;
    }
    final list = [for (final e in got.entries) '${S.t('stat_${e.key.name}')} +${e.value}'].join(', ');
    _snack(S.tn('tr_gain', {'list': list.isEmpty ? S.t('lesson_rest') : list, 's': l.stress >= 0 ? '+${l.stress}' : '${l.stress}'}));
    if (o.trainee.stage > stageBefore) {
      _say(o.trainee.look, S.t('tr_${o.trainee.name}'), S.tn('tr_grow_${o.trainee.stage}', {'name': S.t('tr_${o.trainee.name}')}));
    }
    setState(() {});
  }

  Future<void> _graduate() async {
    final name = S.t('tr_${o.trainee.name}');
    final look = o.trainee.look;
    if (!await confirm(context, S.tn('tr_graduate_q', {'name': name}))) return;
    final e = o.graduate();
    if (e == null || !mounted) return;
    setState(() {});
    await _say(look, name, '${S.t('end_${e.name}')}!\n${S.t('end_${e.name}_d')}', title: S.t('tr_graduate'));
    if (!mounted) return;
    await _say(o.trainee.look, S.t('tr_${o.trainee.name}'), S.tn('tr_next', {'name': S.t('tr_${o.trainee.name}')}));
  }

  // ---------------------------------------------------------------- 친해지기

  Widget _dating() => ListView(padding: const EdgeInsets.all(16), children: [
        Text(S.tn('dt_today', {'n': o.actionsLeft, 'm': actionsPerDay}), style: const TextStyle(fontSize: 15, color: inkColor)),
        const SizedBox(height: 8),
        for (final d in datables) _dateCard(d),
      ]);

  Widget _dateCard(Datable d) {
    final metNow = o.metDate(d);
    final hearts = o.heartsOfDate(d.id);
    final lover = o.lover == d.id;
    Widget act(String key, IconData icon, VoidCallback? onTap, {Color color = Colors.white}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: inkColor, padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: onTap,
            icon: Icon(icon, size: 16),
            label: Text(S.t(key), style: const TextStyle(fontSize: 13)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: _box(lover ? const Color(0xFFFCE4EC) : (metNow ? Colors.white : const Color(0xFFEEEEEE))),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 64, height: 64, child: CustomPaint(painter: Portrait(d.look, hidden: !metNow, anim: lover ? Anim.yes : Anim.idle))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(metNow ? S.t('dt_${d.id}') : '???', style: const TextStyle(fontSize: 18, color: inkColor)),
                  if (lover) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFEC407A), borderRadius: BorderRadius.circular(10)),
                      child: Text(S.t('dt_lover'), style: const TextStyle(fontSize: 12, color: Colors.white)),
                    ),
                  ],
                ]),
                Text(
                    metNow
                        ? S.t('dt_${d.id}_role')
                        : (d.idol ? S.t('dt_locked_idol') : S.tn('dt_locked_level', {'n': d.level})),
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                Text('♥' * hearts + '♡' * (5 - hearts), style: const TextStyle(fontSize: 16, color: Color(0xFFEC407A))),
              ]),
            ),
            if (metNow)
              Column(children: [
                Text(S.t('dt_likes'), style: const TextStyle(fontSize: 10, color: Colors.black45)),
                Row(children: [for (final p in d.likes) SizedBox(width: 24, height: 24, child: CustomPaint(painter: FoodPreview(p)))]),
              ]),
          ]),
          if (lover)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(S.t('dt_${d.id}_perk'), style: const TextStyle(fontSize: 13, color: Color(0xFFAD1457))),
            ),
          if (metNow) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                act('dt_talk', Icons.chat_bubble_rounded, () => _talk(d)),
                act('dt_gift', Icons.card_giftcard_rounded, () => _gift(d)),
                act('dt_date', Icons.favorite_rounded, () => _date(d), color: hearts >= dateHearts ? const Color(0xFFF8BBD0) : const Color(0xFFEEEEEE)),
                if (hearts >= 5 && !lover) act('dt_confess', Icons.volunteer_activism_rounded, () => _confess(d), color: const Color(0xFFFFD54F)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  bool _canMeet() {
    if (o.actionsLeft > 0) return true;
    _snack(S.t('dt_none_left'));
    return false;
  }

  Future<void> _after(Datable d, (int, List<int>)? res, String line) async {
    if (res == null) return;
    setState(() {});
    final (n, hearts) = res;
    await _say(d.look, S.t('dt_${d.id}'), line);
    _snack(S.tn(n >= 0 ? 'dt_gain' : 'dt_loss', {'name': S.t('dt_${d.id}'), 'n': n}));
    for (final h in hearts) {
      if (!mounted) return;
      await _say(d.look, S.t('dt_${d.id}'), S.t('dt_${d.id}_h$h'), title: '♥' * h);
    }
  }

  Future<void> _talk(Datable d) async {
    if (!_canMeet()) return;
    final res = o.talk(d, rng: _rng);
    await _after(d, res, S.t('dt_${d.id}_talk${_rng.nextInt(3)}'));
  }

  Future<void> _gift(Datable d) async {
    if (!_canMeet()) return;
    final options = products.where((p) => p.holiday == null && o.level >= p.level).toList();
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(S.tn('dt_pick_gift', {'name': S.t('dt_${d.id}')}), style: const TextStyle(fontSize: 19, color: inkColor)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in options)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(c, p.id),
                  child: Container(
                    width: 76,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: inkColor, width: 1.2)),
                    child: Column(children: [
                      SizedBox(width: 36, height: 36, child: CustomPaint(painter: FoodPreview(p.id))),
                      Text(S.t('p_${p.id}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: inkColor)),
                      Coins(giftCost(p.id), size: 11),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (pick == null || !mounted) return;
    if (o.money < giftCost(pick)) {
      _snack(S.t('no_money'));
      return;
    }
    final res = o.gift(d, pick);
    final key = d.likes.contains(pick) ? 'gift_like' : (d.dislike == pick ? 'gift_dislike' : 'gift_normal');
    await _after(d, res, S.t(key));
  }

  Future<void> _date(Datable d) async {
    if (o.heartsOfDate(d.id) < dateHearts) {
      _snack(S.tn('dt_need_hearts', {'n': dateHearts}));
      return;
    }
    if (!_canMeet()) return;
    final place = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(S.tn('dt_pick_place', {'name': S.t('dt_${d.id}')}), style: const TextStyle(fontSize: 19, color: inkColor)),
            for (final e in datePlaces.entries)
              ListTile(
                leading: Icon(
                    switch (e.key) {
                      'cafe' => Icons.local_cafe_rounded,
                      'beach' => Icons.beach_access_rounded,
                      'amusement' => Icons.attractions_rounded,
                      _ => Icons.mic_rounded,
                    },
                    color: const Color(0xFFEC407A)),
                title: Text(S.t('place_${e.key}'), style: const TextStyle(color: inkColor)),
                trailing: Coins(e.value, size: 14),
                onTap: () => Navigator.pop(c, e.key),
              ),
          ]),
        ),
      ),
    );
    if (place == null || !mounted) return;
    if (o.money < datePlaces[place]!) {
      _snack(S.t('no_money'));
      return;
    }
    final res = o.date(d, place);
    await _after(d, res, d.place == place ? '${S.t('date_$place')}\n${S.t('date_fav')}' : S.t('date_$place'));
  }

  Future<void> _confess(Datable d) async {
    if (o.lover != null) {
      _snack(S.t('dt_has_lover'));
      return;
    }
    if (!o.confess(d)) return;
    setState(() {});
    await _say(d.look, S.t('dt_${d.id}'), '${S.t('dt_${d.id}_yes')}\n\n${S.t('dt_${d.id}_perk')}', title: '♥♥♥♥♥');
  }

  Future<void> _say(int look, String name, String text, {String? title}) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: bg,
          title: title == null ? null : Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFEC407A))),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 100, height: 100, child: CustomPaint(painter: Portrait(look, anim: Anim.yes))),
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFEC407A), borderRadius: BorderRadius.circular(10)),
              child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: inkColor, height: 1.5)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(S.t('btn_ok')))],
        ),
      );
}
