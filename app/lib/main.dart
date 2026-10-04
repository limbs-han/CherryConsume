/// 앱 시작. 폰 안 DB를 열고 쓸 카탈로그를 고른 뒤 바로 홈이다. 로그인은 없다. 작업 006 설계 2절, 4절
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'api.dart';
import 'catalog/cache.dart';
import 'clock.dart' as clock;
import 'catalog/download.dart';
import 'files.dart';
import 'screens/shell.dart';
import 'store/db.dart';
import 'store/store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = '${await filesDir()}/cherry.db';
  final bundled = await rootBundle.loadString('assets/catalog.json');
  // 받기는 화면을 막지 않게 기다리지 않는다. 실패해도 던지지 않고 가진 것을 쓴다
  final (app, _) = boot(path, bundled);
  runApp(app);
}

/// DB를 열고 쓸 카탈로그를 고른 뒤 새 카탈로그 받기를 건다. 받은 카탈로그는 다음에 켤 때부터 쓴다. 시험이 받기를
/// 기다릴 수 있게 그 Future도 돌려준다. 시험은 가짜 응답을 주는 받기를 넣는다
(Widget, Future<Refresh>?) boot(
  String path,
  String bundled, {
  Future<Refresh> Function(Database, String, InUse) refresh = refreshCatalog,
}) {
  try {
    final db = openDb(path);
    final used = inUse(db);
    final store = Store(
      db,
      chooseCatalog(db, bundled, used),
      clock: () => clock.now(),
    );
    return (CherryApp(api: Api(store)), refresh(db, bundled, used));
  } catch (e, st) {
    // 앱보다 새 판이 만든 DB, 깨진 파일, 가득 찬 저장 공간. 이 DB가 기록의 하나뿐인 사본이라 지우라고 하지 않는다
    debugPrint('$e\n$st');
    return (const _CannotOpen(), null);
  }
}

class _CannotOpen extends StatelessWidget {
  const _CannotOpen();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '체리컨슘',
    theme: theme(),
    home: const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '기록을 열지 못했어요',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text('앱을 최신 판으로 올린 뒤 다시 켜 주세요. 앱을 지우거나 앱 데이터를 지우면 기록이 모두 사라져요.'),
            ],
          ),
        ),
      ),
    ),
  );
}

class CherryApp extends StatelessWidget {
  const CherryApp({super.key, required this.api});
  final Api api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '체리컨슘',
    theme: theme(),
    // Android 15부터 앱이 아래 막대 뒤까지 그린다. 3버튼 막대 뒤에는 Android가 반투명 바탕을 깔아 글자가 비치지
    // 않게 한다. 제스처 막대는 그대로 투명하다. 작업 011 설계 2절 Z3
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: true,
      ),
      child: child!,
    ),
    home: Shell(api: api),
  );
}
