import 'package:flutter_test/flutter_test.dart';
import 'package:peep_mart/strings.dart';

void main() {
  test('모든 언어가 영어와 같은 열쇠를 가진다', () {
    expect(S.missingKeys(), isEmpty);
  });

  test('숫자 자리 {n} 은 모든 언어에 그대로 있다', () {
    for (final MapEntry(key: code, value: table) in S.strings.entries) {
      expect(table['welcome_back'], contains('{n}'), reason: code);
    }
  });
}
