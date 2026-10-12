import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/catalog.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';

void run(World w, double seconds) {
  for (var t = 0.0; t < seconds; t += 0.05) {
    w.tick(0.05);
  }
}

Game shop(int level) {
  final g = Game()
    ..money = 50000
    ..level = level;
  g.owner.tutorial = TutorialStep.done;
  return g;
}

/// 문 닫기: 시간을 다 쓰고 손님을 내보낸다.
void close(World w) {
  w.dayTime = dayLength;
  w.customers.clear();
  w.tick(0.01);
  w.customers.clear();
  w.tick(0.01);
}

Item first(Game g, String type) => g.items.firstWhere((i) => i.type == type);

void main() {
  test('유통기한: 신선 진열대는 밤마다 늙고 기한이 되면 버린다, 임박이면 반값 스티커', () {
    final g = shop(3);
    final fridge = first(g, 'fridge');
    expect(g.setProduct(fridge, 'gimbap'), isTrue);
    fridge.stock = 4;
    final w = World(g, seed: 1);
    expect(g.expiring(fridge), isFalse);
    w.openDay();
    close(w);
    expect(fridge.age, 1);
    expect(g.expiring(fridge), isTrue);
    final full = g.salePrice(fridge, 'gimbap');
    expect(g.toggleSticker(fridge), isTrue);
    expect(g.salePrice(fridge, 'gimbap'), (full * stickerPrice).round());
    w.result = null;
    w.openDay();
    close(w);
    expect(fridge.stock, 0);
    expect(fridge.sticker, isFalse);
    expect(w.result!.wasted, 4);
    // 신선하지 않은 상품은 늙지 않는다
    expect(first(g, 'rack').age, 0);
  });
}
