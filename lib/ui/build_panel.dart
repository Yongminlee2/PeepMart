import 'package:flutter/material.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../strings.dart';
import 'store_painter.dart';
import 'widgets.dart';

enum BuildTab { shelves, boxes, counters, decor, floors, land, staff, upgrades }

const _tabIcons = {
  BuildTab.shelves: Icons.shelves,
  BuildTab.boxes: Icons.inventory_2_rounded,
  BuildTab.counters: Icons.point_of_sale_rounded,
  BuildTab.decor: Icons.local_florist_rounded,
  BuildTab.floors: Icons.format_paint_rounded,
  BuildTab.land: Icons.landscape_rounded,
  BuildTab.staff: Icons.groups_rounded,
  BuildTab.upgrades: Icons.trending_up_rounded,
};

/// 건설 모드 아래쪽 판. 고르면 [BuildView] 를 바꾸고, 지도를 누르면 화면이 놓는다.
class BuildPanel extends StatefulWidget {
  final Game game;
  final BuildView view;
  final VoidCallback onChanged;
  final void Function(String) toast;
  const BuildPanel({super.key, required this.game, required this.view, required this.onChanged, required this.toast});

  @override
  State<BuildPanel> createState() => _BuildPanelState();
}

class _BuildPanelState extends State<BuildPanel> {
  BuildTab tab = BuildTab.shelves;
  String? shelfType; // 진열대를 고르고 상품을 고르는 중

  Game get game => widget.game;
  BuildView get v => widget.view;

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _setTab(BuildTab t) {
    tab = t;
    shelfType = null;
    v
      ..place = null
      ..product = null
      ..land = t == BuildTab.land
      ..selected = null;
    _changed();
  }

