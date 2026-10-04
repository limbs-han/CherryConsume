// 자동 백업 끄기. 결제 기록이 사용자 모르게 Google 계정이나 다른 폰으로 가지 않는다. 작업 006 설계 6절, 계획 단계 6의 3
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const manifest = 'android/app/src/main/AndroidManifest.xml';
const rules = 'android/app/src/main/res/xml/data_extraction_rules.xml';

void main() {
  test('Android 11까지의 백업과 클라우드 백업을 끈다', () {
    final app = XmlDocument.parse(
      File(manifest).readAsStringSync(),
    ).findAllElements('application').single;
    expect(app.getAttribute('android:allowBackup'), 'false');
    expect(
      app.getAttribute('android:dataExtractionRules'),
      '@xml/data_extraction_rules',
    );
  });

  test('Android 12부터의 클라우드 백업, 기기 사이 옮기기, iOS로 옮기기에서 앱 폴더를 모두 뺀다', () {
    // 공식 문서는 규칙이 없는 방식은 모두 켜진다고 적는다. 빈 칸도 그렇게 읽힐 수 있어 칸마다 모든 곳을 뺀다
    final root = XmlDocument.parse(File(rules).readAsStringSync()).rootElement;
    for (final section in [
      'cloud-backup',
      'device-transfer',
      'cross-platform-transfer',
    ]) {
      final found = root.findElements(section).single;
      expect(found.findElements('include'), isEmpty, reason: section);
      expect(
        {
          for (final e in found.findElements('exclude'))
            (e.getAttribute('domain'), e.getAttribute('path')),
        },
        {
          // 기기 보호 저장소는 잠금을 풀기 전에도 읽히는 곳이다. 앱은 쓰지 않지만 함께 뺀다. 단계 6 위험 검토 8번
          for (final d in [
            'root',
            'file',
            'database',
            'sharedpref',
            'external',
            'device_root',
            'device_file',
            'device_database',
            'device_sharedpref',
          ])
            // 도메인 전체는 `.`이다. 출시 빌드의 lint는 database와 sharedpref 칸의 `/`를 하위 폴더로 보고 막는다. 2026-10-04 단계 8
            (d, '.'),
        },
        reason: section,
      );
    }
  });
}
