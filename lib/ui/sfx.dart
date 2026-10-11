import 'package:audioplayers/audioplayers.dart';
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

  static final _ctx = AudioContext(android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none));

  static Future<LowLatencySfx> fromAsset(String asset, {int voices = 3}) async {
    final players = <AudioPlayer>[];
    for (var i = 0; i < voices; i++) {
      final p = AudioPlayer();
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setAudioContext(_ctx);
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
    FxKind.unlock: 'unlock',
    FxKind.angry: 'angry',
  };

  static Future<void> load() async {
    for (final e in _files.entries) {
      try {
        _sounds[e.key] = await LowLatencySfx.fromAsset('audio/${e.value}.wav');
      } catch (_) {
        // 소리를 못 열어도 게임은 돈다.
      }
    }
  }

  static void play(FxKind k, double now) {
    if (now - (_last[k] ?? -9) < 0.07) return;
    _last[k] = now;
    if (Settings.i.sound) _sounds[k]?.start();
    if (!Settings.i.vibration) return;
    switch (k) {
      case FxKind.unlock:
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
