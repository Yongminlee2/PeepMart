part of 'store_painter.dart';

// 가게 바깥 동네: 찻길·인도·건너편 건물·나무·가로등, 지나가는 차와 사람, 안 산 땅의 공원·주차장·공터·꽃밭.
// 지도(땅 20필지) 바깥 [townMargin] 칸까지 그리고, 가장자리는 하늘색으로 흐려진다.
//
// 찻길은 지도 둘레를 도는 고리(지도에서 3~4칸 떨어진 두 줄)를 바깥까지 쭉 이은 여덟 줄이다:
// 바깥 동네로 이어져 보이고, 모퉁이마다 교차로·횡단보도가 생긴다. 찻길 양옆은 인도.
// (찻길을 벽 바로 뒤에 두면 차가 벽 위를 달리는 것처럼 보여서 3~4칸으로 뺐다.)

const townMargin = 16;
const _fog = 5; // 가장자리에서 이만큼이 흐려진다

/// 지도 밖으로 몇 칸 떨어졌나 (지도 안이면 0).
int _outside(int x, int y) => max(max(-x, -y), max(x - (mapW - 1), y - (mapH - 1))).clamp(0, 999);

/// 벽보다 뒤(먼저 그릴 쪽)인가: 왼쪽 위(x<0)나 오른쪽 위(y<0).
bool _behind(double x, double y) => x < 0 || y < 0;

bool _roadRow(int y) => y == -4 || y == -3 || y == mapH + 2 || y == mapH + 3;
bool _roadCol(int x) => x == -4 || x == -3 || x == mapW + 2 || x == mapW + 3;

/// 찻길 칸인가 (지도 안은 아니다).
bool _isRoad(int x, int y) => _outside(x, y) > 0 && (_roadRow(y) || _roadCol(x));

/// 인도 칸인가: 지도와 고리 사이(1~2칸), 그리고 찻길 바로 옆.
bool _isWalk(int x, int y) {
  if (_isRoad(x, y)) return false;
  final d = _outside(x, y);
  if (d == 0) return false;
  if (d <= 2) return true;
  for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)]) {
    if (_isRoad(x + dx, y + dy)) return true;
  }
  return false;
}

/// 칸마다 정해진 무작위 값 0~1 (그릴 때마다 같다).
double _hash(int x, int y, int salt) {
  var h = x * 374761393 + y * 668265263 + salt * 2147483647;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF;
}

/// 이야기 진행에 따른 길 건너 큰 건물: 0 공사 중, 1 메가마트, 2 삐약마트 별관.
int megaStage(Owner o) => o.story.contains('finale') ? 2 : (o.story.contains('rival') ? 1 : 0);

/// 메가마트 자리 (삐약동만): 첫 가게 왼쪽 위, 찻길 건너.
const _megaX = -12, _megaY = 1, _megaW = 6, _megaD = 6;

class _Look {
  final Color ground, ground2, road, line, walk;
  final bool night, snow, beach;
  const _Look(this.ground, this.ground2, this.road, this.line, this.walk,
      {this.night = false, this.snow = false, this.beach = false});
  Color get water => const Color(0xFF4FC3F7);
  Color get curb => Color.lerp(walk, Colors.black, 0.25)!;

