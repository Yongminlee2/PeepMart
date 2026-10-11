import 'package:flutter/material.dart';

import 'engine/catalog.dart';
import 'settings.dart';
import 'strings.dart';
import 'ui/sfx.dart';
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
  runApp(const PeepMartApp());
}

class PeepMartApp extends StatelessWidget {
  const PeepMartApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: AppLang(),
        builder: (context, _, _) => MaterialApp(
          title: 'Peep Mart',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Jua', colorSchemeSeed: const Color(0xFFFFB74D)),
          home: const TitleScreen(),
        ),
      );
}
