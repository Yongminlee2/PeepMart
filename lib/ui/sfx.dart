import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/world.dart';
import '../settings.dart';

/// 저지연 모드(안드로이드 SoundPool) 플레이어 몇 개를 돌려 가며 쓴다.
/// 기본(MediaPlayer) 모드는 재생할 때마다 메인 스레드를 0.1초씩 붙잡아 화면이 끊긴다.
/// 출처: common/flutter/sfx_low_latency.dart
class LowLatencySfx {
  final List<AudioPlayer> _players;
  var _next = 0;
  LowLatencySfx(this._players);

  /// 아이폰은 ambient: 무음 스위치를 따르고, 다른 앱 음악을 끊지 않는다.
  static final ctx = AudioContext(
    android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  static Future<LowLatencySfx> fromAsset(String asset, {int voices = 3}) async {
    final players = <AudioPlayer>[];
    for (var i = 0; i < voices; i++) {
      final p = AudioPlayer();
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setAudioContext(ctx);
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource(asset));
      players.add(p);
    }
    return LowLatencySfx(players);
  }

  Future<void> start() async {
    final p = _players[_next];
    _next = (_next + 1) % _players.length;
    // 저지연 모드는 "재생 끝" 신호가 없어서 멈춰 두지 않으면 다음 재생이 조용히 넘어간다.
    await p.stop();
    await p.resume();
  }
}

/// 게임 사건 → 소리·진동. 같은 소리가 너무 촘촘하면 거른다.
class Sfx {
  static final Map<FxKind, LowLatencySfx> _sounds = {};
  static final Map<FxKind, double> _last = {};

  static const _files = {
    FxKind.pick: 'pick',
    FxKind.place: 'place',
    FxKind.scan: 'scan',
    FxKind.pay: 'pay',
    FxKind.cash: 'cash',
    FxKind.levelUp: 'unlock',
    FxKind.angry: 'angry',
    FxKind.clean: 'pick',
    FxKind.cook: 'place',
    FxKind.wake: 'pick',
  };

  /// 사건 소리: 경보(도둑·고장·진상·빈 상자), 좋음(잡음·고침·달램·우수), 나쁨(놓침·불량), 딩동(주문·도착·점검관), 피버, 상자.
  static const cues = ['alarm', 'good', 'bad', 'bell', 'fever', 'chest'];
  static final Map<String, LowLatencySfx> _cues = {};
  static final Map<String, double> _cueLast = {};

  static Future<void> load() async {
    for (final e in _files.entries) {
      try {
        _sounds[e.key] = await LowLatencySfx.fromAsset('audio/${e.value}.wav');
      } catch (_) {
        // 소리를 못 열어도 게임은 돈다.
      }
    }
    for (final c in cues) {
      try {
        _cues[c] = await LowLatencySfx.fromAsset('audio/$c.wav', voices: 2);
      } catch (_) {}
    }
  }

  /// 이름 붙은 사건 소리. 좋은 일·나쁜 일엔 진동도.
  static void cue(String name, double now) {
    if (now - (_cueLast[name] ?? -9) < 0.15) return;
    _cueLast[name] = now;
    if (Settings.i.sound) _cues[name]?.start();
    if (!Settings.i.vibration) return;
    if (name == 'alarm' || name == 'bad') HapticFeedback.heavyImpact();
    if (name == 'good' || name == 'fever' || name == 'chest') HapticFeedback.mediumImpact();
  }

  static void play(FxKind k, double now) {
    if (now - (_last[k] ?? -9) < 0.07) return;
    _last[k] = now;
    if (Settings.i.sound) _sounds[k]?.start();
    if (!Settings.i.vibration) return;
    switch (k) {
      case FxKind.levelUp:
        HapticFeedback.mediumImpact();
      case FxKind.pay || FxKind.place:
        HapticFeedback.selectionClick();
      default:
    }
  }
}

/// 배경음악 한 곡을 계속 돌린다. 설정에서 끄면 멈추고, 앱이 뒤로 가면 쉰다.
/// WAV 라 이음매 없이 돈다(AAC·MP3 는 앞뒤에 빈틈이 생기고, 아이폰은 OGG 를 못 튼다).
class Music {
  static final _player = AudioPlayer();
  static bool _ready = false, _paused = false;

  static Future<void> init() async {
    try {
      // 아이폰만: 효과음과 같은 ambient. 안드로이드 음악은 예전처럼 오디오 포커스를 받는다.
      if (defaultTargetPlatform == TargetPlatform.iOS) await _player.setAudioContext(LowLatencySfx.ctx);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.35);
      await _player.setSource(AssetSource('audio/bgm.wav'));
      _ready = true;
    } catch (_) {
      return; // 음악이 없어도 게임은 돈다
    }
    Settings.i.addListener(_apply);
    _apply();
  }

  static bool _fast = false;

  /// 피버 타임 동안은 음악을 조금 빠르게.
  static void fast(bool on) {
    if (!_ready || on == _fast) return;
    _fast = on;
    _player.setPlaybackRate(on ? 1.18 : 1.0);
  }

  /// 앱이 뒤로 갔다(true)/돌아왔다(false).
  static void background(bool away) {
    _paused = away;
    _apply();
  }

  static void _apply() {
    if (!_ready) return;
    if (Settings.i.music && !_paused) {
      _player.resume();
    } else {
      _player.pause();
    }
  }
}
