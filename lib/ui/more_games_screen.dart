import 'dart:io';

import 'package:flutter/material.dart';

import '../more_games.dart';
import '../strings.dart';
import 'widgets.dart';

/// 개발자의 다른 게임. 저장본을 바로 그리고, 새로 받으면 다시 그린다.
class MoreGamesScreen extends StatefulWidget {
  const MoreGamesScreen({super.key});

  @override
  State<MoreGamesScreen> createState() => _MoreGamesScreenState();
}

class _MoreGamesScreenState extends State<MoreGamesScreen> {
  List<MoreGame>? games; // null = 아직 아무것도 모름
  bool fetching = true;

  String get _lang => S.resolvedLanguage;

  /// 아이폰은 앱스토어 번호가 있는 게임만 보인다.
  List<MoreGame> _parse(String json) => MoreGames.visible(MoreGames.parse(json, lang: _lang), ios: MoreGames.onIos);

  @override
  void initState() {
    super.initState();
    MoreGames.cached().then((c) {
      if (c != null && mounted && games == null) setState(() => games = _parse(c));
    });
    MoreGames.fetch().then((f) {
      if (!mounted) return;
      setState(() {
        fetching = false;
        if (f != null) games = _parse(f);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = games;
    final Widget body;
    if (list == null || list.isEmpty) {
      body = Center(
        child: Text(
          fetching ? S.t('more_loading') : (list == null ? S.t('more_offline') : S.t('more_empty')),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: Colors.black54),
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _GameRow(list[i]),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: inkColor,
        title: Text(S.t('more_title'), style: const TextStyle(color: inkColor)),
      ),
      body: body,
    );
  }
}

class _GameRow extends StatelessWidget {
  final MoreGame g;
  const _GameRow(this.g);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: inkColor, width: 2),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: FutureBuilder<File?>(
                future: MoreGames.icon(g.icon),
                builder: (_, s) => s.data == null
                    ? Container(color: const Color(0xFFFFE0B2))
                    : Image.file(s.data!, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.name, style: const TextStyle(fontSize: 18, color: inkColor)),
              if (g.desc.isNotEmpty)
                Text(g.desc, maxLines: 3, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ]),
          ),
          const SizedBox(width: 8),
          g.self
              ? Text(S.t('more_now'), style: const TextStyle(fontSize: 15, color: Color(0xFF43A047)))
              : FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFB74D), foregroundColor: inkColor),
                  onPressed: () => MoreGames.openStore(MoreGames.storeKey(g, ios: MoreGames.onIos)),
                  child: Text(S.t('more_get')),
                ),
        ]),
      );
}
