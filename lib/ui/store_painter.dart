import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/catalog.dart';
import '../engine/game.dart';
import '../engine/world.dart';
import 'sprites.dart';

// 가구는 아직 페인터 그림이다. 같은 자리에 PNG 를 끼우면 된다.

const tw = 64.0, th = 32.0; // 바닥 한 칸의 화면 크기 (2:1 아이소)
const wallH = 72.0;
const ink = Color(0xFF5D4037); // 외곽선

/// 칸 좌표 → 그림 좌표. 정수 값이 칸 한가운데다. (0,0) 칸 중앙이 (0, th/2).
Offset iso(double x, double y) => Offset((x - y) * tw / 2, (x + y + 1) * th / 2);

/// 칸 모서리 좌표(칸 중앙에서 반 칸씩 어긋난 격자) → 그림 좌표.
Offset corner(double x, double y) => iso(x - 0.5, y - 0.5);

Rect storeBounds(Layout l) =>
    Rect.fromLTRB(-l.h * tw / 2 - 8, -wallH - 8, l.w * tw / 2 + 8, (l.w + l.h) * th / 2 + 8);

/// 화면 방향(조이스틱) → 세계 방향.
(double, double) screenToWorld(double u, double v) {
  final a = u / (tw / 2), b = v / (th / 2);
  return ((a + b) / 2, (b - a) / 2);
}

Color productColor(String id) => switch (id) {
      'soda' => const Color(0xFFE57373),
      'chips' => const Color(0xFFFFCA28),
      'ramen' => const Color(0xFFFF8A65),
      'sandwich' => const Color(0xFFAED581),
      'icecream' => const Color(0xFFF8BBD0),
      'fruit' => const Color(0xFFFFA726),
      'bento' => const Color(0xFF8D6E63),
      _ => const Color(0xFFCE93D8),
    };

double boxHeight(ShelfKind k) => switch (k) {
      ShelfKind.rack => 30,
      ShelfKind.fridge => 58,
      ShelfKind.freezer => 24,
    };

/// 날아가는 물건·돈, 떠오르는 글자.
class Flight {
  final Fx fx;
  double age = 0;
  Flight(this.fx);
  double get life => fx.kind == FxKind.item || fx.kind == FxKind.cash ? 0.28 : 1.0;
}

class StorePainter extends CustomPainter {
  final World world;
  final List<Flight> flights;
  final double clock;
  final Offset camera; // 화면 가운데에 올 그림 좌표

  StorePainter(this.world, this.flights, this.clock, this.camera);

