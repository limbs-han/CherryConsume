/// 화면들이 함께 쓰는 부품. 작업 011 설계 1절의 원칙과 4절
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';
import 'theme.dart';

/// 스크롤되는 내용 아래에 주요 버튼 하나를 고정한다. 키보드가 뜨면 Scaffold가 몸통을 줄여 버튼이 키보드 위로 오고,
/// 키보드가 없으면 아래 막대 위에 놓인다. 원칙 1, 설계 2절 Z2
class WithAction extends StatelessWidget {
  const WithAction({
    super.key,
    required this.children,
    required this.action,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });
  final List<Widget> children;
  final Widget action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(padding: padding, children: children),
      ),
      SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: Pressable(child: action),
        ),
      ),
    ],
  );
}

/// 뒤로 가기가 없는 탭 화면의 제목은 시안대로 24에서 시작한다. 뒤로 가기가 있으면 테마의 간격을 쓴다. 작업 011 설계 2절 G5
double? rootTitleSpacing(BuildContext context) =>
    ModalRoute.of(context)?.impliesAppBarDismissal ?? false ? null : 24;

/// 누르는 동안 0.96배로 작아졌다가 돌아온다. onTap이 없으면 안의 버튼이 누름을 받는다. 원칙 4
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final scaled = AnimatedScale(
      scale: _down ? 0.96 : 1,
      duration: const Duration(milliseconds: 100),
      child: widget.child,
    );
    if (widget.onTap == null) {
      return Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: scaled,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: scaled,
    );
  }
}

/// 완전히 둥근 고르기 칩. 고르면 진한 남색 바탕에 흰 글자다. 누르면 짧게 떤다. 설계 2절 G2
class ChoicePill extends StatelessWidget {
  const ChoicePill(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? C.text : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: C.line),
        ),
        // 가운데에 두되 폭은 글자만큼이다. 폭이 정해진 줄에서 늘어나지 않는다
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : C.sub,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 가로로 미는 칩 줄. 화면 좌우 20 안에서만 보이고 밀려 뒤로 가기 손짓 자리와 겹치지 않는다. 설계 2절 Z4
/// 이미 좌우 20 여백 안에 놓이면 inset을 0으로 준다
class PillRow extends StatelessWidget {
  const PillRow({super.key, required this.children, this.inset = 20});
  final List<Widget> children;
  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: inset),
    // 스크롤 영역이 제 크기로 잘라 여백 밖으로 칩이 보이지 않는다
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            c,
          ],
        ],
      ),
    ),
  );
}

/// 아래에서 올라오는 시트에서 큰 줄로 하나를 고른다. 시트는 상태 표시줄 아래에서 멈춘다. 원칙 5, 설계 2절 Z1
Future<T?> pickSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  T? selected,
}) => showModalBottomSheet<T>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final (value, label) in options)
                _SheetRow(
                  label: label,
                  selected: value == selected,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, value);
                  },
                ),
            ],
          ),
        ),
      ],
    ),
  ),
);

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? C.blueSoft : null,
          borderRadius: r16,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? C.blue : C.text,
                ),
              ),
            ),
            if (selected) const Icon(Icons.check, color: C.blue),
          ],
        ),
      ),
    ),
  );
}

/// "1,234,000"에서 1234000. 비면 null
int? amountOf(String text) => int.tryParse(text.replaceAll(',', ''));

/// 숫자만 받아 세 자리마다 쉼표를 넣는다. 자릿수가 차면 더 받지 않는다
class ThousandsFormatter extends TextInputFormatter {
  ThousandsFormatter(this.maxDigits);
  final int maxDigits;

  static final _notDigit = RegExp(r'[^0-9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(_notDigit, '');
    // 뒤를 잘라 받으면 가운데에 친 숫자가 다른 금액을 만든다. 작업 011 위험 검토 3번
    if (digits.length > maxDigits) return oldValue;
    final n = int.tryParse(digits);
    final text = n == null ? '' : comma(n);
    // 커서 앞 숫자 수를 지켜 가운데를 고쳐도 커서가 그 자리에 남는다. 끝으로 보내면 12,500의 2를 3으로 고칠 때
    // 15,003이 된다. 위험 검토 2번. 지워진 앞자리 0만큼 줄인다
    final end = newValue.selection.isValid
        ? newValue.selection.end
        : newValue.text.length;
    final zeros = digits.length - (n?.toString().length ?? 0);
    final before =
        newValue.text.substring(0, end).replaceAll(_notDigit, '').length -
        zeros;
    var offset = 0;
    for (var seen = 0; offset < text.length && seen < before; offset++) {
      if (text[offset] != ',') seen++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// 크게 쓰는 금액 칸. 밑줄은 고른 동안 2px 코발트다. 쉼표를 넣고 숫자 키보드를 연다. 원칙 6
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.onChanged,
    this.size = 28,
    this.autofocus = false,
    this.hint,
    this.maxDigits = 10,
  });
  final TextEditingController controller;
  final ValueChanged<int?>? onChanged;
  final double size;
  final bool autofocus;
  final String? hint;

