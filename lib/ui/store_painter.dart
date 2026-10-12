import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../engine/world.dart';
import '../strings.dart';
import 'sprites.dart';

part 'town.dart';

/// 단골 이름 (화면 글자 표에서).
String regularName(String id) => S.t('reg_${id}_name');

// 가구는 일부(진열 선반·상자·화분·의자·탁자·전등·휴지통)만 그림이고 나머지는 페인터 그림이다.

const tw = 64.0, th = 32.0; // 바닥 한 칸의 화면 크기 (2:1 아이소)
const wallH = 60.0;
const ink = Color(0xFF5D4037); // 외곽선

/// 칸 좌표 → 그림 좌표. 정수 값이 칸 한가운데다.
Offset iso(double x, double y) => Offset((x - y) * tw / 2, (x + y + 1) * th / 2);

/// 칸 모서리 좌표(칸 중앙에서 반 칸씩 어긋난 격자) → 그림 좌표.
Offset corner(double x, double y) => iso(x - 0.5, y - 0.5);

/// 그림 좌표 → 칸.
Tile tileOf(Offset p) {
  final a = p.dx / (tw / 2), b = p.dy / (th / 2) - 1;
  return (((a + b) / 2).round(), ((b - a) / 2).round());
}

/// 물건이 화면에서 위로 솟은 높이(그림 좌표). 누른 곳 찾기에 쓴다.
double itemHeight(String type) => switch (type) {
      'fridge' => 70,
      'rack' || 'register' || 'bakerycase' || 'coffeemachine' || 'hotcounter' || 'fruitstand' => 56,
      'plant' || 'lamp' || 'claw' => 60,
      'vending' || 'photo' => 72,
      'atm' || 'service' => 56,
      'selfcheck' => 64,
      'freezer' || 'box' || 'bin' || 'chair' || 'table' || 'flowers' => 40,
      _ => 0,
    };

/// 그림 좌표 [p] 를 누른 것: 보이는 물건(솟은 몸통 포함)이 있으면 그 칸, 없으면 바닥 칸.
/// 앞에 그려진 것(x+y 큰 것)이 먼저다.
Tile tileAtPoint(Game g, Offset p) {
  Item? best;
  for (final i in g.items) {
    final h = itemHeight(i.type);
    if (h == 0) continue;
    final feet = iso(i.c + 0.0, i.r + 0.0);
    final box = Rect.fromLTRB(feet.dx - tw * 0.42, feet.dy - h, feet.dx + tw * 0.42, feet.dy + th * 0.45);
    if (box.contains(p) && (best == null || i.c + i.r > best.c + best.r)) best = i;
  }
  return best?.tile ?? tileOf(p);
}

/// 화면 방향(조이스틱) → 세계 방향.
(double, double) screenToWorld(double u, double v) {
  final a = u / (tw / 2), b = v / (th / 2);
  return ((a + b) / 2, (b - a) / 2);
}

/// 지도 전체를 담는 사각형(그림 좌표).
Rect get mapBounds => Rect.fromLTRB(-mapH * tw / 2 - 160, -wallH - 160, mapW * tw / 2 + 160, (mapW + mapH) * th / 2 + 120);

Color productColor(String id) => Color(0xFF000000 | ((id.hashCode * 2654435761) & 0x7F7F7F) + 0x606060);

/// 동네마다 다른 색: (잔디 두 톤, 바닥 두 톤, 왼벽, 오른벽, 띠).
class MapTheme {
  final Color grassA, grassB, floorA, floorB, wallL, wallR, band, sky;
  const MapTheme(this.grassA, this.grassB, this.floorA, this.floorB, this.wallL, this.wallR, this.band, this.sky);
}

const themes = {
  'piyak': MapTheme(Color(0xFFC5E1A5), Color(0xFFB9DB94), Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFF8BBD0),
      Color(0xFFFCE4EC), Color(0xFFF48FB1), Color(0xFFDCEDC8)),
  'beach': MapTheme(Color(0xFFFFE9B0), Color(0xFFFFE09A), Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFF80DEEA),
      Color(0xFFB2EBF2), Color(0xFF26C6DA), Color(0xFFB3E5FC)),
  'night': MapTheme(Color(0xFF455A64), Color(0xFF3E4F58), Color(0xFFD1C4E9), Color(0xFFB39DDB), Color(0xFF7E57C2),
      Color(0xFF9575CD), Color(0xFFFF4081), Color(0xFF37474F)),
  'snow': MapTheme(Color(0xFFF5F7FA), Color(0xFFE8EEF4), Color(0xFFFFF3E0), Color(0xFFFFE0B2), Color(0xFFBCAAA4),
      Color(0xFFD7CCC8), Color(0xFF8D6E63), Color(0xFFE3F2FD)),
};

MapTheme themeOf(String branch) => themes[branch] ?? themes['piyak']!;

/// 날아가는 물건·돈, 떠오르는 글자.
class Flight {
  final Fx fx;
  double age = 0;
  Flight(this.fx);
  double get life => switch (fx.kind) {
        FxKind.pick || FxKind.place || FxKind.cash => 0.28,
        FxKind.tip => 0.5,
        FxKind.scan => 0,
        FxKind.levelUp || FxKind.goal || FxKind.regular => 1.6,
        FxKind.event || FxKind.day || FxKind.incident || FxKind.combo => 0,
        _ => 1.0,
      };
}

/// 건설 모드에서 화면에 얹을 것.
class BuildView {
  String? place; // 놓으려는 것
  String? product; // 진열대·상자에 넣을 상품
  int rot = 0;
  Tile? hover; // 놓을 자리(마지막으로 누른 칸)
  bool land = false; // 땅 사기 화면
  Item? selected; // 고른 물건
  Item? moving; // 옮기는 중인 물건

  /// 미리보기로 그릴 물건 종류 (놓기·옮기기 중일 때).
  String? get ghostType => moving?.type ?? (place == 'eraser' || (place?.startsWith('floor-') ?? false) ? null : place);
}

/// 카메라: 가운데에 올 그림 좌표와 확대 배율.
class Camera {
  Offset center;
  double zoom;
  Camera(this.center, this.zoom);

  Offset toScreen(Offset p, Size s) => (p - center) * zoom + s.center(Offset.zero);
  Offset toWorld(Offset p, Size s) => (p - s.center(Offset.zero)) / zoom + center;
  Rect visible(Size s) => Rect.fromCenter(center: center, width: s.width / zoom, height: s.height / zoom);
}

class StorePainter extends CustomPainter {
  final World world;
  final List<Flight> flights;
  final double clock;
  final Camera camera;
  final BuildView? build;
  final Tile? dest; // 누른 곳(걸어가는 목적지)
  final Tile? guide; // 처음 안내가 가리키는 칸

  StorePainter(this.world, this.flights, this.clock, this.camera, this.build, {this.dest, this.guide});

  Game get game => world.game;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(camera.zoom)
      ..translate(-camera.center.dx, -camera.center.dy);
    canvas.drawPicture(_basePicture(game));
    final view = camera.visible(size).inflate(120);
    bool seen(double x, double y) => view.contains(iso(x, y));
    _traffic(canvas, seen, behind: true);
    canvas.drawPicture(_wallPicture(game));
    _rankSign(canvas);
    if (world.holiday != null) _bunting(canvas, world.holiday!);

    final b = build;
    if (b != null && b.land) _plotsForSale(canvas);

