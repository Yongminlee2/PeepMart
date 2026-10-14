import 'package:flutter/material.dart';

import 'engine/catalog.dart';
import 'settings.dart';
import 'strings.dart';
import 'ui/sfx.dart';
import 'ui/debug_shot.dart';
import 'ui/sprites.dart';
import 'ui/title_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLang().load();
  await Settings.i.load();
  await Sprites.load();
  await Props.load(products.map((p) => p.id));
  await Sfx.load();
  await Music.init();
  runApp(PeepMartApp(home: await debugShotHome()));
}

class PeepMartApp extends StatelessWidget {
  final Widget? home; // 디버그 화면 확인(debug_shot.dart)이 아니면 비어 있다
  const PeepMartApp({super.key, this.home});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: AppLang(),
        builder: (context, _, _) => MaterialApp(
          title: 'Peep Mart',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Jua', colorSchemeSeed: const Color(0xFFFFB74D)),
          home: home ?? const TitleScreen(),
        ),
      );
}
