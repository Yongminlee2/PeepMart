/// 사람들: 견습생 키우기(프린세스 메이커식)와 친해지기(연애). 값 표와 규칙.
/// 상태는 [Owner] 가 들고([Trainee], 호감도), 효과는 [Game]·[World] 가 [Owner.perkOf] 등으로 본다.
library;

import 'dart:math';

import 'catalog.dart';

// ------------------------------------------------------------------ 견습생 키우기

/// 견습생 능력치. 0~100.
enum TStat { stamina, cook, kind, sense, charm }

/// 수업: 하루(닫힌 동안) 한 번. 돈을 내고 능력치가 오르고 스트레스가 쌓인다. 쉬기는 스트레스를 푼다.
class Lesson {
  final String id;
  final int cost;
  final Map<TStat, int> gain;
  final int stress;
  const Lesson(this.id, this.cost, this.gain, this.stress);
}

const lessons = [
  Lesson('cooking', 60, {TStat.cook: 7}, 9),
  Lesson('manners', 50, {TStat.kind: 7}, 7),
  Lesson('gym', 40, {TStat.stamina: 8}, 10),
  Lesson('study', 70, {TStat.sense: 7}, 9),
  Lesson('vocal', 80, {TStat.charm: 7}, 9),
  Lesson('practice', 0, {TStat.stamina: 2, TStat.cook: 2, TStat.kind: 2, TStat.sense: 2, TStat.charm: 2}, 6),
  Lesson('rest', 30, {}, -30),
];
Lesson lessonById(String id) => lessons.firstWhere((l) => l.id == id);

const traineeLevel = 4; // 이 레벨에 할머니가 견습생을 보낸다
const graduateAt = 30; // 수업(쉬기 빼고) 이만큼이면 졸업
const stressTired = 70; // 이 위면 수업 효과 절반
const stressSulk = 90; // 이 위면 쉬기 말고는 안 한다
const traineeNames = ['saessak', 'kkomul', 'kongal', 'bangul', 'dotori'];
const traineeLooks = [33, 35, 29, 37, 47]; // 캐릭터 시트 번호(lib/ui/sprites.dart characterFiles)

/// 기수가 올라갈수록 수업료가 오른다.
int lessonCost(Lesson l, int generation) => (l.cost * (1 + 0.5 * generation)).round();

/// 졸업 진로: 가장 높은 능력치로 정해지고, 다 60 이상이면 전설. 진로마다 가게에 영원한 덤이 붙는다(기수마다 쌓인다).
enum Ending { legend, idol, chef, host, ceo, courier }

const endingVisitors = {Ending.legend: 0.05, Ending.idol: 0.08};
const legendPrice = 1.05;
const chefPrice = 1.15; // 온장·빵 값
const hostChance = 0.3; // 손님 만족 +1
const ceoChain = 1.3; // 체인점 수익
const courierSpeed = 1.15; // 점장 걸음
const courierPay = 1.3; // 배달 값

class Trainee {
  int generation = 0;
  final Map<TStat, int> stats = {for (final s in TStat.values) s: 0};
  int stress = 0, lessonsTaken = 0;
  String lessonKey = ''; // 마지막으로 수업한 날

  String get name => traineeNames[generation % traineeNames.length];
  int get look => traineeLooks[generation % traineeLooks.length];
  int stat(TStat s) => stats[s] ?? 0;
  int get stage => min(2, lessonsTaken ~/ 10); // 0 새내기, 1 견습, 2 수석 견습
  bool get canGraduate => lessonsTaken >= graduateAt;

  Ending get ending {
    if (TStat.values.every((s) => stat(s) >= 60)) return Ending.legend;
    final top = TStat.values.reduce((a, b) => stat(b) > stat(a) ? b : a);
    return switch (top) {
      TStat.charm => Ending.idol,
      TStat.cook => Ending.chef,
      TStat.kind => Ending.host,
      TStat.sense => Ending.ceo,
      TStat.stamina => Ending.courier,
    };
  }

