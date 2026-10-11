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
  Product('riceball', ShelfKind.rack, 4, 2),
  Product('gimbap', ShelfKind.fridge, 6, 2),
  Product('sandwich', ShelfKind.fridge, 6, 3),
  Product('bananamilk', ShelfKind.fridge, 4, 3),
  Product('icecream', ShelfKind.freezer, 5, 4),
  Product('fruit', ShelfKind.fruit, 4, 5),
  Product('banana', ShelfKind.fruit, 4, 5),
  Product('croissant', ShelfKind.bakery, 6, 6),
  Product('coffee', ShelfKind.coffee, 5, 7),
  Product('milk', ShelfKind.fridge, 5, 8),
  Product('cookie', ShelfKind.rack, 4, 8),
  Product('hotdog', ShelfKind.hot, 8, 9),
  Product('cupramen', ShelfKind.hot, 7, 9),
  Product('cake', ShelfKind.bakery, 12, 10),
  Product('muffin', ShelfKind.bakery, 7, 10),
  Product('tteokkochi', ShelfKind.hot, 6, 10),
  Product('watermelon', ShelfKind.fruit, 9, 11),
  Product('hoppang', ShelfKind.hot, 6, 11),
  Product('strawberry', ShelfKind.fruit, 6, 11),
  Product('burger', ShelfKind.hot, 10, 12),
  Product('frappe', ShelfKind.coffee, 8, 12),
  Product('bento', ShelfKind.fridge, 9, 13),
  Product('chocolate', ShelfKind.rack, 5, 13),
  Product('pizza', ShelfKind.hot, 12, 14),
  Product('cupcake', ShelfKind.bakery, 8, 14),
  Product('sundae', ShelfKind.freezer, 9, 15),
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
int xpToNext(int level) => 40 * level * level;
const maxLevel = 30;

// ------------------------------------------------------------------ 움직임·시간

const playerSpeed = 3.5; // 칸/초, 신발 단계마다 25% 빨라진다
const customerSpeed = 2.2;
const staffSpeed = 2.4;
const startArms = 4; // 팔 단계마다 +2
const staffArms = 4;
const reach = 1.2; // 이만큼 가까우면 집거나 놓는다 (대각선 옆 칸도 닿는다)
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

// ------------------------------------------------------------------ 목표

/// 하나씩 차례로 나오는 목표. 다 하면 상금을 받고 다음 목표가 나온다.
enum GoalKind { shelves, served, cashiers, registers, level, plots, decor, stockers, products, rating, seats, janitors }

class Goal {
  final GoalKind kind;
  final int target; // rating 은 별점×10 (45 = 4.5)
  final int reward;
  const Goal(this.kind, this.target, this.reward);
}

const goals = [
  Goal(GoalKind.shelves, 3, 50),
  Goal(GoalKind.served, 10, 60),
  Goal(GoalKind.cashiers, 1, 80),
  Goal(GoalKind.registers, 2, 100),
  Goal(GoalKind.level, 5, 150),
  Goal(GoalKind.plots, 2, 200),
  Goal(GoalKind.decor, 5, 150),
  Goal(GoalKind.stockers, 1, 200),
  Goal(GoalKind.products, 8, 300),
  Goal(GoalKind.rating, 45, 300),
  Goal(GoalKind.seats, 4, 300),
  Goal(GoalKind.level, 10, 500),
  Goal(GoalKind.plots, 4, 800),
  Goal(GoalKind.janitors, 1, 400),
  Goal(GoalKind.served, 500, 1000),
  Goal(GoalKind.products, 15, 1500),
  Goal(GoalKind.level, 15, 1500),
  Goal(GoalKind.plots, 8, 3000),
  Goal(GoalKind.products, 25, 4000),
  Goal(GoalKind.level, 20, 5000),
  Goal(GoalKind.plots, plotCols * plotRows, 20000),
  Goal(GoalKind.level, maxLevel, 30000),
];

// ------------------------------------------------------------------ 손님 종류·행사