    // 바닥에 붙은 것: 계산 자리, 줄(건설 중), 깔개·입구, 쓰레기
    for (final r in game.registers) {
      final (tc, tr) = r.till;
      canvas.drawPath(_diamond(tc.toDouble(), tr.toDouble(), 1, 1, 0.1), Paint()..color = const Color(0xFFB3E5FC));
      if (b != null) {
        for (final t in game.queueTiles(r)) {
          canvas.drawCircle(iso(t.$1 + 0.0, t.$2 + 0.0), 4, Paint()..color = const Color(0x5543A047));
        }
      }
    }
    for (final i in game.items) {
      if (!seen(i.c + 0.0, i.r + 0.0)) continue;
      if (i.type == 'rug') _rug(canvas, i.tile);
      if (i.type == 'entrance') _entrance(canvas, i.tile);
    }
    for (final t in game.trash) {
      _trash(canvas, t);
    }
    // 바닥에 떨어진 팁
    for (final t in world.tips.keys) {
      final p = iso(t.$1 + 0.0, t.$2 + 0.0) + Offset(0, sin(clock * 5 + t.$1) * 1.5);
      for (var k = 0; k < 3; k++) {
        final q = p + Offset(k * 3.0 - 3, -k * 3.0);
        canvas.drawOval(Rect.fromCenter(center: q, width: 14, height: 7), Paint()..color = const Color(0xFFFFC107));
        canvas.drawOval(Rect.fromCenter(center: q, width: 14, height: 7), _stroke(1));
      }
      final glint = (clock * 2 + t.$2) % 2.0;
      if (glint < 0.3) _text(canvas, p + const Offset(6, -14), '*', Colors.white, 10, outline: 1);
    }
    if (dest != null && world.player.path.isNotEmpty) {
      final p = iso(dest!.$1 + 0.0, dest!.$2 + 0.0);
      final k = 0.8 + 0.2 * sin(clock * 8);
      canvas.drawOval(
          Rect.fromCenter(center: p, width: 36 * k, height: 18 * k),
          Paint()
            ..color = const Color(0xFF43A047)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }

    // 뒤에서 앞으로(x+y 가 작은 것부터) 그린다.
    final draws = <(double, void Function())>[];
    void add(double x, double y, void Function() f) {
      if (seen(x, y)) draws.add((x + y, f));
    }

    for (final i in game.items) {
      if (i.type == 'rug' || i.type == 'entrance') continue;
      add(i.c + 0.0, i.r + 0.0, () => drawItem(canvas, i.type, i.tile,
          product: i.product,
          stock: i.stock,
          rot: i.rot,
          cash: i.cash,
          clock: clock,
          highlight: b?.selected == i,
          level: i.level,
          managed: i.t.shelf != null && game.managers.contains(i.t.shelf)));
      if (i.broken) add(i.c + 0.01, i.r + 0.01, () => _brokenMark(canvas, i));
      if (i.raw > 0) add(i.c + 0.01, i.r + 0.01, () => _rawMark(canvas, i));
      if (i.t.kind == ItemKind.box && i.product != null && b == null) add(i.c + 0.01, i.r + 0.01, () => _boxStock(canvas, i));
      if (i.t.kind == ItemKind.shelf && (i.price != defaultPrice || game.inCombo(i) || game.expiring(i))) {
        add(i.c + 0.01, i.r + 0.01, () => _shelfTags(canvas, i));
      }
    }
    for (final s in world.staff) {
      final who = switch (s.kind) {
        Staff.cashier => cashierChar,
        Staff.stocker => stockerChar,
        Staff.janitor => janitorChar,
      };
      add(s.x, s.y + 0.02, () => _walker(canvas, s, who));
    }
    for (final c in world.customers) {
      add(c.x, c.y + 0.02, () => _customer(canvas, c));
    }
    final pl = world.player;
    add(pl.x, pl.y + 0.03, () {
      canvas.drawOval(
          Rect.fromCenter(center: iso(pl.x, pl.y), width: 34, height: 15),
          Paint()
            ..color = const Color(0xFFFFC107)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      _walker(canvas, pl, playerChar);
      if (world.order?.carrying == true) {
        final top = iso(pl.x, pl.y) + const Offset(0, -50);
        final box = Rect.fromCenter(center: top, width: 20, height: 15);
        canvas.drawRect(box, Paint()..color = const Color(0xFFD7A86E));
        canvas.drawRect(box, _stroke(1.5));
        canvas.drawLine(box.topCenter, box.bottomCenter, Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 2);
      }
    });
    for (final (x, y, alongX, dir, col) in _cars(clock)) {
      if (!_behind(x, y)) add(x, y, () => _car(canvas, x, y, alongX, dir, col));
    }
    for (final (x, y, dx, dy, look) in _walkers(clock)) {
      if (!_behind(x, y)) add(x, y, () => _char(canvas, look, x, y, Anim.walk, facingOf(dx, dy), fps: 8));
    }
    draws.sort((a, b) => a.$1.compareTo(b.$1));
    for (final d in draws) {
      d.$2();
    }
    canvas.drawPicture(_frontPicture(game));

    // 놓을 자리 미리보기
    if (b != null && b.ghostType != null && b.hover != null) _ghost(canvas, b);

    // 서비스 손님이 기다리는데 점장이 없으면 카운터를 가리킨다
    if (b == null && world.customers.any((c) => c.kind == CustomerKind.service && c.state == CState.atShelf)) {
      for (final d in game.items.where((i) => i.type == 'service')) {
        if (world.player.distTo(d.tile) < 1.6) continue;
        _arrow(canvas, iso(d.c + 0.0, d.r + 0.0) + Offset(0, -70 + sin(clock * 6) * 4));
      }
    }
    // 계산 기다리는 손님이 있는데 아무도 없는 계산대는 계산 자리를 가리킨다
    if (b == null) {
      for (final r in game.registers) {
        final q = world.queues[r];
        if (q == null || q.isEmpty || !q.first.arrived || world.staffedAt(r) || world.player.distTo(r.till) < standRadius) {
          continue;
        }
        if (r.type == 'selfcheck') continue; // 손님이 알아서 찍는다(오류는 🔧 표시)
        final till = iso(r.till.$1 + 0.0, r.till.$2 + 0.0);
        _arrow(canvas, till + Offset(0, -40 + sin(clock * 6) * 4));
      }
    }
    for (final f in flights) {
      _flight(canvas, f);
    }
    final g = guide;
    if (g != null) {
      final h = itemHeight(game.at(g)?.type ?? '') + 26;
      final p = iso(g.$1 + 0.0, g.$2 + 0.0) + Offset(0, -h + sin(clock * 6) * 6);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.scale(1.8);
      _arrow(canvas, Offset.zero);
      canvas.restore();
    }
    canvas.restore();
    if (world.phase != DayPhase.closed) _weather(canvas, size);
    if (world.night) {
      // 야간 영업: 화면 전체가 밤빛, 가운데는 조금 밝게(가게 불빛)
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(colors: const [Color(0x33101848), Color(0x99101848)], radius: 0.9)
                .createShader(Offset.zero & size));
    }
  }

