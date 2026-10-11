/// 게임에 나오는 값 표. 밸런스는 여기만 고친다.
library;

import 'dart:math';

typedef Tile = (int, int);

// ------------------------------------------------------------------ 땅

const plotSize = 8; // 땅 한 필지 = 8×8 칸
const plotCols = 5, plotRows = 4; // 지도 = 40×32 칸
const mapW = plotSize * plotCols, mapH = plotSize * plotRows;

/// 지금 땅을 owned 필지 갖고 있을 때 다음 필지 값 (처음 땅은 갖고 시작).
int plotPrice(int owned) => (400 * pow(1.45, owned - 1)).round();

// ------------------------------------------------------------------ 상품

/// 진열대 종류. 상품마다 들어가는 진열대가 정해져 있다.
enum ShelfKind { rack, fridge, freezer, fruit, bakery, coffee, hot }

const shelfCapacity = {
  ShelfKind.rack: 8,
  ShelfKind.fridge: 6,
  ShelfKind.freezer: 6,
  ShelfKind.fruit: 8,
  ShelfKind.bakery: 6,
  ShelfKind.coffee: 6,
  ShelfKind.hot: 6,
};

class Product {
  final String id;
  final ShelfKind kind;
  final int price; // 손님이 내는 값 (= 얻는 경험치)
  final int level; // 이 가게 레벨부터 들여올 수 있다
  const Product(this.id, this.kind, this.price, this.level);

  /// 카페처럼 앉아서 먹고 가는 상품인가.
  bool get eatIn => kind == ShelfKind.bakery || kind == ShelfKind.coffee || kind == ShelfKind.hot;
}

const products = [
  Product('soda', ShelfKind.fridge, 3, 1),
  Product('donut', ShelfKind.rack, 3, 1),
  Product('noodles', ShelfKind.rack, 4, 2),
  Product('sandwich', ShelfKind.fridge, 6, 3),
  Product('icecream', ShelfKind.freezer, 5, 4),
  Product('fruit', ShelfKind.fruit, 4, 5),
  Product('banana', ShelfKind.fruit, 4, 5),
  Product('croissant', ShelfKind.bakery, 6, 6),
  Product('coffee', ShelfKind.coffee, 5, 7),
  Product('milk', ShelfKind.fridge, 5, 8),
  Product('cookie', ShelfKind.rack, 4, 8),
  Product('hotdog', ShelfKind.hot, 8, 9),
  Product('cake', ShelfKind.bakery, 12, 10),
  Product('muffin', ShelfKind.bakery, 7, 10),
  Product('watermelon', ShelfKind.fruit, 9, 11),
  Product('strawberry', ShelfKind.fruit, 6, 11),
  Product('burger', ShelfKind.hot, 10, 12),
  Product('frappe', ShelfKind.coffee, 8, 12),
  Product('bento', ShelfKind.fridge, 9, 13),
  Product('chocolate', ShelfKind.rack, 5, 13),
  Product('pizza', ShelfKind.hot, 12, 14),
  Product('cupcake', ShelfKind.bakery, 8, 14),
  Product('sundae', ShelfKind.freezer, 9, 15),
  Product('riceball', ShelfKind.rack, 10, 15),
  Product('fries', ShelfKind.hot, 7, 16),
  Product('tea', ShelfKind.coffee, 5, 16),
  Product('sushi', ShelfKind.fridge, 14, 18),
  Product('grapes', ShelfKind.fruit, 8, 18),
  Product('popsicle', ShelfKind.freezer, 6, 19),
  Product('pie', ShelfKind.bakery, 11, 20),
];

Product productById(String id) => products.firstWhere((p) => p.id == id);

// ------------------------------------------------------------------ 놓는 것

enum ItemKind { shelf, box, register, entrance, decor, seat, bin, floor }

class ItemType {
  final String id;
  final ItemKind kind;
  final int price;
  final int level;
  final ShelfKind? shelf; // 진열대일 때 받는 상품 종류
  final bool walkable; // 위로 지나갈 수 있나 (깔개·바닥·입구·의자)
  const ItemType(this.id, this.kind, this.price, this.level, {this.shelf, this.walkable = false});

  bool get needsProduct => kind == ItemKind.shelf || kind == ItemKind.box;
  bool get rotates => kind == ItemKind.register;
}

