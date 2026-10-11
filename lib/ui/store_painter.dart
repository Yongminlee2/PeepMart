import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../engine/world.dart';
import 'sprites.dart';

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

/// 화면 방향(조이스틱) → 세계 방향.
(double, double) screenToWorld(double u, double v) {
  final a = u / (tw / 2), b = v / (th / 2);
  return ((a + b) / 2, (b - a) / 2);
}

/// 지도 전체를 담는 사각형(그림 좌표).
Rect get mapBounds => Rect.fromLTRB(-mapH * tw / 2, -wallH, mapW * tw / 2, (mapW + mapH) * th / 2);

Color productColor(String id) => Color(0xFF000000 | ((id.hashCode * 2654435761) & 0x7F7F7F) + 0x606060);

/// 날아가는 물건·돈, 떠오르는 글자.
class Flight {
  final Fx fx;
  double age = 0;
  Flight(this.fx);
  double get life => switch (fx.kind) {
        FxKind.pick || FxKind.place || FxKind.cash => 0.28,
        FxKind.scan => 0,
        FxKind.levelUp => 1.6,
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

  StorePainter(this.world, this.flights, this.clock, this.camera, this.build, {this.dest});

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
          product: i.product, stock: i.stock, rot: i.rot, cash: i.cash, clock: clock, highlight: b?.selected == i));
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
    });
    draws.sort((a, b) => a.$1.compareTo(b.$1));
    for (final d in draws) {
      d.$2();
    }

    // 놓을 자리 미리보기
    if (b != null && b.ghostType != null && b.hover != null) _ghost(canvas, b);

    // 계산 기다리는 손님이 있는데 아무도 없는 계산대는 계산 자리를 가리킨다
    if (b == null) {
      for (final r in game.registers) {
        final q = world.queues[r];
        if (q == null || q.isEmpty || !q.first.arrived || world.staffedAt(r) || world.player.distTo(r.till) < standRadius) {
          continue;
        }
        final till = iso(r.till.$1 + 0.0, r.till.$2 + 0.0);
        _arrow(canvas, till + Offset(0, -40 + sin(clock * 6) * 4));
      }
    }
    for (final f in flights) {
      _flight(canvas, f);
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------- 바닥·벽 (캐시)

  static ui.Picture? _cache;
  static (Game, int)? _cacheKey;

  static ui.Picture _basePicture(Game g) {
    final key = (g, g.layoutVersion);
    if (_cache != null && _cacheKey == key) return _cache!;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
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
    c.drawPath(grassA, Paint()..color = const Color(0xFFC5E1A5));
    c.drawPath(grassB, Paint()..color = const Color(0xFFB9DB94));
    c.drawPath(floorA, Paint()..color = const Color(0xFFFFF8E1));
    c.drawPath(floorB, Paint()..color = const Color(0xFFFFECB3));
    for (final e in painted.entries) {
      c.drawPath(e.value, Paint()..color = floorColor(e.key));
    }
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
    // 뒤쪽 벽: 내 땅의 위(r-1)·왼쪽(c-1)이 남의 땅이면 벽을 세운다
    final wallL = Paint()..color = const Color(0xFFF8BBD0), wallR = Paint()..color = const Color(0xFFFCE4EC);
    final band = Paint()..color = const Color(0xFFF48FB1);
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
    _cache = rec.endRecording();
    _cacheKey = key;
    return _cache!;
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
      _sign(canvas, iso(x + plotSize / 2 - 0.5, y + plotSize / 2 - 0.5), '$price', game.money >= price);
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

  void _char(Canvas canvas, int who, double x, double y, Anim anim, Facing f, {double lift = 0, double fps = 10}) {
    final feet = iso(x, y);
    canvas.drawOval(Rect.fromCenter(center: feet, width: 24, height: 10), Paint()..color = const Color(0x33000000));
    canvas.save();
    canvas.translate(feet.dx, feet.dy + lift);
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
  }

  void _customer(Canvas canvas, Customer c) {
    final f = facingOf(c.dx, c.dy);
    final who = customerChars[c.look % customerChars.length];
    final Anim anim;
    if (c.react > 0) {
      anim = c.happy ? Anim.yes : Anim.no;
    } else if (c.state == CState.sitting) {
      anim = Anim.sit;
    } else if (c.state == CState.atShelf && c.timer < pickTime) {
      anim = Anim.pickUp;
    } else if (c.moving) {
      anim = Anim.walk;
    } else {
      anim = Anim.idle;
    }
    _char(canvas, who, c.x, c.y, anim, f, fps: c.moving ? 12 : 8);
    final head = iso(c.x, c.y) + const Offset(0, -52);
    if (c.state == CState.atShelf && c.timer >= pickTime) {
      final worry = (c.timer / shelfPatience).clamp(0.0, 1.0);
      _wantBubble(canvas, head, c.want, Color.lerp(Colors.white, const Color(0xFFFFCDD2), worry)!);
    } else if (c.state == CState.toQueue && c.waited > queuePatience * 0.5 && c.scanned == 0) {
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
    _text(canvas, h, '✥', Colors.white, 16);
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
      case FxKind.pick || FxKind.place || FxKind.cash:
        final a = iso(e.x, e.y) + const Offset(0, -30), b = iso(e.tx, e.ty) + const Offset(0, -40);
        final p = Offset.lerp(a, b, k)! + Offset(0, -sin(k * pi) * 30);
        if (e.kind != FxKind.cash) {
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
      case FxKind.litter:
        _float(canvas, e, k, '!', const Color(0xFF8D6E63));
      case FxKind.clean:
        _float(canvas, e, k, '✨', const Color(0xFF42A5F5));
    }
  }

  void _float(Canvas canvas, Fx e, double k, String text, Color col, {double size = 20}) {
    final p = iso(e.x, e.y) + Offset(0, -56 - k * 40);
    final a = 1 - k;
    _text(canvas, p, text, col.withValues(alpha: a), size, outline: a);
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
    {String? product, int stock = 0, int rot = 0, int cash = 0, double clock = 0, bool highlight = false}) {
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
      const h = 58.0;
      _box(canvas, t, h, const Color(0xFFE3F2FD), const Color(0xFFB3E5FC), const Color(0xFF90CAF9));
      if (product != null) {
        final per = cap ~/ 2;
        for (var i = 0; i < min(stock, cap); i++) {
          final row = i ~/ per, k = i % per;
          _food(canvas, product, corner(c + 0.2 + (k + 0.5) * 0.6 / per, r + 0.9) + Offset(0, -h * (0.28 + row * 0.38)), 12);
        }
      }
    case 'freezer':
      _box(canvas, t, 24, const Color(0xFFB2EBF2), const Color(0xFFE0F7FA), const Color(0xFF80DEEA));
      _items(canvas, c, r, 24, stock, cap, product, 3);
    case 'fruitstand':
      _box(canvas, t, 22, const Color(0xFFA5D6A7), const Color(0xFF8D6E63), const Color(0xFF6D4C41));
      _items(canvas, c, r, 22, stock, cap, product, 4);
      final a = corner(c + 0.05, r + 0.05) + const Offset(0, -50), b = corner(c + 0.95, r + 0.05) + const Offset(0, -50);
      canvas.drawLine(corner(c + 0.1, r + 0.1) + const Offset(0, -22), a + const Offset(0, 6), _stroke(2));
      canvas.drawLine(corner(c + 0.9, r + 0.1) + const Offset(0, -22), b + const Offset(0, 6), _stroke(2));
      final aw = _quad(a, b, b + const Offset(-6, 10), a + const Offset(6, 10));
      canvas.drawPath(aw, Paint()..color = const Color(0xFFEF9A9A));
      canvas.drawPath(aw, _stroke(1.5));
    case 'bakerycase':
      _box(canvas, t, 34, const Color(0xFFFFF3E0), const Color(0xFFE1F5FE), const Color(0xFFFFCC80));
      if (product != null) {
        for (var i = 0; i < min(stock, cap); i++) {
          _food(canvas, product, corner(c + 0.2 + (i % 3 + 0.5) * 0.2, r + 0.9) + Offset(0, -10.0 - (i ~/ 3) * 12), 11);
        }
      }
    case 'coffeemachine':
      _box(canvas, t, 26, const Color(0xFFD7CCC8), const Color(0xFFBCAAA4), const Color(0xFFA1887F));
      final m = RRect.fromRectAndRadius(Rect.fromCenter(center: feet + const Offset(-4, -40), width: 20, height: 24),
          const Radius.circular(4));
      canvas.drawRRect(m, Paint()..color = const Color(0xFF5D4037));
      canvas.drawRRect(m, _stroke(1.5));
      canvas.drawCircle(feet + const Offset(-4, -44), 3, Paint()..color = const Color(0xFFFF7043));
      if (product != null) {
        for (var i = 0; i < min(stock, 3); i++) {
          _food(canvas, product, feet + Offset(10.0 + (i % 2) * 6, -30.0 - i * 3), 10);
        }
      }
    case 'hotcounter':
      _box(canvas, t, 28, const Color(0xFFCFD8DC), const Color(0xFFB0BEC5), const Color(0xFF90A4AE));
      _items(canvas, c, r, 28, stock, cap, product, 3);
      if (stock > 0) {
        for (var k = 0; k < 2; k++) {
          final y = (clock * 20 + k * 10) % 20;
          _text(canvas, feet + Offset(-6.0 + k * 12, -46 - y), '~',
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
      _box(canvas, t, 26, const Color(0xFFFFE0B2), const Color(0xFFFFCC80), const Color(0xFFFFB74D));
      final p = feet + const Offset(0, -26);
      final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(0, -9), width: 26, height: 18),
          const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = const Color(0xFF7986CB));
      canvas.drawRRect(rr, _stroke(2));
      canvas.drawRect(Rect.fromCenter(center: p + const Offset(0, -12), width: 16, height: 6),
          Paint()..color = const Color(0xFFC5E1A5));
      if (cash > 0) {
        final n = min(10, (cash / 4).ceil());
        for (var i = 0; i < n; i++) {
          final o = p + Offset(16 + ((i % 2) * 2 - 1) * 3.0, 10 - i * 3.0);
          canvas.drawPath(
              _quad(o + const Offset(-10, 0), o + const Offset(0, -5), o + const Offset(10, 0), o + const Offset(0, 5)),
              Paint()..color = const Color(0xFF81C784));
        }
        _text(canvas, p + Offset(16, -n * 3.0 - 6), '$cash', const Color(0xFF2E7D32), 13, outline: 1);
      }
    case 'plant' || 'flowers' || 'lamp' || 'chair' || 'table':
      final scale = switch (type) { 'flowers' => 1.6, 'lamp' => 0.7, 'table' => 0.9, _ => 1.0 };
      if (!Props.prop(canvas, type, feet, scale: scale)) {
        _box(canvas, t, 16, const Color(0xFFA5D6A7), const Color(0xFF81C784), const Color(0xFF66BB6A), inset: 0.3);
      }
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
  if (shelf != null && stock == 0 && product != null) {
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
