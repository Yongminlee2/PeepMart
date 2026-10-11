import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 소리·음악·진동 켜고 끄기. 바뀌면 듣는 쪽(음악)이 바로 따라간다.
class Settings extends ChangeNotifier {
  Settings._();
  static final Settings i = Settings._();

  bool sound = true, music = true, vibration = true;
  bool joystick = false; // 끄면 누른 곳으로 걸어간다(기본)

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sound = p.getBool('set_sound') ?? true;
    music = p.getBool('set_music') ?? true;
    vibration = p.getBool('set_vibration') ?? true;
    joystick = p.getBool('set_joystick') ?? false;
  }

  Future<void> set({bool? sound, bool? music, bool? vibration, bool? joystick}) async {
    this.sound = sound ?? this.sound;
    this.music = music ?? this.music;
    this.vibration = vibration ?? this.vibration;
    this.joystick = joystick ?? this.joystick;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('set_sound', this.sound);
    await p.setBool('set_music', this.music);
    await p.setBool('set_vibration', this.vibration);
    await p.setBool('set_joystick', this.joystick);
  }
}
