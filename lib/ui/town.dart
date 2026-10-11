part of 'store_painter.dart';

// 가게 바깥 동네: 인도·찻길·길 건너 건물·나무·가로등, 지나가는 차와 사람.
// 지도(땅 20필지) 바깥 [townMargin] 칸까지 그린다. 지도에서 떨어진 거리(칸)로 띠를 나눈다:
// 1~2 = 인도, 3~4 = 찻길(벽에서 떨어져야 차가 벽 위를 달리는 것처럼 안 보인다), 5 이상 = 건물·나무. 안 산 땅에는 덤불·나무를 듬성듬성 둔다.

const townMargin = 12;

/// 지도 밖으로 몇 칸 떨어졌나 (지도 안이면 0).
int _outside(int x, int y) => max(max(-x, -y), max(x - (mapW - 1), y - (mapH - 1))).clamp(0, 999);

/// 벽보다 뒤(먼저 그릴 쪽)인가: 왼쪽 위(x<0)나 오른쪽 위(y<0).
bool _behind(double x, double y) => x < 0 || y < 0;

/// 칸마다 정해진 무작위 값 0~1 (그릴 때마다 같다).
double _hash(int x, int y, int salt) {
  var h = x * 374761393 + y * 668265263 + salt * 2147483647;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF;
}

/// 이야기 진행에 따른 길 건너 큰 건물: 0 공사 중, 1 메가마트, 2 삐약마트 별관.
int megaStage(Owner o) => o.story.contains('finale') ? 2 : (o.story.contains('rival') ? 1 : 0);

/// 메가마트 자리 (삐약동만): 첫 가게 왼쪽 위, 찻길 건너.
const _megaX = -10, _megaY = 1, _megaW = 6, _megaD = 6;
bool _inMega(int x, int y) => x >= _megaX - 1 && x < _megaX + _megaW && y >= _megaY - 1 && y < _megaY + _megaD + 1;

class _Look {
  final Color ground, ground2, road, line, walk;
  final bool night, snow, beach;
  const _Look(this.ground, this.ground2, this.road, this.line, this.walk,
      {this.night = false, this.snow = false, this.beach = false});
  Color get water => const Color(0xFF4FC3F7);
}

_Look _lookOf(String branch) => switch (branch) {
      'beach' => const _Look(Color(0xFFFFE9B0), Color(0xFFFFE29E), Color(0xFF9E9E9E), Color(0xFFFFFFFF), Color(0xFFF5E6C8),
          beach: true),
      'night' => const _Look(Color(0xFF3E4F58), Color(0xFF38474F), Color(0xFF263238), Color(0xFFFFD54F), Color(0xFF546E7A),
          night: true),
      'snow' => const _Look(Color(0xFFF7F9FC), Color(0xFFEDF2F7), Color(0xFFB0BEC5), Color(0xFFFFFFFF), Color(0xFFE3E9EF),
          snow: true),
      _ => const _Look(Color(0xFFB5D98F), Color(0xFFAAD283), Color(0xFF9E9E9E), Color(0xFFFFFFFF), Color(0xFFE0E0E0)),
    };

// ---------------------------------------------------------------- 바닥·찻길 (캐시에 들어간다)

/// 지도 바깥 땅·인도·찻길·물.
void _townGround(Canvas c, Game g) {
  final lk = _lookOf(g.branch);
  final paths = <Color, Path>{};
  void put(Color col, int x, int y) =>
      paths.putIfAbsent(col, Path.new).addPath(_diamond(x.toDouble(), y.toDouble(), 1, 1), Offset.zero);
  for (var y = -townMargin; y < mapH + townMargin; y++) {
    for (var x = -townMargin; x < mapW + townMargin; x++) {
      final d = _outside(x, y);
      if (d == 0) continue;
      if (d <= 2) {
        put((x + y).isEven ? lk.walk : Color.lerp(lk.walk, Colors.black, 0.05)!, x, y);
      } else if (d <= 4) {
        put(lk.road, x, y);
      } else if (lk.beach && y < -6) {
        put(lk.water, x, y); // 바닷가: 오른쪽 위는 바다
      } else {
        put((x + y).isEven ? lk.ground : lk.ground2, x, y);
      }
    }
  }
  for (final e in paths.entries) {
    c.drawPath(e.value, Paint()..color = e.key);
  }
  // 찻길 가운데 점선: 지도 둘레를 도는 고리(바깥으로 3.5칸)
  final dash = Paint()
    ..color = lk.line.withValues(alpha: 0.8)
    ..strokeWidth = 2;
  const k = 3.5;
  for (var t = -townMargin + 0.0; t < max(mapW, mapH) + townMargin; t += 1.5) {
    void seg(double x0, double y0, double x1, double y1) => c.drawLine(corner(x0, y0), corner(x1, y1), dash);
    if (t < mapW + k) {
      seg(t, -k + 0.5, t + 0.7, -k + 0.5);
      seg(t, mapH + k - 0.5, t + 0.7, mapH + k - 0.5);
    }
    if (t < mapH + k) {
      seg(-k + 0.5, t, -k + 0.5, t + 0.7);
      seg(mapW + k - 0.5, t, mapW + k - 0.5, t + 0.7);
    }
  }
}