/// 보통 / 급한 손님(참을성 절반, 팁 50%) / VIP(여러 개 사고 두 배로 낸다, 별점 4 이상일 때만).
enum CustomerKind { normal, hurry, vip, thief, lost, grumpy }

const hurryChance = 0.15;
const vipChance = 0.05;
const vipMinRating = 4.0;

/// 가끔 벌어지는 일. 레벨 3부터, 2~4분마다.
enum EventKind { rush, vip }

const eventLevel = 3;
const eventGap = (120.0, 240.0); // 다음 행사까지 (최소, 최대) 초
const rushTime = 40.0; // 손님 몰림이 이어지는 초
const rushFactor = 2.5; // 그동안 손님이 이만큼 자주 온다
const vipVisitors = 3; // VIP 방문 행사 때 연달아 오는 VIP 수

// ------------------------------------------------------------------ 가구 레벨업

const maxItemLevel = 5;

/// [level] → [level]+1 로 올리는 값.
int itemUpgradeCost(ItemType t, int level) => (t.price * 1.2 * pow(1.7, level)).round();

/// 진열대: 레벨마다 2칸 더 담고 15% 비싸게 판다. 계산대: 레벨마다 25% 빨리 찍는다.
int levelCapacity(int base, int level) => base + 2 * (level - 1);
double levelPrice(int level) => 1 + 0.15 * (level - 1);
double levelScan(int level) => 1 + 0.25 * (level - 1);

// ------------------------------------------------------------------ 매니저

/// 진열대 종류마다 한 명. 그 코너는 상자 없이 저절로 채워지고 10% 비싸게 팔며,
/// 꺼 둔 동안 버는 돈과 시간이 늘어난다.
class ManagerSpec {
  final ShelfKind kind;
  final int price, level;
  const ManagerSpec(this.kind, this.price, this.level);
}

const managers = [
  ManagerSpec(ShelfKind.rack, 400, 4),
  ManagerSpec(ShelfKind.fridge, 500, 5),
  ManagerSpec(ShelfKind.freezer, 900, 8),
  ManagerSpec(ShelfKind.fruit, 1100, 9),
  ManagerSpec(ShelfKind.bakery, 1800, 11),
  ManagerSpec(ShelfKind.coffee, 2400, 12),
  ManagerSpec(ShelfKind.hot, 3500, 14),
];

const managerRestock = 2.5; // 이만큼마다 그 코너의 가장 빈 진열대에 1개
const managerPrice = 1.1;
const offlineBaseHours = 2.0, offlineHoursPerManager = 1.0, offlineMaxHours = 8.0;

// ------------------------------------------------------------------ 동네(지점)

/// 지점마다 따로 짓고 키운다. 돈·레벨·단골은 함께 쓴다.
/// 대표 상품은 20% 비싸게 팔린다.
class Branch {
  final String id;
  final int level, price;
  final List<String> featured;
  const Branch(this.id, this.level, this.price, this.featured);
}

const branches = [
  Branch('piyak', 1, 0, ['soda', 'donut', 'gimbap', 'bananamilk']),
  Branch('beach', 10, 5000, ['icecream', 'popsicle', 'sundae', 'watermelon', 'soda']),
  Branch('night', 18, 30000, ['hotdog', 'cupramen', 'tteokkochi', 'pizza', 'fries']),
  Branch('snow', 25, 150000, ['coffee', 'tea', 'hoppang', 'cake', 'croissant']),
];

Branch branchById(String id) => branches.firstWhere((b) => b.id == id);
const featuredPrice = 1.2;

// ------------------------------------------------------------------ 단골손님

/// 이름과 이야기가 있는 손님. 좋아하는 상품을 부탁하고, 들어주면 친밀도(하트)가 오른다.
/// 하트마다 이야기 한 토막과 상금.
class Regular {
  final String id;
  final String branch;
  final int look; // 캐릭터 시트 번호
  final String favorite;
  final int level; // 이 레벨부터 찾아온다
  const Regular(this.id, this.branch, this.look, this.favorite, this.level);
}

