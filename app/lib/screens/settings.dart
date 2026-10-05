/// 시안 보드 9 설정. 혜택 계산에 쓰는 답. 작업 004 설계 3.1, 작업 005 설계 5e. 로그인이 없어 계정 칸은 뺐다. 작업 006
///
/// 기록 내보내기와 가져오기. 폰을 바꿀 때 기록을 파일 하나로 옮긴다. 작업 006 설계 6절
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../clock.dart' as clock;
import '../store/backup.dart' show maxBytes;
import '../theme.dart';
import '../ui.dart';
import 'answer.dart';
import 'import.dart' show PickFile;

/// 앱 판. pubspec.yaml의 version과 같아야 한다. 시험이 맞춰 본다. 작업 011 설계 2절 S2
const appVersion = '0.1.0';

/// 개인정보처리방침. Play 정책은 Play Console 칸과 앱 안 두 곳에 두라고 한다. 작업 012 설계 1.4
final privacyUrl = Uri.parse(
  'https://limbs-han.github.io/CherryConsume/privacy/',
);

/// 주소를 폰 브라우저로 연다. 앱이 직접 받지 않는다. 열지 못하면 거짓이다. 시험에서는 바꿔 끼운다
typedef OpenUrl = Future<bool> Function(Uri url);

Future<bool> openInBrowser(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 기록 내보내기 줄 아래 문구. 해가 다르면 해를 붙인다. 작업 012 설계 4.1
String exportedNote(DateTime? at, DateTime now) => at == null
    ? '아직 내보낸 적 없어요'
    : '마지막으로 내보낸 날 ${at.year == now.year ? '' : '${at.year}년 '}${at.month}월 ${at.day}일';

/// 내보낸 파일을 사용자가 고른 곳에 쓴다. 취소하면 거짓이다. 시험에서는 바꿔 끼운다
typedef SaveFile = Future<bool> Function(String name, Uint8List bytes);

Future<bool> saveWithSystem(String name, Uint8List bytes) async =>
    await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: 'application/json',
    ) !=
    null;

