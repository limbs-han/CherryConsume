// PC에서 도는 시험의 SQLite. 작업 006 계획 단계 1의 1
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_check.dart';

void main() {
  test('앱에 묶은 SQLite가 서버가 쓰던 문법을 받는다', () {
    final version = checkSqlite();
    // ignore: avoid_print
    print('PC SQLite $version');
  });
}