  /// 비·눈은 화면 위에 그린다(가게 안팎 구분 없이 분위기만).
  void _weather(Canvas canvas, Size size) {
    final w = world.weather;
    if (w == Weather.hot) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x0FFF9800));
      return;
    }
    if (w != Weather.rain && w != Weather.cold) return;
    final rain = w == Weather.rain;
    if (rain) canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x14546E7A));
    final paint = Paint()
      ..color = rain ? const Color(0x8878909C) : const Color(0xDDFFFFFF)
      ..strokeWidth = rain ? 1.5 : 1;
    const n = 70;
    for (var i = 0; i < n; i++) {
      // 고정된 무작위 자리 + 시간에 따라 떨어진다
      final sx = (i * 73.13) % 1.0, sy = (i * 41.77) % 1.0;
      final speed = rain ? 0.9 + (i % 5) * 0.08 : 0.12 + (i % 4) * 0.03;
      final y = ((sy + clock * speed) % 1.0) * (size.height + 40) - 20;
      final x = (sx * size.width + (rain ? -y * 0.15 : sin(clock + i) * 12)) % size.width;
      if (rain) {
        canvas.drawLine(Offset(x, y), Offset(x - 3, y + 14), paint);
      } else {
        canvas.drawCircle(Offset(x, y), 2 + (i % 3) * 0.7, paint);
      }
    }
  }

  /// 벽 뒤쪽(먼저 그릴 쪽)의 차·사람. 앞쪽 것은 가게 물건과 함께 깊이 순서로 그린다.
  void _traffic(Canvas canvas, bool Function(double, double) seen, {required bool behind}) {
    final list = <(double, void Function())>[];
    for (final (x, y, alongX, dir, col) in _cars(clock)) {
      if (_behind(x, y) == behind && seen(x, y)) list.add((x + y, () => _car(canvas, x, y, alongX, dir, col)));
    }
    for (final (x, y, dx, dy, look) in _walkers(clock)) {
      if (_behind(x, y) == behind && seen(x, y)) {
        list.add((x + y, () => _char(canvas, look, x, y, Anim.walk, facingOf(dx, dy), fps: 8)));
      }
    }
    list.sort((a, b) => a.$1.compareTo(b.$1));
    for (final d in list) {
      d.$2();
    }
  }

  // ---------------------------------------------------------------- 바닥·벽 (캐시)

  static List<_Scenery>? _scenery;
  static (Game, int, int)? _sceneryKey;

  /// 동네 물건(정해진 자리, 깊이 순서). 땅을 사거나 이야기가 진행되면 다시 만든다.
  static List<_Scenery> _sceneryOf(Game g) {
    final key = (g, g.layoutVersion, megaStage(g.owner));
    if (_scenery != null && _sceneryKey == key) return _scenery!;
    _sceneryKey = key;
    return _scenery = _townScenery(g)..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
  }

  static ui.Picture? _front;
  static (Game, int, int)? _frontKey;

  /// 앞쪽(지도 오른쪽 아래·왼쪽 아래) 바깥 동네: 가게 안 모든 것보다 앞이라 맨 나중에 그린다.
  static ui.Picture _frontPicture(Game g) {
    final key = (g, g.layoutVersion, megaStage(g.owner));
    if (_front != null && _frontKey == key) return _front!;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    for (final s in _sceneryOf(g)) {
      if (!_behind(s.x, s.y) && (s.x >= mapW || s.y >= mapH)) s.draw(c);
    }
    _townFog(c, themeOf(g.branch).sky, front: true);
    _frontKey = key;
    return _front = rec.endRecording();
  }

  static ui.Picture? _cache;
  static (Game, int, int)? _cacheKey;

  static ui.Picture _basePicture(Game g) {
    final key = (g, g.layoutVersion, megaStage(g.owner));
    if (_cache != null && _cacheKey == key) return _cache!;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    _townGround(c, g);
    final grassA = Path(), grassB = Path(), floorA = Path(), floorB = Path();
    final painted = <String, Path>{};
    for (var r = 0; r < mapH; r++) {
      for (var x = 0; x < mapW; x++) {
        final p = _diamond(x.toDouble(), r.toDouble(), 1, 1);
        final even = (x + r).isEven;
        if (g.owns((x, r))) {
          final f = g.floors[(x, r)];
          if (f != null) {
            painted.putIfAbsent(f, Path.new).addPath(p, Offset.zero);
          } else {
            (even ? floorA : floorB).addPath(p, Offset.zero);
          }
        } else {
          (even ? grassA : grassB).addPath(p, Offset.zero);
        }
      }
    }
    final th0 = themeOf(g.branch);
    c.drawPath(grassA, Paint()..color = th0.grassA);
    c.drawPath(grassB, Paint()..color = th0.grassB);
    c.drawPath(floorA, Paint()..color = th0.floorA);
    c.drawPath(floorB, Paint()..color = th0.floorB);
    for (final e in painted.entries) {
      c.drawPath(e.value, Paint()..color = floorColor(e.key));
    }
    _lotGround(c, g);
    // 필지 경계(안 산 땅만, 옅게)
    final border = Paint()
      ..color = const Color(0x3365A30D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var py = 0; py < plotRows; py++) {
      for (var px = 0; px < plotCols; px++) {
        if (g.plots.contains((px, py))) continue;
        c.drawPath(
            _diamond((px * plotSize).toDouble(), (py * plotSize).toDouble(), plotSize.toDouble(), plotSize.toDouble(), 0.1),
            border);
      }
    }
    // 뒤쪽 동네와 안 산 땅의 덤불·나무 (벽보다 먼저)
    for (final s in _sceneryOf(g)) {
      if (_behind(s.x, s.y) || (s.x < mapW && s.y < mapH)) s.draw(c);
    }
    _townFog(c, th0.sky, front: false);
    _cache = rec.endRecording();
    _cacheKey = key;
    return _cache!;
  }

  static ui.Picture? _wallCache;
  static (Game, int)? _wallKey;

  static ui.Picture _wallPicture(Game g) {
    final key = (g, g.layoutVersion);
    if (_wallCache != null && _wallKey == key) return _wallCache!;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final th0 = themeOf(g.branch);
    // 뒤쪽 벽: 내 땅의 위(r-1)·왼쪽(c-1)이 남의 땅이면 벽을 세운다
    final wallL = Paint()..color = th0.wallL, wallR = Paint()..color = th0.wallR;
    final band = Paint()..color = th0.band;
    final edge = _stroke(2);
    const up = Offset(0, -wallH);
    for (var r = 0; r < mapH; r++) {
      for (var x = 0; x < mapW; x++) {
        if (!g.owns((x, r))) continue;
        if (!g.owns((x, r - 1))) {
          final a = corner(x.toDouble(), r.toDouble()), b = corner(x + 1.0, r.toDouble());
          c.drawPath(_quad(a, b, b + up, a + up), wallR);
          c.drawPath(_quad(a, b, b + const Offset(0, -12), a + const Offset(0, -12)), band);
          if (x % 4 == 2) {
            final wa = a + up * 0.75 + const Offset(6, 3), wb = b + up * 0.75 + const Offset(-6, -3);
            final win = _quad(wa, wb, wb + const Offset(0, 22), wa + const Offset(0, 22));
            c.drawPath(win, Paint()..color = const Color(0xFFB3E5FC));
            c.drawPath(win, edge);
          }
          c.drawLine(a + up, b + up, edge);
        }
        if (!g.owns((x - 1, r))) {
          final a = corner(x.toDouble(), r.toDouble()), b = corner(x.toDouble(), r + 1.0);
          c.drawPath(_quad(a, b, b + up, a + up), wallL);
          c.drawPath(_quad(a, b, b + const Offset(0, -12), a + const Offset(0, -12)), band);
          c.drawLine(a + up, b + up, edge);
        }
        // 내 땅 테두리를 진하게
        for (final (n, a, b) in [
          ((x, r - 1), corner(x.toDouble(), r.toDouble()), corner(x + 1.0, r.toDouble())),
          ((x - 1, r), corner(x.toDouble(), r.toDouble()), corner(x.toDouble(), r + 1.0)),
          ((x + 1, r), corner(x + 1.0, r.toDouble()), corner(x + 1.0, r + 1.0)),
          ((x, r + 1), corner(x.toDouble(), r + 1.0), corner(x + 1.0, r + 1.0)),
        ]) {
          if (!g.owns(n)) c.drawLine(a, b, edge);
        }
      }
    }
    _wallCache = rec.endRecording();
    _wallKey = key;
    return _wallCache!;
  }

  void _plotsForSale(Canvas canvas) {
    final price = game.nextPlotPrice;
    for (final (px, py) in game.plotsForSale) {
      final x = (px * plotSize).toDouble(), y = (py * plotSize).toDouble();
      final p = _diamond(x, y, plotSize.toDouble(), plotSize.toDouble(), 0.15);
      canvas.drawPath(p, Paint()..color = Color.fromARGB((90 + 40 * sin(clock * 4)).round(), 255, 213, 79));
      canvas.drawPath(
          p,
          Paint()
            ..color = const Color(0xFFFFA000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      final at = iso(x + plotSize / 2 - 0.5, y + plotSize / 2 - 0.5);
      _sign(canvas, at, '$price', game.money >= price);
      if (game.plots.length - 1 < plotVisitorsMax) {
        _text(canvas, at + const Offset(0, 8), S.tn('land_bonus', {'n': (plotVisitors * 100).round()}), const Color(0xFF2E7D32), 12,
            outline: 1);
      }
    }
  }

  void _sign(Canvas canvas, Offset p, String text, bool afford) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(0, -18), width: 86, height: 34),
        const Radius.circular(10));
    canvas.drawRRect(r, Paint()..color = afford ? Colors.white : const Color(0xFFEEEEEE));
    canvas.drawRRect(r, _stroke(2.5));
    canvas.drawLine(p, p + const Offset(0, 14), _stroke(3));
    _text(canvas, p + const Offset(0, -18), text, afford ? const Color(0xFFFFA000) : Colors.black38, 18);
  }

  // ---------------------------------------------------------------- 사람

  void _char(Canvas canvas, int who, double x, double y, Anim anim, Facing f,
      {double lift = 0, double fps = 10, double scale = 1}) {
    final feet = iso(x, y);
    canvas.drawOval(Rect.fromCenter(center: feet, width: 24 * scale, height: 10 * scale), Paint()..color = const Color(0x33000000));
    canvas.save();
    canvas.translate(feet.dx, feet.dy + lift);
    canvas.scale(scale);
    if (!Sprites.draw(canvas, who, Offset.zero, anim, f, clock + who * 0.37, fps: fps)) {
      drawCritter(canvas, Offset.zero, who, clock);
    }
    canvas.restore();
  }

  void _walker(Canvas canvas, Walker w, int who) {
    final f = facingOf(w.dx, w.dy);
    final carrying = w.carry.isNotEmpty;
    final busy = w is StaffAgent &&
        w.kind == Staff.cashier &&
        w.item != null &&
        world.time - (world.lastScan[w.item] ?? -9) < 0.4;
    final anim = busy ? Anim.interact : carrying ? Anim.carry : (w.moving ? Anim.walk : Anim.idle);
    final bob = carrying && w.moving ? -(sin(clock * 16).abs() * 3) : 0.0;
    _char(canvas, who, w.x, w.y, anim, f, lift: bob, fps: w.moving ? 12 : 6);
    final top = iso(w.x, w.y) + Offset(0, -46 + bob);
    for (var i = 0; i < w.carry.length; i++) {
      _food(canvas, w.carry[i], top + Offset(sin(i * 1.7) * 2, -i * 9.0), 15);
    }
    if (w is StaffAgent && w.asleep) {
      // 조는 알바: Zzz 가 올라가고, 깨우라는 말풍선
      for (var k = 0; k < 3; k++) {
        final t = (clock * 0.7 + k / 3) % 1.0;
        _text(canvas, top + Offset(8 + t * 10, -8 - t * 22), 'z', Color.fromRGBO(92, 107, 192, 1 - t), 11 + t * 6, outline: 1 - t);
      }
    }
  }

  void _customer(Canvas canvas, Customer c) {
    final f = facingOf(c.dx, c.dy);
    final who = customerSheet(c);
    final Anim anim;
    if (c.react > 0) {
      anim = c.happy ? Anim.yes : Anim.no;
    } else if (c.state == CState.sitting) {
      anim = Anim.sit;
    } else if ((c.kind == CustomerKind.lost || c.kind == CustomerKind.grumpy) && c.state == CState.atShelf) {
      anim = Anim.no; // 울거나 화내고 있다
    } else if (c.state == CState.atShelf && c.timer < pickTime) {
      anim = Anim.pickUp;
    } else if (c.moving) {
      anim = Anim.walk;
    } else {
      anim = Anim.idle;
    }
    final kid = c.kind == CustomerKind.lost, grumpy = c.kind == CustomerKind.grumpy;
    if (c.kind == CustomerKind.inspector) {
      // 점검관: 머리 위 클립보드
      final p = iso(c.x, c.y) + const Offset(14, -54);
      canvas.drawRect(Rect.fromCenter(center: p, width: 14, height: 18), Paint()..color = Colors.white);
      canvas.drawRect(Rect.fromCenter(center: p, width: 14, height: 18), _stroke(1.5));
      for (var k = 0; k < 3; k++) {
        canvas.drawLine(p + Offset(-4, -5 + k * 5.0), p + Offset(4, -5 + k * 5.0), _stroke(1));
      }
    }
    _char(canvas, who, c.x, c.y, anim, f, fps: c.moving ? 12 : 8, scale: kid ? kidScale : 1);
    final crownAt = iso(c.x, c.y) + const Offset(0, -40);
    if (c.fleeing) {
      // 도둑: 빨간 느낌표가 깜빡이고 훔친 물건을 들고 뛴다
      final a = 0.6 + 0.4 * sin(clock * 12);
      _text(canvas, crownAt + const Offset(0, -6), '!', Color.fromRGBO(229, 57, 53, a), 26, outline: 1);
      for (var i = 0; i < c.carry.length; i++) {
        _food(canvas, c.carry[i], iso(c.x, c.y) + Offset(10, -22 - i * 8.0), 12);
      }
    }
    if ((kid || grumpy) && c.state == CState.atShelf) {
      final p = iso(c.x, c.y) + Offset(sin(clock * (grumpy ? 30 : 0)) * 1.5, (grumpy ? -58 : -34) + sin(clock * 4) * 2);
      canvas.drawCircle(p, 10, Paint()..color = grumpy ? const Color(0xFFFFEBEE) : Colors.white);
      canvas.drawCircle(p, 10, _stroke(1.5));
      _text(canvas, p, grumpy ? '!!' : '?', grumpy ? const Color(0xFFE53935) : const Color(0xFF42A5F5), 15);
      // 남은 참을성
      final k = (1 - c.timer / (grumpy ? grumpyPatience : lostPatience)).clamp(0.0, 1.0);
      canvas.drawLine(p + const Offset(-10, 14), p + Offset(-10 + 20 * k, 14),
          Paint()
            ..color = const Color(0xFFFF7043)
            ..strokeWidth = 3);
    }
    if (c.regular != null) {
      // 단골: 머리 위 하트와 이름
      final hearts = game.owner.heartsOf(c.regular!);
      _text(canvas, crownAt + const Offset(0, -4), '♥', const Color(0xFFEC407A), 16, outline: 1);
      _text(canvas, iso(c.x, c.y) + const Offset(0, 12), '${regularName(c.regular!)} ${'♥' * hearts}',
          const Color(0xFFAD1457), 11, outline: 1);
    }
    if (c.kind == CustomerKind.vip) {
      // 금관
      final cr = Path()
        ..moveTo(crownAt.dx - 9, crownAt.dy)
        ..lineTo(crownAt.dx - 9, crownAt.dy - 8)
        ..lineTo(crownAt.dx - 4, crownAt.dy - 3)
        ..lineTo(crownAt.dx, crownAt.dy - 10)
        ..lineTo(crownAt.dx + 4, crownAt.dy - 3)
        ..lineTo(crownAt.dx + 9, crownAt.dy - 8)
        ..lineTo(crownAt.dx + 9, crownAt.dy)
        ..close();
      canvas.drawPath(cr, Paint()..color = const Color(0xFFFFC107));
      canvas.drawPath(cr, _stroke(1.5));
    } else if (c.kind == CustomerKind.hurry) {
      // 땀방울
      final d = crownAt + const Offset(12, 4);
      final drop = Path()
        ..moveTo(d.dx, d.dy - 7)
        ..quadraticBezierTo(d.dx + 5, d.dy, d.dx, d.dy + 3)
        ..quadraticBezierTo(d.dx - 5, d.dy, d.dx, d.dy - 7)
        ..close();
      canvas.drawPath(drop, Paint()..color = const Color(0xFF81D4FA));
      canvas.drawPath(drop, _stroke(1.2));
    }
    final head = iso(c.x, c.y) + const Offset(0, -52);
    if (c.kind == CustomerKind.service && c.state == CState.atShelf) {
      final worry = (c.timer / servicePatience).clamp(0.0, 1.0);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: head, width: 30, height: 26), const Radius.circular(10));
      canvas.drawRRect(r, Paint()..color = Color.lerp(Colors.white, const Color(0xFFFFCDD2), worry)!);
      canvas.drawRRect(r, _stroke(2));
      _text(canvas, head, c.service == 'parcel' ? '📦' : '🎫', const Color(0xFF5D4037), 15);
      if (c.waited > 0) {
        canvas.drawLine(head + const Offset(-12, 17), head + Offset(-12 + 24 * (c.waited / serviceTime).clamp(0.0, 1.0), 17),
            Paint()
              ..color = const Color(0xFF43A047)
              ..strokeWidth = 3);
      }
    } else if (c.state == CState.atShelf && c.timer >= pickTime && c.wants.isNotEmpty) {
      final worry = (c.timer / shelfPatience).clamp(0.0, 1.0);
      _wantBubble(canvas, head, c.want, Color.lerp(Colors.white, const Color(0xFFFFCDD2), worry)!);
    } else if (c.state == CState.toQueue && c.waited > queuePatience * c.patience * 0.5 && c.scanned == 0) {
      _bubble(canvas, head, '!', const Color(0xFFFB8C00));
    } else if (c.state == CState.sitting) {
      _text(canvas, head + Offset(0, sin(clock * 3) * 2), '♥', const Color(0xFFEC407A), 16);
    }
    if (c.state != CState.sitting) {
      for (var i = 0; i < c.carry.length; i++) {
        _food(canvas, c.carry[i], iso(c.x, c.y) + Offset(14 + i * 7.0, -14), 10);
      }
    }
  }

  void _wantBubble(Canvas canvas, Offset p, String item, Color bg) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 32, height: 28), const Radius.circular(10));
    canvas.drawRRect(r, Paint()..color = bg);
    canvas.drawRRect(r, _stroke(2));
    _food(canvas, item, p, 18);
  }

  // ---------------------------------------------------------------- 연출

  void _ghost(Canvas canvas, BuildView b) {
    final t = b.hover!;
    final type = b.ghostType!;
    final mv = b.moving;
    final ok = (mv != null ? game.canMove(mv, t, rot: b.rot) : game.canPlace(type, t, rot: b.rot)) == PlaceResult.ok;
    canvas.drawPath(
        _diamond(t.$1 + 0.0, t.$2 + 0.0, 1, 1), Paint()..color = ok ? const Color(0x6643A047) : const Color(0x66E53935));
    canvas.saveLayer(null, Paint()..color = const Color(0xAAFFFFFF));
    drawItem(canvas, type, t, product: mv?.product ?? b.product, stock: 99, rot: b.rot, clock: clock);
    canvas.restore();
    // 끌어서 옮길 수 있다는 손잡이
    final h = iso(t.$1 + 0.0, t.$2 + 0.0) + const Offset(0, 26);
    canvas.drawCircle(h, 13, Paint()..color = ok ? const Color(0xFF43A047) : const Color(0xFFE53935));
    canvas.drawCircle(
        h,
        13,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    _text(canvas, h, '+', Colors.white, 16);
    if (itemType(type).rotates) {
      final d = rotations[b.rot];
      final till = (t.$1 + d.$1, t.$2 + d.$2), front = (t.$1 - d.$1, t.$2 - d.$2);
      canvas.drawPath(_diamond(till.$1 + 0.0, till.$2 + 0.0, 1, 1, 0.15), Paint()..color = const Color(0x8842A5F5));
      canvas.drawPath(_diamond(front.$1 + 0.0, front.$2 + 0.0, 1, 1, 0.15), Paint()..color = const Color(0x8866BB6A));
    }
  }

  void _flight(Canvas canvas, Flight f) {
    final e = f.fx;
    final k = (f.age / f.life).clamp(0.0, 1.0);
    switch (e.kind) {
      case FxKind.scan:
        break;
      case FxKind.pick || FxKind.place || FxKind.cash || FxKind.tip:
        final a = iso(e.x, e.y) + const Offset(0, -30), b = iso(e.tx, e.ty) + const Offset(0, -40);
        final p = Offset.lerp(a, b, k)! + Offset(0, -sin(k * pi) * 30);
        if (e.kind != FxKind.cash && e.kind != FxKind.tip) {
          _food(canvas, e.product, p, 15);
        } else {
          _text(canvas, p, '+${e.amount}', const Color(0xFF2E7D32), 15, outline: 1);
        }
      case FxKind.pay:
        _float(canvas, e, k, '+${e.amount}', const Color(0xFFFFA000));
      case FxKind.levelUp:
        _float(canvas, e, k, 'LEVEL ${e.amount}!', const Color(0xFFFF7043), size: 26);
      case FxKind.angry:
        _float(canvas, e, k, '!!', const Color(0xFFE53935));
      case FxKind.sad:
        _float(canvas, e, k, '...', const Color(0xFF90A4AE));
      case FxKind.sleep:
        _float(canvas, e, k, 'Zzz', const Color(0xFF5C6BC0));
      case FxKind.wake:
        _float(canvas, e, k, '!', const Color(0xFFFF9800), size: 24);
      case FxKind.cook:
        _float(canvas, e, k, '~', const Color(0xFFFF7043), size: 22);
      case FxKind.missing:
        // 찾던 상품이 없다: 그 상품 아이콘에 빨간 X
        final p = iso(e.x, e.y) + Offset(0, -62 - k * 22);
        canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - k * k));
        _food(canvas, e.product, p, 16);
        _text(canvas, p + const Offset(9, 7), 'X', const Color(0xFFE53935), 15, outline: 1);
        canvas.restore();
      case FxKind.litter:
        _float(canvas, e, k, '!', const Color(0xFF8D6E63));
      case FxKind.clean:
        _float(canvas, e, k, '✨', const Color(0xFF42A5F5));
      case FxKind.goal:
        _float(canvas, e, k, e.product == 'new' ? 'NEW!' : '+${e.amount}',
            e.product == 'new' ? const Color(0xFFFF4081) : const Color(0xFF43A047),
            size: e.product == 'new' ? 18 : 24);
      case FxKind.stamp:
        _float(canvas, e, k, '★ +${e.amount}', const Color(0xFF7E57C2), size: 20);
      case FxKind.event || FxKind.day || FxKind.incident || FxKind.combo:
        break; // 화면 위 알림으로 보여 준다
      case FxKind.regular:
        _float(canvas, e, k, e.amount > 0 ? '♥' * e.amount : '♥', const Color(0xFFEC407A), size: 22);
    }
  }

  void _float(Canvas canvas, Fx e, double k, String text, Color col, {double size = 20}) {
    final p = iso(e.x, e.y) + Offset(0, -56 - k * 40);
    final a = 1 - k;
    _text(canvas, p, text, col.withValues(alpha: a), size, outline: a);
  }

  /// 진열대 옆 표: 가격표(싸게↓·비싸게↑·프리미엄↑↑)와 세트 별.
  void _shelfTags(Canvas canvas, Item i) {
    final base = iso(i.c + 0.0, i.r + 0.0) + const Offset(18, -8);
    if (i.price != defaultPrice) {
      final (col, mark) = switch (i.price) {
        0 => (const Color(0xFF43A047), '-'),
        2 => (const Color(0xFFFF9800), '+'),
        _ => (const Color(0xFFE53935), '++'),
      };
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: base, width: 20, height: 13), const Radius.circular(4));
      canvas.drawRRect(r, Paint()..color = col);
      canvas.drawRRect(r, _stroke(1.2));
      _text(canvas, base, mark, Colors.white, 10);
    }
    if (game.expiring(i)) {
      // 유통기한 임박: 노란 딱지, 반값 스티커를 붙였으면 '½'
      final p = base + const Offset(-4, -26);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: i.sticker ? 26 : 26, height: 14), const Radius.circular(7));
      canvas.drawRRect(r, Paint()..color = i.sticker ? const Color(0xFFFFEB3B) : const Color(0xFFFFA726));
      canvas.drawRRect(r, _stroke(1.2));
      _text(canvas, p, i.sticker ? '50%' : S.t('tag_expiring'), const Color(0xFF5D4037), 9);
    }
    if (game.inCombo(i)) {
      final p = base + const Offset(-36, -4);
      _text(canvas, p, '★', Color.fromRGBO(255, 193, 7, 0.75 + 0.25 * sin(clock * 4)), 15, outline: 1);
    }
  }

  /// 상자 남은 양: 막대와 숫자, 비면 빨간 !, 주문 중이면 트럭과 남은 초.
  void _boxStock(Canvas canvas, Item i) {
    final p = iso(i.c + 0.0, i.r + 0.0) + const Offset(0, 14);
    if (i.incoming > 0) {
      _text(canvas, p + const Offset(0, -2), '🚚 ${i.incoming.ceil()}s', const Color(0xFF1565C0), 11, outline: 1);
      return;
    }
    if (i.units == 0) {
      final q = iso(i.c + 0.0, i.r + 0.0) + Offset(0, -48 + sin(clock * 6) * 3);
      canvas.drawCircle(q, 11, Paint()..color = const Color(0xFFE53935));
      canvas.drawCircle(q, 11, _stroke(1.5));
      _text(canvas, q, '!', Colors.white, 15);
      return;
    }
    final k = (i.units / boxSize).clamp(0.0, 1.0);
    final r = Rect.fromCenter(center: p, width: 30, height: 5);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), Paint()..color = const Color(0x55000000));
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width * k, r.height), const Radius.circular(2)),
        Paint()..color = k < 0.25 ? const Color(0xFFFF7043) : const Color(0xFF66BB6A));
  }

  /// 고장 난 진열대: 연기와 빨간 공구 표시.
  void _brokenMark(Canvas canvas, Item i) {
    final p = iso(i.c + 0.0, i.r + 0.0) + Offset(0, -itemHeight(i.type) - 8);
    for (var k = 0; k < 3; k++) {
      final t = (clock * 0.8 + k / 3) % 1.0;
      canvas.drawCircle(p + Offset(sin(t * 6 + k) * 6, -t * 26), 5 + t * 7,
          Paint()..color = Color.fromRGBO(120, 120, 120, 0.45 * (1 - t)));
    }
    final a = 0.65 + 0.35 * sin(clock * 10);
    canvas.drawCircle(p, 11, Paint()..color = Color.fromRGBO(229, 57, 53, a));
    canvas.drawCircle(p, 11, _stroke(1.5));
    _text(canvas, p, '🔧', Colors.white, 12);
  }

  /// 첫 땅 뒤쪽 벽의 간판: 가게 등급 이름.
  void _rankSign(Canvas canvas) {
    if (game.owns((4, -1))) return;
    final p = iso(4.5, 0.0) + Offset(-tw / 4, -th / 4) + const Offset(0, -wallH * 0.62); // 창문(2·6번 칸) 사이
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.skew(0, 0.5); // 벽 기울기(2:1)에 맞춘다
    paintSign(canvas, game.rank, 84, 22);
    canvas.restore();
  }

  /// 온장 진열대의 날것: 프라이팬과 개수, 굽는 중이면 둥근 진행 막대.
  void _rawMark(Canvas canvas, Item i) {
    final p = iso(i.c + 0.0, i.r + 0.0) + Offset(0, -66 + sin(clock * 5) * 2);
    final cooking = world.cooking == i;
    canvas.drawCircle(p, 13, Paint()..color = cooking ? const Color(0xFFFFE0B2) : const Color(0xFFFF7043));
    canvas.drawCircle(p, 13, _stroke(1.5));
    if (cooking) {
      canvas.drawArc(Rect.fromCircle(center: p, radius: 16), -pi / 2, 2 * pi * (world.cookT / cookTime).clamp(0.0, 1.0), false,
          Paint()
            ..color = const Color(0xFFE65100)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5);
    }
    _text(canvas, p + const Offset(0, -1), '🍳', Colors.white, 12);
    _text(canvas, p + const Offset(13, 9), '${i.raw}', const Color(0xFFE65100), 11, outline: 1);
  }

  /// 명절 장식: 뒷벽 두 면 위쪽에 삼각 깃발 줄.
  void _bunting(Canvas canvas, Holiday h) {
    final cols = switch (h) {
      Holiday.newyear => const [Color(0xFFE53935), Color(0xFFFFD54F), Color(0xFF1E88E5)],
      Holiday.childrens => const [Color(0xFF81D4FA), Color(0xFFFFF176), Color(0xFFA5D6A7), Color(0xFFF48FB1)],
      Holiday.halloween => const [Color(0xFFFF9800), Color(0xFF4A148C), Color(0xFF212121)],
      Holiday.pepero => const [Color(0xFF8D6E63), Color(0xFFF8BBD0), Color(0xFFFFFFFF)],
      Holiday.christmas => const [Color(0xFFC62828), Color(0xFF2E7D32), Color(0xFFFFFFFF)],
    };
    const up = Offset(0, -wallH * 0.86);
    for (final (a, b) in [(corner(0.2, 0), corner(plotSize - 0.2, 0)), (corner(0, 0.2), corner(0, plotSize - 0.2))]) {
      const n = 14;
      Offset at(double k) => Offset.lerp(a, b, k)! + up + Offset(0, sin(k * pi) * 10);
      final line = Path()..moveTo(at(0).dx, at(0).dy);
      for (var i = 1; i <= 20; i++) {
        final q = at(i / 20);
        line.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(line, _stroke(1.2));
      for (var i = 0; i < n; i++) {
        final p0 = at((i + 0.15) / n), p1 = at((i + 0.85) / n);
        final tip = Offset.lerp(p0, p1, 0.5)! + Offset(0, 11 + sin(clock * 3 + i) * 1.5);
        final flag = Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..close();
        canvas.drawPath(flag, Paint()..color = cols[i % cols.length]);
        canvas.drawPath(flag, _stroke(0.8));
      }
    }
  }

  void _arrow(Canvas canvas, Offset p) {
    final a = Path()
      ..moveTo(p.dx - 9, p.dy - 10)
      ..lineTo(p.dx + 9, p.dy - 10)
      ..lineTo(p.dx, p.dy)
      ..close();
    canvas.drawPath(a, Paint()..color = const Color(0xFF43A047));
    canvas.drawPath(
        a,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  void _bubble(Canvas canvas, Offset p, String text, Color col) {
    canvas.drawCircle(p, 11, Paint()..color = col);
    canvas.drawCircle(
        p,
        11,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    _text(canvas, p, text, Colors.white, 14);
  }

  void _rug(Canvas canvas, Tile t) {
    canvas.drawPath(_diamond(t.$1 + 0.0, t.$2 + 0.0, 1, 1, 0.12), Paint()..color = const Color(0xFFF48FB1));
    canvas.drawPath(_diamond(t.$1 + 0.0, t.$2 + 0.0, 1, 1, 0.26), Paint()..color = const Color(0xFFF8BBD0));
  }

  void _entrance(Canvas canvas, Tile t) {
    canvas.drawPath(_diamond(t.$1 + 0.0, t.$2 + 0.0, 1, 1, 0.08), Paint()..color = const Color(0xFF81C784));
    _text(canvas, iso(t.$1 + 0.0, t.$2 + 0.0), 'OPEN', const Color(0xFF1B5E20), 11);
  }

  void _trash(Canvas canvas, Tile t) {
    final p = iso(t.$1 + 0.0, t.$2 + 0.0);
    canvas.drawOval(Rect.fromCenter(center: p + const Offset(5, -1), width: 10, height: 6), Paint()..color = const Color(0xFFBCAAA4));
    canvas.drawOval(Rect.fromCenter(center: p + const Offset(-5, 2), width: 12, height: 7), Paint()..color = Colors.white);
    canvas.drawOval(Rect.fromCenter(center: p + const Offset(-5, 2), width: 12, height: 7), _stroke(1.2));
  }

  @override
  bool shouldRepaint(StorePainter old) => true;
}

// ------------------------------------------------------------------ 가구 그리기 (미리보기에서도 쓴다)

Paint _stroke(double w) => Paint()
  ..color = ink
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round;

Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy)
  ..lineTo(c.dx, c.dy)
  ..lineTo(d.dx, d.dy)
  ..close();

Path _diamond(double x, double y, double w, double h, [double inset = 0]) => _quad(
      corner(x + inset, y + inset),
      corner(x + w - inset, y + inset),
      corner(x + w - inset, y + h - inset),
      corner(x + inset, y + h - inset),
    );

Color floorColor(String id) => switch (id) {
      'floor-pink' => const Color(0xFFFCE4EC),
      'floor-mint' => const Color(0xFFE0F2F1),
      'floor-blue' => const Color(0xFFE3F2FD),
      _ => const Color(0xFFD7B98E),
    };

/// 아이소 상자. 윗면·왼면·오른면 색을 따로 받는다.
void _box(Canvas canvas, Tile t, double h, Color top, Color left, Color right, {double inset = 0.1}) {
  final (c, r) = t;
  final x = c + inset, y = r + inset, w = 1 - inset * 2;
  final a = corner(x, y), b = corner(x + w, y), cc = corner(x + w, y + w), d = corner(x, y + w);
  final up = Offset(0, -h);
  canvas.drawOval(Rect.fromCenter(center: iso(c + 0.0, r + 0.0) + const Offset(0, 2), width: tw * 0.85, height: th * 0.7),
      Paint()..color = const Color(0x22000000));
  for (final (p, col) in [
    (_quad(d, cc, cc + up, d + up), left),
    (_quad(cc, b, b + up, cc + up), right),
    (_quad(a + up, b + up, cc + up, d + up), top),
  ]) {
    canvas.drawPath(p, Paint()..color = col);
    canvas.drawPath(p, _stroke(2));
  }
}

// ---------------------------------------------------------------- 가구 그리기 도구 (입체감)

/// 깎은 상자: 바닥 (x0..x0+w, y0..y0+d) 칸 좌표, 높이 h. 면마다 위가 밝고 아래가 어두운 그라데이션,
/// 윗모서리 하이라이트, 부드러운 그림자. 앞 두 면(왼쪽 아래·오른쪽 아래를 보는 면)과 윗면만 보인다.
void _nbox(Canvas canvas, double x0, double y0, double w, double d, double h, Color col, {bool shadow = true}) {
  final up = Offset(0, -h);
  final a = corner(x0 + 0.5, y0 + d + 0.5), b = corner(x0 + w + 0.5, y0 + d + 0.5);
  final rt = corner(x0 + w + 0.5, y0 + 0.5), tl = corner(x0 + 0.5, y0 + 0.5);
  if (shadow) {
    final mid = Offset((a.dx + rt.dx) / 2, (a.dy + rt.dy) / 2);
    canvas.drawOval(Rect.fromCenter(center: mid + const Offset(2, 3), width: tw * (w + d) * 0.55, height: th * (w + d) * 0.55),
        Paint()..color = const Color(0x2A000000));
  }
  Paint grad(Color top, Color bottom, Offset from, Offset to) =>
      Paint()..shader = ui.Gradient.linear(from, to, [top, bottom]);
  final left = Color.lerp(col, Colors.black, 0.06)!, right = Color.lerp(col, Colors.black, 0.2)!;
  final lf = _quad(a, b, b + up, a + up), rf = _quad(b, rt, rt + up, b + up), tf = _quad(tl + up, rt + up, b + up, a + up);
  canvas.drawPath(lf, grad(Color.lerp(left, Colors.white, 0.18)!, Color.lerp(left, Colors.black, 0.08)!, a + up, a));
  canvas.drawPath(rf, grad(Color.lerp(right, Colors.white, 0.12)!, Color.lerp(right, Colors.black, 0.1)!, b + up, b));
  canvas.drawPath(tf, Paint()..color = Color.lerp(col, Colors.white, 0.35)!);
  final edge = Paint()
    ..color = ink.withValues(alpha: 0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(lf, edge);
  canvas.drawPath(rf, edge);
  canvas.drawPath(tf, edge);
  // 윗모서리 하이라이트
  final hl = Paint()
    ..color = Colors.white.withValues(alpha: 0.7)
    ..strokeWidth = 1.4;
  canvas.drawLine(a + up + const Offset(1, 1), b + up + const Offset(0, 1), hl);
  canvas.drawLine(b + up + const Offset(0, 1), rt + up + const Offset(-1, 1), hl);
}

/// 앞면(왼쪽 아래를 보는 면)의 유리문: x0..x0+w, 앞 y, 높이 from..to. 칸 선과 비스듬한 반사.
void _glass(Canvas canvas, double x0, double y, double w, double from, double to, {int shelves = 0}) {
  final a = corner(x0 + 0.5, y + 0.5), b = corner(x0 + w + 0.5, y + 0.5);
  final g = _quad(a + Offset(0, -from), b + Offset(0, -from), b + Offset(0, -to), a + Offset(0, -to));
  canvas.drawPath(g, Paint()..color = const Color(0x55B3E5FC));
  for (var k = 1; k <= shelves; k++) {
    final hh = from + (to - from) * k / (shelves + 1) - 4;
    canvas.drawLine(a + Offset(0, -hh), b + Offset(0, -hh), Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1.5);
  }
  // 반사 줄 두 개
  canvas.save();
  canvas.clipPath(g);
  final sh = Paint()
    ..color = const Color(0x66FFFFFF)
    ..strokeWidth = 5;
  final mid = Offset.lerp(a, b, 0.3)! + Offset(0, -(from + to) / 2);
  canvas.drawLine(mid + const Offset(-14, 26), mid + const Offset(10, -30), sh);
  canvas.drawLine(mid + const Offset(2, 26), mid + const Offset(20, -16), sh..strokeWidth = 2.5);
  canvas.restore();
  canvas.drawPath(g, _stroke(1.4));
}

/// 앞면 띠(간판·손잡이 자리): 앞 y, 높이 from..to.
void _faceBand(Canvas canvas, double x0, double y, double w, double from, double to, Color col) {
  final a = corner(x0 + 0.5, y + 0.5), b = corner(x0 + w + 0.5, y + 0.5);
  final band = _quad(a + Offset(0, -from), b + Offset(0, -from), b + Offset(0, -to), a + Offset(0, -to));
  canvas.drawPath(band, Paint()..color = col);
  canvas.drawPath(band, _stroke(1.2));
}

/// 윗면 유리 뚜껑(냉동고).
void _topGlass(Canvas canvas, double x0, double y0, double w, double d, double h) {
  final up = Offset(0, -h);
  final q = _quad(corner(x0 + 0.5, y0 + 0.5) + up, corner(x0 + w + 0.5, y0 + 0.5) + up, corner(x0 + w + 0.5, y0 + d + 0.5) + up,
      corner(x0 + 0.5, y0 + d + 0.5) + up);
  canvas.drawPath(q, Paint()..color = const Color(0x44B3E5FC));
  canvas.save();
  canvas.clipPath(q);
  final c0 = corner(x0 + w * 0.3 + 0.5, y0 + d * 0.5 + 0.5) + up;
  canvas.drawLine(c0 + const Offset(-20, 6), c0 + const Offset(20, -8), Paint()
    ..color = const Color(0x77FFFFFF)
    ..strokeWidth = 4);
  canvas.restore();
  canvas.drawPath(q, _stroke(1.2));
}

/// 유리 상자(쇼케이스): 받침 높이 base 위로 top 까지, 앞·옆·위 유리.
void _glassBox(Canvas canvas, double x0, double y0, double w, double d, double base, double top,
    {Color tint = const Color(0x40B3E5FC)}) {
  Offset at(double x, double y, double hgt) => corner(x + 0.5, y + 0.5) + Offset(0, -hgt);
  final a0 = at(x0, y0 + d, base), b0 = at(x0 + w, y0 + d, base), r0 = at(x0 + w, y0, base);
  final a1 = at(x0, y0 + d, top), b1 = at(x0 + w, y0 + d, top), r1 = at(x0 + w, y0, top), t1 = at(x0, y0, top);
  for (final q in [_quad(a0, b0, b1, a1), _quad(b0, r0, r1, b1), _quad(t1, r1, b1, a1)]) {
    canvas.drawPath(q, Paint()..color = tint);
  }
  canvas.save();
  canvas.clipPath(_quad(a0, b0, b1, a1));
  final m = Offset.lerp(a0, b1, 0.35)!;
  canvas.drawLine(m + const Offset(-10, 14), m + const Offset(8, -16), Paint()
    ..color = const Color(0x77FFFFFF)
    ..strokeWidth = 4);
  canvas.restore();
  final e = _stroke(1.3);
  canvas.drawPath(_quad(a0, b0, b1, a1), e);
  canvas.drawPath(_quad(b0, r0, r1, b1), e);
  canvas.drawPath(_quad(t1, r1, b1, a1), e);
}

void _dot(Canvas canvas, Offset p, Color col, double rad) {
  canvas.drawCircle(p, rad, Paint()..color = col);
  canvas.drawCircle(p, rad, _stroke(1.5));
}

/// 음식 아이콘. 그림이 없으면 그 색 동그라미.
void _food(Canvas canvas, String id, Offset p, double size) {
  if (!Props.food(canvas, id, p, size)) _dot(canvas, p, productColor(id), size * 0.45);
}

/// 윗면에 상품을 격자로 올린다.
void _items(Canvas canvas, int c, int r, double h, int stock, int cap, String? id, int cols) {
  if (id == null) return;
  final rows = (cap / cols).ceil();
  for (var i = 0; i < min(stock, cap); i++) {
    final fx = c - 0.3 + ((i % cols) + 0.5) * 0.6 / cols;
    final fy = r - 0.3 + ((i ~/ cols) + 0.5) * 0.6 / rows;
    _food(canvas, id, iso(fx, fy) + Offset(0, -h - 5), 12);
  }
}

/// 놓인 물건 하나를 그린다. 건설 미리보기·메뉴 아이콘도 이걸 쓴다.
void drawItem(Canvas canvas, String type, Tile t,
    {String? product,
    int stock = 0,
    int rot = 0,
    int cash = 0,
    double clock = 0,
    bool highlight = false,
    int level = 1,
    bool managed = false}) {
  final (c, r) = t;
  final feet = iso(c + 0.0, r + 0.0);
  final shelf = itemType(type).shelf;
  final cap = shelf == null ? 0 : shelfCapacity[shelf]!;
  if (highlight) {
    canvas.drawPath(_diamond(c + 0.0, r + 0.0, 1, 1, -0.05), Paint()..color = const Color(0x88FFC107));
  }
  switch (type) {
    case 'rack':
      var h = 30.0;
      if (Props.prop(canvas, 'rack', feet)) {
        h = 34;
      } else {
        _box(canvas, t, h, const Color(0xFFD7A86E), const Color(0xFFBC8A5F), const Color(0xFFA47148));
      }
      _items(canvas, c, r, h, stock, cap, product, 4);
    case 'fridge':
      // 편의점 유리문 냉장고: 하얀 몸통, 위 파란 간판, 앞(왼쪽 아래를 보는 면)은 유리문, 칸마다 상품
      const h = 62.0;
      final x0 = c - 0.42, y0 = r - 0.42;
      _nbox(canvas, x0, y0, 0.84, 0.84, h, const Color(0xFFF5F7FA));
      final front = y0 + 0.84;
      if (product != null) {
        final per = (cap / 2).ceil();
        for (var i = 0; i < min(stock, cap); i++) {
          final row = i ~/ per, k = i % per;
          _food(canvas, product, corner(x0 + 0.08 + (k + 0.5) * 0.68 / per + 0.5, front + 0.5 - 0.06) + Offset(0, -12 - row * 20.0), 11);
        }
      }
      _glass(canvas, x0 + 0.06, front, 0.72, 4, h - 12, shelves: 2);
      _faceBand(canvas, x0, front, 0.84, h - 10, h, const Color(0xFF42A5F5));
    case 'freezer':
      // 아이스크림 냉동고: 낮은 하얀 통, 유리 뚜껑 아래 상품
      _nbox(canvas, c - 0.44, r - 0.4, 0.88, 0.8, 26, const Color(0xFFE0F7FA));
      _items(canvas, c, r, 24, stock, cap, product, 3);
      _topGlass(canvas, c - 0.38, r - 0.34, 0.76, 0.68, 27);
      _faceBand(canvas, c - 0.44, r + 0.4, 0.88, 4, 10, const Color(0xFF4DD0E1));
    case 'fruitstand':
      // 과일 매대: 나무 받침에 비스듬한 상자, 줄무늬 차양
      _nbox(canvas, c - 0.44, r - 0.44, 0.88, 0.88, 18, const Color(0xFFA1887F));
      _items(canvas, c, r, 20, stock, cap, product, 4);
      final a = corner(c - 0.4, r - 0.4) + const Offset(0, -44), b = corner(c + 0.5, r - 0.4) + const Offset(0, -44);
      canvas.drawLine(corner(c - 0.38, r - 0.38) + const Offset(0, -18), a + const Offset(0, 8), Paint()..color = const Color(0xFF6D4C41)..strokeWidth = 3);
      canvas.drawLine(corner(c + 0.48, r - 0.38) + const Offset(0, -18), b + const Offset(0, 8), Paint()..color = const Color(0xFF6D4C41)..strokeWidth = 3);
      for (var k = 0; k < 6; k++) {
        final p0 = Offset.lerp(a, b, k / 6)!, p1 = Offset.lerp(a, b, (k + 1) / 6)!;
        final stripe = _quad(p0, p1, p1 + const Offset(-6, 12), p0 + const Offset(-6, 12));
        canvas.drawPath(stripe, Paint()..color = k.isEven ? const Color(0xFFEF5350) : Colors.white);
      }
      canvas.drawPath(_quad(a, b, b + const Offset(-6, 12), a + const Offset(-6, 12)), _stroke(1.5));
    case 'bakerycase':
      // 빵 쇼케이스: 나무 받침 위 유리 상자, 안에 빵 두 줄
      const h = 40.0;
      _nbox(canvas, c - 0.44, r - 0.4, 0.88, 0.8, 16, const Color(0xFFBCAAA4));
      if (product != null) {
        for (var i = 0; i < min(stock, cap); i++) {
          _food(canvas, product, corner(c - 0.3 + (i % 3 + 0.5) * 0.24 + 0.5, r + 0.34 + 0.5) + Offset(0, -20.0 - (i ~/ 3) * 12), 11);
        }
      }
      _glassBox(canvas, c - 0.42, r - 0.38, 0.84, 0.76, 16, h);
    case 'coffeemachine':
      // 커피 기계: 카운터 위 짙은 기계, 빨간 불, 컵
      _nbox(canvas, c - 0.44, r - 0.44, 0.88, 0.88, 26, const Color(0xFFD7CCC8));
      canvas.save();
      canvas.translate(0, -26);
      _nbox(canvas, c - 0.3, r - 0.3, 0.42, 0.42, 30, const Color(0xFF5D4037), shadow: false);
      canvas.restore();
      canvas.drawCircle(feet + const Offset(-12, -44), 3, Paint()..color = const Color(0xFFFF7043));
      canvas.drawCircle(feet + const Offset(-12, -44), 6, Paint()..color = const Color(0x44FF7043));
      if (product != null) {
        for (var i = 0; i < min(stock, 3); i++) {
          _food(canvas, product, feet + Offset(10.0 + (i % 2) * 7, -32.0 - i * 3), 10);
        }
      }
    case 'hotcounter':
      // 온장 진열대: 스테인리스 받침, 따뜻한 빛 유리 칸, 김
      _nbox(canvas, c - 0.44, r - 0.4, 0.88, 0.8, 20, const Color(0xFFB0BEC5));
      _items(canvas, c, r, 22, stock, cap, product, 3);
      _glassBox(canvas, c - 0.42, r - 0.38, 0.84, 0.76, 20, 38, tint: const Color(0x33FFB74D));
      if (stock > 0) {
        for (var k = 0; k < 2; k++) {
          final y = (clock * 20 + k * 10) % 20;
          _text(canvas, feet + Offset(-6.0 + k * 12, -50 - y), '~',
              Color.fromARGB((200 - y * 9).round().clamp(0, 255), 255, 255, 255), 14);
        }
      }
    case 'box':
      if (!Props.prop(canvas, 'crate', feet, scale: 1.25)) {
        _box(canvas, t, 20, const Color(0xFFFFE0B2), const Color(0xFFD7A86E), const Color(0xFFBC8A5F), inset: 0.16);
      }
      if (product != null) {
        for (final (dx, dy) in const [(-7.0, -28.0), (7.0, -27.0), (0.0, -33.0)]) {
          _food(canvas, product, feet + Offset(dx, dy), 15);
        }
      }
    case 'register':
      // 계산대: 나무 카운터, 포스 화면(초록 글자), 카드 단말기
      _nbox(canvas, c - 0.44, r - 0.44, 0.88, 0.88, 28, const Color(0xFFFFCC80));
      final p = feet + const Offset(0, -28);
      final stand = Rect.fromCenter(center: p + const Offset(-2, -4), width: 6, height: 8);
      canvas.drawRect(stand, Paint()..color = const Color(0xFF455A64));
      final scr = RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(-2, -16), width: 28, height: 18), const Radius.circular(3));
      canvas.drawRRect(scr, Paint()..color = const Color(0xFF37474F));
      canvas.drawRRect(scr.deflate(2.5), Paint()..color = const Color(0xFF80CBC4));
      canvas.drawLine(p + const Offset(-11, -18), p + const Offset(4, -18), Paint()..color = const Color(0xFF00695C)..strokeWidth = 1.5);
      canvas.drawLine(p + const Offset(-11, -14), p + const Offset(0, -14), Paint()..color = const Color(0xFF00695C)..strokeWidth = 1.5);
      canvas.drawRRect(scr, _stroke(1.5));
      final card = RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(15, -3), width: 8, height: 11), const Radius.circular(2));
      canvas.drawRRect(card, Paint()..color = const Color(0xFF263238));
      if (cash > 0) {
        final n = min(10, (cash / 4).ceil());
        for (var i = 0; i < n; i++) {
          final o = p + Offset(16 + ((i % 2) * 2 - 1) * 3.0, 12 - i * 3.0);
          canvas.drawPath(
              _quad(o + const Offset(-10, 0), o + const Offset(0, -5), o + const Offset(10, 0), o + const Offset(0, 5)),
              Paint()..color = const Color(0xFF81C784));
          canvas.drawPath(
              _quad(o + const Offset(-10, 0), o + const Offset(0, -5), o + const Offset(10, 0), o + const Offset(0, 5)), _stroke(0.8));
        }
        _text(canvas, p + Offset(16, -n * 3.0 - 4), '$cash', const Color(0xFF2E7D32), 13, outline: 1);
      }
    case 'plant' || 'flowers' || 'lamp' || 'chair' || 'table':
      final scale = switch (type) { 'flowers' => 1.6, 'lamp' => 0.7, 'table' => 0.9, _ => 1.0 };
      if (!Props.prop(canvas, type, feet, scale: scale)) {
        _box(canvas, t, 16, const Color(0xFFA5D6A7), const Color(0xFF81C784), const Color(0xFF66BB6A), inset: 0.3);
      }
    case 'claw':
      // 인형뽑기: 분홍 받침, 유리 상자 안 인형들, 집게가 흔들린다
      _box(canvas, t, 22, const Color(0xFFF48FB1), const Color(0xFFEC407A), const Color(0xFFD81B60), inset: 0.18);
      final top = feet + const Offset(0, -22);
      final glass = Rect.fromCenter(center: top + const Offset(0, -18), width: 40, height: 34);
      canvas.drawRect(glass, Paint()..color = const Color(0x88E1F5FE));
      for (var k = 0; k < 5; k++) {
        final q = glass.bottomCenter + Offset((k - 2) * 7.0, -6 - (k % 2) * 4.0);
        canvas.drawCircle(q, 5, Paint()..color = const [Color(0xFFFFF176), Color(0xFF81D4FA), Color(0xFFA5D6A7), Color(0xFFCE93D8), Color(0xFFFFAB91)][k]);
      }
      final sway = sin(clock * 1.5) * 10;
      canvas.drawLine(glass.topCenter + Offset(sway, 0), glass.topCenter + Offset(sway, 14), _stroke(1.5));
      canvas.drawArc(Rect.fromCenter(center: glass.topCenter + Offset(sway, 16), width: 10, height: 8), 0, pi, false, _stroke(1.5));
      canvas.drawRect(glass, _stroke(1.5));
      canvas.drawRect(Rect.fromCenter(center: glass.topCenter + const Offset(0, -5), width: 44, height: 10), Paint()..color = const Color(0xFFEC407A));
      canvas.drawRect(Rect.fromCenter(center: glass.topCenter + const Offset(0, -5), width: 44, height: 10), _stroke(1.5));
    case 'selfcheck':
      // 셀프 계산대: 낮은 받침, 기둥 위 큰 화면, 바코드 빛
      _nbox(canvas, c - 0.4, r - 0.4, 0.8, 0.8, 22, const Color(0xFFB2DFDB));
      final top = feet + const Offset(0, -22);
      canvas.drawLine(top, top + const Offset(0, -18), Paint()..color = const Color(0xFF455A64)..strokeWidth = 4);
      final scr = RRect.fromRectAndRadius(Rect.fromCenter(center: top + const Offset(0, -30), width: 30, height: 22), const Radius.circular(4));
      canvas.drawRRect(scr, Paint()..color = const Color(0xFF263238));
      canvas.drawRRect(scr.deflate(3), Paint()..color = const Color(0xFF80DEEA));
      canvas.drawRRect(scr, _stroke(1.5));
      _text(canvas, top + const Offset(0, -30), 'SELF', const Color(0xFF00695C), 8);
      final beam = 0.5 + 0.5 * sin(clock * 6);
      canvas.drawLine(top + const Offset(-10, -2), top + const Offset(10, -2),
          Paint()
            ..color = Color.fromRGBO(244, 67, 54, 0.4 + 0.5 * beam)
            ..strokeWidth = 2);
    case 'service':
      // 서비스 카운터: 하늘색 카운터, 위에 택배 상자, 옆에 복권 간판
      _nbox(canvas, c - 0.44, r - 0.4, 0.88, 0.8, 26, const Color(0xFF90CAF9));
      final top = feet + const Offset(0, -26);
      canvas.drawRect(Rect.fromCenter(center: top + const Offset(-8, -6), width: 16, height: 11), Paint()..color = const Color(0xFFD7A86E));
      canvas.drawRect(Rect.fromCenter(center: top + const Offset(-8, -6), width: 16, height: 11), _stroke(1.2));
      canvas.drawLine(top + const Offset(-8, -11), top + const Offset(-8, -1), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 2);
      final sign = RRect.fromRectAndRadius(Rect.fromCenter(center: top + const Offset(12, -16), width: 18, height: 14), const Radius.circular(3));
      canvas.drawRRect(sign, Paint()..color = const Color(0xFFFFEB3B));
      canvas.drawRRect(sign, _stroke(1.2));
      _text(canvas, top + const Offset(12, -16), 'W', const Color(0xFFE65100), 10);
    case 'vending':
      // 자판기: 빨간 몸통, 앞면 유리 칸에 캔 세 줄, 동전 구멍
      const h = 62.0;
      final x0 = c - 0.36, y0 = r - 0.32;
      _nbox(canvas, x0, y0, 0.72, 0.64, h, const Color(0xFFE53935));
      final front = y0 + 0.64;
      _glass(canvas, x0 + 0.06, front, 0.44, 18, h - 6, shelves: 3);
      const cans = [Color(0xFF42A5F5), Color(0xFFFFCA28), Color(0xFF66BB6A), Color(0xFFAB47BC)];
      for (var row = 0; row < 3; row++) {
        for (var k = 0; k < 3; k++) {
          final q = corner(x0 + 0.12 + k * 0.13 + 0.5, front + 0.5) + Offset(0, -24.0 - row * 12);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: q, width: 5, height: 8), const Radius.circular(1.5)),
              Paint()..color = cans[(row + k) % cans.length]);
        }
      }
      final slot = corner(x0 + 0.6 + 0.5, front + 0.5) + const Offset(0, -34);
      canvas.drawRect(Rect.fromCenter(center: slot, width: 4, height: 9), Paint()..color = const Color(0xFF212121));
      canvas.drawRect(Rect.fromCenter(center: corner(x0 + 0.3 + 0.5, front + 0.5) + const Offset(0, -9), width: 16, height: 6),
          Paint()..color = const Color(0xFF263238));
    case 'atm':
      // ATM: 회색 몸통, 파란 화면, 숫자판
      const h = 50.0;
      final x0 = c - 0.34, y0 = r - 0.3;
      _nbox(canvas, x0, y0, 0.68, 0.6, h, const Color(0xFFCFD8DC));
      final front = y0 + 0.6;
      _faceBand(canvas, x0, front, 0.68, h - 8, h, const Color(0xFF1565C0));
      final scr = corner(x0 + 0.34 + 0.5, front + 0.5) + const Offset(0, -34);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: scr, width: 20, height: 12), const Radius.circular(2)),
          Paint()..color = const Color(0xFF4FC3F7));
      for (var k = 0; k < 6; k++) {
        canvas.drawCircle(scr + Offset(-6.0 + (k % 3) * 6, 12.0 + (k ~/ 3) * 5), 1.6, Paint()..color = const Color(0xFF455A64));
      }
    case 'photo':
      // 즉석 사진기: 보라 부스, 줄무늬 커튼, 위에 별 간판
      const h = 64.0;
      final x0 = c - 0.42, y0 = r - 0.42;
      _nbox(canvas, x0, y0, 0.84, 0.84, h, const Color(0xFFBA68C8));
      final front = y0 + 0.84;
      for (var k = 0; k < 5; k++) {
        final a = corner(x0 + 0.1 + k * 0.1 + 0.5, front + 0.5), b = corner(x0 + 0.2 + k * 0.1 + 0.5, front + 0.5);
        canvas.drawPath(_quad(a + const Offset(0, -4), b + const Offset(0, -4), b + const Offset(0, -h + 14), a + const Offset(0, -h + 14)),
            Paint()..color = k.isEven ? const Color(0xFFF8BBD0) : const Color(0xFFF48FB1));
      }
      _faceBand(canvas, x0, front, 0.84, h - 12, h, const Color(0xFF7B1FA2));
      _text(canvas, corner(x0 + 0.42 + 0.5, front + 0.5) + const Offset(0, -h + 6), '★', const Color(0xFFFFEB3B), 11);
    case 'bin':
      if (!Props.prop(canvas, 'trash', feet, scale: 0.6)) {
        _box(canvas, t, 20, const Color(0xFFB0BEC5), const Color(0xFF90A4AE), const Color(0xFF78909C), inset: 0.32);
      }
    case 'rug':
      canvas.drawPath(_diamond(c + 0.0, r + 0.0, 1, 1, 0.12), Paint()..color = const Color(0xFFF48FB1));
    case 'entrance':
      canvas.drawPath(_diamond(c + 0.0, r + 0.0, 1, 1, 0.08), Paint()..color = const Color(0xFF81C784));
    default:
      if (type.startsWith('floor-')) {
        canvas.drawPath(_diamond(c + 0.0, r + 0.0, 1, 1, 0.02), Paint()..color = floorColor(type));
        canvas.drawPath(_diamond(c + 0.0, r + 0.0, 1, 1, 0.02), _stroke(1));
      }
  }
  // 가구 레벨: 노란 별 / 매니저가 맡은 코너: 넥타이 표시
  if (level > 1) {
    final p = feet + const Offset(-20, 10);
    for (var k = 0; k < level - 1; k++) {
      _text(canvas, p + Offset(k * 8.0, 0), '★', const Color(0xFFFFB300), 11, outline: 1);
    }
  }
  if (managed) _text(canvas, feet + const Offset(20, 10), 'M', const Color(0xFF5C6BC0), 12, outline: 1);
  if (shelf != null && stock == 0 && product != null && !managed) {
    canvas.drawCircle(feet + const Offset(0, -80), 10, Paint()..color = const Color(0xFFE53935));
    _text(canvas, feet + const Offset(0, -80), '!', Colors.white, 13);
  }
}

