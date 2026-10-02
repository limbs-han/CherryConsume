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

/// 로그인. 계획 단계 7에서 지우면 여기서도 뺀다
const untilStep7 = {'lib/social.dart'};

/// 앱이 쓰는 패키지. 새 패키지가 밖으로 나가지 않는지 확인하고 여기에 더한다. 예를 들어 google_fonts는 실행 중에
/// 글꼴을 받는다. 2026-10-02 위험 검토
const allowed = {
  'flutter',
  'file_picker',
  'http',
  'sqlite3',
  // 계획 단계 7에서 지운다
  'flutter_secure_storage',
  'google_sign_in',
  'kakao_flutter_sdk_user',
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
    expect(found, {'lib/catalog/download.dart', ...untilStep7});
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
