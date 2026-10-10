/// 게임에 나오는 값 표. 밸런스는 여기만 고친다.
library;

typedef Tile = (int, int);

enum ShelfKind { rack, fridge, freezer }

const shelfCapacity = {ShelfKind.rack: 8, ShelfKind.fridge: 6, ShelfKind.freezer: 6};

class Product {
  final String id;
  final ShelfKind kind;
  final int price; // 손님이 내는 값
  const Product(this.id, this.kind, this.price);
}

const products = [
  Product('soda', ShelfKind.fridge, 3),
  Product('chips', ShelfKind.rack, 3),
  Product('ramen', ShelfKind.rack, 4),
  Product('sandwich', ShelfKind.fridge, 6),
  Product('icecream', ShelfKind.freezer, 5),
  Product('fruit', ShelfKind.rack, 5),
  Product('bento', ShelfKind.fridge, 9),
  Product('cake', ShelfKind.fridge, 12),
];

Product productById(String id) => products.firstWhere((p) => p.id == id);

/// 바닥의 구매 칸에 서서 돈을 채우면 생기는 것. 이 순서대로 하나씩 열린다.
sealed class Unlock {
  final int price;
  const Unlock(this.price);
}

class NewProduct extends Unlock {
  final String product;
  const NewProduct(this.product, super.price);
}

class HireCashier extends Unlock {
  const HireCashier(super.price);
}

class HireStocker extends Unlock {
  const HireStocker(super.price);
}

class BiggerArms extends Unlock {
  const BiggerArms(super.price); // 한 번에 드는 개수 +2
}

class Expand extends Unlock {
  const Expand(super.price);
}

const startProducts = ['soda', 'chips'];

const unlocks = <Unlock>[
  NewProduct('ramen', 30),
  HireCashier(80),
  NewProduct('sandwich', 60),
  BiggerArms(60),
  HireStocker(150),
  NewProduct('icecream', 120),
  NewProduct('fruit', 160),
  Expand(400),
  NewProduct('bento', 300),
  NewProduct('cake', 450),
];

/// 가게 한 단계. 다음 단계의 상자·진열대 자리는 이전 단계를 전부 포함한다
/// (넓혀도 이미 놓인 것이 그 자리에 그대로 남는다).
class Layout {
  final int w, h;
  final Tile register; // 계산대
  final Tile till; // 계산하는 사람이 서는 칸(계산대 뒤)
  final Tile cash; // 돈이 쌓이는 칸
  final Tile door;
  final List<Tile> queue; // 맨 앞부터
  final List<Tile> crates; // 상품 상자 자리, 상품을 연 순서대로
  final List<Tile> shelves; // 진열대 자리, 상품을 연 순서대로
  final List<Tile> pads; // 상품이 아닌 구매 칸 자리
  const Layout({
    required this.w,
    required this.h,
    required this.register,
    required this.till,
    required this.cash,
    required this.door,
    required this.queue,
    required this.crates,
    required this.shelves,
    required this.pads,
  });
}

List<Tile> _col(int c, int r0, int r1) => [for (var r = r0; r <= r1; r++) (c, r)];
List<Tile> _row(int r, int c0, int c1) => [for (var c = c0; c <= c1; c++) (c, r)];

final layouts = [
  Layout(
    w: 8, h: 8,
    register: (6, 3), till: (7, 3), cash: (6, 2), door: (7, 7),
    queue: _col(5, 3, 6),
    crates: [..._row(0, 1, 4), ..._col(0, 1, 4)],
    shelves: [(2, 2), (3, 2), (2, 4), (3, 4), (2, 6), (3, 6)],
    pads: [(6, 5), (6, 6), (4, 7)],
  ),
  Layout(
    w: 11, h: 9,
    register: (9, 3), till: (10, 3), cash: (9, 2), door: (10, 8),
    queue: _col(8, 3, 7),
    crates: [..._row(0, 1, 7), ..._col(0, 1, 6)],
    shelves: [(2, 2), (3, 2), (2, 4), (3, 4), (2, 6), (3, 6), (5, 2), (6, 2), (5, 4), (6, 4), (5, 6), (6, 6)],
    pads: [(9, 5), (9, 6), (7, 8)],
  ),
];

const playerSpeed = 3.2; // 칸/초
const customerSpeed = 2.2;
const stockerSpeed = 2.4;
const startArms = 4; // 처음에 한 번에 드는 개수
const reach = 0.9; // 이만큼 가까우면 집거나 놓는다
const moveStep = 0.12; // 물건 하나 옮기는 데 걸리는 초
const scanStepPlayer = 0.3;
const scanStepCashier = 0.5;
const payPerSecond = 60.0; // 구매 칸에 서 있으면 초당 이만큼 낸다
const shelfPatience = 20.0; // 빈 진열대 앞에서 기다리는 한계
const queuePatience = 40.0;
const pickTime = 0.5;
const startRating = 3.0;
const maxCustomers = 10;