/// 기록 파일 고르기. 20MB를 넘으면 bytes가 null이다
Future<({String name, Uint8List? bytes})?> pickRecords() async {
  // 고르기 안에서 복사가 실패해도 사본 조각을 지우게 고르기부터 감싼다. 단계 6 위험 검토 5번
  try {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return null;
    final f = files.first;
    final size = await f.length();
    if (size != null && size > maxBytes) return (name: f.name, bytes: null);
    final bytes = await f.readAsBytes();
    return (name: f.name, bytes: bytes.length > maxBytes ? null : bytes);
  } finally {
    // Android는 고른 파일을 앱 임시 폴더에 복사한다. 기록 사본이 남지 않게 지운다
    await FilePicker.clearTemporaryFiles();
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    this.save = saveWithSystem,
    this.pick = pickRecords,
    this.open = openInBrowser,
  });
  final Api api;
  final SaveFile save;
  final PickFile pick;
  final OpenUrl open;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<FactQuestion>> _facts = widget.api.userFacts();
  late Future<DateTime?> _exported = widget.api.lastExported();

  Future<void> _answer(FactQuestion q, Object value) async {
    try {
      final repriced = await widget.api.answerFacts({q.key: value});
      if (!mounted) return;
      answered(context, repriced);
      setState(() {
        _facts = widget.api.userFacts();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('답을 적지 못했어요.')));
      }
    }
  }

  // 앞 안내가 떠 있어도 바로 바꿔 보인다. 줄을 세우면 다시 누른 결과가 4초 뒤에 뜬다
  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _ask(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(yes),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _export() async {
    if (!await _ask(
      '기록 내보내기',
      '이 파일에는 결제 기록이 그대로 들어 있어요. 남에게 보내지 마세요.',
      '내보내기',
    )) {
      return;
    }
    try {
      final text = await widget.api.exportRecords();
      final now = clock.now();
      final day =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final saved = await widget.save(
        'cherryconsume-$day.json',
        utf8.encode(text),
      );
      if (saved) {
        // 파일은 이미 저장됐다. 날 적기가 실패해도 내보냈다고 알린다. 위험 검토 낮음 4
        try {
          await widget.api.markExported();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _exported = widget.api.lastExported();
          });
          _say('기록을 내보냈어요.');
        }
      }
    } catch (_) {
      if (mounted) _say('기록을 내보내지 못했어요.');
    }
  }

  Future<void> _privacy() async {
    if (!await widget.open(privacyUrl) && mounted) {
      _say('브라우저를 열지 못했어요. ${privacyUrl.host}${privacyUrl.path}에서 볼 수 있어요.');
    }
  }

  Future<void> _import() async {
    final ({String name, Uint8List? bytes})? f;
    try {
      f = await widget.pick();
    } catch (_) {
      if (mounted) _say('파일을 읽지 못했어요.');
      return;
    }
    if (f == null || !mounted) return;
    final bytes = f.bytes;
    if (bytes == null) return _say('파일이 20MB보다 커요.');
    if (await widget.api.hasRecords() &&
        !await _ask('기록 가져오기', '지금 기록을 지우고 파일의 기록으로 바꿀까요?', '바꾸기')) {
      return;
    }
    // 가져오기만 감싼다. 가져온 뒤 화면 그리기의 오류까지 잡으면 가져왔는데도 못 가져왔다고 알린다. 2026-10-03
    // 에뮬레이터에서 찾았다
    try {
      await widget.api.importRecords(bytes);
    } on ApiError catch (e) {
      // 받지 않는 파일은 까닭을 그대로 보인다. 지금 기록은 그대로다
      if (mounted) {
        _say(e.status == 413 || e.status == 422 ? e.body : '기록을 가져오지 못했어요.');
      }
      return;
    } catch (_) {
      if (mounted) _say('기록을 가져오지 못했어요.');
      return;
    }
    if (!mounted) return;
    _say('기록을 가져왔어요.');
    setState(() {
      _facts = widget.api.userFacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.api.catalogDay();
    // 시안대로 묶음마다 흰 카드에 줄, 오른쪽 값, 화살표다. 작업 011 설계 2절 S1, S2
    return Scaffold(
      appBar: AppBar(
        titleSpacing: rootTitleSpacing(context),
        title: const Text('설정'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const _Group('혜택 계산에 쓰는 답'),
          FutureBuilder(
            future: _facts,
            builder: (context, snap) => switch (snap) {
              AsyncSnapshot(hasError: true) => const Text('답을 불러오지 못했어요.'),
              AsyncSnapshot(:final data?) when data.isEmpty => const Text(
                '지금 가진 카드에는 물을 것이 없어요.',
                style: TextStyle(color: C.sub),
              ),
              AsyncSnapshot(:final data?) => _Rows([
                for (final q in data)
                  FactRow(
                    q: q,
                    note: '쓰는 카드 · ${q.cards.join(', ')}',
                    onAnswer: (v) => _answer(q, v),
                  ),
              ]),
              _ => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ),
          const _Group('기록 옮기기'),
          _Rows([
            // 기록이 폰 안에만 있어 마지막으로 내보낸 날을 보인다. 작업 012 설계 4.1
            FutureBuilder<DateTime?>(
              future: _exported,
              builder: (context, snap) => TapRow(
                title: '기록 내보내기',
                // 다시 읽는 동안 앞 날을 그대로 보여 줄 높이가 출렁이지 않는다
                sub:
                    snap.connectionState == ConnectionState.done || snap.hasData
                    ? exportedNote(snap.data, clock.now().toLocal())
                    : null,
                onTap: _export,
              ),
            ),
            TapRow(title: '기록 가져오기', sub: '내보낸 파일의 기록으로 바꿔요', onTap: _import),
          ]),
          const _Group('앱'),
          _Rows([
            TapRow(
              title: '앱 정보',
              trailing: RowValue('$appVersion · 카탈로그 ${day.month}/${day.day}'),
            ),
            TapRow(title: '개인정보처리방침', onTap: _privacy),
          ]),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: C.sub,
      ),
    ),
  );
}

/// 흰 카드 하나에 줄을 구분선으로 잇는다
class _Rows extends StatelessWidget {
  const _Rows(this.lines);
  final List<Widget> lines;

  @override
  Widget build(BuildContext context) => Box(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      children: [
        for (final (i, l) in lines.indexed) ...[
          if (i > 0) const Divider(height: 1, color: C.line),
          l,
        ],
      ],
    ),
  );
}