// ---------------------------------------------------------------- 건물·나무 (정해진 자리)

/// 동네 물건 하나: 바닥 한가운데 (x, y) 를 기준으로 그린다.
class _Scenery {
  final double x, y; // 깊이(그리는 순서)용 앞쪽 칸
  final void Function(Canvas) draw;
  _Scenery(this.x, this.y, this.draw);
}

/// 지도 바깥과 안 산 땅의 동네 물건들.
List<_Scenery> _townScenery(Game g) {
  final lk = _lookOf(g.branch);
  final out = <_Scenery>[];
  final piyak = g.branch == 'piyak';

  // 찻길 건너 한 줄: 3×3 건물을 4칸마다 (네 변)
  void row(int count, (int, int) Function(int i) at, int salt) {
    for (var i = 0; i < count; i++) {
      final (x0, y0) = at(i);
      if (piyak && (_inMega(x0, y0) || _inMega(x0 + 2, y0 + 2))) continue;
      if (lk.beach && y0 < -6) continue;
      final r = _hash(x0, y0, salt);
      out.add(_Scenery(x0 + 2.0, y0 + 2.0, (c) => _block(c, lk, x0, y0, r)));
    }
  }

  final nx = (mapW + 2 * townMargin) ~/ 4, ny = (mapH + 2 * townMargin) ~/ 4;
  row(ny, (i) => (-7, -townMargin + 1 + i * 4), 1); // 왼쪽 위 변
  row(nx, (i) => (-townMargin + 1 + i * 4, -7), 2); // 오른쪽 위 변
  row(ny, (i) => (mapW + 4, -townMargin + 1 + i * 4), 3); // 오른쪽 아래 변
  row(nx, (i) => (-townMargin + 1 + i * 4, mapH + 4), 4); // 왼쪽 아래 변

  // 더 바깥: 나무 듬성듬성
  for (var y = -townMargin; y < mapH + townMargin; y++) {
    for (var x = -townMargin; x < mapW + townMargin; x++) {
      final d = _outside(x, y);
      if (d < 8 || _hash(x, y, 7) > 0.10) continue;
      if (lk.beach && y < -6) continue;
      if (piyak && _inMega(x, y)) continue;
      out.add(_Scenery(x + 0.0, y + 0.0, (c) => _tree(c, lk, iso(x + 0.0, y + 0.0), _hash(x, y, 8))));
    }
  }
  // 바닷가 등대, 눈 마을 큰 눈사람
  if (lk.beach) out.add(_Scenery(6, -9, (c) => _lighthouse(c, iso(6, -9))));
  if (lk.snow) out.add(_Scenery(-6, 3, (c) => _snowman(c, iso(-6, 3), 2.2)));

  // 인도 가로등: 6칸마다
  for (var t = -townMargin + 2; t < max(mapW, mapH) + townMargin; t += 6) {
    for (final (x, y) in [(t, -2), (-2, t), (t, mapH + 1), (mapW + 1, t)]) {
      if (_outside(x, y) != 2) continue;
      out.add(_Scenery(x + 0.0, y + 0.0, (c) => _lamp(c, lk, iso(x + 0.0, y + 0.0))));
    }
  }

  // 메가마트(삐약동)
  if (piyak) {
    final stage = megaStage(g.owner);
    out.add(_Scenery(_megaX + _megaW - 1.0, _megaY + _megaD - 1.0, (c) => _megaMart(c, stage)));
  }

  // 안 산 땅: 내 땅에서 두 칸 이상 떨어진 곳에 덤불·꽃·나무
  for (var y = 0; y < mapH; y++) {
    for (var x = 0; x < mapW; x++) {
      if (g.owns((x, y))) continue;
      final r = _hash(x, y, 11);
      if (r > 0.14) continue;
      var near = false;
      for (var dy = -2; dy <= 2 && !near; dy++) {
        for (var dx = -2; dx <= 2 && !near; dx++) {
          near = g.owns((x + dx, y + dy));
        }
      }
      if (near) continue;
      final p = iso(x + 0.0, y + 0.0);
      out.add(_Scenery(x + 0.0, y + 0.0, (c) {
        if (r < 0.05) {
          _tree(c, lk, p, _hash(x, y, 12));
        } else if (r < 0.10) {
          _bush(c, lk, p);
        } else {
          _flowers(c, p, _hash(x, y, 13));
        }
      }));
    }
  }
  return out;
}

