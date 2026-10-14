/// 게임에 나오는 값 표. 밸런스는 여기만 고친다.
library;

import 'dart:math';

typedef Tile = (int, int);

// ------------------------------------------------------------------ 땅

const plotSize = 8; // 땅 한 필지 = 8×8 칸
const plotCols = 5, plotRows = 4; // 지도 = 40×32 칸
const mapW = plotSize * plotCols, mapH = plotSize * plotRows;

/// 지금 땅을 owned 필지 갖고 있을 때 다음 필지 값 (처음 땅은 갖고 시작).
int plotPrice(int owned) => (1000 * pow(1.45, owned - 1)).round();

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
  final String? holiday; // 명절 한정 상품이면 그 명절 이름: 그날에만 손님이 찾는다
  const Product(this.id, this.kind, this.price, this.level, [this.holiday]);

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
  // 명절 한정: 그날에만 손님이 찾으니 전날 미리 진열해 둔다
  Product('lollipop', ShelfKind.rack, 5, 5, 'childrens'),
  Product('pepero', ShelfKind.rack, 6, 5, 'pepero'),
  Product('pear', ShelfKind.fruit, 12, 6, 'newyear'),
  Product('pumpkin', ShelfKind.fruit, 10, 8, 'halloween'),
  Product('xmascake', ShelfKind.bakery, 20, 10, 'christmas'),
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

// 값: 예전엔 진열대가 반나절 만에 본전을 뽑아 지을수록 눈덩이로 불어나서 2.5배(꾸미기 2배)로 올렸다.
const itemTypes = [
  ItemType('rack', ItemKind.shelf, 100, 1, shelf: ShelfKind.rack),
  ItemType('fridge', ItemKind.shelf, 200, 1, shelf: ShelfKind.fridge),
  ItemType('freezer', ItemKind.shelf, 300, 4, shelf: ShelfKind.freezer),
  ItemType('fruitstand', ItemKind.shelf, 225, 5, shelf: ShelfKind.fruit),
  ItemType('bakerycase', ItemKind.shelf, 375, 6, shelf: ShelfKind.bakery),
  ItemType('coffeemachine', ItemKind.shelf, 400, 7, shelf: ShelfKind.coffee),
  ItemType('hotcounter', ItemKind.shelf, 550, 9, shelf: ShelfKind.hot),
  ItemType('box', ItemKind.box, 50, 1),
  ItemType('register', ItemKind.register, 250, 1),
  ItemType('selfcheck', ItemKind.register, 700, 10), // 셀프 계산대: 손님이 알아서 찍는다, 가끔 오류
  ItemType('entrance', ItemKind.entrance, 125, 3, walkable: true),
  ItemType('plant', ItemKind.decor, 30, 1),
  ItemType('flowers', ItemKind.decor, 50, 3),
  ItemType('lamp', ItemKind.decor, 60, 5),
  ItemType('rug', ItemKind.decor, 40, 3, walkable: true),
  ItemType('bin', ItemKind.bin, 50, 2),
  ItemType('chair', ItemKind.seat, 70, 7, walkable: true),
  ItemType('table', ItemKind.decor, 90, 7),
  ItemType('claw', ItemKind.decor, 360, 6), // 인형뽑기: 지나가는 손님이 가끔 하고 간다
  ItemType('vending', ItemKind.decor, 400, 4), // 수익 기계들: 손님이 쓰면 돈, 가끔 고장
  ItemType('service', ItemKind.decor, 450, 6), // 서비스 카운터: 택배·복권 손님(점장이 처리)
  ItemType('atm', ItemKind.decor, 900, 8),
  ItemType('photo', ItemKind.decor, 1500, 12),
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
  Staff.cashier: StaffSpec(150, 14, 2, 20), // 계산대 수까지만 일한다
  Staff.stocker: StaffSpec(250, 18, 4, 8),
  Staff.janitor: StaffSpec(200, 12, 6, 4),
};

