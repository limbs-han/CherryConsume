// 앱에 묶은 SQLite의 판과 서버가 쓰던 문법. PC 시험과 폰 시험이 함께 쓴다. 작업 006 설계 1절, 계획 단계 1의 1
import 'package:sqlite3/sqlite3.dart';

/// 판을 돌려준다. 3.35보다 낮거나 문법 하나라도 안 되면 던진다
String checkSqlite() {
  final db = sqlite3.openInMemory();
  try {
    final version =
        db.select('select sqlite_version() as v').first['v'] as String;
    final [major, minor, ...] = version.split('.').map(int.parse).toList();
    if (major < 3 || (major == 3 && minor < 35)) {
      throw StateError('SQLite $version는 3.35보다 낮다');
    }
    db.execute('create table t (id text primary key, n int not null)');
    // 같은 키면 고쳐 쓰기 3.24, 조건 붙은 합계 3.30, 바꾼 행 돌려받기 3.35
    for (var i = 0; i < 2; i++) {
      db.execute(
        "insert into t values ('a', 1) on conflict (id) do update set n = n + 1",
      );
    }
    final n = db
        .select("update t set n = n + 1 where id = 'a' returning n")
        .first['n'];
    final c = db
        .select('select count(*) filter (where n > 2) as c from t')
        .first['c'];
    if (n != 3 || c != 1) throw StateError('문법 결과가 다르다: $n, $c');
    return version;
  } finally {
    db.close();
  }
}