// ---------------------------------------------------------------- 그림 조각

/// 바닥 (x0..x0+w, y0..y0+d) 칸 위에 높이 h 상자. 앞의 두 면과 윗면만 보인다.
void _tbox(Canvas c, double x0, double y0, double w, double d, double h, Color left, Color right, Color top) {
  final up = Offset(0, -h);
  final a = corner(x0, y0 + d), b = corner(x0 + w, y0 + d), r = corner(x0 + w, y0), t = corner(x0, y0);
  c.drawPath(_quad(a, b, b + up, a + up), Paint()..color = left);
  c.drawPath(_quad(b, r, r + up, b + up), Paint()..color = right);
  c.drawPath(_quad(t + up, r + up, b + up, a + up), Paint()..color = top);
  final e = _stroke(1.5);
  c.drawPath(_quad(a, b, b + up, a + up), e);
  c.drawPath(_quad(b, r, r + up, b + up), e);
  c.drawPath(_quad(t + up, r + up, b + up, a + up), e);
}

/// 앞면(왼쪽 아래를 보는 면)에 창문 줄.
void _windows(Canvas c, double x0, double y1, double w, double fromH, double toH, Color glass, {double step = 1}) {
  for (var x = x0 + 0.3; x + 0.5 <= x0 + w; x += step) {
    for (var h = fromH; h + 10 <= toH; h += 18) {
      final a = corner(x, y1) + Offset(0, -h), b = corner(x + 0.45, y1) + Offset(0, -h);
      c.drawPath(_quad(a, b, b + const Offset(0, -10), a + const Offset(0, -10)), Paint()..color = glass);
    }
  }
}

/// 옆면(오른쪽 아래를 보는 면)에 창문 줄.
void _sideWindows(Canvas c, double x1, double y0, double d, double fromH, double toH, Color glass) {
  for (var y = y0 + 0.3; y + 0.5 <= y0 + d; y += 1) {
    for (var h = fromH; h + 10 <= toH; h += 18) {
      final a = corner(x1, y + 0.45) + Offset(0, -h), b = corner(x1, y) + Offset(0, -h);
      c.drawPath(_quad(a, b, b + const Offset(0, -10), a + const Offset(0, -10)), Paint()..color = glass);
    }
  }
}

const _pastels = [
  Color(0xFFFFCDD2), Color(0xFFFFF59D), Color(0xFFC8E6C9), Color(0xFFBBDEFB), Color(0xFFE1BEE7), Color(0xFFFFE0B2),
];
const _roofs = [Color(0xFFE57373), Color(0xFF64B5F6), Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFBA68C8)];

