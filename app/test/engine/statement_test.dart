// 사용자 IBK 나라사랑 이용대금명세서 대조. Python `backend/tests/engine/test_statement.py`를 옮겼다. 엔진 설계 6.6
//
// 입력은 `backend/tests/engine/local/`에만 있고 저장소에 올리지 않는다. 파일이 없는 PC에서는 건너뛴다.
// 형식은 cases.dart와 같고, 엔진과 다른 결제에는 difference에 까닭을 적는다
import 'dart:io';

import 'package:cherry_consume/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cases.dart';
import 'helpers.dart';

/// 작업 006 단계 7에서 `app/test/local/`로 옮긴다
const localDir = '../backend/tests/engine/local';

void main() {
  final cases = Directory(localDir).existsSync()
      ? loadCases(localDir)
      : <Case>[];

  test(
    'test_statement_matches_engine',
    skip: cases.isEmpty ? '명세서 입력이 없는 PC' : null,
    () {
      final eng = Engine(realCatalog);
      final problems = {
        for (final c in cases)
          if (mismatches(eng, c) case final m when m.isNotEmpty) c.name: m,
      };
      expect(problems, isEmpty);
    },
  );
}
