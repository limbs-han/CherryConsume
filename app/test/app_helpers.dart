// 화면 시험의 앱. 가짜 서버 대신 메모리 SQLite와 커밋된 카탈로그 위의 실제 저장소다. 작업 006 설계 4절 "시험"
//
// 시계는 서버 시험처럼 2026-09-15 21:00 한국 시간이다. 화면과 저장소가 같은 시계를 본다
import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/clock.dart' as clock;
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine/helpers.dart' show realCatalog;
import 'store/helpers.dart' show start;

({Api api, Store s}) app([DateTime? at]) {
  final fixed = at ?? start;
  clock.now = () => fixed;
  addTearDown(() => clock.now = DateTime.now);
  final s = Store(openDb(), realCatalog, clock: () => clock.now());
  return (api: Api(s), s: s);
}