/// 찻길 건너 3×3 한 덩어리: 집·가게·아파트·작은 공원 중 하나.
void _block(Canvas c, _Look lk, int x0, int y0, double r) {
  final x = x0 + 0.0, y = y0 + 0.0;
  final wall = _pastels[(r * 97).floor() % _pastels.length];
  final dark = Color.lerp(wall, Colors.black, 0.12)!;
  final glass = lk.night ? const Color(0xFFFFE082) : const Color(0xFFB3E5FC);
  if (lk.beach && r < 0.5) {
    _hut(c, x, y, wall, r);
    _palm(c, iso(x + 2.6, y + 0.4), r);
    return;
  }
  if (r < 0.22) {
    // 작은 공원: 나무 셋과 의자
    _tree(c, lk, iso(x + 0.5, y + 0.5), r);
    _tree(c, lk, iso(x + 2, y + 0.8), 1 - r);
    _bench(c, iso(x + 1.4, y + 2.0));
    _tree(c, lk, iso(x + 0.6, y + 2.3), r * 0.5);
    return;
  }
  if (r < 0.55 && !lk.night) {
    // 집: 세모 지붕
    const h = 34.0;
    _tbox(c, x + 0.3, y + 0.3, 2.4, 2.4, h, wall, dark, wall);
    final roof = lk.snow ? Colors.white : _roofs[(r * 31).floor() % _roofs.length];
    final top = [corner(x + 0.1, y + 0.1), corner(x + 2.9, y + 0.1), corner(x + 2.9, y + 2.9), corner(x + 0.1, y + 2.9)]
        .map((p) => p + const Offset(0, -h))
        .toList();
    final apex = iso(x + 1, y + 1) + const Offset(0, -h - 30);
    for (final (i, j) in [(0, 1), (3, 0), (1, 2), (2, 3)]) {
      final tri = Path()
        ..moveTo(top[i].dx, top[i].dy)
        ..lineTo(top[j].dx, top[j].dy)
        ..lineTo(apex.dx, apex.dy)
        ..close();
      c.drawPath(tri, Paint()..color = (i == 2 || i == 1) ? Color.lerp(roof, Colors.black, 0.15)! : roof);
      c.drawPath(tri, _stroke(1.5));
    }
    // 문과 창문
    final da = corner(x + 1.2, y + 2.7), db = corner(x + 1.7, y + 2.7);
    c.drawPath(_quad(da, db, db + const Offset(0, -20), da + const Offset(0, -20)), Paint()..color = const Color(0xFF8D6E63));
    _windows(c, x + 0.3, y + 2.7, 0.9, 14, 26, glass);
    _sideWindows(c, x + 2.7, y + 0.3, 2.4, 14, 26, glass);
    return;
  }
  // 가게·아파트: 네모 건물, 밤엔 더 높고 창문이 환하다
  final h = lk.night ? 70 + r * 60 : (r < 0.8 ? 46.0 : 80.0);
  _tbox(c, x + 0.2, y + 0.2, 2.6, 2.6, h, wall, dark, Color.lerp(wall, Colors.white, 0.3)!);
  _windows(c, x + 0.2, y + 2.8, 2.6, 22, h - 6, glass);
  _sideWindows(c, x + 2.8, y + 0.2, 2.6, 22, h - 6, glass);
  // 가게 차양
  final awn = _roofs[(r * 53).floor() % _roofs.length];
  final a = corner(x + 0.2, y + 2.8) + const Offset(0, -16), b = corner(x + 2.8, y + 2.8) + const Offset(0, -16);
  c.drawPath(_quad(a, b, b + const Offset(-6, 7), a + const Offset(-6, 7)), Paint()..color = awn);
  c.drawPath(_quad(a, b, b + const Offset(-6, 7), a + const Offset(-6, 7)), _stroke(1.2));
  if (lk.night) {
    // 네온 간판
    final p = corner(x + 1.5, y + 2.8) + Offset(0, -h * 0.6);
    final neon = [const Color(0xFFFF4081), const Color(0xFF18FFFF), const Color(0xFFFFEB3B)][(r * 7).floor() % 3];
    c.drawCircle(p, 16, Paint()..color = neon.withValues(alpha: 0.25));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 26, height: 10), const Radius.circular(4)),
        Paint()..color = neon);
  }
}

void _tree(Canvas c, _Look lk, Offset p, double r) {
  c.drawOval(Rect.fromCenter(center: p, width: 26, height: 10), Paint()..color = const Color(0x22000000));
  if (lk.beach) {
    _palm(c, p, r);
    return;
  }
  if (lk.snow) {
    // 눈 덮인 소나무
    for (var i = 0; i < 3; i++) {
      final w = 26.0 - i * 6, top = p.dy - 14 - i * 12;
      final tri = Path()
        ..moveTo(p.dx - w / 2, top + 14)
        ..lineTo(p.dx + w / 2, top + 14)
        ..lineTo(p.dx, top - 8)
        ..close();
      c.drawPath(tri, Paint()..color = const Color(0xFF2E7D32));
      c.drawPath(tri, _stroke(1.2));
      c.drawCircle(Offset(p.dx, top - 4), 4, Paint()..color = Colors.white);
    }
    return;
  }
  c.drawRect(Rect.fromLTWH(p.dx - 3, p.dy - 18, 6, 18), Paint()..color = const Color(0xFF8D6E63));
  final leaf = lk.night ? const Color(0xFF2E5D3A) : Color.lerp(const Color(0xFF66BB6A), const Color(0xFF9CCC65), r)!;
  final s = 0.85 + r * 0.4;
  for (final (dx, dy, rad) in [(-7.0, -24.0, 11.0), (7.0, -24.0, 11.0), (0.0, -33.0, 12.0)]) {
    c.drawCircle(p + Offset(dx * s, dy * s), rad * s, Paint()..color = leaf);
    c.drawCircle(p + Offset(dx * s, dy * s), rad * s, _stroke(1.2));
  }
  c.drawCircle(p + Offset(-3 * s, -36 * s), 4 * s, Paint()..color = Colors.white.withValues(alpha: 0.35));
}

