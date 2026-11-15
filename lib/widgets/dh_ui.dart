// lib/widgets/dh_ui.dart
// 동화랑 공용 부품 (홈 '장난감 책장' 톤): 도톰한 바탕, 아이콘, 글꼴, 방 배경, 그림 종이
// 에셋 위치: assets/donghwarang/ (frames, icons, shared, home, controls, swatches, avatar/layers)
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const String _dh = 'assets/donghwarang';

/// 시안의 진한 고동색 글자
const Color dhBrown = Color(0xFF5A3A22);

/// 시안의 굵고 둥근 한글 글씨
TextStyle dhText(double size, {Color color = dhBrown, double height = 1.2}) =>
    GoogleFonts.jua(fontSize: size, color: color, height: height);

/// 홈 화면과 같은 장난감 느낌의 바탕: 둥근 모서리, 밝은 테두리, 아래로 도톰한 그림자.
/// 이름은 예전 종이 프레임 이름을 그대로 받는다 (button_yellow, button_cream, paper_panel …).
BoxDecoration dhFrame(String name, {double scale = 2}) {
  Color color = const Color(0xFFFFF0DA), edge = const Color(0xFFE3C79E), line = const Color(0xCCFFFFFF);
  double radius = 28, lineWidth = 3, depth = 5;
  switch (name) {
    case 'button_yellow':
      color = const Color(0xFFFFCB3D);
      edge = const Color(0xFFE3A520);
    case 'button_blue':
      color = const Color(0xFFC4E3F8);
      edge = const Color(0xFF8FBFE3);
    case 'button_disabled':
      color = const Color(0xFFF1E6D4);
      edge = const Color(0xFFDDD0BA);
    case 'title_swash':
      color = const Color(0xFFFFE48A);
      edge = const Color(0xFFE9BF45);
      radius = 34;
    case 'paper_panel' || 'tool_tray' || 'notebook':
      color = const Color(0xFFFFF7EA);
      radius = 34;
      depth = 6;
    case 'speech':
      color = const Color(0xFFFFF7EA);
      radius = 38;
    case 'gallery_slot':
      color = const Color(0xFFFFFDF6);
      line = const Color(0xFFEBCFA6);
      lineWidth = 2;
      radius = 20;
      depth = 3;
    case 'slot_selected':
      color = const Color(0xFFFFF6D6);
      line = const Color(0xFFFFCB3D);
      edge = const Color(0xFFE3A520);
      lineWidth = 4;
      radius = 20;
      depth = 3;
  }
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: line, width: lineWidth),
    boxShadow: [
      BoxShadow(color: edge, offset: Offset(0, depth)),
      BoxShadow(color: const Color(0x33A9794A), blurRadius: 8, offset: Offset(0, depth + 4)),
    ],
  );
}

String dhIconPath(String name) => '$_dh/icons/$name.png';
String dhShared(String name) => '$_dh/shared/$name.png';
String dhHome(String name) => '$_dh/home/$name.png';
String dhControl(String name) => '$_dh/controls/$name.png';
String dhSwatch(String name) => '$_dh/swatches/$name.png';
String dhLayer(String name) => '$_dh/avatar/layers/$name.png';
String dhFramePath(String name) => '$_dh/frames/$name.png';

/// 시안 아이콘 (PNG). 장식이면 그대로, 버튼이면 바깥에서 Semantics 를 붙인다.
class DhIcon extends StatelessWidget {
  final String name;
  final double size;
  final double opacity;
  const DhIcon(this.name, {super.key, this.size = 32, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      dhIconPath(name),
      width: size,
      height: size,
      fit: BoxFit.contain,
      opacity: opacity == 1 ? null : AlwaysStoppedAnimation(opacity),
    );
  }
}

/// 홈 화면과 같은 방 배경 (하늘색 벽 + 원목 탁자). 화면을 꽉 채운다.
class DhMeadow extends StatelessWidget {
  const DhMeadow({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/toy_shelf/backgrounds/background_room.png', fit: BoxFit.fill);
  }
}

/// 그림 그리는 종이: 하얀 종이 판에 도톰한 그림자
class DhNotebook extends StatelessWidget {
  final Widget child;
  final String frame;
  const DhNotebook({super.key, required this.child, this.frame = 'notebook'});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: dhFrame(frame).copyWith(color: const Color(0xFFFFFDF8)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 눌리는 느낌(살짝 내려가고 작아짐)을 주는 버튼 껍데기
class DhPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? label; // 한국어 접근성 이름
  const DhPressable({super.key, required this.child, this.onTap, this.label});

  @override
  State<DhPressable> createState() => _DhPressableState();
}

class _DhPressableState extends State<DhPressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
          child: AnimatedScale(scale: _down ? 0.97 : 1, duration: const Duration(milliseconds: 90), child: widget.child),
        ),
      ),
    );
    if (widget.label == null) return button;
    return Semantics(label: widget.label, button: true, enabled: widget.onTap != null, child: button);
  }
}

/// 시안(1586×992) 좌표로 화면을 짜는 판. 자식들은 시안 픽셀 좌표의 Positioned 로 놓는다.
/// 화면 비율이 시안과 거의 같으면 여백 없이 꽉 채우고, 많이 다르면 비율을 지킨다 (남는 곳은 뒤 배경이 보임).
class DhDesignCanvas extends StatelessWidget {
  static const Size design = Size(1586, 992);
  final List<Widget> children;
  const DhDesignCanvas({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final gap = (screen.width / screen.height) / (design.width / design.height);
    final nearlySame = gap > 0.95 && gap < 1.05;
    return Center(
      child: FittedBox(
        fit: nearlySame ? BoxFit.fill : BoxFit.contain,
        child: SizedBox(width: design.width, height: design.height, child: Stack(children: children)),
      ),
    );
  }
}

/// 시안 그림 위의 투명 버튼 (누르면 살짝 밝아짐). Stack 의 직접 자식으로 쓴다.
class DhHit extends StatelessWidget {
  final Rect rect;
  final String label;
  final VoidCallback? onTap;
  final double radius;
  const DhHit(this.rect, this.label, this.onTap, {super.key, this.radius = 40});

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        label: label,
        button: true,
        enabled: onTap != null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            splashColor: Colors.white.withValues(alpha: 0.35),
            highlightColor: Colors.white.withValues(alpha: 0.22),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// 시안 그림의 한 부분을 종이색으로 덮고 그 위에 실제 내용을 얹는다. Stack 의 직접 자식으로 쓴다.
class DhPatch extends StatelessWidget {
  final Rect rect;
  final Color color;
  final double radius;
  final Widget? child;
  final Alignment alignment;
  const DhPatch(this.rect, this.color, {super.key, this.child, this.radius = 14, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
        alignment: alignment,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
