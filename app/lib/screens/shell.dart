/// 아래 탭. 홈, 추천, 기록, 설정. 작업 005 설계 8절
/// 막대와 그림은 작업 011 설계 3절이다. 고른 탭은 코발트로 채운 그림, 안 고른 탭은 회색 선이다
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'home.dart';
import 'records.dart';
import 'recommend.dart';
import 'settings.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.api});
  final Api api;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    // 탭을 바꿀 때마다 새로 그려 다른 탭에서 바뀐 결제와 카드를 반영한다
    body: switch (_tab) {
      0 => HomeScreen(api: widget.api),
      1 => RecommendScreen(api: widget.api),
      2 => RecordsScreen(api: widget.api),
      _ => SettingsScreen(api: widget.api),
    },
    bottomNavigationBar: Tabs(
      selected: _tab,
      onSelect: (i) => setState(() => _tab = i),
    ),
  );
}

enum TabKind { home, recommend, records, settings }

const _labels = ['홈', '추천', '기록', '설정'];

/// 흰 바탕에 위쪽 가는 선. 칸마다 누를 자리는 높이 56 이상이다
class Tabs extends StatelessWidget {
  const Tabs({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: C.line)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          for (final kind in TabKind.values)
            Expanded(child: _tile(kind, kind.index == selected)),
        ],
      ),
    ),
  );

  Widget _tile(TabKind kind, bool on) {
    final color = on ? C.blue : C.faint;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: on,
        child: InkResponse(
          onTap: () => onSelect(kind.index),
          highlightShape: BoxShape.rectangle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TabIcon(kind, filled: on, color: color),
                const SizedBox(height: 4),
                Text(
                  _labels[kind.index],
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 탭 그림. 24 칸에 선 굵기 1.8로 그리고 채움일 때는 안의 선을 바탕색으로 판다. 같은 그림이 design/tab-icons.svg에 있다
class TabIcon extends StatelessWidget {
  const TabIcon(
    this.kind, {
    super.key,
    required this.filled,
    required this.color,
  });
  final TabKind kind;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size.square(26),
      painter: _TabPainter(kind, filled, color),
    ),
  );
}

class _TabPainter extends CustomPainter {
  _TabPainter(this.kind, this.filled, this.color);
  final TabKind kind;
  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final ink = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // 채운 그림 위에 바탕색으로 긋는 선. 안 채운 그림은 같은 색 선이다
    final line = Paint()
      ..color = filled ? Colors.white : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    switch (kind) {
      case TabKind.home:
        canvas.drawPath(_house, ink);
      case TabKind.recommend:
        canvas.drawRRect(_card, ink);
        canvas.drawLine(const Offset(3, 10.6), const Offset(17, 10.6), line);
        canvas.drawPath(_star, ink);
      case TabKind.records:
        canvas.drawPath(_receipt, ink);
        for (final (y, end) in [(8.5, 15.0), (12.0, 15.0), (15.5, 12.5)]) {
          canvas.drawLine(Offset(9, y), Offset(end, y), line);
        }
      case TabKind.settings:
        canvas.drawPath(_gear, ink);
        canvas.drawCircle(
          const Offset(12, 12),
          2.6,
          filled ? (Paint()..color = Colors.white) : line,
        );
    }
  }

  @override
  bool shouldRepaint(_TabPainter old) =>
      old.kind != kind || old.filled != filled || old.color != color;
}

final _house = Path()
  ..moveTo(4, 11.2)
  ..lineTo(12, 4.5)
  ..lineTo(20, 11.2)
  ..lineTo(20, 19)
  ..arcToPoint(const Offset(18.5, 20.5), radius: const Radius.circular(1.5))
  ..lineTo(14.8, 20.5)
  ..lineTo(14.8, 15.3)
  ..lineTo(9.2, 15.3)
  ..lineTo(9.2, 20.5)
  ..lineTo(5.5, 20.5)
  ..arcToPoint(const Offset(4, 19), radius: const Radius.circular(1.5))
  ..close();

final _card = RRect.fromLTRBR(3, 7, 17, 18, const Radius.circular(2));

final _star = Path()
  ..addPolygon(const [
    Offset(18.3, 3.2),
    Offset(19.35, 5.35),
    Offset(21.7, 5.7),
    Offset(20, 7.35),
    Offset(20.4, 9.7),
    Offset(18.3, 8.6),
    Offset(16.2, 9.7),
    Offset(16.6, 7.35),
    Offset(14.9, 5.7),
    Offset(17.25, 5.35),
  ], true);

final _receipt = Path()
  ..moveTo(6.5, 3.5)
  ..lineTo(17.5, 3.5)
  ..arcToPoint(const Offset(18.5, 4.5), radius: const Radius.circular(1))
  ..lineTo(18.5, 20.5)
  ..lineTo(16.4, 19.1)
  ..lineTo(14.3, 20.5)
  ..lineTo(12, 19.1)
  ..lineTo(9.7, 20.5)
  ..lineTo(7.6, 19.1)
  ..lineTo(5.5, 20.5)
  ..lineTo(5.5, 4.5)
  ..arcToPoint(const Offset(6.5, 3.5), radius: const Radius.circular(1))
  ..close();

/// 톱니 8개. 바깥 반지름 8.5, 안쪽 6.6. 한 바퀴를 32칸으로 나눠 네 칸마다 두 칸이 톱니다
final _gear = Path()
  ..addPolygon([
    for (var i = 0; i < 32; i++)
      Offset(
        12 +
            (i % 4 == 1 || i % 4 == 2 ? 8.5 : 6.6) * math.cos(i * math.pi / 16),
        12 +
            (i % 4 == 1 || i % 4 == 2 ? 8.5 : 6.6) * math.sin(i * math.pi / 16),
      ),
  ], true);