  /// 화면에 보일 영역: 가로 viewTiles 칸만큼, 가게 밖은 안 보이게 붙인다.
  static Rect view(Size size, Layout l, Offset camera) {
    const viewTiles = 4.6;
    final b = storeBounds(l);
    final w = min(b.width, viewTiles * tw), h = w * size.height / size.width;
    double clampTo(double v, double lo, double hi, double half) =>
        hi - lo <= half * 2 ? (lo + hi) / 2 : v.clamp(lo + half, hi - half);
    final cx = clampTo(camera.dx, b.left, b.right, w / 2), cy = clampTo(camera.dy, b.top, b.bottom, h / 2);
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  Game get game => world.game;

  static (double, Offset) fit(Size size, Rect view) {
    final s = min(size.width / view.width, size.height / view.height);
    return (
      s,
      Offset((size.width - view.width * s) / 2 - view.left * s, (size.height - view.height * s) / 2 - view.top * s)
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = game.layout;
    final (s, off) = fit(size, view(size, l, camera));
    canvas
      ..save()
      ..translate(off.dx, off.dy)
      ..scale(s);
    _floor(canvas, l);
    _walls(canvas, l);
    for (final (i, t) in game.pads) {
      _pad(canvas, i, t);
    }

    // 뒤에서 앞으로(x+y 가 작은 것부터) 그린다.
    final draws = <(double, void Function())>[];
    void add(double x, double y, void Function() f) => draws.add((x + y, f));
    for (final p in game.openProducts) {
      final c = game.crateTile(p), sh = game.shelfTile(p);
      add(c.$1 + 0.0, c.$2 + 0.0, () => _crate(canvas, c, p));
      add(sh.$1 + 0.0, sh.$2 + 0.0, () => _shelf(canvas, sh, p));
    }
    add(l.register.$1 + 0.0, l.register.$2 + 0.0, () => _register(canvas, l.register));
    add(l.cash.$1 + 0.0, l.cash.$2 + 0.0, () => _cash(canvas, l.cash));
    if (game.hasCashier) {
      final busy = world.time - world.lastScan < 0.4;
      add(l.till.$1 + 0.01, l.till.$2 + 0.0,
          () => _char(canvas, cashierChar, l.till.$1 + 0.0, l.till.$2 + 0.0, busy ? Anim.interact : Anim.idle, Facing.downLeft));
    }
    final st = world.stocker;
    if (st != null) add(st.x, st.y + 0.02, () => _walker(canvas, st, stockerChar));
    for (final c in world.customers) {
      add(c.x, c.y + 0.02, () => _customer(canvas, c));
    }
    final pl = world.player;
    add(pl.x, pl.y + 0.03, () {
      // 내 캐릭터 표시: 발밑의 노란 고리
      final ring = Rect.fromCenter(center: iso(pl.x, pl.y), width: 34, height: 15);
      canvas.drawOval(
          ring,
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
    for (final f in flights) {
      _flight(canvas, f);
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------- 바닥·벽

  Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  /// 칸 하나(또는 여러 칸)의 바닥 마름모. inset 만큼 안으로 줄인다.
  Path _diamond(double x, double y, double w, double h, [double inset = 0]) => _quad(
        corner(x + inset, y + inset),
        corner(x + w - inset, y + inset),
        corner(x + w - inset, y + h - inset),
        corner(x + inset, y + h - inset),
      );

  void _floor(Canvas canvas, Layout l) {
    final line = Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 0; r < l.h; r++) {
      for (var c = 0; c < l.w; c++) {
        final p = _diamond(c.toDouble(), r.toDouble(), 1, 1);
        canvas.drawPath(p, Paint()..color = (c + r).isEven ? const Color(0xFFFFF8E1) : const Color(0xFFFFECB3));
        canvas.drawPath(p, line);
      }
    }
    final (dc, dr) = l.door;
    canvas.drawPath(_diamond(dc.toDouble(), dr.toDouble(), 1, 1, 0.12), Paint()..color = const Color(0xFF81C784));
    // 계산대 뒤 발판
    final (tc, tr) = l.till;
    canvas.drawPath(_diamond(tc.toDouble(), tr.toDouble(), 1, 1, 0.1), Paint()..color = const Color(0xFFB3E5FC));
    canvas.drawPath(
        _diamond(0, 0, l.w.toDouble(), l.h.toDouble()),
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  void _walls(Canvas canvas, Layout l) {
    final o = corner(0, 0), right = corner(l.w.toDouble(), 0), left = corner(0, l.h.toDouble());
    const up = Offset(0, -wallH);
    final edge = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    final lw = _quad(o, left, left + up, o + up), rw = _quad(o, right, right + up, o + up);
    canvas.drawPath(lw, Paint()..color = const Color(0xFFF8BBD0));
    canvas.drawPath(rw, Paint()..color = const Color(0xFFFCE4EC));
    final band = Paint()..color = const Color(0xFFF48FB1);
    for (final b in [left, right]) {
      canvas.drawPath(_quad(o, b, b + const Offset(0, -14), o + const Offset(0, -14)), band);
    }
    for (var c = 4; c < l.w - 1; c += 3) {
      final a = corner(c + 0.2, 0) + up * 0.75, b = corner(c + 1.8, 0) + up * 0.75;
      final win = _quad(a, b, b + const Offset(0, 26), a + const Offset(0, 26));
      canvas.drawPath(win, Paint()..color = const Color(0xFFB3E5FC));
      canvas.drawPath(win, edge);
    }
    canvas.drawPath(lw, edge);
    canvas.drawPath(rw, edge);
  }

  // ---------------------------------------------------------------- 가구

  /// 아이소 상자. 윗면·왼면·오른면 색을 따로 받는다.
  void _box(Canvas canvas, Tile t, double h, Color top, Color left, Color right, {double inset = 0.1}) {
    final (c, r) = t;
    final x = c + inset, y = r + inset, w = 1 - inset * 2;
    final a = corner(x, y), b = corner(x + w, y), cc = corner(x + w, y + w), d = corner(x, y + w);
    final up = Offset(0, -h);
    final edge = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawOval(Rect.fromCenter(center: iso(c + 0.0, r + 0.0) + const Offset(0, 2), width: tw * 0.85, height: th * 0.7),
        Paint()..color = const Color(0x22000000));
    for (final (p, col) in [
      (_quad(d, cc, cc + up, d + up), left),
      (_quad(cc, b, b + up, cc + up), right),
      (_quad(a + up, b + up, cc + up, d + up), top),
    ]) {
      canvas.drawPath(p, Paint()..color = col);
      canvas.drawPath(p, edge);
    }
  }

  void _shelf(Canvas canvas, Tile t, String p) {
    final kind = productById(p).kind;
    final h = boxHeight(kind);
    final col = productColor(p);
    final stock = game.stock[p]!, cap = game.capacity(p);
    final (c, r) = t;
    switch (kind) {
      case ShelfKind.rack:
        _box(canvas, t, h, const Color(0xFFD7A86E), const Color(0xFFBC8A5F), const Color(0xFFA47148));
        _items(canvas, c, r, h, stock, cap, col, 4);
      case ShelfKind.fridge:
        _box(canvas, t, h, const Color(0xFFE3F2FD), const Color(0xFFB3E5FC), const Color(0xFF90CAF9));
        final per = cap ~/ 2;
        for (var i = 0; i < stock; i++) {
          final row = i ~/ per, k = i % per;
          final p = corner(c + 0.2 + (k + 0.5) * 0.6 / per, r + 0.9) + Offset(0, -h * (0.3 + row * 0.38));
          _dot(canvas, p, col, 5.5);
        }
      case ShelfKind.freezer:
        _box(canvas, t, h, const Color(0xFFB2EBF2), const Color(0xFFE0F7FA), const Color(0xFF80DEEA));
        _items(canvas, c, r, h, stock, cap, col, 3);
    }
    if (stock == 0) _bubble(canvas, iso(c + 0.0, r + 0.0) + Offset(0, -h - 26), '!', const Color(0xFFE53935));
  }

  /// 상품 상자: 나무 상자 위에 그 상품이 수북이.
  void _crate(Canvas canvas, Tile t, String p) {
    _box(canvas, t, 20, const Color(0xFFFFE0B2), const Color(0xFFD7A86E), const Color(0xFFBC8A5F), inset: 0.16);
    final (c, r) = t;
    final col = productColor(p);
    for (var i = 0; i < 5; i++) {
      final o = [(-8.0, 0.0), (8.0, 0.0), (0.0, -4.0), (0.0, 5.0), (0.0, -11.0)][i];
      _dot(canvas, iso(c + 0.0, r + 0.0) + Offset(o.$1, -24 + o.$2), col, 6);
    }
  }

  void _items(Canvas canvas, int c, int r, double h, int stock, int cap, Color col, int cols) {
    final rows = (cap / cols).ceil();
    for (var i = 0; i < stock; i++) {
      final fx = c - 0.3 + ((i % cols) + 0.5) * 0.6 / cols;
      final fy = r - 0.3 + ((i ~/ cols) + 0.5) * 0.6 / rows;
      _dot(canvas, iso(fx, fy) + Offset(0, -h - 4), col, 5.5);
    }
  }

  void _dot(Canvas canvas, Offset p, Color col, double rad) {
    canvas.drawCircle(p, rad, Paint()..color = col);
    canvas.drawCircle(
        p,
        rad,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(p + Offset(-rad * 0.35, -rad * 0.35), rad * 0.3, Paint()..color = Colors.white70);
  }

  void _register(Canvas canvas, Tile t) {
    _box(canvas, t, 26, const Color(0xFFFFE0B2), const Color(0xFFFFCC80), const Color(0xFFFFB74D));
    final p = iso(t.$1 + 0.0, t.$2 + 0.0) + const Offset(0, -26);
    final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(0, -9), width: 26, height: 18),
        const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF7986CB));
    canvas.drawRRect(
        rr,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawRect(Rect.fromCenter(center: p + const Offset(0, -12), width: 16, height: 6),
        Paint()..color = const Color(0xFFC5E1A5));
    // 계산 기다리는 손님이 있는데 아무도 없으면 계산대 뒤를 가리킨다
    final q = world.queue;
    final manned = game.hasCashier || world.player.distTo(game.layout.till) < 0.6;
    if (q.isNotEmpty && q.first.arrived && !manned) {
      final till = iso(game.layout.till.$1 + 0.0, game.layout.till.$2 + 0.0);
      _arrow(canvas, till + Offset(0, -40 + sin(clock * 6) * 4));
    }
  }

  /// 돈 더미: 지폐 다발을 쌓는다.
  void _cash(Canvas canvas, Tile t) {
    if (game.cash <= 0) return;
    final base = iso(t.$1 + 0.0, t.$2 + 0.0);
    final n = min(14, (game.cash / 4).ceil());
    for (var i = 0; i < n; i++) {
      final o = base + Offset(((i % 2) * 2 - 1) * 6.0, -i * 3.5);
      final bill = Path()
        ..moveTo(o.dx - 12, o.dy)
        ..lineTo(o.dx, o.dy - 6)
        ..lineTo(o.dx + 12, o.dy)
        ..lineTo(o.dx, o.dy + 6)
        ..close();
      canvas.drawPath(bill, Paint()..color = const Color(0xFF81C784));
      canvas.drawPath(
          bill,
          Paint()
            ..color = const Color(0xFF2E7D32)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    _label(canvas, base + Offset(0, -n * 3.5 - 16), '${game.cash}', const Color(0xFF2E7D32));
  }

  /// 구매 칸: 바닥에 테두리 마름모, 채운 만큼 차오르고, 무엇인지와 남은 값.
  void _pad(Canvas canvas, int i, Tile t) {
    final u = unlocks[i];
    final (c, r) = t;
    final done = (game.paid[i] ?? 0) / u.price;
    final outer = _diamond(c.toDouble(), r.toDouble(), 1, 1, 0.06);
    canvas.drawPath(outer, Paint()..color = const Color(0x55FFFFFF));
    final fillTop = r + 1 - 0.06 - (1 - 0.12) * done;
    canvas.save();
    canvas.clipPath(outer);
    canvas.drawPath(
        _quad(corner(c - 1.0, fillTop), corner(c + 2.0, fillTop), corner(c + 2.0, r + 2.0), corner(c - 1.0, r + 2.0)),
        Paint()..color = const Color(0x8866BB6A));
    canvas.restore();
    final pulse = 2 + sin(clock * 5) * 0.8;
    canvas.drawPath(
        outer,
        Paint()
          ..color = const Color(0xFF43A047)
          ..style = PaintingStyle.stroke
          ..strokeWidth = pulse);
    final center = iso(c + 0.0, r + 0.0);
    switch (u) {
      case NewProduct(:final product):
        _dot(canvas, center + const Offset(0, -6), productColor(product), 8);
      case HireCashier():
        _char(canvas, cashierChar, c + 0.0, r + 0.0, Anim.idle, Facing.downLeft, scale: 0.7);
      case HireStocker():
        _char(canvas, stockerChar, c + 0.0, r + 0.0, Anim.idle, Facing.downLeft, scale: 0.7);
      case BiggerArms():
        for (var k = 0; k < 3; k++) {
          _crateIcon(canvas, center + Offset(0, -4 - k * 7.0));
        }
      case Expand():
        _icon(canvas, Icons.home_rounded, center + const Offset(0, -8), const Color(0xFFF48FB1), 26);
    }
    _label(canvas, center + const Offset(0, 14), '${u.price - (game.paid[i] ?? 0)}', const Color(0xFFFFA000));
  }

  void _crateIcon(Canvas canvas, Offset p) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 18, height: 7), const Radius.circular(2));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFD7A86E));
    canvas.drawRRect(
        r,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  // ---------------------------------------------------------------- 사람

  void _char(Canvas canvas, int who, double x, double y, Anim anim, Facing f,
      {double scale = 1, double lift = 0, double fps = 10}) {
    final feet = iso(x, y);
    canvas.drawOval(Rect.fromCenter(center: feet, width: 24 * scale, height: 10 * scale),
        Paint()..color = const Color(0x33000000));
    canvas.save();
    canvas.translate(feet.dx, feet.dy + lift);
    canvas.scale(scale);
    final t = clock + who * 0.37;
    if (!Sprites.draw(canvas, who, Offset.zero, anim, f, t, fps: fps)) {
      drawCritter(canvas, Offset.zero, who, clock);
    }
    canvas.restore();
  }

  void _walker(Canvas canvas, Walker w, int who) {
    final f = facingOf(w.dx, w.dy);
    final carrying = w.carry.isNotEmpty;
    final anim = carrying ? Anim.carry : (w.moving ? Anim.walk : Anim.idle);
    final bob = carrying && w.moving ? -(sin(clock * 16).abs() * 3) : 0.0;
    _char(canvas, who, w.x, w.y, anim, f, lift: bob, fps: w.moving ? 12 : 6);
    // 머리 위로 쌓인 짐
    final top = iso(w.x, w.y) + Offset(0, -44 + bob);
    for (var i = 0; i < w.carry.length; i++) {
      final p = top + Offset(0, -i * 8.0);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 20, height: 9), const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = productColor(w.carry[i]));
      canvas.drawRRect(
          r,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  void _customer(Canvas canvas, Customer c) {
    final f = facingOf(c.dx, c.dy);
    final who = customerChars[c.look % customerChars.length];
    final Anim anim;
    if (c.react > 0) {
      anim = c.happy ? Anim.yes : Anim.no;
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
      // 원하는 물건이 없다: 그 물건 말풍선, 오래 기다릴수록 빨개진다
      final worry = (c.timer / shelfPatience).clamp(0.0, 1.0);
      _wantBubble(canvas, head, productColor(c.want), Color.lerp(Colors.white, const Color(0xFFFFCDD2), worry)!);
    } else if (c.state == CState.toQueue && c.timer > queuePatience * 0.5 && c.scanned == 0) {
      _bubble(canvas, head, '!', const Color(0xFFFB8C00));
    }
    for (var i = 0; i < c.carry.length; i++) {
      _dot(canvas, iso(c.x, c.y) + Offset(13 + i * 6.0, -14), productColor(c.carry[i]), 4);
    }
  }

  void _wantBubble(Canvas canvas, Offset p, Color item, Color bg) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 28, height: 24), const Radius.circular(10));
    canvas.drawRRect(r, Paint()..color = bg);
    canvas.drawRRect(
        r,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    _dot(canvas, p, item, 6);
  }

  // ---------------------------------------------------------------- 연출

  void _flight(Canvas canvas, Flight f) {
    final e = f.fx;
    final k = (f.age / f.life).clamp(0.0, 1.0);
    switch (e.kind) {
      case FxKind.item || FxKind.cash:
        final a = iso(e.x, e.y) + const Offset(0, -30), b = iso(e.tx, e.ty) + const Offset(0, -40);
        final p = Offset.lerp(a, b, k)! + Offset(0, -sin(k * pi) * 30);
        if (e.kind == FxKind.item) {
          _dot(canvas, p, productColor(e.product), 6);
        } else {
          _label(canvas, p, '+${e.amount}', const Color(0xFF2E7D32));
        }
      case FxKind.pay:
        _float(canvas, e, k, '+${e.amount}', const Color(0xFFFFA000));
      case FxKind.unlock:
        _float(canvas, e, k, '★', const Color(0xFFFFC107), size: 30);
      case FxKind.angry:
        _float(canvas, e, k, '!!', const Color(0xFFE53935));
      case FxKind.sad:
        _float(canvas, e, k, '...', const Color(0xFF90A4AE));
    }
  }

  void _float(Canvas canvas, Fx e, double k, String text, Color col, {double size = 20}) {
    final p = iso(e.x, e.y) + Offset(0, -56 - k * 40);
    final a = 1 - k;
    _text(canvas, p, text, col.withValues(alpha: a), size, outline: a);
  }

  void _label(Canvas canvas, Offset p, String text, Color col) => _text(canvas, p, text, col, 15, outline: 1);

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

  void _icon(Canvas canvas, IconData icon, Offset c, Color col, double size) {
    final tp = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: col)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(StorePainter old) => true;
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
  final edge = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final center = feet + const Offset(0, -17);
  canvas.drawCircle(center, 15, Paint()..color = colors[look % colors.length]);
  canvas.drawCircle(center, 15, edge);
  final blink = (clock + look * 0.7) % 3.2 < 0.12;
  for (final dx in [-5.0, 5.0]) {
    if (blink) {
      canvas.drawLine(center + Offset(dx - 2, -2), center + Offset(dx + 2, -2), edge);
    } else {
      canvas.drawCircle(center + Offset(dx, -2), 2.4, Paint()..color = ink);
    }
  }
}