void _palm(Canvas c, Offset p, double r) {
  final top = p + Offset(6 + r * 6, -48);
  final trunk = Path()
    ..moveTo(p.dx - 3, p.dy)
    ..quadraticBezierTo(p.dx + 2, p.dy - 26, top.dx, top.dy)
    ..lineTo(top.dx + 4, top.dy + 2)
    ..quadraticBezierTo(p.dx + 6, p.dy - 24, p.dx + 3, p.dy)
    ..close();
  c.drawPath(trunk, Paint()..color = const Color(0xFFA1887F));
  c.drawPath(trunk, _stroke(1.2));
  for (var i = 0; i < 5; i++) {
    final a = -pi / 2 + (i - 2) * 0.75;
    final end = top + Offset(cos(a) * 24, sin(a) * 12 + 10);
    final leaf = Path()
      ..moveTo(top.dx, top.dy)
      ..quadraticBezierTo((top.dx + end.dx) / 2, top.dy - 10, end.dx, end.dy)
      ..quadraticBezierTo((top.dx + end.dx) / 2, top.dy - 2, top.dx, top.dy);
    c.drawPath(leaf, Paint()..color = const Color(0xFF43A047));
    c.drawPath(leaf, _stroke(1));
  }
}

void _hut(Canvas c, double x, double y, Color wall, double r) {
  _tbox(c, x + 0.4, y + 0.4, 2.0, 2.0, 26, const Color(0xFFFFF3E0), const Color(0xFFFFE0B2), const Color(0xFFFFF3E0));
  // 파라솔 지붕
  final p = iso(x + 1.4, y + 1.4) + const Offset(0, -26);
  final roof = Path()..addOval(Rect.fromCenter(center: p + const Offset(0, -6), width: 92, height: 34));
  c.drawPath(roof, Paint()..color = _roofs[(r * 31).floor() % _roofs.length]);
  c.drawPath(roof, _stroke(1.5));
}

void _bush(Canvas c, _Look lk, Offset p) {
  final col = lk.snow ? Colors.white : (lk.night ? const Color(0xFF2E5D3A) : const Color(0xFF7CB342));
  for (final (dx, dy, rad) in [(-6.0, -6.0, 7.0), (6.0, -6.0, 7.0), (0.0, -10.0, 8.0)]) {
    c.drawCircle(p + Offset(dx, dy), rad, Paint()..color = col);
    c.drawCircle(p + Offset(dx, dy), rad, _stroke(1));
  }
}

void _flowers(Canvas c, Offset p, double r) {
  const cols = [Color(0xFFFF8A80), Color(0xFFFFFF8D), Color(0xFFEA80FC), Color(0xFFFFFFFF)];
  for (var i = 0; i < 5; i++) {
    final q = p + Offset(cos(i * 2.4 + r * 6) * 9, sin(i * 2.4 + r * 6) * 4 - 2);
    c.drawCircle(q, 2.6, Paint()..color = cols[(i + (r * 4).floor()) % cols.length]);
  }
}

void _bench(Canvas c, Offset p) {
  final a = p + const Offset(-14, -2), b = p + const Offset(10, 10);
  c.drawLine(a + const Offset(0, -10), b + const Offset(0, -10), Paint()
    ..color = const Color(0xFFA1887F)
    ..strokeWidth = 5);
  c.drawLine(a + const Offset(0, -17), b + const Offset(0, -17), Paint()
    ..color = const Color(0xFF8D6E63)
    ..strokeWidth = 3);
}