const regulars = [
  Regular('mina', 'piyak', 0, 'donut', 1),
  Regular('jun', 'piyak', 10, 'sandwich', 3),
  Regular('sora', 'beach', 33, 'icecream', 10),
  Regular('taeo', 'beach', 8, 'watermelon', 12),
  Regular('rin', 'night', 1, 'pizza', 18),
  Regular('dal', 'night', 30, 'hotdog', 20),
  Regular('yuki', 'snow', 25, 'coffee', 25),
  Regular('bom', 'snow', 32, 'cake', 27),
];

Regular regularById(String id) => regulars.firstWhere((r) => r.id == id);
const maxHearts = 5;
const regularChance = 0.12; // 손님이 올 때 단골일 확률
const regularCooldown = 45.0; // 같은 단골이 다시 오기까지 초
int heartReward(int heart) => 80 * heart * heart;

// ------------------------------------------------------------------ 처음 안내

enum TutorialStep { pickBox, fillShelf, checkout, collect, build, done }

// ------------------------------------------------------------------ 하루 장사

/// 하루: 문을 열고 [dayLength] 초 동안 손님을 받는다. 시간이 다 되면 새 손님은 안 오고,
/// 남은 손님이 다 나가면 닫고 결과(별·보너스·할 일)를 보여 준다. 닫힌 동안은 느긋하게 짓는다.
const dayLength = 180.0;
const lastCall = 30.0; // 마감 전 이만큼은 손님이 더 몰린다
const lastCallFactor = 1.5;
const dayTargetShare = 1.0; // 첫날 목표 = 진열대가 늘 차 있을 때 벌 돈의 이만큼(× 처음 며칠 낮춤)
const dayTargetGrowth = 1.1; // 둘째 날부터 목표 = 최근 하루 평균의 1.1배 (평소만큼이면 별 하나, 더 잘해야 둘·셋)
const dayAverageWeight = 0.4; // 오늘이 평균에 얼마나 들어가나
const dayStars = [0.7, 1.0, 1.3]; // 목표의 이만큼 벌면 별 1·2·3개
const dayBonus = [0.0, 0.1, 0.2, 0.3]; // 별 개수별 보너스 (그날 번 돈 대비)
const dayTaskReward = 0.15; // 할 일 하나 = 목표의 이만큼
const calmLimit = 2; // "실망한 손님 n명 이하"

enum DayTaskKind { sell, serve, calm }

class DayTask {
  final DayTaskKind kind;
  final String product; // sell 일 때만
  final int n;
  const DayTask(this.kind, this.n, {this.product = ''});
}

// ------------------------------------------------------------------ 가게 등급

/// 레벨이 오르면 가게 등급이 오른다: 구멍가게 → 동네 편의점 → 큰 편의점 → 슈퍼마켓 → 대형마트 → 백화점.
/// 등급마다 손님이 조금 더 오고, 새 놀이가 하나씩 열린다(아래 rank* 상수).
const rankLevels = [1, 5, 10, 15, 20, 25];
int rankOf(int level) => rankLevels.lastIndexWhere((l) => level >= l);
const rankVisitorBonus = 0.08; // 등급마다 손님 8% 더
const rankWeather = 1; // 날씨 예보
const rankSpecialDay = 2; // 5일마다 특별한 날
const rankIncidents = 1; // 도둑·길 잃은 아이·고장
const rankGrumpy = 2; // 진상 손님
const rankDelivery = 3; // 배달 주문
const rankFestival = 4; // 특별한 날에 동네 축제가 끼어든다
const rankVip = 5; // VIP 가 두 배로 자주

// ------------------------------------------------------------------ 날씨·특별한 날

/// 날씨(동네 편의점부터): 그날 잘 팔리는 상품이 바뀐다. 문 열기 전에 예보로 보여 준다.
enum Weather { sunny, hot, rain, cold }

const weatherGoods = {
  Weather.sunny: <String>[],
  Weather.hot: ['icecream', 'popsicle', 'sundae', 'bananamilk', 'soda', 'frappe', 'watermelon', 'milk'],
  Weather.rain: ['cupramen', 'hoppang', 'tteokkochi', 'noodles', 'coffee', 'tea'],
  Weather.cold: ['hoppang', 'coffee', 'tea', 'cupramen', 'tteokkochi', 'croissant'],
};