  /// 동네 분위기에 맞춘 색: 밤엔 어둡게, 눈 마을은 눈 덮인 듯 밝게.
  Color tone(Color c) => night ? Color.lerp(c, const Color(0xFF263238), 0.5)! : (snow ? Color.lerp(c, Colors.white, 0.6)! : c);
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

// ---------------------------------------------------------------- 안 산 땅의 쓰임

/// 안 산 필지마다 정해진 모습: 공원·주차장·공터(매물)·꽃밭.
enum _Lot { park, parking, empty, flowers }

_Lot _lotOf(int px, int py) => _Lot.values[(_hash(px, py, 91) * _Lot.values.length).floor() % _Lot.values.length];

// ---------------------------------------------------------------- 바닥·찻길 (캐시에 들어간다)

/// 지도 바깥 땅·인도·찻길·물, 안 산 땅의 바닥(주차장 아스팔트·공터 흙·공원 길).
void _townGround(Canvas c, Game g) {
  final lk = _lookOf(g.branch);
  final paths = <Color, Path>{};
  void put(Color col, int x, int y) =>
      paths.putIfAbsent(col, Path.new).addPath(_diamond(x.toDouble(), y.toDouble(), 1, 1), Offset.zero);
  for (var y = -townMargin; y < mapH + townMargin; y++) {
    for (var x = -townMargin; x < mapW + townMargin; x++) {
      final d = _outside(x, y);
      if (d == 0) continue;
      if (_isRoad(x, y)) {
        put(lk.road, x, y);
      } else if (_isWalk(x, y)) {
        put((x + y).isEven ? lk.walk : Color.lerp(lk.walk, Colors.black, 0.05)!, x, y);
      } else if (lk.beach && y < -6) {
        put(y < -8 ? lk.water : const Color(0xFFFFF3C4), x, y); // 바닷가: 오른쪽 위는 모래사장과 바다
      } else {
        put((x + y).isEven ? lk.ground : lk.ground2, x, y);
      }
    }
  }
  for (final e in paths.entries) {
    c.drawPath(e.value, Paint()..color = e.key);
  }
  // 연석: 찻길이 다른 땅과 닿는 가장자리
  final curb = Paint()
    ..color = lk.curb
    ..strokeWidth = 2;
  final dash = Paint()
    ..color = lk.line.withValues(alpha: 0.85)
    ..strokeWidth = 2;
  final zebra = Paint()
    ..color = Colors.white.withValues(alpha: 0.9)
    ..strokeWidth = 3.5;
  for (var y = -townMargin; y < mapH + townMargin; y++) {
    for (var x = -townMargin; x < mapW + townMargin; x++) {
      if (!_isRoad(x, y)) continue;
      final xd = x.toDouble(), yd = y.toDouble();
      if (!_isRoad(x, y - 1)) c.drawLine(corner(xd, yd), corner(xd + 1, yd), curb);
      if (!_isRoad(x, y + 1)) c.drawLine(corner(xd, yd + 1), corner(xd + 1, yd + 1), curb);
      if (!_isRoad(x - 1, y)) c.drawLine(corner(xd, yd), corner(xd, yd + 1), curb);
      if (!_isRoad(x + 1, y)) c.drawLine(corner(xd + 1, yd), corner(xd + 1, yd + 1), curb);
      final row = _roadRow(y), col = _roadCol(x);
      if (row && col) continue; // 교차로 한가운데
      // 가운데 점선: 두 줄 찻길의 경계
      if (row && (y == -4 || y == mapH + 2)) c.drawLine(corner(xd + 0.2, yd + 1), corner(xd + 0.75, yd + 1), dash);
      if (col && (x == -4 || x == mapW + 2)) c.drawLine(corner(xd + 1, yd + 0.2), corner(xd + 1, yd + 0.75), dash);
      // 교차로 바로 앞 횡단보도
      if (row && (_roadCol(x + 1) || _roadCol(x - 1))) {
        for (var k = 0; k < 3; k++) {
          final yy = yd + 0.2 + k * 0.3;
          c.drawLine(corner(xd + 0.15, yy), corner(xd + 0.85, yy), zebra);
        }
      }
      if (col && (_roadRow(y + 1) || _roadRow(y - 1))) {
        for (var k = 0; k < 3; k++) {
          final xx = xd + 0.2 + k * 0.3;
          c.drawLine(corner(xx, yd + 0.15), corner(xx, yd + 0.85), zebra);
        }
      }
    }
  }
}

/// 안 산 땅의 바닥(주차장 아스팔트·공터 흙·공원 길)과 주차선. 지도 안 잔디를 깐 다음에 그린다.
void _lotGround(Canvas c, Game g) {
  final lk = _lookOf(g.branch);
  final paths = <Color, Path>{};
  void put(Color col, int x, int y) =>
      paths.putIfAbsent(col, Path.new).addPath(_diamond(x.toDouble(), y.toDouble(), 1, 1), Offset.zero);
  for (var py = 0; py < plotRows; py++) {
    for (var px = 0; px < plotCols; px++) {
      if (g.plots.contains((px, py))) continue;
      final lot = _lotOf(px, py);
      for (var y = py * plotSize; y < (py + 1) * plotSize; y++) {
        for (var x = px * plotSize; x < (px + 1) * plotSize; x++) {
          final edge = x == px * plotSize || y == py * plotSize || x == (px + 1) * plotSize - 1 || y == (py + 1) * plotSize - 1;
          switch (lot) {
            case _Lot.parking:
              put(edge ? lk.walk : (lk.night ? const Color(0xFF37474F) : const Color(0xFF8E9AA0)), x, y);
            case _Lot.empty:
              put(lk.tone((x + y).isEven ? const Color(0xFFC8A97E) : const Color(0xFFBF9F72)), x, y);
            case _Lot.park:
              final mid = plotSize ~/ 2;
              final path = x - px * plotSize == mid || y - py * plotSize == mid;
              if (path) put(lk.tone(const Color(0xFFEAD9B0)), x, y);
            case _Lot.flowers:
              break;
          }
        }
      }
    }
  }
  for (final e in paths.entries) {
    c.drawPath(e.value, Paint()..color = e.key);
  }
  // 주차장 주차선
  final white = Paint()
    ..color = Colors.white.withValues(alpha: 0.85)
    ..strokeWidth = 1.6;
  for (var py = 0; py < plotRows; py++) {
    for (var px = 0; px < plotCols; px++) {
      if (g.plots.contains((px, py)) || _lotOf(px, py) != _Lot.parking) continue;
      final x0 = px * plotSize + 1.0, y0 = py * plotSize + 1.0;
      for (var k = 0; k <= plotSize - 2; k += 1) {
        c.drawLine(corner(x0 + k, y0 + 0.5), corner(x0 + k, y0 + 2.4), white);
        c.drawLine(corner(x0 + k, y0 + plotSize - 4.4), corner(x0 + k, y0 + plotSize - 2.5), white);
      }
    }
  }
}

/// 가장자리 안개: 그려진 땅의 끝이 하늘색으로 부드럽게 사라진다. [front] 면 앞쪽 두 변, 아니면 뒤쪽 두 변.
void _townFog(Canvas c, Color sky, {required bool front}) {
  final m = townMargin.toDouble(), f = _fog.toDouble();
  final o = [corner(-m, -m), corner(mapW + m, -m), corner(mapW + m, mapH + m), corner(-m, mapH + m)];
  final i = [corner(-m + f, -m + f), corner(mapW + m - f, -m + f), corner(mapW + m - f, mapH + m - f), corner(-m + f, mapH + m - f)];
  // 뒤쪽 변: 0-1(오른쪽 위), 3-0(왼쪽 위). 앞쪽 변: 1-2, 2-3.
  final edges = front ? const [(1, 2), (2, 3)] : const [(0, 1), (3, 0)];
  for (final (a, b) in edges) {
    final quad = _quad(o[a], o[b], i[b], i[a]);
    final from = Offset.lerp(o[a], o[b], 0.5)!, to = Offset.lerp(i[a], i[b], 0.5)!;
    c.drawPath(quad, Paint()..shader = ui.Gradient.linear(from, to, [sky, sky.withValues(alpha: 0)]));
    // 바깥은 하늘색으로 덮는다(끝의 지그재그 칸을 가린다)
    final out = from + (from - to) * 3;
    c.drawPath(_quad(o[a], o[b], o[b] + (out - from), o[a] + (out - from)), Paint()..color = sky);
  }
}

// ---------------------------------------------------------------- 건물·나무 (정해진 자리)

/// 동네 물건 하나. (x, y) 는 깊이(그리는 순서)용 앞쪽 칸.
class _Scenery {
  final double x, y;
  final void Function(Canvas) draw;
  _Scenery(this.x, this.y, this.draw);
}

/// 지도 바깥과 안 산 땅의 동네 물건들.
List<_Scenery> _townScenery(Game g) {
  final lk = _lookOf(g.branch);
  final out = <_Scenery>[];
  final piyak = g.branch == 'piyak';
  final used = <Tile>{};
  bool free(int x0, int y0, int w, int d) {
    for (var y = y0 - 1; y <= y0 + d; y++) {
      for (var x = x0 - 1; x <= x0 + w; x++) {
        final inside = x >= x0 && x < x0 + w && y >= y0 && y < y0 + d;
        if (inside && (_outside(x, y) < 5 || _isRoad(x, y) || _isWalk(x, y) || used.contains((x, y)))) return false;
        if (inside && (x < -townMargin + 2 || y < -townMargin + 2 || x >= mapW + townMargin - 2 || y >= mapH + townMargin - 2)) {
          return false;
        }
        if (lk.beach && inside && y < -6) return false;
      }
    }
    return true;
  }

  void take(int x0, int y0, int w, int d) {
    for (var y = y0; y < y0 + d; y++) {
      for (var x = x0; x < x0 + w; x++) {
        used.add((x, y));
      }
    }
  }

  // 메가마트(삐약동) 먼저 자리를 잡는다
  if (piyak) {
    take(_megaX, _megaY, _megaW, _megaD);
    final stage = megaStage(g.owner);
    out.add(_Scenery(_megaX + _megaW - 1.0, _megaY + _megaD - 1.0, (c) => _megaMart(c, stage)));
  }

  // 찻길·인도 바로 바깥 줄부터 안쪽으로: 크기가 다른 건물을 빈틈없이 늘어놓는다
  for (var y = -townMargin; y < mapH + townMargin; y++) {
    for (var x = -townMargin; x < mapW + townMargin; x++) {
      final r = _hash(x, y, 31);
      final w = r < 0.5 ? 2 : 3, d = _hash(x, y, 32) < 0.5 ? 2 : 3;
      if (!free(x, y, w, d)) continue;
      // 찻길에 붙은 줄(인도 바로 옆)이면 건물, 더 안쪽은 가끔 건물·작은 공원
      var nearWalk = false;
      for (var yy = y - 1; yy <= y + d && !nearWalk; yy++) {
        for (var xx = x - 1; xx <= x + w && !nearWalk; xx++) {
          nearWalk = _isWalk(xx, yy);
        }
      }
      if (!nearWalk && _hash(x, y, 33) > 0.22) continue;
      take(x, y, w, d);
      final rr = _hash(x, y, 34);
      out.add(_Scenery(x + w - 1.0, y + d - 1.0, (c) => _building(c, lk, x, y, w, d, rr, street: nearWalk)));
    }
  }

  // 남는 땅: 나무 듬성듬성
  for (var y = -townMargin + 1; y < mapH + townMargin - 1; y++) {
    for (var x = -townMargin + 1; x < mapW + townMargin - 1; x++) {
      if (_outside(x, y) < 5 || _isRoad(x, y) || _isWalk(x, y) || used.contains((x, y))) continue;
      if (lk.beach && y < -6) continue;
      if (_hash(x, y, 7) > 0.18) continue;
      out.add(_Scenery(x + 0.0, y + 0.0, (c) => _tree(c, lk, iso(x + 0.0, y + 0.0), _hash(x, y, 8))));
    }
  }
  // 바닷가 등대·파라솔, 눈 마을 큰 눈사람
  if (lk.beach) {
    out.add(_Scenery(14, -13, (c) => _lighthouse(c, iso(14, -13))));
    for (var k = 0; k < 6; k++) {
      final x = -6 + k * 7, y = -7 - (k % 2);
      out.add(_Scenery(x + 0.0, y + 0.0, (c) => _umbrella(c, iso(x + 0.0, y + 0.0), _hash(x, y, 51))));
    }
  }
  if (lk.snow) out.add(_Scenery(-8, 10, (c) => _snowman(c, iso(-8, 10), 2.2)));

  // 인도 가로등: 고리 안쪽 인도에 6칸마다
  for (var t = -townMargin + 2; t < max(mapW, mapH) + townMargin; t += 6) {
    for (final (x, y) in [(t, -2), (-2, t), (t, mapH + 1), (mapW + 1, t)]) {
      if (_outside(x, y) != 2) continue;
      out.add(_Scenery(x + 0.0, y + 0.0, (c) => _lamp(c, lk, iso(x + 0.0, y + 0.0))));
    }
  }

  // 안 산 땅: 쓰임에 맞는 물건. 내 땅에서 두 칸 이상 떨어진 곳에만(가게 물건을 가리지 않게)
  bool nearMine(int x, int y) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        if (g.owns((x + dx, y + dy))) return true;
      }
    }
    return false;
  }

  for (var py = 0; py < plotRows; py++) {
    for (var px = 0; px < plotCols; px++) {
      if (g.plots.contains((px, py))) continue;
      final lot = _lotOf(px, py);
      final x0 = px * plotSize, y0 = py * plotSize;
      switch (lot) {
        case _Lot.park:
          final pond = (x0 + 2, y0 + 2);
          if (!nearMine(pond.$1, pond.$2)) out.add(_Scenery(pond.$1 + 0.0, pond.$2 + 0.0, (c) => _pond(c, lk, pond)));
          for (final (x, y) in [(x0 + 5, y0 + 1), (x0 + 6, y0 + 6), (x0 + 1, y0 + 6), (x0 + 6, y0 + 3)]) {
            if (!nearMine(x, y)) out.add(_Scenery(x + 0.0, y + 0.0, (c) => _tree(c, lk, iso(x + 0.0, y + 0.0), _hash(x, y, 61))));
          }
          final b = (x0 + 3, y0 + 5);
          if (!nearMine(b.$1, b.$2)) out.add(_Scenery(b.$1 + 0.0, b.$2 + 0.0, (c) => _bench(c, iso(b.$1 + 0.0, b.$2 + 0.0))));
        case _Lot.parking:
          for (var k = 0; k < plotSize - 2; k++) {
            if (_hash(x0 + k, y0, 71) > 0.55) continue;
            for (final (x, y) in [(x0 + 1 + k, y0 + 1.3), (x0 + 1 + k, y0 + plotSize - 3.2)]) {
              if (nearMine(x, y.round())) continue;
              final col = _carColors[(_hash(x, y.round(), 72) * _carColors.length).floor() % _carColors.length];
              out.add(_Scenery(x + 0.0, y, (c) => _car(c, x + 0.0, y, false, 1, col)));
            }
          }
        case _Lot.empty:
          final s = (x0 + plotSize ~/ 2, y0 + plotSize ~/ 2);
          if (!nearMine(s.$1, s.$2)) out.add(_Scenery(s.$1 + 0.0, s.$2 + 0.0, (c) => _forSale(c, iso(s.$1 + 0.0, s.$2 + 0.0))));
          for (var k = 0; k < 4; k++) {
            final x = x0 + 1 + (_hash(px, py, 80 + k) * (plotSize - 2)).floor(), y = y0 + 1 + (_hash(py, px, 90 + k) * (plotSize - 2)).floor();
            if (!nearMine(x, y)) out.add(_Scenery(x + 0.0, y + 0.0, (c) => _bush(c, lk, iso(x + 0.0, y + 0.0))));
          }
        case _Lot.flowers:
          if (lk.snow) {
            for (var k = 0; k < 3; k++) {
              final x = x0 + 2 + k * 2, y = y0 + 2 + (k % 2) * 3;
              if (!nearMine(x, y)) out.add(_Scenery(x + 0.0, y + 0.0, (c) => _snowman(c, iso(x + 0.0, y + 0.0), 1.0)));
            }
            break;
          }
          for (var y = y0 + 1; y < y0 + plotSize - 1; y += 2) {
            for (var x = x0 + 1; x < x0 + plotSize - 1; x++) {
              if (!nearMine(x, y)) out.add(_Scenery(x + 0.0, y + 0.0, (c) => _flowers(c, iso(x + 0.0, y + 0.0), _hash(x, y, 13))));
            }
          }
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------- 그림 조각

/// 바닥 (x0..x0+w, y0..y0+d) 칸 위에 높이 h 상자. 앞의 두 면과 윗면만 보인다.
void _tbox(Canvas c, double x0, double y0, double w, double d, double h, Color left, Color right, Color top) {
  final up = Offset(0, -h);
  final a = corner(x0, y0 + d), b = corner(x0 + w, y0 + d), r = corner(x0 + w, y0), t = corner(x0, y0);
  c.drawPath(_quad(a, b, b + up, a + up), Paint()..shader = ui.Gradient.linear(a + up, a, [Color.lerp(left, Colors.white, 0.12)!, left]));
  c.drawPath(_quad(b, r, r + up, b + up), Paint()..shader = ui.Gradient.linear(b + up, b, [Color.lerp(right, Colors.white, 0.08)!, right]));
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
      final q = _quad(a, b, b + const Offset(0, -10), a + const Offset(0, -10));
      c.drawPath(q, Paint()..color = glass);
      c.drawPath(q, Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8);
    }
  }
}

/// 옆면(오른쪽 아래를 보는 면)에 창문 줄.
void _sideWindows(Canvas c, double x1, double y0, double d, double fromH, double toH, Color glass) {
  for (var y = y0 + 0.3; y + 0.5 <= y0 + d; y += 1) {
    for (var h = fromH; h + 10 <= toH; h += 18) {
      final a = corner(x1, y + 0.45) + Offset(0, -h), b = corner(x1, y) + Offset(0, -h);
      final q = _quad(a, b, b + const Offset(0, -10), a + const Offset(0, -10));
      c.drawPath(q, Paint()..color = glass);
      c.drawPath(q, Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8);
    }
  }
}

const _pastels = [
  Color(0xFFFFCDD2), Color(0xFFFFF59D), Color(0xFFC8E6C9), Color(0xFFBBDEFB), Color(0xFFE1BEE7), Color(0xFFFFE0B2),
  Color(0xFFD7CCC8), Color(0xFFB2DFDB),
];
const _roofs = [Color(0xFFE57373), Color(0xFF64B5F6), Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF8D6E63)];