void _lamp(Canvas c, _Look lk, Offset p) {
  c.drawLine(p, p + const Offset(0, -46), Paint()
    ..color = const Color(0xFF616161)
    ..strokeWidth = 3);
  final head = p + const Offset(0, -48);
  if (lk.night) {
    c.drawCircle(head, 22, Paint()..color = const Color(0x33FFE082));
    c.drawOval(Rect.fromCenter(center: p, width: 50, height: 22), Paint()..color = const Color(0x22FFE082));
  }
  c.drawCircle(head, 5, Paint()..color = lk.night ? const Color(0xFFFFF59D) : const Color(0xFFEEEEEE));
  c.drawCircle(head, 5, _stroke(1.2));
}

void _snowman(Canvas c, Offset p, double s) {
  for (final (dy, rad) in [(-10.0, 11.0), (-27.0, 8.0)]) {
    c.drawCircle(p + Offset(0, dy * s), rad * s, Paint()..color = Colors.white);
    c.drawCircle(p + Offset(0, dy * s), rad * s, _stroke(1.5));
  }
  c.drawCircle(p + Offset(-3 * s, -29 * s), 1.2 * s, Paint()..color = ink);
  c.drawCircle(p + Offset(3 * s, -29 * s), 1.2 * s, Paint()..color = ink);
  c.drawLine(p + Offset(0, -26 * s), p + Offset(5 * s, -25 * s), Paint()
    ..color = const Color(0xFFFF7043)
    ..strokeWidth = 2 * s);
  c.drawRect(Rect.fromCenter(center: p + Offset(0, -35 * s), width: 10 * s, height: 6 * s), Paint()..color = ink);
}

void _lighthouse(Canvas c, Offset p) {
  for (var i = 0; i < 4; i++) {
    final w = 24.0 - i * 3, y = p.dy - i * 22;
    c.drawRect(Rect.fromLTWH(p.dx - w / 2, y - 22, w, 22), Paint()..color = i.isEven ? Colors.white : const Color(0xFFE53935));
    c.drawRect(Rect.fromLTWH(p.dx - w / 2, y - 22, w, 22), _stroke(1.2));
  }
  c.drawCircle(Offset(p.dx, p.dy - 96), 8, Paint()..color = const Color(0xFFFFEB3B));
  c.drawCircle(Offset(p.dx, p.dy - 96), 8, _stroke(1.2));
}

/// 메가마트: 공사 중 → 메가마트 → (결말 뒤) 삐약마트 별관.
void _megaMart(Canvas c, int stage) {
  const x = _megaX + 0.0, y = _megaY + 0.0, w = _megaW + 0.0, d = _megaD + 0.0;
  if (stage == 0) {
    // 공사장 울타리와 표지
    final f = Paint()
      ..color = const Color(0xFFFFB300)
      ..strokeWidth = 3;
    for (final (a, b) in [
      (corner(x, y), corner(x + w, y)),
      (corner(x + w, y), corner(x + w, y + d)),
      (corner(x, y + d), corner(x + w, y + d)),
      (corner(x, y), corner(x, y + d)),
    ]) {
      c.drawLine(a + const Offset(0, -10), b + const Offset(0, -10), f);
      c.drawLine(a + const Offset(0, -18), b + const Offset(0, -18), f);
    }
    final p = iso(x + w / 2, y + d / 2) + const Offset(0, -26);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 70, height: 20), const Radius.circular(4)),
        Paint()..color = const Color(0xFFFFEB3B));
    _text(c, p, S.t('town_construction'), ink, 11);
    return;
  }
  final annex = stage == 2;
  final wall = annex ? const Color(0xFFFCE4EC) : const Color(0xFFECEFF1);
  _tbox(c, x, y, w, d, 96, wall, Color.lerp(wall, Colors.black, 0.12)!, Color.lerp(wall, Colors.white, 0.4)!);
  final glass = annex ? const Color(0xFFFFF59D) : const Color(0xFFB3E5FC);
  _windows(c, x, y + d, w, 30, 86, glass);
  // 오른쪽 아래를 보는 면(우리 가게 쪽): 큰 유리문과 간판
  final a = corner(x + w, y + d - 1.6), b = corner(x + w, y + d - 3.2);
  c.drawPath(_quad(a, b, b + const Offset(0, -26), a + const Offset(0, -26)), Paint()..color = glass);
  c.drawPath(_quad(a, b, b + const Offset(0, -26), a + const Offset(0, -26)), _stroke(1.5));
  final sa = corner(x + w, y + d - 0.4) + const Offset(0, -64), sb = corner(x + w, y + 0.4) + const Offset(0, -64);
  final board = _quad(sa, sb, sb + const Offset(0, -22), sa + const Offset(0, -22));
  c.drawPath(board, Paint()..color = annex ? const Color(0xFFFFB74D) : const Color(0xFFE53935));
  c.drawPath(board, _stroke(2));
  final mid = Offset((sa.dx + sb.dx) / 2, (sa.dy + sb.dy) / 2 - 11);
  c.save();
  c.translate(mid.dx, mid.dy);
  c.skew(0, -0.5); // 오른쪽 아래를 보는 면의 기울기
  _text(c, Offset.zero, annex ? S.t('town_annex') : 'MEGA MART', Colors.white, 14, outline: annex ? 0 : 0);
  c.restore();
}

