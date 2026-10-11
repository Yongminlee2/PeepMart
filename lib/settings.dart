import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 소리·음악·진동 켜고 끄기. 바뀌면 듣는 쪽(음악)이 바로 따라간다.
class Settings extends ChangeNotifier {
  Settings._();
  static final Settings i = Settings._();

  bool sound = true, music = true, vibration = true;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sound = p.getBool('set_sound') ?? true;
    music = p.getBool('set_music') ?? true;
    vibration = p.getBool('set_vibration') ?? true;
  }

  Future<void> set({bool? sound, bool? music, bool? vibration}) async {
    this.sound = sound ?? this.sound;
    this.music = music ?? this.music;
    this.vibration = vibration ?? this.vibration;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('set_sound', this.sound);
    await p.setBool('set_music', this.music);
    await p.setBool('set_vibration', this.vibration);
  }
}