/// 알바 성격: 뽑을 때 정해진다. 빠름(25% 빨리), 졸음(가끔 졸아서 점장이 가서 깨워야 한다), 싹싹함(계산원이면 손님 만족 +1).
enum Trait { normal, quick, sleepy, cheerful }

const traitOdds = [4, 2, 2, 2]; // 뽑힐 무게 (Trait 차례)
const quickSpeed = 1.25;
const dozeChance = 0.015; // 졸음 알바가 일하다 1초마다 조는 확률
const wakeRange = 1.5;

/// 알바 숙련도: 직원 종류마다 일한 만큼 쌓이고, 레벨마다 10% 빨라진다(최대 5).
int staffLevel(int xp) => min(5, 1 + sqrt(xp / staffXpUnit).floor());
const staffXpUnit = 40;
double staffLevelSpeed(int level) => 1 + 0.1 * (level - 1);

enum Upgrade { shoes, arms, autoOrder }

/// 단계별 (값, 필요 레벨).
const upgradeSteps = {
  Upgrade.shoes: [(100, 2), (400, 6), (1500, 12)],
  Upgrade.arms: [(80, 3), (500, 8), (2000, 14)],
  Upgrade.autoOrder: [(3000, 15)], // 슈퍼마켓부터: 상자가 바닥나기 전에 저절로 주문(수수료 붙음)
};

// ------------------------------------------------------------------ 레벨

/// 다음 레벨까지 필요한 경험치. 팔린 물건값만큼 경험치가 쌓인다.
int xpToNext(int level) => 45 * level * level; // 피버 타임이 들어와 40 에서 올림(자동 플레이 레벨 20 이 110분 → 약 125분)
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
const wagePeriod = 40.0; // 이만큼마다 일당을 낸다
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
  Goal(GoalKind.shelves, 3, 20),
  Goal(GoalKind.served, 10, 20),
  Goal(GoalKind.cashiers, 1, 20),
  Goal(GoalKind.registers, 2, 25),
  Goal(GoalKind.level, 5, 37),
  Goal(GoalKind.plots, 2, 50),
  Goal(GoalKind.decor, 5, 37),
  Goal(GoalKind.stockers, 1, 50),
  Goal(GoalKind.products, 8, 75),
  Goal(GoalKind.rating, 45, 75),
  Goal(GoalKind.seats, 4, 75),
  Goal(GoalKind.level, 10, 125),
  Goal(GoalKind.plots, 4, 200),
  Goal(GoalKind.janitors, 1, 100),
  Goal(GoalKind.served, 500, 250),
  Goal(GoalKind.products, 15, 375),
  Goal(GoalKind.level, 15, 375),
  Goal(GoalKind.plots, 8, 750),
  Goal(GoalKind.products, 25, 1000),
  Goal(GoalKind.level, 20, 1250),
  Goal(GoalKind.plots, plotCols * plotRows, 5000),
  Goal(GoalKind.level, maxLevel, 7500),
];

// ------------------------------------------------------------------ 손님 종류·행사

/// 보통 / 급한 손님(참을성 절반, 팁 50%) / VIP(여러 개 사고 두 배로 낸다, 별점 4 이상일 때만).
enum CustomerKind { normal, hurry, vip, thief, lost, grumpy, inspector, service }

const hurryChance = 0.15;
const vipChance = 0.05;
const vipMinRating = 4.0;

/// 가끔 벌어지는 일. 레벨 3부터, 2~4분마다.
enum EventKind { rush, vip }

const eventLevel = 3;
const eventGap = (120.0, 240.0); // 다음 행사까지 (최소, 최대) 초
const rushTime = 30.0; // 손님 몰림이 이어지는 초
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
  Regular('mina', 'piyak', 58, 'donut', 1), // VRoid D (친해지기의 민아와 같은 사람)
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
int heartReward(int heart) => 20 * heart * heart;