/// 건물 한 채: 집(세모 지붕)·가게(차양·간판)·아파트(옥상 실외기)·작은 공원 중 하나. [street] 면 찻길에 붙은 줄.
void _building(Canvas c, _Look lk, int x0i, int y0i, int w, int d, double r, {required bool street}) {
  final x0 = x0i + 0.0, y0 = y0i + 0.0;
  final wall = _pastels[(r * 97).floor() % _pastels.length];
  final dark = Color.lerp(wall, Colors.black, 0.14)!;
  final glass = lk.night ? const Color(0xFFFFE082) : const Color(0xFFB3E5FC);
  final ox = x0 - 0.5 + 0.15, oy = y0 - 0.5 + 0.15, ow = w - 0.3, od = d - 0.3; // 칸 가장자리에서 조금 들인 바닥
  if (lk.beach && r < 0.45) {
    _hut(c, x0, y0, wall, r);
    _palm(c, iso(x0 + w - 0.3, y0 - 0.2), r);
    return;
  }
  if (!street && r < 0.4) {
    // 작은 공원: 나무와 의자
    _tree(c, lk, iso(x0, y0), r);
    _tree(c, lk, iso(x0 + w - 1, y0 + 0.3), 1 - r);
    _bench(c, iso(x0 + w / 2 - 0.5, y0 + d - 1));
    return;
  }
  final kind = (r * 3).floor(); // 0 집, 1 가게, 2 아파트
  if (kind == 0 && !lk.night) {
    // 집: 낮은 벽, 세모 지붕, 문, 창문, 굴뚝
    const h = 30.0;
    _tbox(c, ox, oy, ow, od, h, wall, dark, wall);
    final roof = lk.snow ? Colors.white : _roofs[(r * 31).floor() % _roofs.length];
    const lip = 0.12;
    final top = [corner(ox - lip, oy - lip), corner(ox + ow + lip, oy - lip), corner(ox + ow + lip, oy + od + lip), corner(ox - lip, oy + od + lip)]
        .map((p) => p + const Offset(0, -h))
        .toList();
    final apex = iso(ox + ow / 2 - 0.5 + 0.5, oy + od / 2) + Offset(0, -h - 14 - 8.0 * min(w, d));
    for (final (i, j) in [(0, 1), (3, 0), (1, 2), (2, 3)]) {
      final tri = Path()
        ..moveTo(top[i].dx, top[i].dy)
        ..lineTo(top[j].dx, top[j].dy)
        ..lineTo(apex.dx, apex.dy)
        ..close();
      c.drawPath(tri, Paint()..color = (i == 1 || i == 2) ? Color.lerp(roof, Colors.black, 0.18)! : roof);
      c.drawPath(tri, _stroke(1.3));
    }
    // 굴뚝
    final ch = Offset.lerp(top[1], apex, 0.45)!;
    c.drawRect(Rect.fromLTWH(ch.dx - 3, ch.dy - 12, 6, 12), Paint()..color = const Color(0xFF8D6E63));
    c.drawRect(Rect.fromLTWH(ch.dx - 3, ch.dy - 12, 6, 12), _stroke(1));
    // 문과 창문
    final da = corner(ox + ow * 0.45, oy + od), db = corner(ox + ow * 0.45 + 0.35, oy + od);
    c.drawPath(_quad(da, db, db + const Offset(0, -18), da + const Offset(0, -18)), Paint()..color = const Color(0xFF8D6E63));
    c.drawPath(_quad(da, db, db + const Offset(0, -18), da + const Offset(0, -18)), _stroke(1));
    _windows(c, ox, oy + od, ow * 0.4, 10, 22, glass);
    _sideWindows(c, ox + ow, oy, od, 10, 22, glass);
    return;
  }
  // 가게·아파트
  final h = kind == 2 || lk.night ? 64.0 + r * 50 + (w + d) * 6 : 40.0;
  final top = Color.lerp(wall, Colors.white, 0.3)!;
  _tbox(c, ox, oy, ow, od, h, wall, dark, top);
  if (kind == 2 || lk.night) {
    _windows(c, ox, oy + od, ow, 22, h - 6, glass);
    _sideWindows(c, ox + ow, oy, od, 22, h - 6, glass);
    // 옥상 실외기
    final ac = corner(ox + ow * 0.3, oy + od * 0.3) + Offset(0, -h);
    c.drawRect(Rect.fromCenter(center: ac + const Offset(0, -4), width: 12, height: 8), Paint()..color = const Color(0xFFCFD8DC));
    c.drawRect(Rect.fromCenter(center: ac + const Offset(0, -4), width: 12, height: 8), _stroke(1));
    if (lk.snow) {
      c.drawPath(_quad(corner(ox, oy) + Offset(0, -h), corner(ox + ow, oy) + Offset(0, -h), corner(ox + ow, oy + od) + Offset(0, -h),
          corner(ox, oy + od) + Offset(0, -h)), Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
  } else {
    // 가게: 큰 유리창, 간판 띠, 줄무늬 차양
    final a = corner(ox + 0.15, oy + od), b = corner(ox + ow - 0.15, oy + od);
    c.drawPath(_quad(a + const Offset(0, -4), b + const Offset(0, -4), b + const Offset(0, -22), a + const Offset(0, -22)),
        Paint()..color = glass);
    final sa = corner(ox, oy + od) + Offset(0, -h + 4), sb = corner(ox + ow, oy + od) + Offset(0, -h + 4);
    final signCol = _roofs[(r * 53).floor() % _roofs.length];
    c.drawPath(_quad(sa, sb, sb + const Offset(0, 9), sa + const Offset(0, 9)), Paint()..color = signCol);
    c.drawPath(_quad(sa, sb, sb + const Offset(0, 9), sa + const Offset(0, 9)), _stroke(1));
    final aa = corner(ox, oy + od) + const Offset(0, -24), ab = corner(ox + ow, oy + od) + const Offset(0, -24);
    final stripes = (ow * 3).round();
    for (var k = 0; k < stripes; k++) {
      final p0 = Offset.lerp(aa, ab, k / stripes)!, p1 = Offset.lerp(aa, ab, (k + 1) / stripes)!;
      c.drawPath(_quad(p0, p1, p1 + const Offset(-5, 8), p0 + const Offset(-5, 8)), Paint()..color = k.isEven ? signCol : Colors.white);
    }
    c.drawPath(_quad(aa, ab, ab + const Offset(-5, 8), aa + const Offset(-5, 8)), _stroke(1.1));
    _sideWindows(c, ox + ow, oy, od, 14, h - 8, glass);
  }
  if (lk.night) {
    // 네온 간판
    final p = corner(ox + ow / 2, oy + od) + Offset(0, -h * 0.62);
    final neon = [const Color(0xFFFF4081), const Color(0xFF18FFFF), const Color(0xFFFFEB3B)][(r * 7).floor() % 3];
    c.drawCircle(p, 18, Paint()..color = neon.withValues(alpha: 0.22));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 28, height: 10), const Radius.circular(4)), Paint()..color = neon);
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
  _tbox(c, x - 0.3, y - 0.3, 1.6, 1.6, 26, const Color(0xFFFFF3E0), const Color(0xFFFFE0B2), const Color(0xFFFFF3E0));
  final p = iso(x + 0.5, y + 0.5) + const Offset(0, -26);
  final roof = Path()..addOval(Rect.fromCenter(center: p + const Offset(0, -6), width: 92, height: 34));
  c.drawPath(roof, Paint()..color = _roofs[(r * 31).floor() % _roofs.length]);
  c.drawPath(roof, _stroke(1.5));
}

