// 앱이 인터넷으로 하는 일은 카탈로그 받기 하나뿐이다. 의도 성공 기준 4, 작업 006 설계 2절, 계획 단계 3의 3
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// 네트워크를 부를 수 있는 패키지
const packages = [
  'package:http/',
  'package:dio/',
  'package:web_socket_channel/',
  'package:google_sign_in/',
  'package:kakao_flutter_sdk',
];

/// dart:io와 Flutter에 든 네트워크 길
final calls = RegExp(
  r'\b(HttpClient|Socket|SecureSocket|RawSocket|RawDatagramSocket|WebSocket|'
  r'InternetAddress|NetworkImage|NetworkAssetBundle|FadeInImage)\b|Image\.network',
);

/// 앱이 쓰는 패키지. 새 패키지가 밖으로 나가지 않는지 확인하고 여기에 더한다. 예를 들어 google_fonts는 실행 중에
/// 글꼴을 받는다. 2026-10-02 위험 검토
const allowed = {
  'flutter',
  'file_picker',
  'http',
  'sqlite3',
  // 엑셀 가져오기. 2026-10-02 소스에서 네트워크 호출이 없는 것을 봤다. 작업 006 설계 5절
  'archive',
  'cp949_codec',
  'crypto',
  'html',
  'xml',
  // 설정의 개인정보처리방침 줄과 카드 추가 화면의 카드 요청하기가 주소를 폰 브라우저로 넘긴다. 앱은 받지 않는다.
  // 앱 안 웹 화면은 열지 않게 LaunchMode.externalApplication만 쓴다. 2026-10-05 Android 소스에서 앱 안 웹 화면
  // 말고는 네트워크 호출이 없는 것을 봤다. 작업 012 설계 1.4, 6절
  'url_launcher',
};

/// import와 export 문 하나. 조건부 import는 문 안의 주소가 여럿이다
final directive = RegExp(r'^\s*(?:import|export)\b[^;]*;', multiLine: true);
final quoted = RegExp(r'''['"]([^'"]+)['"]''');

Iterable<String> urisIn(String text) => [
  for (final d in directive.allMatches(text))
    for (final q in quoted.allMatches(d.group(0)!)) q.group(1)!,
];

void main() {
  test('네트워크를 부르는 파일은 catalog/download.dart 하나뿐이다', () {
    final found = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      if (urisIn(text).any((u) => packages.any(u.startsWith)) ||
          calls.hasMatch(text)) {
        found.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(found, {'lib/catalog/download.dart'});
  });

  test('url_launcher는 바깥 브라우저로만 연다', () {
    // 모드 없이 launchUrl을 부르면 Android가 https를 앱 안 웹 화면으로 연다. 작업 012 위험 검토
    final users = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      if (!urisIn(text).any((u) => u.startsWith('package:url_launcher/'))) {
        continue;
      }
      users.add(f.path.replaceAll(r'\', '/'));
      expect(
        'launchUrl('.allMatches(text).length,
        'LaunchMode.externalApplication'.allMatches(text).length,
        reason: f.path,
      );
    }
    expect(users, {'lib/screens/settings.dart'});
  });

  test('앱 의존성은 확인한 패키지뿐이다', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect((pubspec['dependencies'] as Map).keys.toSet(), allowed);
  });

  test('찾는 규칙이 큰따옴표, export, 조건부 import, Flutter 그림 받기를 잡는다', () {
    expect(urisIn('import "package:http/http.dart";'), [
      'package:http/http.dart',
    ]);
    expect(urisIn("export 'package:http/http.dart';"), [
      'package:http/http.dart',
    ]);
    expect(
      urisIn(
        "import 'stub.dart'\n"
        "    if (dart.library.io) 'package:http/io_client.dart';",
      ),
      ['stub.dart', 'package:http/io_client.dart'],
    );
    for (final call in [
      "Image.network('https://x')",
      'InternetAddress.lookup(host)',
      "FadeInImage.assetNetwork(placeholder: 'a', image: 'https://x')",
    ]) {
      expect(calls.hasMatch(call), isTrue, reason: call);
    }
    expect(calls.hasMatch('SocketException'), isFalse);
  });
}