// ------------------------------------------------------------------ 처음 안내

enum TutorialStep { pickBox, fillShelf, checkout, collect, build, done }

// ------------------------------------------------------------------ 하루 장사

/// 하루: 문을 열고 [dayLength] 초 동안 손님을 받는다. 시간이 다 되면 새 손님은 안 오고,
/// 남은 손님이 다 나가면 닫고 결과(별·보너스·할 일)를 보여 준다. 닫힌 동안은 느긋하게 짓는다.
const dayLength = 120.0;
const lastCall = 20.0; // 마감 전 이만큼은 손님이 더 몰린다
const lastCallFactor = 1.5;
const dayTargetShare = 1.0; // 첫날 목표 = 진열대가 늘 차 있을 때 벌 돈의 이만큼(× 처음 며칠 낮춤)
const dayTargetGrowth = 1.15; // 둘째 날부터 목표 = 최근 하루 평균의 1.15배 (평소만큼이면 별 하나, 더 잘해야 둘·셋)
const dayAverageWeight = 0.4; // 오늘이 평균에 얼마나 들어가나
const dayStars = [0.7, 1.0, 1.3]; // 목표의 이만큼 벌면 별 1·2·3개
const dayBonus = [0.0, 0.03, 0.05, 0.08]; // 별 개수별 보너스 (그날 번 돈 대비). 돈은 장사로 벌고 상금은 덤이 되게
const dayTaskReward = 0.04; // 할 일 하나 = 목표의 이만큼
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
const rankNight = 2; // 하루가 끝난 뒤 야간 영업

/// 야간 영업: 낮 장사가 끝나면 한 번 [nightLength] 초 더 열 수 있다. 손님은 [nightVisitors] 배로 적지만
/// 값을 [nightPay] 배로 받고, 도둑·진상 손님이 [nightIncidents] 번쯤 든다. 목표·별·할 일은 없다.
const nightLength = 60.0;
const nightVisitors = 0.8;
const nightPay = 1.4;
const nightIncidents = (2, 4);

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

/// 명절(동네 편의점부터 [holidayEvery] 일마다, 차례로): 손님이 [holidayVisitors] 배, 명절 상품이 잘 팔리고
/// 그날만 나오는 한정 상품을 찾는다. 가게 안에 명절 장식이 걸린다.
enum Holiday { newyear, childrens, halloween, pepero, christmas }

const rankHoliday = 1;
const holidayEvery = 8; // 4·12·20·28…일째
const holidayVisitors = 1.3;
const holidayPull = 0.5; // 손님이 한정 상품을 맨 먼저 찾을 확률
const holidayGoods = {
  Holiday.newyear: ['pear', 'fruit', 'tteokkochi', 'gimbap'],
  Holiday.childrens: ['lollipop', 'icecream', 'bananamilk', 'donut'],
  Holiday.halloween: ['pumpkin', 'chocolate', 'cookie', 'pie'],
  Holiday.pepero: ['pepero', 'chocolate', 'cookie'],
  Holiday.christmas: ['xmascake', 'cake', 'cupcake', 'strawberry'],
};
Product holidayProduct(Holiday h) => products.firstWhere((p) => p.holiday == h.name);

/// 홍보(문 닫힌 동안 다음 날 것을 고른다): 전단지는 손님 [flyerVisitors] 배(값 = 최근 하루 매출의 [flyerShare]),
/// 1+1 행사는 고른 상품을 사면 하나 더 준다(물건이 두 배로 나간다) — 손님이 그 상품을 찾아오고 조금 더 온다.
enum Promo { flyer, onePlusOne }