void _umbrella(Canvas c, Offset p, double r) {
  c.drawLine(p, p + const Offset(0, -30), Paint()
    ..color = const Color(0xFF8D6E63)
    ..strokeWidth = 2);
  final cols = [_roofs[(r * 6).floor() % _roofs.length], Colors.white];
  for (var k = 0; k < 6; k++) {
    final a0 = pi + k * pi / 6, a1 = pi + (k + 1) * pi / 6;
    final path = Path()
      ..moveTo(p.dx, p.dy - 34)
      ..lineTo(p.dx + cos(a0) * 22, p.dy - 26 + sin(a0) * 6)
      ..lineTo(p.dx + cos(a1) * 22, p.dy - 26 + sin(a1) * 6)
      ..close();
    c.drawPath(path, Paint()..color = cols[k % 2]);
  }
  c.drawOval(Rect.fromCenter(center: p + const Offset(8, 4), width: 26, height: 10), Paint()..color = const Color(0x55FFFFFF));
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
  for (var i = 0; i < 6; i++) {
    final q = p + Offset(cos(i * 2.4 + r * 6) * 10, sin(i * 2.4 + r * 6) * 4 - 2);
    c.drawLine(q, q + const Offset(0, 5), Paint()
      ..color = const Color(0xFF558B2F)
      ..strokeWidth = 1.2);
    c.drawCircle(q, 2.8, Paint()..color = cols[(i + (r * 4).floor()) % cols.length]);
  }
}

