// 폰에서 도는 앱의 SQLite. PC 시험과 같은 판인지 본다. 작업 006 계획 단계 1의 1
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/sqlite_check.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('폰의 앱에 묶은 SQLite가 서버가 쓰던 문법을 받는다', () {
    final version = checkSqlite();
    // ignore: avoid_print
    print('폰 SQLite $version');
  });
}
