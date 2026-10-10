import 'catalog.dart';

/// 꺼도 남는 상태. 몇 초마다, 그리고 앱이 뒤로 갈 때 저장한다.
class Game {
  int money = 0;
  int level = 0;
  int cash = 0; // 계산대 옆에 쌓여 아직 안 주운 돈
  final Set<int> bought = {}; // 산 unlocks 번호
  final Map<int, int> paid = {}; // 구매 칸에 일부만 낸 돈
  final Map<String, int> stock = {for (final p in startProducts) p: shelfCapacity[productById(p).kind]!};
  final List<int> recent = []; // 최근 손님 만족도 0~5

  Layout get layout => layouts[level];

  bool get hasCashier => _has<HireCashier>();
  bool get hasStocker => _has<HireStocker>();
  int get arms => startArms + 2 * [for (final i in bought) unlocks[i]].whereType<BiggerArms>().length;

  bool _has<T>() => bought.any((i) => unlocks[i] is T);

  /// 상품 → 자리 번호. 자리 번호로 상자·진열대 위치가 정해진다.
  /// 연 순서와 상관없이 unlocks 표 순서로 고정이라 저장이 단순하다.
  static final Map<String, int> slotOf = {
    for (final (i, p) in startProducts.indexed) p: i,
    for (final (i, u) in unlocks.whereType<NewProduct>().indexed) u.product: startProducts.length + i,
  };

  List<String> get openProducts => [
        ...startProducts,
        for (final i in bought)
          if (unlocks[i] case NewProduct(:final product)) product,
      ];

  Tile shelfTile(String p) => layout.shelves[slotOf[p]!];
  Tile crateTile(String p) => layout.crates[slotOf[p]!];
  int capacity(String p) => shelfCapacity[productById(p).kind]!;

  double get rating =>
      recent.isEmpty ? startRating : recent.reduce((a, b) => a + b) / recent.length;

  void rate(int satisfaction) {
    recent.add(satisfaction.clamp(0, 5));
    if (recent.length > 20) recent.removeAt(0);
  }

  /// 지금 바닥에 떠 있는 구매 칸들: 아직 안 산 것 중 놓을 자리가 있는 앞의 두 개.
  List<(int, Tile)> get pads {
    final out = <(int, Tile)>[];
    var spot = 0;
    for (var i = 0; i < unlocks.length && out.length < 2; i++) {
      if (bought.contains(i)) continue;
      final u = unlocks[i];
      if (u is NewProduct) {
        final s = slotOf[u.product]!;
        if (s < layout.shelves.length) out.add((i, layout.shelves[s]));
      } else if (u is! Expand || level + 1 < layouts.length) {
        out.add((i, layout.pads[spot++]));
      }
    }
    return out;
  }

  /// 구매 칸에 돈을 넣는다. 다 채우면 산 것으로 치고 true.
  bool pay(int unlock, int amount) {
    final price = unlocks[unlock].price;
    final put = amount.clamp(0, money).clamp(0, price - (paid[unlock] ?? 0));
    money -= put;
    paid[unlock] = (paid[unlock] ?? 0) + put;
    if (paid[unlock]! < price) return false;
    paid.remove(unlock);
    bought.add(unlock);
    switch (unlocks[unlock]) {
      case NewProduct(:final product):
        stock[product] = capacity(product);
      case Expand():
        level++;
      default:
    }
    return true;
  }

  Map<String, Object> toJson() => {
        'money': money,
        'level': level,
        'cash': cash,
        'bought': bought.toList(),
        'paid': {for (final e in paid.entries) '${e.key}': e.value},
        'stock': stock,
        'recent': recent,
      };

  static Game fromJson(Map<String, dynamic> j) {
    final g = Game()
      ..money = j['money'] as int
      ..level = j['level'] as int
      ..cash = j['cash'] as int;
    g.bought.addAll((j['bought'] as List).cast<int>());
    g.paid.addAll({for (final e in (j['paid'] as Map).entries) int.parse(e.key as String): e.value as int});
    g.stock
      ..clear()
      ..addAll((j['stock'] as Map).cast<String, int>());
    g.recent.addAll((j['recent'] as List).cast<int>());
    return g;
  }
}
