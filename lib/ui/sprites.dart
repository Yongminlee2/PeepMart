import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'store_painter.dart' show tw;

// tool/render_chars.py 가 만든 캐릭터 시트와 같은 값이어야 한다.
const frameSize = 128.0;
const frameCols = 8;
const footY = 0.85;
const orthoWorld = 1.15; // 한 칸에 담긴 세계 크기
const charScale = 1.2; // 바닥 한 칸(1) 대비 캐릭터 크기

enum Anim { idle, walk, pickUp, yes, no, interact, carry, sit }

enum Facing { downLeft, downRight, upLeft, upRight }

/// 시트의 줄 번호. back 이 없는 동작은 front 를 쓴다.
int _row(Anim a, bool back) => switch (a) {
      Anim.idle => back ? 1 : 0,
      Anim.walk => back ? 3 : 2,
      Anim.pickUp => back ? 5 : 4,
      Anim.yes => 6,
      Anim.no => 7,
      Anim.interact => 8,
      Anim.carry => back ? 10 : 9,
      Anim.sit => back ? 12 : 11,
    };

// 앞 46개는 tool/render_chars.py 의 CHARS 순서(Quaternius), 뒤 12개는 Kenney Mini Characters.
const characterFiles = [
  'casual-female', 'casual3-female', 'chef-female', 'suit-female', 'cashier', 'janitor',
  'owner', 'casual2-male', 'old-male', 'stocker', 'suit-male', 'doctor-female',
  'bald-male', 'chef-male', 'cowboy-female', 'cowboy-male', 'doctor-male-old', 'doctor-female-old',
  'doctor-male', 'kimono-female', 'kimono-male', 'old-female', 'worker-female', 'pirate-female',
  'pirate-male', 'viking-female', 'wizard', 'witch', 'elf',
  'casual-female-b', 'casual-male-b', 'casual2-male-b', 'casual3-female-b', 'casual2-female-b',
  'casual3-male-b', 'casual2-female-c', 'casual-male-c', 'casual-female-c', 'bald-male-b', 'worker-male-b',
  'suit-female-b', 'suit-male-b', 'pug', 'cow', 'goblin-female', 'goblin-male',
  'female-a', 'female-b', 'female-c', 'female-d', 'female-e', 'female-f',
  'male-a', 'male-b', 'male-c', 'male-d', 'male-e', 'male-f',
];

/// 걷는 방향(세계 좌표) → 화면에서 보는 방향.
Facing facingOf(double dx, double dy) {
  final sx = dx - dy, sy = dx + dy;
  if (sy >= 0) return sx < 0 ? Facing.downLeft : Facing.downRight;
  return sx < 0 ? Facing.upLeft : Facing.upRight;
}

/// 시트 번호: 플레이어·알바는 고정, 손님은 나머지 전부에서 고른다.
const playerChar = 6, cashierChar = 4, stockerChar = 9, janitorChar = 5;
const _staffChars = {playerChar, cashierChar, stockerChar, janitorChar};
final customerChars = [
  for (var i = 0; i < characterFiles.length; i++)
    if (!_staffChars.contains(i)) i
];

Future<ui.Image?> _image(String asset) async {
  try {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null; // 그림이 없으면 페인터로 그린다
  }
}

/// tool/render_props.py 가 찍은 음식 아이콘과 가구.
class Props {
  static final Map<String, ui.Image> _images = {};
  static const foodFit = 0.8 / 1.25; // 음식이 칸에서 차지하는 비율
  static const propWorld = 1.9, propFoot = 0.80;

  static Future<void> load(Iterable<String> foods) async {
    for (final n in [for (final f in foods) 'food-$f', 'prop-crate', 'prop-rack', 'prop-plant', 'prop-plant-small', 'prop-trash', 'prop-flowers', 'prop-lamp', 'prop-chair', 'prop-table']) {
      final img = await _image('assets/props/$n.png');
      if (img != null) _images[n] = img;
    }
  }