/// 벤치: 다리 넷, 나무 판자 의자와 등받이.
void _bench(Canvas c, Offset p) {
  final a = p + const Offset(-14, -2), b = p + const Offset(12, 10);
  final legs = Paint()
    ..color = const Color(0xFF5D4037)
    ..strokeWidth = 2;
  for (final q in [a, b, a + const Offset(6, -4), b + const Offset(6, -4)]) {
    c.drawLine(q, q + const Offset(0, -9), legs);
  }
  final seat = _quad(a + const Offset(0, -9), b + const Offset(0, -9), b + const Offset(6, -13), a + const Offset(6, -13));
  c.drawPath(seat, Paint()..color = const Color(0xFFBC8A5F));
  c.drawPath(seat, _stroke(1.2));
  final back = _quad(a + const Offset(6, -13), b + const Offset(6, -13), b + const Offset(6, -22), a + const Offset(6, -22));
  c.drawPath(back, Paint()..color = const Color(0xFFA47148));
  c.drawPath(back, _stroke(1.2));
}

/// 공원 연못: 물결이 비치는 타원과 돌 테두리.
void _pond(Canvas c, _Look lk, Tile t) {
  final p = iso(t.$1 + 0.5, t.$2 + 0.5);
  final rect = Rect.fromCenter(center: p, width: tw * 2.2, height: th * 2.2);
  c.drawOval(rect.inflate(4), Paint()..color = lk.tone(const Color(0xFFB0BEC5)));
  // 눈 마을은 얼어 있다
  c.drawOval(rect, Paint()..color = lk.snow ? const Color(0xFFD6EEF8) : (lk.night ? const Color(0xFF1E3A5F) : const Color(0xFF64B5F6)));
  c.drawOval(rect.deflate(10).shift(const Offset(-6, -3)), Paint()..color = const Color(0x55FFFFFF));
  c.drawOval(rect.inflate(4), _stroke(1.2));
}

