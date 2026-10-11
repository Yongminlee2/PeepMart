import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/engine/catalog.dart';
import 'package:peep_mart/engine/game.dart';
import 'package:peep_mart/engine/world.dart';
import 'package:peep_mart/ui/sprites.dart';
import 'package:peep_mart/ui/store_painter.dart';

const out = r'C:\WORKAN~1\TMP-AS~1\claude\C--workAndroid-app\cd2dc23c-71fe-420e-958c-6e0c0a3a8c61\scratchpad\';

Future<void> shot(World w, String name, Offset center, double zoom, {Size size = const Size(1400, 1000)}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Offset.zero & size, Paint()..color = themeOf(w.game.branch).sky);
  StorePainter(w, [], 3.0, Camera(center, zoom), null).paint(c, size);
  final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$out$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('scene', (tester) async {
    await tester.runAsync(() async {
      await Sprites.load();
      await Props.load(products.map((p) => p.id));
      for (final branch in ['piyak', 'beach', 'night', 'snow']) {
        final g = Game()..level = 30;
        if (branch != 'piyak') {
          g.money = 999999;
          g.owner.open(branch);
        }
        final gg = g.owner.game;
        gg.owner.story.addAll(['opening', 'rival']);
        gg.owner.tutorial = TutorialStep.done;
        final w = World(gg, seed: 3)..openDay();
        for (var i = 0; i < 400; i++) {
          w.tick(0.05);
        }
        // 가게 쪽(처음 화면)과 넓게 본 모습
        await shot(w, 'scene_${branch}_near', iso(4, 4), 1.0);
        await shot(w, 'scene_${branch}_far', iso(10, 6), 0.45);
      }
    });
  });
}
