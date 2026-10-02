package com.cherryconsume.cherry_consume

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 폰 안 DB를 둘 앱 전용 폴더를 Dart에 알려 준다. Dart만으로는 이 폴더를 모르고, 경로 패키지를 더 넣지 않기로 했다.
// 앱을 지우면 함께 지워진다. 작업 006 설계 4절 "열 때"
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cherry/files")
            .setMethodCallHandler { call, result ->
                if (call.method == "filesDir") result.success(filesDir.absolutePath) else result.notImplemented()
            }
    }
}