  void _startPlacing(String type, [String? product]) {
    v
      ..place = type
      ..product = product
      ..moving = null
      ..hover = null
      ..rot = 0
      ..selected = null;
    widget.toast(S.t(type == 'eraser' || type.startsWith('floor-') ? 'paint_hint' : 'drag_hint'));
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final sel = v.selected;
    return Container(
      decoration: const BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: inkColor, width: 2)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 높이를 고정해 둔다: 이 줄이 생겼다 없어지면 지도가 위아래로 들썩인다
        SizedBox(
          height: 48,
          child: sel != null
              ? _selectedBar(sel)
              : (v.place != null || v.moving != null)
                  ? _placingBar()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(S.t(v.land ? 'tab_land' : 'build_hint'),
                            style: const TextStyle(fontSize: 14, color: Colors.black45), overflow: TextOverflow.ellipsis),
                      ),
                    ),
        ),
        SizedBox(height: 132, child: _content()),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Row(children: [
            for (final t in BuildTab.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  avatar: Icon(_tabIcons[t], size: 18, color: inkColor),
                  label: Text(S.t('tab_${t.name}'), style: const TextStyle(color: inkColor)),
                  selected: tab == t,
                  selectedColor: const Color(0xFFFFCC80),
                  backgroundColor: Colors.white,
                  showCheckmark: false,
                  onSelected: (_) => _setTab(t),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- 위쪽 줄

  Widget _placingBar() {
    final mv = v.moving;
    final type = mv?.type ?? v.place!;
    final label = mv != null
        ? S.tn('moving', {'item': _name(mv.type, mv.product)})
        : type == 'eraser'
            ? S.t('eraser')
            : S.tn('placing', {'item': _name(type, v.product)});
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: inkColor), overflow: TextOverflow.ellipsis)),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: inkColor),
          onPressed: () {
            v
              ..place = null
              ..moving = null
              ..hover = null;
            _changed();
          },
        ),
      ]),
    );
  }

  Widget _selectedBar(Item i) {
    final refund = (i.t.price * sellRefund).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
      child: Row(children: [
        Expanded(
          child: Text(_name(i.type, i.product), style: const TextStyle(fontSize: 16, color: inkColor), overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: S.t('move'),
          icon: const Icon(Icons.open_with_rounded, color: inkColor),
          onPressed: () {
            v
              ..moving = i
              ..place = null
              ..rot = i.rot
              ..hover = i.tile
              ..selected = null;
            widget.toast(S.t('drag_hint'));
            _changed();
          },
        ),
        if (i.t.needsProduct)
          TextButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded, color: inkColor),
            label: Text(S.t('change_product'), style: const TextStyle(color: inkColor)),
            onPressed: () => _pickProduct(i.t, (p) {
              if (!game.setProduct(i, p)) widget.toast(S.t('occupied'));
              _changed();
            }),
          ),
        if (i.t.rotates)
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded, color: inkColor),
            onPressed: () {
              if (!game.rotate(i)) widget.toast(S.t('occupied'));
              _changed();
            },
          ),
        TextButton.icon(
          icon: const Icon(Icons.sell_rounded, color: Color(0xFFE53935)),
          label: Text('+$refund', style: const TextStyle(color: Color(0xFFE53935))),
          onPressed: () {
            if (game.sell(i)) {
              v.selected = null;
            } else {
              widget.toast(S.t('cant_sell'));
            }
            _changed();
          },
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: inkColor),
          onPressed: () {
            v.selected = null;
            _changed();
          },
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- 칸들

  Widget _content() => switch (tab) {
        BuildTab.shelves => _row([
            for (final t in itemTypes.where((t) => t.kind == ItemKind.shelf))
              _card(
                preview: ItemPreview(t.id),
                label: S.t('i_${t.id}'),
                price: t.price,
                lockedAt: game.unlockedItem(t) ? null : t.level,
                selected: v.place == t.id,
                onTap: () => _pickProduct(t, (p) => _startPlacing(t.id, p)),
              ),
          ]),
        BuildTab.boxes => _row([
            for (final p in products)
              _card(
                preview: ItemPreview('box', p.id),
                label: S.t('p_${p.id}'),
                price: itemType('box').price,
                lockedAt: game.unlockedProduct(p) ? null : p.level,
                selected: v.place == 'box' && v.product == p.id,
                onTap: () => _startPlacing('box', p.id),
              ),
          ]),
        BuildTab.counters => _types([ItemKind.register, ItemKind.entrance]),
        BuildTab.decor => _types([ItemKind.decor, ItemKind.seat, ItemKind.bin]),
        BuildTab.floors => _row([
            ...itemTypes.where((t) => t.kind == ItemKind.floor).map(_typeCard),
            _card(
              preview: null,
              icon: Icons.cleaning_services_rounded,
              label: S.t('eraser'),
              price: 0,
              selected: v.place == 'eraser',
              onTap: () => _startPlacing('eraser'),
            ),
          ]),
        BuildTab.land => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                game.plotsForSale.isEmpty ? S.t('land_all') : S.tn('land_hint', {'n': game.nextPlotPrice}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, color: inkColor),
              ),
            ),
          ),
        BuildTab.staff => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [for (final s in Staff.values) _staffRow(s)],
          ),
        BuildTab.upgrades => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [for (final u in Upgrade.values) _upgradeRow(u)],
          ),
      };

  Widget _types(List<ItemKind> kinds) => _row([...itemTypes.where((t) => kinds.contains(t.kind)).map(_typeCard)]);

  Widget _typeCard(ItemType t) => _card(
        preview: ItemPreview(t.id),
        label: S.t('i_${t.id}'),
        price: t.price,
        lockedAt: game.unlockedItem(t) ? null : t.level,
        selected: v.place == t.id,
        onTap: () => _startPlacing(t.id),
      );

  Widget _row(List<Widget> cards) => ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: cards,
      );

  Widget _card({
    required CustomPainter? preview,
    IconData? icon,
    required String label,
    required int price,
    int? lockedAt,
    bool selected = false,
    required VoidCallback onTap,
  }) {
    final locked = lockedAt != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: locked ? () => widget.toast(S.tn('need_level', {'n': lockedAt})) : onTap,
        child: Container(
          width: 88,
          decoration: BoxDecoration(
            color: locked ? const Color(0xFFEEEEEE) : (selected ? const Color(0xFFFFE0B2) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? const Color(0xFFFF9800) : inkColor, width: selected ? 3 : 1.5),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            Expanded(
              child: Opacity(
                opacity: locked ? 0.4 : 1,
                child: preview != null
                    ? CustomPaint(painter: preview, size: Size.infinite)
                    : Icon(icon, size: 40, color: inkColor),
              ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: inkColor)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: locked
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_rounded, size: 14, color: Colors.black45),
                      Text(S.tn('level_n', {'n': lockedAt}), style: const TextStyle(fontSize: 12, color: Colors.black45)),
                    ])
                  : Coins(price, size: 13),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _staffRow(Staff s) {
    final spec = staffSpecs[s]!;
    final locked = game.level < spec.level;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${S.t('staff_${s.name}')}  ×${game.count(s)}', style: const TextStyle(fontSize: 16, color: inkColor)),
            Text(locked ? S.tn('need_level', {'n': spec.level}) : S.tn('wage', {'n': spec.wage}),
                style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_rounded, color: inkColor),
          onPressed: game.count(s) == 0
              ? null
              : () {
                  game.fire(s);
                  _changed();
                },
        ),
        FilledButton.tonal(
          onPressed: game.canHire(s)
              ? () {
                  game.hire(s);
                  _changed();
                }
              : null,
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.add_rounded, size: 18), Coins(spec.hire, size: 14)]),
        ),
      ]),
    );
  }

  Widget _upgradeRow(Upgrade u) {
    final next = game.nextUpgrade(u);
    final steps = upgradeSteps[u]!.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${S.t('up_${u.name}')}  ${game.step(u)}/$steps', style: const TextStyle(fontSize: 16, color: inkColor)),
            Text(
              next == null
                  ? S.t('up_max')
                  : (game.level < next.$2 ? S.tn('need_level', {'n': next.$2}) : S.t('up_${u.name}_desc')),
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ]),
        ),
        if (next != null)
          FilledButton.tonal(
            onPressed: game.money >= next.$1 && game.level >= next.$2
                ? () {
                    game.buyUpgrade(u);
                    _changed();
                  }
                : null,
            child: Coins(next.$1, size: 14),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- 상품 고르기

  void _pickProduct(ItemType t, void Function(String) done) {
    final options = products.where((p) => t.kind == ItemKind.box || p.kind == t.shelf).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(S.tn('pick_product', {'item': S.t('i_${t.id}')}), style: const TextStyle(fontSize: 20, color: inkColor)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in options)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: game.unlockedProduct(p)
                      ? () {
                          Navigator.pop(c);
                          done(p.id);
                        }
                      : () => widget.toast(S.tn('need_level', {'n': p.level})),
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: game.unlockedProduct(p) ? Colors.white : const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: inkColor, width: 1.5),
                    ),
                    child: Column(children: [
                      Opacity(
                        opacity: game.unlockedProduct(p) ? 1 : 0.35,
                        child: SizedBox(width: 44, height: 44, child: CustomPaint(painter: FoodPreview(p.id))),
                      ),
                      Text(S.t('p_${p.id}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: inkColor)),
                      game.unlockedProduct(p)
                          ? Coins(p.price, size: 12)
                          : Text(S.tn('level_n', {'n': p.level}), style: const TextStyle(fontSize: 12, color: Colors.black45)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  String _name(String type, String? product) =>
      product == null ? S.t('i_$type') : '${S.t('i_$type')} · ${S.t('p_$product')}';
}