/// 메뉴 칸에 물건 하나를 그린다.
class ItemPreview extends CustomPainter {
  final String type;
  final String? product;
  ItemPreview(this.type, [this.product]);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..translate(size.width / 2, size.height * 0.8)
      ..scale(size.width / 80)
      ..translate(0, -th / 2);
    drawItem(canvas, type, (0, 0), product: product, stock: 99);
  }

  @override
  bool shouldRepaint(ItemPreview old) => old.type != type || old.product != product;
}

/// 메뉴 칸에 음식 하나를 그린다.
class FoodPreview extends CustomPainter {
  final String product;
  FoodPreview(this.product);

  @override
  void paint(Canvas canvas, Size size) => _food(canvas, product, size.center(Offset.zero), size.width * 0.7);

  @override
  bool shouldRepaint(FoodPreview old) => old.product != product;
}

void _text(Canvas canvas, Offset center, String text, Color color, double size, {double outline = 0}) {
  TextPainter tp(Paint? stroke) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontFamily: 'Jua', fontSize: size, color: stroke == null ? color : null, foreground: stroke),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
  if (outline > 0) {
    final o = tp(Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withValues(alpha: outline));
    o.paint(canvas, center - Offset(o.width / 2, o.height / 2));
  }
  final t = tp(null);
  t.paint(canvas, center - Offset(t.width / 2, t.height / 2));
}

