// 자동 생성 — 언어 등록표.

import 'ko.dart';
import 'en.dart';
import 'ja.dart';
import 'zh.dart';
import 'zh_Hant.dart';
import 'es.dart';
import 'pt.dart';
import 'de.dart';
import 'fr.dart';
import 'it.dart';
import 'ru.dart';
import 'id.dart';
import 'vi.dart';
import 'th.dart';

const Map<String, Map<String, String>> kStrings = {
  'ko': kKo,
  'en': kEn,
  'ja': kJa,
  'zh': kZh,
  'zh_Hant': kZhHant,
  'es': kEs,
  'pt': kPt,
  'de': kDe,
  'fr': kFr,
  'it': kIt,
  'ru': kRu,
  'id': kId,
  'vi': kVi,
  'th': kTh,
};

/// 설정 화면에 보여 줄 차례.
const List<String> kLanguageOrder = [
  'ko',
  'en',
  'ja',
  'zh',
  'zh_Hant',
  'es',
  'pt',
  'de',
  'fr',
  'it',
  'ru',
  'id',
  'vi',
  'th',
];

/// 각 언어를 그 언어 글자로 적는다 — 자기 나라 말을 찾는 사람은
/// 글자 모양을 보지 영어 낱말을 읽지 않는다. 번역하지 않는다.
const Map<String, String> kLanguageNames = {
  'ko': '한국어',
  'en': 'English',
  'ja': '日本語',
  'zh': '简体中文',
  'zh_Hant': '繁體中文',
  'es': 'Español',
  'pt': 'Português',
  'de': 'Deutsch',
  'fr': 'Français',
  'it': 'Italiano',
  'ru': 'Русский',
  'id': 'Bahasa Indonesia',
  'vi': 'Tiếng Việt',
  'th': 'ไทย',
};
