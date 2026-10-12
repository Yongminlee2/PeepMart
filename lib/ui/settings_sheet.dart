import 'package:flutter/material.dart';

import '../settings.dart';
import '../strings.dart';
import 'widgets.dart';

/// 설정: 효과음·배경음악·진동·언어, 그리고 만든 재료(출처).
/// onReset 을 주면 맨 아래에 「처음부터 다시」가 생긴다(타이틀에서만).
Future<void> showSettings(BuildContext context, {VoidCallback? onReset}) => showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SettingsSheet(onReset),
    );

class _SettingsSheet extends StatelessWidget {
  final VoidCallback? onReset;
  const _SettingsSheet(this.onReset);

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 19, color: inkColor);
    return ListenableBuilder(
      listenable: Listenable.merge([Settings.i, AppLang()]),
      builder: (context, _) {
        final s = Settings.i;
        Widget toggle(String key, bool on, ValueChanged<bool> set) => SwitchListTile(
              title: Text(S.t(key), style: label),
              value: on,
              activeThumbColor: const Color(0xFF66BB6A),
              onChanged: set,
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(S.t('settings_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, color: inkColor)),
              const SizedBox(height: 8),
              toggle('set_sound', s.sound, (v) => s.set(sound: v)),
              toggle('set_music', s.music, (v) => s.set(music: v)),
              toggle('set_vibration', s.vibration, (v) => s.set(vibration: v)),
              toggle('set_joystick', s.joystick, (v) => s.set(joystick: v)),
              ListTile(
                title: Text(S.t('set_language'), style: label),
                trailing: DropdownButton<String>(
                  value: AppLang().value,
                  style: const TextStyle(fontFamily: 'Jua', fontSize: 17, color: inkColor),
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(value: 'system', child: Text(S.t('lang_system'))),
                    for (final code in kLanguageOrder) DropdownMenuItem(value: code, child: Text(kLanguageNames[code]!)),
                  ],
                  onChanged: (v) => AppLang().set(v ?? 'system'),
                ),
              ),
              if (onReset != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      final ok = await confirm(context, S.t('reset_confirm'));
                      if (ok && context.mounted) {
                        Navigator.of(context).pop();
                        onReset!();
                      }
                    },
                    child: Text(S.t('btn_reset'), style: const TextStyle(fontSize: 17, color: Color(0xFFE53935))),
                  ),
                ),
              ],
              const Divider(height: 32),
              Text(S.t('credits_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: inkColor)),
              const SizedBox(height: 6),
              Text(
                '${S.t('credits_art')}: Kenney (kenney.nl), Quaternius (quaternius.com), CC0\n'
                '${S.t('credits_music')}: "Happy Clappy Loop" OwlishMedia, CC0\n'
                '${S.t('credits_font')}: Jua, SIL OFL',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black45, height: 1.6),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// 예/아니오 묻기.
Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: bg,
        content: Text(message, style: const TextStyle(fontSize: 18, color: inkColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.t('btn_cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(S.t('btn_ok'))),
        ],
      ),
    ) ??
    false;