const itemTypes = [
  ItemType('rack', ItemKind.shelf, 40, 1, shelf: ShelfKind.rack),
  ItemType('fridge', ItemKind.shelf, 80, 1, shelf: ShelfKind.fridge),
  ItemType('freezer', ItemKind.shelf, 120, 4, shelf: ShelfKind.freezer),
  ItemType('fruitstand', ItemKind.shelf, 90, 5, shelf: ShelfKind.fruit),
  ItemType('bakerycase', ItemKind.shelf, 150, 6, shelf: ShelfKind.bakery),
  ItemType('coffeemachine', ItemKind.shelf, 160, 7, shelf: ShelfKind.coffee),
  ItemType('hotcounter', ItemKind.shelf, 220, 9, shelf: ShelfKind.hot),
  ItemType('box', ItemKind.box, 20, 1),
  ItemType('register', ItemKind.register, 100, 1),
  ItemType('entrance', ItemKind.entrance, 50, 3, walkable: true),
  ItemType('plant', ItemKind.decor, 15, 1),
  ItemType('flowers', ItemKind.decor, 25, 3),
  ItemType('lamp', ItemKind.decor, 30, 5),
  ItemType('rug', ItemKind.decor, 20, 3, walkable: true),
  ItemType('bin', ItemKind.bin, 25, 2),
  ItemType('chair', ItemKind.seat, 35, 7, walkable: true),
  ItemType('table', ItemKind.decor, 45, 7),
  ItemType('floor-pink', ItemKind.floor, 2, 1, walkable: true),
  ItemType('floor-mint', ItemKind.floor, 2, 1, walkable: true),
  ItemType('floor-blue', ItemKind.floor, 2, 2, walkable: true),
  ItemType('floor-wood', ItemKind.floor, 3, 4, walkable: true),
];

ItemType itemType(String id) => itemTypes.firstWhere((t) => t.id == id);

/// 계산대 방향: 계산하는 사람은 칸 + d, 손님은 칸 - d 에서 그 뒤로 줄을 선다.
const rotations = <Tile>[(1, 0), (0, 1), (-1, 0), (0, -1)];

// ------------------------------------------------------------------ 직원·업그레이드

enum Staff { cashier, stocker, janitor }

class StaffSpec {
  final int hire, wage, level, max; // wage: wagePeriod 마다
  const StaffSpec(this.hire, this.wage, this.level, this.max);
}

const staffSpecs = {
  Staff.cashier: StaffSpec(60, 4, 2, 20), // 계산대 수까지만 일한다
  Staff.stocker: StaffSpec(100, 6, 4, 8),
  Staff.janitor: StaffSpec(80, 5, 6, 4),
};

enum Upgrade { shoes, arms }

/// 단계별 (값, 필요 레벨).
const upgradeSteps = {
  Upgrade.shoes: [(100, 2), (400, 6), (1500, 12)],
  Upgrade.arms: [(80, 3), (500, 8), (2000, 14)],
};

// ------------------------------------------------------------------ 레벨

/// 다음 레벨까지 필요한 경험치. 팔린 물건값만큼 경험치가 쌓인다.
int xpToNext(int level) => (30 * pow(level, 1.6)).round();
const maxLevel = 30;

// ------------------------------------------------------------------ 움직임·시간

const playerSpeed = 3.0; // 칸/초, 신발 단계마다 25% 빨라진다
const customerSpeed = 2.2;
const staffSpeed = 2.4;
const startArms = 4; // 팔 단계마다 +2
const staffArms = 4;
const reach = 0.9; // 이만큼 가까우면 집거나 놓는다
const standRadius = 0.85; // 계산대 뒤에 이만큼 가까우면 올라선 것으로 친다
const moveStep = 0.12; // 물건 하나 옮기는 데 걸리는 초
const scanStepPlayer = 0.3;
const scanStepCashier = 0.5;
const shelfPatience = 20.0; // 빈 진열대 앞에서 기다리는 한계
const queuePatience = 40.0;
const pickTime = 0.5;
const sitTime = 5.0;
const startRating = 3.0;
const startMoney = 150;
const wagePeriod = 60.0; // 이만큼마다 일당을 낸다
const litterChance = 0.2; // 휴지통이 멀면 이 확률로 쓰레기를 버린다
const binRange = 5; // 이 칸 수 안에 휴지통이 있으면 안 버린다
const sellRefund = 0.5;