const flyerVisitors = 1.35;
const flyerShare = 0.25;
const flyerMin = 80;
const onePlusOneVisitors = 1.15;
const onePlusOnePull = 0.5;

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
const incidentWindow = (15.0, 100.0); // 하루 중 이 사이(초)에 일어난다 (하루 2분: 마감 몰림 전까지)
const thiefFine = 2; // 잡으면 훔친 값의 이만큼을 벌금으로
const thiefSpeed = 1.25; // 도망칠 때 손님 걸음의 이만큼 (플레이어보다는 느리다)
const catchRange = 1.1; // 이만큼 가까이 가면 잡는다/달랜다
const lostPatience = 35.0; // 길 잃은 아이가 기다리는 초
const lostReward = 0.05; // 아이를 찾아 주면 오늘 목표의 이만큼
const kidScale = 0.72;
const orderTime = 60.0; // 배달 주문 제한 시간
const orderPay = 2; // 배달은 값의 이만큼을 받는다

// ------------------------------------------------------------------ 도감

/// 손님 도감: 처음 보는 손님을 만나면 기록되고, [meetEvery] 명마다 상금.
const meetEvery = 10;
int meetReward(int milestone) => 50 * milestone; // milestone = 10명째 1, 20명째 2, ...

/// 상품 도장: 한 상품을 [stampAt] 개 팔면 도장과 상금(값 × [stampPay]).
const stampAt = 30, stampPay = 4;

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
int incidentsPerDay(int rank, int extra) => rank + 2 + extra;
/// 즉석 조리: 온장 진열대에 채운 건 날것이라 못 판다. 점장이 옆에 멈춰 서 있으면 [cookTime] 초마다 [cookBatch] 개씩 익는다.
/// 알바는 날것을 채우기만 하고 굽지는 못한다(온장 매니저가 있으면 익혀서 채운다). 알바를 다 둬도 점장 일이 남게.
const cookTime = 1.4;
const cookBatch = 2;

const breakableShelves = {ShelfKind.fridge, ShelfKind.freezer, ShelfKind.coffee, ShelfKind.hot}; // 고장 나는 전기 진열대
const repairTime = 1.2; // 고장 난 진열대 옆에 멈춰 서 있으면 이만큼 뒤 고친다
const grumpyPatience = 30.0; // 진상 손님이 참는 초
const grumpyAngerRate = 2; // 못 달래면 실망 손님으로 이만큼 센다
double patienceFactor(int rank) => 1 - 0.07 * rank; // 등급이 오를수록 손님이 덜 참는다
// 하루 운영비: 땅 한 필지 임대료 × (1 + 0.3 × 등급) + 진열대마다 관리비
const rentPerPlot = 24; // 첫 필지는 할머니 땅이라 임대료가 없다

/// 빚 막기: 하루 끝에 돈이 모자라면 알바 한 명이 그만두고, 그래도 [aidFloor] 아래면 할머니가 그만큼 채워 준다.
const aidFloor = 60;
const rentPerRank = 0.3;
const upkeepPerShelf = 6;

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

// ------------------------------------------------------------------ 피버 타임 (연속 계산 콤보)

/// 계산을 손님이 오는 간격의 [comboSlack] 배(6~14초) 안에 이어 가면 콤보가 쌓이고, [feverAt] 콤보면 피버 타임:
/// [feverTime] 초 동안 값 [feverPay] 배, 손님 [feverVisitors] 배. 실망한 손님이 나오면 콤보가 끊긴다.
/// (고정 6초로 하니 작은 가게는 손님 간격이 5~6초라 피버를 거의 못 봤다.)
const comboSlack = 2.2;
double comboWindow(double spawnGap) => (spawnGap * comboSlack).clamp(6.0, 14.0);
const feverAt = 15;
const feverTime = 15.0;
const feverPay = 1.3;
const feverVisitors = 1.4;

// ------------------------------------------------------------------ 위생 점검의 날