/// 그림 파일이 없을 때 쓰는 동글동글 캐릭터.
void drawCritter(Canvas canvas, Offset feet, int look, double clock) {
  const colors = [Color(0xFFFFD54F), Color(0xFFFFFFFF), Color(0xFFBCAAA4), Color(0xFFB0BEC5), Color(0xFFA5D6A7)];
  final center = feet + const Offset(0, -17);
  canvas.drawCircle(center, 15, Paint()..color = colors[look % colors.length]);
  canvas.drawCircle(center, 15, _stroke(2));
  for (final dx in [-5.0, 5.0]) {
    canvas.drawCircle(center + Offset(dx, -2), 2.4, Paint()..color = ink);
  }
}

/// 간판 색: 등급마다 (판, 글자).
const _signColors = [
  (Color(0xFFBCAAA4), Color(0xFF4E342E)),
  (Color(0xFF80CBC4), Color(0xFF004D40)),
  (Color(0xFF90CAF9), Color(0xFF0D47A1)),
  (Color(0xFFA5D6A7), Color(0xFF1B5E20)),
  (Color(0xFFEF9A9A), Color(0xFFB71C1C)),
  (Color(0xFFFFD54F), Color(0xFF6D4C41)),
];

/// (0,0) 을 가운데로 [w]×[h] 간판을 그린다.
void paintSign(Canvas canvas, int rank, double w, double h) {
  final (board, ink) = _signColors[rank.clamp(0, _signColors.length - 1)];
  final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h * 0.25));
  canvas.drawRRect(r.shift(Offset(0, h * 0.12)), Paint()..color = const Color(0x33000000));
  canvas.drawRRect(r, Paint()..color = board);
  canvas.drawRRect(r, _stroke(2));
  if (rank >= rankVip) {
    for (final x in [-w / 2 + h * 0.4, w / 2 - h * 0.4]) {
      _text(canvas, Offset(x, 0), '★', Colors.white, h * 0.5);
    }
  }
  final tp = TextPainter(
    text: TextSpan(text: S.t('rank_$rank'), style: TextStyle(fontFamily: 'Jua', fontSize: h * 0.55, color: ink)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final k = min(1.0, (w - h) / tp.width);
  canvas.save();
  canvas.scale(k);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

/// 승급 창의 간판.
class RankSign extends CustomPainter {
  final int rank;
  RankSign(this.rank);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    paintSign(canvas, rank, size.width - 8, size.height - 10);
  }

  @override
  bool shouldRepaint(RankSign old) => old.rank != rank;
}

IconData weatherIcon(Weather w) => switch (w) {
      Weather.sunny => Icons.wb_sunny_rounded,
      Weather.hot => Icons.local_fire_department_rounded,
      Weather.rain => Icons.umbrella_rounded,
      Weather.cold => Icons.ac_unit_rounded,
    };

Color weatherColor(Weather w) => switch (w) {
      Weather.sunny => const Color(0xFFFFA000),
      Weather.hot => const Color(0xFFFF5722),
      Weather.rain => const Color(0xFF42A5F5),
      Weather.cold => const Color(0xFF4FC3F7),
    };

/// 손님이 쓰는 캐릭터 시트: 단골은 정해진 얼굴, 그냥 손님은 손님 시트 중 하나.
int customerSheet(Customer c) => c.regular != null ? c.look : customerChars[c.look % customerChars.length];

/// 동네 지도 카드의 작은 장면: 그 동네 땅·가게·나무(야자수·네온·눈사람).
class BranchThumb extends CustomPainter {
  final String branch;
  BranchThumb(this.branch);

  @override
  void paint(Canvas canvas, Size size) {
    final th0 = themeOf(branch);
    final lk = _lookOf(branch);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = th0.sky);
    canvas.translate(size.width / 2, size.height * 0.34);
    canvas.scale(size.width / 190);
    // 땅과 찻길
    for (var y = -2; y < 4; y++) {
      for (var x = -2; x < 4; x++) {
        final d = max(max(-x, -y), max(x - 1, y - 1));
        final col = d <= 0 ? ((x + y).isEven ? th0.floorA : th0.floorB) : (d == 1 ? lk.road : ((x + y).isEven ? lk.ground : lk.ground2));
        canvas.drawPath(_diamond(x.toDouble(), y.toDouble(), 1, 1), Paint()..color = col);
      }
    }
    // 가게: 뒤쪽 벽 두 면
    const up = Offset(0, -wallH);
    final a = corner(0, 0), b = corner(2, 0), cc = corner(0, 2);
    canvas.drawPath(_quad(a, b, b + up, a + up), Paint()..color = th0.wallR);
    canvas.drawPath(_quad(cc, a, a + up, cc + up), Paint()..color = th0.wallL);
    canvas.drawPath(_quad(a, b, b + const Offset(0, -12), a + const Offset(0, -12)), Paint()..color = th0.band);
    canvas.drawPath(_quad(cc, a, a + const Offset(0, -12), cc + const Offset(0, -12)), Paint()..color = th0.band);
    canvas.drawPath(_quad(a, b, b + up, a + up), _stroke(2));
    canvas.drawPath(_quad(cc, a, a + up, cc + up), _stroke(2));
    drawItem(canvas, 'fridge', (0, 1), product: null);
    drawItem(canvas, 'register', (1, 1));
    // 동네다운 것
    switch (branch) {
      case 'beach':
        _palm(canvas, iso(2.3, 0.4), 0.4);
        _palm(canvas, iso(0.3, 2.5), 0.8);
      case 'night':
        _tbox(canvas, 2.0, -0.9, 0.9, 0.9, 60, const Color(0xFF7E57C2), const Color(0xFF5E35B1), const Color(0xFF9575CD));
        _lamp(canvas, lk, iso(0.2, 2.4));
      case 'snow':
        _snowman(canvas, iso(2.2, 0.9), 1.1);
        _tree(canvas, lk, iso(0.2, 2.5), 0.5);
      default:
        _tree(canvas, lk, iso(2.3, 0.3), 0.3);
        _tree(canvas, lk, iso(0.2, 2.5), 0.7);
    }
  }

  @override
  bool shouldRepaint(BranchThumb old) => old.branch != branch;
}