// ---------------------------------------------------------------- 지나가는 차와 사람 (매 장면)

const _carColors = [
  Color(0xFFEF5350), Color(0xFF42A5F5), Color(0xFFFFCA28), Color(0xFF66BB6A), Color(0xFFAB47BC), Color(0xFFFFFFFF),
];

/// 찻길 고리 네 변의 차선: (x 방향인가, 고정 좌표, 방향 +1/-1).
const _lanes = [
  (true, -3.0, 1), (true, -4.0, -1), // 오른쪽 위 찻길
  (false, -3.0, -1), (false, -4.0, 1), // 왼쪽 위 찻길
  (true, mapH + 2.0, -1), (true, mapH + 3.0, 1), // 왼쪽 아래 찻길
  (false, mapW + 2.0, 1), (false, mapW + 3.0, -1), // 오른쪽 아래 찻길
];

/// 시각 [t] 의 차들: (x, y, x 방향인가, 방향, 색). 상태 없이 시각에서 바로 구한다.
Iterable<(double, double, bool, int, Color)> _cars(double t) sync* {
  for (final (i, (alongX, fixed, dir)) in _lanes.indexed) {
    final len = (alongX ? mapW : mapH) + 2.0 * townMargin;
    for (var k = 0; k < 3; k++) {
      final speed = 2.2 + _hash(i, k, 21) * 1.5;
      var s = (_hash(i, k, 22) * len + t * speed) % len;
      if (dir < 0) s = len - s;
      final along = -townMargin + s;
      yield alongX
          ? (along, fixed, true, dir, _carColors[(i * 3 + k) % _carColors.length])
          : (fixed, along, false, dir, _carColors[(i * 3 + k) % _carColors.length]);
    }
  }
}

void _car(Canvas c, double x, double y, bool alongX, Color col) {
  final w = alongX ? 1.5 : 0.8, d = alongX ? 0.8 : 1.5;
  final x0 = x - w / 2 + 0.5, y0 = y - d / 2 + 0.5;
  c.drawOval(Rect.fromCenter(center: iso(x, y), width: 46, height: 18), Paint()..color = const Color(0x33000000));
  _tbox(c, x0, y0, w, d, 12, col, Color.lerp(col, Colors.black, 0.18)!, Color.lerp(col, Colors.white, 0.15)!);
  // 지붕(유리)
  final cw = alongX ? 0.8 : 0.6, cd = alongX ? 0.6 : 0.8;
  final cx = x - cw / 2 + 0.5, cy = y - cd / 2 + 0.5;
  final up = const Offset(0, -12);
  c.save();
  c.translate(up.dx, up.dy);
  _tbox(c, cx, cy, cw, cd, 9, const Color(0xFFB3E5FC), const Color(0xFF81D4FA), col);
  c.restore();
}

/// 인도 위를 걷는 사람들: (x, y, dx, dy, 얼굴 번호).
Iterable<(double, double, double, double, int)> _walkers(double t) sync* {
  const sides = [
    (true, -2.0, 1), (false, -2.0, -1), (true, mapH + 1.0, -1), (false, mapW + 1.0, 1),
    (true, -2.0, -1), (false, -2.0, 1),
  ];
  for (final (i, (alongX, fixed, dir)) in sides.indexed) {
    final len = (alongX ? mapW : mapH) + 2.0 * townMargin;
    var s = (_hash(i, 1, 31) * len + t * 0.9) % len;
    if (dir < 0) s = len - s;
    final along = -townMargin + s;
    final look = customerChars[(i * 7 + 3) % customerChars.length];
    yield alongX ? (along, fixed, dir.toDouble(), 0.0, look) : (fixed, along, 0.0, dir.toDouble(), look);
  }
}