/// 지점마다 날씨가 나올 무게 (맑음, 더움, 비, 추움). 바닷가는 덥고, 눈 동네는 춥다.
List<int> weatherOdds(String branch) => switch (branch) {
      'beach' => const [3, 4, 2, 1],
      'snow' => const [2, 0, 1, 5],
      _ => const [4, 2, 2, 2],
    };

/// 손님이 날씨·특별한 날 상품을 맨 먼저 집을 확률 (진열돼 있을 때).
const favoredPull = 0.5;
const rainVisitors = 0.9; // 비 오는 날은 손님이 조금 덜 온다

/// 특별한 날(큰 편의점부터 5일마다): 소풍날 → 시험 기간 → (대형마트부터) 동네 축제 차례로.
enum SpecialDay { picnic, exam, festival }

const specialEvery = 5;
const specialGoods = {
  SpecialDay.picnic: ['gimbap', 'riceball', 'sandwich', 'soda', 'bananamilk', 'fruit', 'banana'],
  SpecialDay.exam: ['riceball', 'cupramen', 'coffee', 'chocolate', 'gimbap', 'bananamilk'],
  SpecialDay.festival: ['tteokkochi', 'hotdog', 'soda', 'icecream', 'popsicle', 'fries'],
};
const picnicGroup = (2, 4); // 소풍날 한꺼번에 들어오는 손님 수 (최소, 최대)
const examHurry = 3.0; // 시험 기간엔 급한 손님이 이만큼 많다
const festivalVisitors = 1.6;
const festivalBonus = 2; // 축제 날 별 보너스 배수

// ------------------------------------------------------------------ 돌발 사건

/// 하루 동안 끼어드는 일(큰 편의점부터 도둑·길 잃은 아이, 슈퍼마켓부터 배달 주문).
const incidentWindow = (20.0, 150.0); // 하루 중 이 사이(초)에 일어난다
const thiefFine = 2; // 잡으면 훔친 값의 이만큼을 벌금으로
const thiefSpeed = 1.25; // 도망칠 때 손님 걸음의 이만큼 (플레이어보다는 느리다)
const catchRange = 1.1; // 이만큼 가까이 가면 잡는다/달랜다
const lostPatience = 45.0; // 길 잃은 아이가 기다리는 초
const lostReward = 0.1; // 아이를 찾아 주면 오늘 목표의 이만큼
const kidScale = 0.72;
const orderTime = 75.0; // 배달 주문 제한 시간
const orderPay = 2; // 배달은 값의 이만큼을 받는다

// ------------------------------------------------------------------ 도감

/// 손님 도감: 처음 보는 손님을 만나면 기록되고, [meetEvery] 명마다 상금.
const meetEvery = 10;
int meetReward(int milestone) => 300 * milestone; // milestone = 10명째 1, 20명째 2, ...

/// 상품 도장: 한 상품을 [stampAt] 개 팔면 도장과 상금(값 × [stampAt]).
const stampAt = 30;

// ------------------------------------------------------------------ 삐약동 이야기

/// 이야기에 나오는 사람: 나(점장), 가게를 물려준 할머니, 길 건너 메가마트 사장 강대장, 이장님, 알바생 보리.
enum Npc { me, grandma, rival, mayor, bori }

/// 이야기 한 편: 줄마다 말하는 사람. 글은 `story_{id}_{줄 번호}`, 제목은 `story_{id}_t`.
class Chapter {
  final String id;
  final List<Npc> lines;
  const Chapter(this.id, this.lines);
}