/// 동네 편의점부터 [inspectEvery] 일마다 점검관이 가게를 둘러보고 점수를 매긴다.
/// 100점에서 쓰레기·빈 진열대·고장마다 깎는다. 80점 이상 우수(상금), 50점 미만 불량(벌금).
const inspectEvery = 7;
const rankInspection = 1;
const inspectWindow = (35.0, 90.0); // 이 사이(초)에 온다
const inspectStops = 3; // 둘러보는 곳 수
const inspectTrash = 15, inspectEmpty = 10, inspectBroken = 20;
const inspectGood = 80, inspectBad = 50;
const inspectReward = 0.15, inspectFine = 0.2; // 오늘 목표 대비

// ------------------------------------------------------------------ 재고·재주문

/// 상자 하나에 [boxSize] 개. 꺼낼 때마다 줄고, 비면 다시 주문해야 한다(알바는 빈 상자로 못 채운다).
/// 주문은 도매가(판매가 × [wholesaleRate]) × [boxSize], [restockDelay] 초 뒤 도착. 매니저 코너도 한 개마다 도매가를 낸다.
const boxSize = 16;
const boxMax = boxSize * 2; // 주문이 쌓여도 상자에 이만큼까지
const wholesaleRate = 0.55; // 남는 건 45%: 많이 팔아야 남는다
const restockDelay = 20.0;
int wholesale(String product) => max(1, (productById(product).price * wholesaleRate).round());
int reorderCost(String product) => wholesale(product) * boxSize;

// ------------------------------------------------------------------ 단체 주문·가격 전쟁·보물 상자·인형뽑기

/// 단체 대량 주문(슈퍼마켓부터): 두 상품을 합쳐 [bulkCount] 개, [bulkTime] 초, 값의 [bulkPay] 배.
const bulkCount = (8, 12);
const bulkTime = 80.0;
const bulkPay = 2.5;

/// 메가마트 가격 전쟁 날(삐약동, 이야기 '길 건너 메가마트' 뒤 결말 전까지 [priceWarEvery] 일마다):
/// 손님이 값에 민감해지고(보통 +10%, 비싸게 +25%, 프리미엄 +30% 더 안 산다) 손님이 조금 줄어든다.
/// 별 둘 이상이면 이긴 것: 목표의 [priceWarPrize] 만큼 보너스.
const priceWarEvery = 6;
const priceWarBalk = [0.0, 0.10, 0.25, 0.30];
const priceWarVisitors = 0.85;
const priceWarPrize = 0.2;

/// 보물 상자: 별 둘 이상인 날 결과 창에서 연다. 상금은 오늘 목표 대비.
/// 별 둘: 5~10%, 별 셋: 10~20%, 별 셋이면 [chestJackpot] 확률로 대박(목표만큼).
const chestJackpot = 0.05;

/// 인형뽑기: 나가는 손님이 [clawRange] 칸 안에 있으면 [clawChance] 확률로 한 판([clawPlay] 원).
const clawRange = 5; // 계산을 마친 자리(계산대 앞)에서 잰다
const clawChance = 0.25;
const clawPlay = 3;

/// 수익 기계: 나가는 손님이 [clawRange] 칸 안에 있으면 (확률, 내는 돈). 쓸 때마다 [machineBreak] 확률로 고장 나서
/// 점장이 옆에 서서 고칠 때까지 돈을 못 번다(밤사이 기사가 고친다).
const machineSpecs = {
  'claw': (clawChance, clawPlay),
  'vending': (0.22, 4),
  'atm': (0.12, 8),
  'photo': (0.1, 14),
};
const machineBreak = 0.05;

/// 서비스 카운터: 있으면 손님이 올 때 [serviceChance] 확률로 물건 대신 택배·복권 손님이 온다.
/// 점장이 카운터 옆에 [serviceTime] 초 서 있으면 처리하고 수수료를 받는다(알바는 못 한다). [servicePatience] 초 넘게 기다리면 화내고 간다.
const serviceChance = 0.12;

