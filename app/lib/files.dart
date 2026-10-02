/// 폰 안 DB를 둘 앱 전용 폴더. Android의 filesDir이다. MainActivity가 알려 준다. 작업 006 설계 4절 "열 때"
library;

import 'package:flutter/services.dart';

const _channel = MethodChannel('cherry/files');

Future<String> filesDir() async =>
    (await _channel.invokeMethod<String>('filesDir'))!;