/// 공터 매물 표지판.
void _forSale(Canvas c, Offset p) {
  c.drawLine(p, p + const Offset(0, -26), Paint()
    ..color = const Color(0xFF6D4C41)
    ..strokeWidth = 2.5);
  final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(0, -32), width: 34, height: 18), const Radius.circular(3));
  c.drawRRect(r, Paint()..color = Colors.white);
  c.drawRRect(r, _stroke(1.2));
  _text(c, p + const Offset(0, -32), S.t('town_forsale'), const Color(0xFFE53935), 10);
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
  const x = _megaX - 0.5, y = _megaY - 0.5, w = _megaW + 0.0, d = _megaD + 0.0;
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
  _text(c, Offset.zero, annex ? S.t('town_annex') : 'MEGA MART', Colors.white, 14);
  c.restore();
}

// ---------------------------------------------------------------- 지나가는 차와 사람 (매 장면)

const _carColors = [
  Color(0xFFEF5350), Color(0xFF42A5F5), Color(0xFFFFCA28), Color(0xFF66BB6A), Color(0xFFAB47BC), Color(0xFFFFFFFF),
  Color(0xFF78909C),
];

/// 차선: (x 방향인가, 고정 좌표(칸 가운데), 방향 +1/-1). 찻길은 바깥 끝까지 이어진다.
const _lanes = [
  (true, -3.0, 1), (true, -4.0, -1), // 오른쪽 위 찻길
  (false, -3.0, -1), (false, -4.0, 1), // 왼쪽 위 찻길
  (true, mapH + 2.0, -1), (true, mapH + 3.0, 1), // 왼쪽 아래 찻길
  (false, mapW + 2.0, 1), (false, mapW + 3.0, -1), // 오른쪽 아래 찻길
];