/// 셀프 계산대: 계산원 없이 손님이 [selfScanTime] 초마다 하나씩 찍는다(계산원보다 느리다).
/// 손님마다 [selfError] 확률로 오류가 나서 멈추고, 점장이 옆에 서서 풀어 줘야 한다.
const selfScanTime = 0.8;
const selfError = 0.15;
const serviceTime = 1.8;
const servicePatience = 30.0;
const serviceFees = {'parcel': 9, 'lottery': 6};

// ------------------------------------------------------------------ 자동 발주·동네 규칙·끝없는 목표

/// 자동 발주: 상자가 [autoOrderAt] 개 아래면 저절로 주문한다. 값은 [autoOrderFee] 배(편한 대신 비싸다).
const autoOrderAt = 6;
const autoOrderFee = 1.25;

/// 동네마다 다른 규칙. 1 이면 보통.
class BranchRule {
  final double visitors, patience, vip, thief, breakdown, walk;
  const BranchRule({this.visitors = 1, this.patience = 1, this.vip = 1, this.thief = 1, this.breakdown = 1, this.walk = 1});
}

const branchRules = {
  'beach': BranchRule(visitors: 1.2, patience: 0.85), // 피서객이 많지만 성격이 급하다
  'night': BranchRule(vip: 2, thief: 2), // 큰손도 도둑도 많다
  'snow': BranchRule(walk: 0.85, breakdown: 2), // 눈길에 느리고, 추위에 기계가 자주 고장 난다
};
BranchRule ruleOf(String branch) => branchRules[branch] ?? const BranchRule();

/// 동네 매출 순위: 7일마다 동네 가게 넷과 그 주 매출을 겨룬다. 라이벌 매출 = 주 시작 때 내 하루 평균 × 7 × 배율(주마다 조금씩 출렁).
/// 1·2·3위면 내 하루 평균의 [weekPrizes] 배 상금. 1등을 하려면 평소보다 30% 넘게 벌어야 한다.
const weekLength = 7;
const rivalShops = [1.3, 1.1, 0.95, 0.75]; // rival_0 메가마트, rival_1 행복슈퍼, rival_2 골목상회, rival_3 24시 편의점
const weekPrizes = [0.5, 0.25, 0.1];

/// 큰 이벤트: 문을 열 때 [bigEventChance] 확률로 그날 하나(명절·야간엔 없음), [bigEventWindow] 사이에 벌어진다.
/// 아이돌 방문(스타삐약이 와서 팬이 몰린다, 친해지기가 열린다) · TV 촬영(찍는 동안 실망 손님 [tvMaxUpset] 이하면 상금과 다음 날 손님↑)
/// · 정전(전기 진열대가 다 꺼져서 하나씩 다시 켠다) · 관광버스(손님이 한꺼번에) · 유튜버(만족시키면 별점과 며칠 손님↑, 실망시키면 별점↓).
enum BigEvent { idol, tv, blackout, tour, youtuber }

const bigEventChance = 0.4;
const bigEventRank = {BigEvent.idol: 2, BigEvent.tv: 2, BigEvent.blackout: 1, BigEvent.tour: 3, BigEvent.youtuber: 1};
const bigEventWindow = (25.0, 70.0);
const idolFans = 25.0; // 아이돌이 오면 이만큼(초) 손님 몰림
const tvTime = 40.0, tvMaxUpset = 1, tvReward = 0.12;
const tourGroup = (8, 12);
const buzzVisitors = 1.2; // 방송·리뷰 효과가 남은 날 손님
const buzzDaysTv = 1, buzzDaysYoutube = 2;

/// 체인점: 레벨이 되면 동네 밖 자리(학교 앞·역 앞…)에 작은 점포를 연다. 직접 운영하지 않고 하루가 끝날 때마다 수익이 들어온다.
/// 레벨(1~[chainMaxLevel])을 올리면 수익이 50%씩 늘고, 체인점 하나마다 모든 가게 손님이 [chainVisitors] 늘어난다(브랜드).
/// 하루가 끝날 때 [chainBoomChance] 확률로 한 곳이 대박(그날 그 점포 수익 두 배).
class ChainSpot {
  final String id;
  final int level, cost, income;
  const ChainSpot(this.id, this.level, this.cost, this.income);
}