  /// 수업을 받는다. 오른 능력치(스트레스가 너무 높으면 null: 쉬기만 한다).
  Map<TStat, int>? take(Lesson l, Random r) {
    if (l.id != 'rest' && stress >= stressSulk) return null;
    final half = stress >= stressTired;
    final got = <TStat, int>{};
    for (final e in l.gain.entries) {
      var g = max(1, e.value + r.nextInt(3) - 1);
      if (half) g = (g / 2).ceil();
      stats[e.key] = min(100, stat(e.key) + g);
      got[e.key] = g;
    }
    stress = (stress + l.stress).clamp(0, 100);
    if (l.id != 'rest') lessonsTaken++;
    return got;
  }

  Map<String, Object> toJson() => {
        'gen': generation,
        'stats': {for (final e in stats.entries) e.key.name: e.value},
        'stress': stress,
        'n': lessonsTaken,
        'key': lessonKey,
      };

  void fromJson(Map<String, dynamic> j) {
    generation = j['gen'] as int? ?? 0;
    for (final e in ((j['stats'] as Map?) ?? const {}).entries) {
      final s = TStat.values.asNameMap()[e.key];
      if (s != null) stats[s] = e.value as int;
    }
    stress = j['stress'] as int? ?? 0;
    lessonsTaken = j['n'] as int? ?? 0;
    lessonKey = j['key'] as String? ?? '';
  }
}

/// 견습생 능력치가 가게에 주는 힘(수업 중에도 바로).
double traineeVisitors(Trainee t) => min(0.2, t.stat(TStat.charm) / 500); // 매력: 손님
double traineeSatisfy(Trainee t) => t.stat(TStat.kind) / 300; // 친절: 손님 만족 +1 확률
double traineeDiscount(Trainee t) => min(0.2, t.stat(TStat.sense) / 500); // 센스: 재주문 할인
double traineeStaffSpeed(Trainee t) => min(0.1, t.stat(TStat.stamina) / 1000); // 체력: 알바 속도
/// 요리 30 부터: 온장 진열대 날것을 이만큼(초)마다 하나씩 대신 굽는다. 아직이면 null.
double? traineeCookEvery(Trainee t) => t.stat(TStat.cook) < 30 ? null : max(1.2, 4.5 - t.stat(TStat.cook) / 30);

// ------------------------------------------------------------------ 친해지기(연애)

/// 친해질 수 있는 사람. look 은 캐릭터 시트 번호, idol 이면 아이돌이 가게에 한 번 다녀간 뒤에 만난다.
class Datable {
  final String id;
  final int look, level;
  final List<String> likes;
  final String dislike;
  final String place; // 가장 좋아하는 데이트 장소
  final bool idol;
  const Datable(this.id, this.look, this.level, this.likes, this.dislike, this.place, {this.idol = false});
}

const datables = [
  Datable('bori', 4, 2, ['bananamilk', 'donut'], 'coffee', 'cafe'),
  Datable('hajun', 9, 4, ['cupramen', 'hotdog'], 'cake', 'amusement'),
  Datable('mina', 0, 1, ['donut', 'cupcake'], 'sushi', 'cafe'),
  Datable('jun', 10, 3, ['sandwich', 'coffee'], 'donut', 'beach'),
  Datable('luna', 58, 1, ['strawberry', 'frappe'], 'cupramen', 'concert', idol: true),
  Datable('rio', 61, 1, ['burger', 'soda'], 'tea', 'concert', idol: true),
];
Datable datableById(String id) => datables.firstWhere((d) => d.id == id);

const actionsPerDay = 2; // 하루(닫힌 동안)에 할 수 있는 만남
const talkGain = 4;
const giftLike = 12, giftNormal = 5, giftDislike = -4;
int giftCost(String product) => productById(product).price * 6;
const datePlaces = {'cafe': 120, 'beach': 250, 'amusement': 400, 'concert': 600};
const datePlaceGain = {'cafe': 10, 'beach': 14, 'amusement': 18, 'concert': 20};
const favPlaceBonus = 10;
const dateHearts = 2; // 이만큼 친해져야 데이트
const heartStep = 20; // 호감도 이만큼마다 하트 하나 (최대 5)
int heartsFor(int affection) => min(5, affection ~/ heartStep);

/// 연인이 되면 가게에 붙는 덤.
const loverCashier = 1.15; // 보리: 계산원 속도
const loverStocker = 1.15; // 하준: 진열원 속도
const loverRegular = 2.0; // 민아: 단골이 자주
const loverPay = 1.3; // 준: 배달 값
const loverVisitors = 0.1; // 루나: 손님
const loverFever = 5.0; // 리오: 피버 시간 +