/// 시각 [t] 의 차들: (x, y, x 방향인가, 방향, 색). 상태 없이 시각에서 바로 구한다.
Iterable<(double, double, bool, int, Color)> _cars(double t) sync* {
  for (final (i, (alongX, fixed, dir)) in _lanes.indexed) {
    final len = (alongX ? mapW : mapH) + 2.0 * (townMargin - 2);
    for (var k = 0; k < 3; k++) {
      final speed = 2.2 + _hash(i, k, 21) * 1.5;
      var s = (_hash(i, k, 22) * len + t * speed) % len;
      if (dir < 0) s = len - s;
      final along = -(townMargin - 2) + s;
      final col = _carColors[(i * 3 + k) % _carColors.length];
      yield alongX ? (along, fixed, true, dir, col) : (fixed, along, false, dir, col);
    }
  }
}

/// 차 한 대: 몸통·지붕·창문·바퀴·전조등. 끝자락(안개 속)에선 흐려진다.
void _car(Canvas c, double x, double y, bool alongX, int dir, Color col) {
  final along = alongX ? x : y, len = alongX ? mapW : mapH;
  final edge = min(along + townMargin - 2, len + townMargin - 2 - along);
  final fade = (edge / 4).clamp(0.0, 1.0);
  if (fade <= 0) return;
  if (fade < 1) c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, fade));
  final w = alongX ? 1.3 : 0.62, d = alongX ? 0.62 : 1.3;
  final x0 = x - w / 2, y0 = y - d / 2;
  c.drawOval(Rect.fromCenter(center: iso(x, y) + const Offset(0, 3), width: 48, height: 18), Paint()..color = const Color(0x33000000));
  // 바퀴(앞 두 면 쪽만 보인다)
  final wheel = Paint()..color = const Color(0xFF263238);
  for (final (wx, wy) in alongX ? [(x0 + 0.2, y0 + d), (x0 + w - 0.2, y0 + d)] : [(x0 + w, y0 + 0.2), (x0 + w, y0 + d - 0.2)]) {
    c.drawOval(Rect.fromCenter(center: corner(wx + 0.5, wy + 0.5) + const Offset(0, -2), width: 8, height: 7), wheel);
  }
  _tbox(c, x0 + 0.5, y0 + 0.5, w, d, 9, col, Color.lerp(col, Colors.black, 0.2)!, Color.lerp(col, Colors.white, 0.18)!);
  // 지붕(창문)
  final cw = alongX ? 0.62 : 0.5, cd = alongX ? 0.5 : 0.62;
  c.save();
  c.translate(0, -9);
  final cx = x - cw / 2 + 0.5 + (alongX ? -0.06 * dir : 0), cy = y - cd / 2 + 0.5 + (alongX ? 0 : -0.06 * dir);
  _tbox(c, cx, cy, cw, cd, 8, const Color(0xFF90CAF9), const Color(0xFF64B5F6), Color.lerp(col, Colors.white, 0.1)!);
  c.restore();
  // 전조등: 가는 쪽 끝
  final head = alongX ? corner(x0 + 0.5 + (dir > 0 ? w : 0), y0 + 0.5 + d * 0.8) : corner(x0 + 0.5 + w * 0.8, y0 + 0.5 + (dir > 0 ? d : 0));
  c.drawCircle(head + const Offset(0, -5), 2.2, Paint()..color = const Color(0xFFFFF59D));
  if (fade < 1) c.restore();
}

/// 인도 위를 걷는 사람들: (x, y, dx, dy, 얼굴 번호).
Iterable<(double, double, double, double, int)> _walkers(double t) sync* {
  const sides = [
    (true, -2.0, 1), (false, -2.0, -1), (true, mapH + 1.0, -1), (false, mapW + 1.0, 1),
    (true, -2.0, -1), (false, -2.0, 1), (true, -5.0, 1), (false, -5.0, -1),
  ];
  for (final (i, (alongX, fixed, dir)) in sides.indexed) {
    final len = (alongX ? mapW : mapH) + 6.0;
    var s = (_hash(i, 1, 31) * len + t * 0.9) % len;
    if (dir < 0) s = len - s;
    final along = -3 + s;
    final look = customerChars[(i * 7 + 3) % customerChars.length];
    yield alongX ? (along, fixed, dir.toDouble(), 0.0, look) : (fixed, along, 0.0, dir.toDouble(), look);
  }
}