  /// 받는 자릿수. 10자리면 99억 원까지다
  final int maxDigits;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [ThousandsFormatter(maxDigits)],
    onChanged: (t) => onChanged?.call(amountOf(t)),
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      color: C.text,
    ),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: size, color: C.line),
      suffixText: '원',
      suffixStyle: TextStyle(
        fontSize: size / 2,
        fontWeight: FontWeight.w700,
        color: C.sub,
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: C.line),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: C.blue, width: 2),
      ),
    ),
  );
}

/// 금액이나 비율이 바뀌면 0.6초 동안 새 값까지 간다. 처음에는 0에서 올라간다. 애니메이션 줄이기 설정이면 바로 바뀐다.
/// 화면에 보이는 값만 움직이고 계산하는 값은 늘 정수 그대로다. 원칙 3
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, required this.builder});
  final int value;
  final Widget Function(int) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 600),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => builder(v.round()),
  );
}

/// 카드사 색. 카드 그림 대신 쓴다. 설계 문서 3절의 저작권 결정, 작업 011 설계 2절 H4, A1
const issuerColors = {
  'shinhan': Color(0xFF2E3F8F),
  'samsung': Color(0xFF1D3C8F),
  'hyundai': Color(0xFF1E1E1E),
  'kb': Color(0xFF7A6A4F),
  'lotte': Color(0xFFC8102E),
  'hana': Color(0xFF00857C),
  'woori': Color(0xFF0A6EBD),
  'nh': Color(0xFF1B8A4B),
  'ibk': Color(0xFF1F5FAD),
  'kakaobank': Color(0xFF3C3C3C),
};

/// 카드사 색으로 칠한 작은 카드 모양
class IssuerSwatch extends StatelessWidget {
  const IssuerSwatch(this.issuer, {super.key});
  final String? issuer;

  @override
  Widget build(BuildContext context) {
    final c = issuerColors[issuer] ?? C.faint;
    return Container(
      width: 44,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: r8,
        gradient: LinearGradient(
          colors: [c, Color.lerp(c, Colors.white, 0.25)!],
        ),
      ),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.fromLTRB(6, 9, 0, 0),
      child: Container(
        width: 10,
        height: 7,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 점선 테두리 상자. 빈 홈의 혜택 띠와 카드 추가 버튼이다. 작업 011 설계 2절 H2, H6
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    this.color,
    this.borderColor = const Color(0xFFC9D0DB),
    this.radius = 16,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final Color? color;
  final Color borderColor;
  final double radius;
  final EdgeInsets padding;

  @override
  // 바탕색이 점선을 덮지 않게 점선을 위에 그린다
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _Dashes(borderColor, radius),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    ),
  );
}

class _Dashes extends CustomPainter {
  _Dashes(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final border = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(radius),
        ),
      );
    for (final m in border.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color || old.radius != radius;
}

/// 줄 오른쪽의 값. 길면 줄여서 이름 칸을 남긴다
class RowValue extends StatelessWidget {
  const RowValue(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 160),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: const TextStyle(fontSize: 15, color: C.sub),
    ),
  );
}

/// 이름, 설명, 오른쪽 값, 화살표 한 줄. 누를 곳이 없으면 화살표를 두지 않는다. 설정과 카드 상세가 쓴다. 작업 011 설계 2절 S1, T3
class TapRow extends StatelessWidget {
  const TapRow({
    super.key,
    required this.title,
    this.sub,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: C.text,
                  ),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub!,
                      style: const TextStyle(fontSize: 13, color: C.sub),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          if (onTap != null) const Icon(Icons.chevron_right, color: C.faint),
        ],
      ),
    );
    if (onTap == null) return line;
    return Semantics(
      button: true,
      child: Pressable(onTap: onTap, child: line),
    );
  }
}