/// 차례대로 열린다. 여는 조건은 [Owner.chapterReady].
const chapters = [
  Chapter('opening', [Npc.grandma, Npc.grandma, Npc.rival, Npc.me, Npc.rival]),
  Chapter('rival', [Npc.bori, Npc.rival, Npc.me, Npc.bori]),
  Chapter('mayor', [Npc.mayor, Npc.mayor, Npc.bori, Npc.me]),
  Chapter('beach', [Npc.grandma, Npc.me, Npc.grandma]),
  Chapter('scheme', [Npc.bori, Npc.rival, Npc.me, Npc.mayor]),
  Chapter('night', [Npc.bori, Npc.rival, Npc.me]),
  Chapter('festival', [Npc.mayor, Npc.rival, Npc.bori, Npc.me, Npc.rival]),
  Chapter('snow', [Npc.mayor, Npc.bori, Npc.me]),
  Chapter('finale', [Npc.grandma, Npc.rival, Npc.rival, Npc.me, Npc.grandma, Npc.me]),
];

// ------------------------------------------------------------------ 어려움 (알바를 다 둬도 할 일이 남게)

/// 하루에 끼어드는 사건 수: 1 + 등급 (+0~1). 알바가 못 하는 일이라 가게가 커질수록 바빠진다.
int incidentsPerDay(int rank, int extra) => rank + 1 + extra;
const breakableShelves = {ShelfKind.fridge, ShelfKind.freezer, ShelfKind.coffee, ShelfKind.hot}; // 고장 나는 전기 진열대
const repairTime = 1.2; // 고장 난 진열대 옆에 멈춰 서 있으면 이만큼 뒤 고친다
const grumpyPatience = 30.0; // 진상 손님이 참는 초
const grumpyAngerRate = 2; // 못 달래면 실망 손님으로 이만큼 센다
double patienceFactor(int rank) => 1 - 0.06 * rank; // 등급이 오를수록 손님이 덜 참는다
// 하루 운영비: 땅 한 필지 임대료 × (1 + 0.3 × 등급) + 진열대마다 관리비
const rentPerPlot = 20;
const rentPerRank = 0.3;
const upkeepPerShelf = 3;

// ------------------------------------------------------------------ 진열 세트 (카이로소프트식 콤보)

/// 세 상품의 진열대를 가까이(서로 [comboRange] 칸 안) 두면 세트가 된다:
/// 세트 진열대는 값이 [comboPrice] 배, 세트 상품을 사는 손님은 [comboPull] 확률로 나머지도 함께 산다.
class Combo {
  final String id;
  final List<String> products;
  const Combo(this.id, this.products);
}

const combos = [
  Combo('snack', ['gimbap', 'tteokkochi', 'cupramen']),
  Combo('breakfast', ['sandwich', 'milk', 'coffee']),
  Combo('picnic', ['riceball', 'bananamilk', 'banana']),
  Combo('summer', ['icecream', 'popsicle', 'soda']),
  Combo('fastfood', ['burger', 'fries', 'soda']),
  Combo('bakery', ['croissant', 'muffin', 'tea']),
  Combo('dessert', ['cake', 'cupcake', 'frappe']),
  Combo('winter', ['hoppang', 'coffee', 'tea']),
  Combo('fruit', ['strawberry', 'grapes', 'watermelon']),
  Combo('lunchbox', ['bento', 'riceball', 'tea']),
  Combo('sweets', ['donut', 'cookie', 'chocolate']),
  Combo('latenight', ['hotdog', 'pizza', 'cupramen']),
];
const comboRange = 2;
const comboPrice = 1.2;
const comboPull = 0.4;

// ------------------------------------------------------------------ 가격표 (Supermarket Simulator 식)

/// 진열대마다 가격: 싸게·보통·비싸게·프리미엄. 비쌀수록 남지만 그냥 돌아가는 손님이 생기고, 싸면 손님이 좋아한다.
const priceLevels = [0.85, 1.0, 1.2, 1.4];
const priceBalk = [0.0, 0.0, 0.15, 0.35]; // 진열대 앞에서 값을 보고 안 사고 가는 확률
const defaultPrice = 1;

// ------------------------------------------------------------------ 팁

/// 아주 만족한 손님은 가끔 바닥에 팁을 두고 간다(직접 주워야 한다, 하루가 끝나면 사라진다).
const tipChance = 0.3;
const tipShare = 0.3; // 낸 값의 이만큼
const tipRange = 1.0;