const chainSpots = [
  ChainSpot('school', 6, 1500, 120),
  ChainSpot('station', 9, 3500, 220),
  ChainSpot('hospital', 12, 6000, 320),
  ChainSpot('campus', 15, 10000, 450),
  ChainSpot('office', 18, 16000, 600),
  ChainSpot('park', 21, 25000, 800),
  ChainSpot('airport', 24, 40000, 1100),
  ChainSpot('tower', 27, 60000, 1500),
];
ChainSpot chainSpotById(String id) => chainSpots.firstWhere((s) => s.id == id);
const chainMaxLevel = 5;
const chainVisitors = 0.02;
const chainBoomChance = 0.12;
int chainUpgradeCost(ChainSpot s, int level) => (s.cost * 0.8 * level).round();
int chainIncome(ChainSpot s, int level) => level <= 0 ? 0 : (s.income * (1 + 0.5 * (level - 1))).round();

/// 목표를 다 이루면 끝없이 이어지는 목표: 그때부터 손님 [extraGoalStep] 명마다.
const extraGoalStep = 500;
int extraGoalReward(int i) => 1000 + 250 * i;

// ------------------------------------------------------------------ 땅 보너스·손님 장바구니

/// 땅을 넓힐수록 손님이 는다: 필지마다 [plotVisitors] (최대 [plotVisitorsMax] 필지분). 임대료가 오르는 만큼의 보람.
const plotVisitors = 0.06;
const plotVisitorsMax = 12;
double plotBonus(int plots) => plotVisitors * min(plots - 1, plotVisitorsMax);

/// 손님 한 명이 담는 개수: 보통 2~4개(같은 상품을 여러 개 사기도 한다). 진열대가 금방 빈다.
/// 한 손님이 사려는 개수: 1개부터, 파는 종류가 많을수록 많이 산다(한곳에서 다 사는 재미). 1~3개에서 4종마다 하나씩, 최대 6개.
const basketMin = 1, basketMax = 6;
int basketCap(int kinds) => min(basketMax, 3 + kinds ~/ 4);

/// 손님은 첫 물건은 가게에 있는 것(밖에서 보고 들어왔다), 나머지는 동네에서 찾는 상품(지금 레벨에서 열린 것)도 섞어 고른다.
/// 가게에 없는 상품은 못 팔고 지나간다 → 종류를 늘리고, 그러려면 진열대와 땅이 필요하다.
const carriedPull = 0.6; // 둘째 물건부터: 이 확률로 가게에 있는 것, 아니면 동네에서 찾는 것

// ------------------------------------------------------------------ 유통기한

/// 신선 상품(김밥·도시락·우유·빵 등)은 진열대에서 밤을 넘길 때마다 하루 늙고, [freshDays] 가 되면 남은 걸 버린다.
/// 진열대가 한 번 비면(다 팔리면) 날짜가 새로 시작한다. 하루 전(임박)엔 반값 스티커: 값 절반, 손님이 먼저 집는다.
const freshDays = 2;
const freshProducts = {
  'gimbap', 'sandwich', 'bananamilk', 'milk', 'bento', 'sushi', //
  'croissant', 'cake', 'muffin', 'cupcake', 'pie', 'xmascake',
};
bool isFresh(String? p) => freshProducts.contains(p);
const stickerPrice = 0.5;
const stickerPull = 0.5; // 손님이 반값 상품을 맨 먼저 집을 확률

/// 처음 안내 중에는 손님을 이만큼만(안내가 끝나야 1일째 시계가 가서, 그동안 돈이 끝없이 쌓이던 것).
const tutorialCustomers = 2;