  /// 음식 아이콘. size 는 음식 자체의 크기(그림 좌표). 그림이 없으면 false.
  static bool food(Canvas canvas, String id, Offset center, double size) {
    final img = _images['food-$id'];
    if (img == null) return false;
    final d = size / foodFit;
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: center, width: d, height: d), Paint()..filterQuality = FilterQuality.medium);
    return true;
  }

  /// 가구 한 점. 바닥 한가운데가 feet 에 온다. scale 로 더 키우거나 줄인다.
  static bool prop(Canvas canvas, String name, Offset feet, {double scale = 1}) {
    final img = _images['prop-$name'];
    if (img == null) return false;
    final d = propWorld * (tw / 1.41421356) * scale;
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(feet.dx - d / 2, feet.dy - d * propFoot, d, d), Paint()..filterQuality = FilterQuality.medium);
    return true;
  }
}

class Sprites {
  // ponytail: 시트 하나가 풀리면 6.8MB 라 58개를 다 올리면 400MB 가 가깝다.
  // 처음 그릴 때 올리고, 넘치면 한동안 안 그린 손님부터 내린다.
  static const _keep = 18;
  static final Map<int, ui.Image> _sheets = {};
  static final Map<int, int> _used = {}; // 마지막으로 그린 때(ms)
  static final Set<int> _loading = {}, _missing = {};
  static final _clock = Stopwatch()..start();

  /// 시트가 새로 올라올 때마다 바뀐다. 한 번만 그리는 그림(초상화 등)이 다시 그리게.
  static final loaded = ValueNotifier(0);

  static Future<void> _load(int i) async {
    _loading.add(i);
    final img = await _image('assets/characters/character-${characterFiles[i]}.png');
    _loading.remove(i);
    if (img == null) {
      _missing.add(i);
      return;
    }
    _sheets[i] = img;
    _evict();
    loaded.value++;
  }

  static void _evict() {
    if (_sheets.length <= _keep) return;
    final now = _clock.elapsedMilliseconds;
    final idle = _sheets.keys.where((k) => !_staffChars.contains(k) && now - (_used[k] ?? 0) > 3000).toList()
      ..sort((a, b) => (_used[a] ?? 0).compareTo(_used[b] ?? 0));
    for (final k in idle.take(_sheets.length - _keep)) {
      _sheets.remove(k)?.dispose();
    }
  }

  /// 첫 화면에 나오는 사람만 미리 올린다.
  static Future<void> load() async {
    for (final i in {..._staffChars, customerChars[0], customerChars[3]}) {
      await _load(i);
    }
  }

  /// 발 위치에 캐릭터 한 프레임을 그린다. 그림이 없으면 false.
  static bool draw(Canvas canvas, int who, Offset feet, Anim anim, Facing facing, double t, {double fps = 10}) {
    who %= characterFiles.length;
    _used[who] = _clock.elapsedMilliseconds;
    final img = _sheets[who];
    if (img == null) {
      if (_missing.contains(who)) return false;
      if (!_loading.contains(who)) _load(who);
      return true; // 올라오는 동안(한두 프레임)은 비워 둔다
    }
    final back = facing == Facing.upLeft || facing == Facing.upRight;
    final flip = facing == Facing.downRight || facing == Facing.upLeft;
    final frame = (t * fps).floor() % frameCols;
    var row = _row(anim, back);
    if ((row + 1) * frameSize > img.height) row = back ? 1 : 0; // 옛 시트에 없는 동작은 서 있기로
    final src = Rect.fromLTWH(frame * frameSize, row * frameSize, frameSize, frameSize);
    final size = orthoWorld * (tw / 1.41421356) * charScale;
    final dst = Rect.fromLTWH(-size / 2, -size * footY, size, size);
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    if (flip) canvas.scale(-1, 1);
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    return true;
  }
}
