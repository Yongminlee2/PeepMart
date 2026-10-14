// 아이폰 설정이 안드로이드·게임 코드와 어긋나지 않는지 본다. 아이폰 빌드는 맥에서만 되므로,
// 윈도우에서 안드로이드만 고치다가 생긴 차이(번들 ID·앱 이름·언어·화면 방향)를 여기서 먼저 잡는다.
// 출처: common/flutter/ios/ios_config_test.dart. 저장소 루트에서 `flutter test` 로 돈다(파일을 직접 읽는다).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/more_games.dart';
import 'package:peep_mart/strings.dart';

void main() {
  // 윈도우에서 받은 저장소는 줄 끝이 CRLF 라, 비교하기 전에 맞춘다.
  final plist = File('ios/Runner/Info.plist').readAsStringSync().replaceAll('\r\n', '\n');
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  // 앱 언어 코드 → 아이폰 .lproj 이름
  const iosCode = {'zh': 'zh-Hans', 'zh_Hant': 'zh-Hant'};

  test('번들 ID가 안드로이드 패키지 이름·다른 게임 selfId 와 같다', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final androidId = RegExp(r'applicationId = "([^"]+)"').firstMatch(gradle)!.group(1);
    final iosIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);')
        .allMatches(pbxproj)
        .map((m) => m.group(1)!)
        .where((id) => !id.endsWith('.RunnerTests'))
        .toSet();
    expect(iosIds, {androidId});
    expect(MoreGames.selfId, androidId);
  });

  test('언어마다 홈 화면 이름이 i18n 의 app_name 과 같고, 언어를 전부 신고한다', () {
    for (final code in S.strings.keys) {
      final lproj = iosCode[code] ?? code;
      expect(plist, contains('<string>$lproj</string>'), reason: '$code: CFBundleLocalizations');
      final f = File('ios/Runner/$lproj.lproj/InfoPlist.strings');
      expect(f.existsSync(), isTrue, reason: '$lproj.lproj');
      final name = RegExp(r'"CFBundleDisplayName" = "([^"]+)";').firstMatch(f.readAsStringSync())!.group(1);
      final want = (jsonDecode(File('i18n/$code.json').readAsStringSync()) as Map)['app_name'];
      expect(name, want, reason: lproj);
      expect(pbxproj, contains('path = $lproj.lproj/InfoPlist.strings;'), reason: '$lproj 가 앱에 실린다');
    }
  });

  test('아이폰 전용·세로 전용(아이패드는 아이폰 앱으로 돈다)', () {
    expect(RegExp(r'TARGETED_DEVICE_FAMILY = ([^;]+);').allMatches(pbxproj).map((m) => m.group(1)).toSet(), {'1'});
    final orient = RegExp(r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>', dotAll: true)
        .firstMatch(plist)!
        .group(1)!;
    expect(RegExp(r'<string>(\w+)</string>').allMatches(orient).map((m) => m.group(1)).toList(),
        ['UIInterfaceOrientationPortrait']);
  });

  test('수출 규정 질문을 건너뛴다(표준 암호화만 쓴다)', () {
    expect(plist, contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'));
  });

  test('앱 아이콘 1024 는 투명 픽셀이 없다(앱 스토어가 거부한다)', () {
    final png = File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png').readAsBytesSync();
    // IHDR: 폭·높이(4바이트씩), 비트 깊이, 색 형식. 색 형식 2 = 알파 없는 RGB.
    int u32(int o) => (png[o] << 24) | (png[o + 1] << 16) | (png[o + 2] << 8) | png[o + 3];
    expect(u32(16), 1024);
    expect(u32(20), 1024);
    expect(png[25], 2);
  });

  test('개인정보 매니페스트가 앱에 실리고, 추적하지 않는다고 적혀 있다', () {
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync().replaceAll('\r\n', '\n');
    expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    expect(pbxproj, contains('PrivacyInfo.xcprivacy in Resources'));
  });

  test('디버그 화면 통로는 Swift 에서도 DEBUG 빌드에만 있다', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final open = delegate.indexOf('#if DEBUG');
    expect(open, greaterThan(0));
    expect(delegate.indexOf('peep/debug'), greaterThan(open));
  });
}
