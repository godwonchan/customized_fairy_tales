import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import 'story_result_screen.dart';

// ===== 공통 라벤더 팔레트 =====
const _kBg = Color(0xFFF8F4FF);
const _kPrimary = Color(0xFF7E57C2);
const _kPrimaryLight = Color(0xFF9575CD);
const _kPill = Color(0xFFEDE7F6);
const _kInk = Color(0xFF3D2C8D);
const _kSub = Color(0xFF8B82A8);

class _DrawingPath {
  final Color color;
  final double strokeWidth;
  final List<Offset> points;

  _DrawingPath({
    required this.color,
    required this.strokeWidth,
    required this.points,
  });
}

class _DrawingPainter extends CustomPainter {
  final List<_DrawingPath> paths;

  _DrawingPainter(this.paths);

  @override
  void paint(Canvas canvas, Size size) {
    for (final path in paths) {
      if (path.points.isEmpty) continue;
      final paint = Paint()
        ..color = path.color
        ..strokeWidth = path.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, paint);
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter old) => true;
}

class DrawingGuideScreen extends StatefulWidget {
  final String character;
  final String background;

  const DrawingGuideScreen({
    super.key,
    required this.character,
    required this.background,
  });

  @override
  State<DrawingGuideScreen> createState() => _DrawingGuideScreenState();
}

class _DrawingGuideScreenState extends State<DrawingGuideScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _canvasKey = GlobalKey();

  final List<_DrawingPath> _paths = [];
  _DrawingPath? _currentPath;

  Color _selectedColor = const Color(0xFF3D2C8D);
  double _strokeWidth = 6.0;
  bool _isEraser = false;

  bool _isLoadingGuide = true;
  String _guideText = '';
  List<String> _guideSteps = [];
  String? _guideError;
  bool _isSubmitting = false;

  late AnimationController _loadingController;

  final List<Color> _palette = [
    const Color(0xFF3D2C8D),
    const Color(0xFFE53935),
    const Color(0xFFFF8F00),
    const Color(0xFFFFD600),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFF8E24AA),
    const Color(0xFFEC407A),
    const Color(0xFF6D4C41),
    Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadDrawingGuide();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  Future<void> _loadDrawingGuide() async {
    setState(() {
      _isLoadingGuide = true;
      _guideError = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/stories/drawing-guide'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'character': widget.character,
          'background': widget.background,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _guideText = data['description'] ?? '';
          _guideSteps = List<String>.from(data['steps'] ?? []);
          _isLoadingGuide = false;
        });
      } else {
        setState(() {
          _guideError = '가이드를 불러오지 못했어요.';
          _isLoadingGuide = false;
        });
      }
    } catch (e) {
      setState(() {
        _guideError = '서버 연결 실패: $e';
        _isLoadingGuide = false;
      });
    }
  }

  Future<void> _submitDrawing() async {
    if (_paths.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('그림을 먼저 그려주세요! ✏️')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final boundary =
          _canvasKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();
      final base64Image = base64Encode(pngBytes);
      if (!mounted) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, animation, __) => StoryResultScreen(
            character: widget.character,
            background: widget.background,
            drawingBase64: base64Image,
          ),
          transitionsBuilder: (_, animation, __, child) => SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: FadeTransition(opacity: animation, child: child),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _clearCanvas() => setState(() {
    _paths.clear();
    _currentPath = null;
  });
  void _undo() {
    if (_paths.isNotEmpty) setState(() => _paths.removeLast());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // 장식 버블
          Positioned(
            top: -50,
            right: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kPrimaryLight.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEC407A).withOpacity(0.05),
              ),
            ),
          ),
          // 메인 콘텐츠
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 280, child: _buildGuidePanel()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildDrawingPanel()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _kPrimaryLight.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                      color: _kPrimary.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: _kPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '그림 그리기',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
                Text(
                  '${widget.character} · ${widget.background}',
                  style: const TextStyle(fontSize: 11, color: _kSub),
                ),
              ],
            ),
          ),
          _miniStep(1, '입력', false),
          _stepConnector(true),
          _miniStep(2, '그리기', true),
          _stepConnector(false),
          _miniStep(3, '완성', false),
        ],
      ),
    );
  }

  Widget _miniStep(int num, String label, bool active) => Column(
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active
              ? const LinearGradient(colors: [_kPrimaryLight, _kPrimary])
              : null,
          color: active ? null : _kPill,
          boxShadow: active
              ? [BoxShadow(color: _kPrimary.withOpacity(0.4), blurRadius: 8)]
              : null,
        ),
        child: Center(
          child: Text(
            '$num',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : _kSub,
            ),
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: active ? _kPrimary : _kSub,
        ),
      ),
    ],
  );

  Widget _stepConnector(bool active) => Container(
    width: 20,
    height: 2,
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: active ? _kPrimary : _kPill,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _buildGuidePanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kPrimaryLight, _kPrimary]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_fix_high_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI 그리기 가이드',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!_isLoadingGuide && _guideError == null)
                  GestureDetector(
                    onTap: _loadDrawingGuide,
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Wrap(
              spacing: 6,
              children: [
                _tag(widget.character, _kPrimary),
                _tag(widget.background, const Color(0xFF5B8DEF)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoadingGuide
                ? _buildLoadingGuide()
                : _guideError != null
                ? _buildGuideError()
                : _buildGuideContent(),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );

  Widget _buildLoadingGuide() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_kPrimary),
          strokeWidth: 3,
        ),
        const SizedBox(height: 16),
        const Text(
          'AI가 그리기 가이드를\n만들고 있어요 ✨',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _kSub,
            height: 1.6,
          ),
        ),
      ],
    ),
  );

  Widget _buildGuideError() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('😢', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text(
          _guideError!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: _kSub, height: 1.5),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _loadDrawingGuide,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kPrimaryLight, _kPrimary]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.35),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Text(
              '다시 시도',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildGuideContent() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_guideText.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kPrimaryLight.withOpacity(0.3)),
            ),
            child: Text(
              _guideText,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4A4466),
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          '단계별 그리기',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _kPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          _guideSteps.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kPrimaryLight, _kPrimary],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kPrimary.withOpacity(0.3),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _guideSteps[i],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4A4466),
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildDrawingPanel() {
    return Column(
      children: [
        _buildToolbar(),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: RepaintBoundary(
                key: _canvasKey,
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _currentPath = _DrawingPath(
                        color: _isEraser ? Colors.white : _selectedColor,
                        strokeWidth: _isEraser
                            ? _strokeWidth * 3
                            : _strokeWidth,
                        points: [details.localPosition],
                      );
                      _paths.add(_currentPath!);
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _currentPath?.points.add(details.localPosition);
                    });
                  },
                  onPanEnd: (_) => _currentPath = null,
                  child: CustomPaint(
                    painter: _DrawingPainter(_paths),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.07),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          ..._palette.map((color) {
            final isSelected = !_isEraser && _selectedColor == color;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedColor = color;
                _isEraser = false;
              }),
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? _kPrimary
                        : const Color(0xFFD9D0EC),
                    width: isSelected ? 2.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _kPrimary.withOpacity(0.4),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }),
          const SizedBox(width: 6),
          const Icon(
            Icons.line_weight_rounded,
            size: 16,
            color: _kSub,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: _kPrimary,
                inactiveTrackColor: _kPill,
                thumbColor: _kPrimary,
                overlayColor: _kPrimary.withOpacity(0.15),
              ),
              child: Slider(
                value: _strokeWidth,
                min: 2,
                max: 20,
                onChanged: (v) => setState(() => _strokeWidth = v),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isEraser = !_isEraser),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _isEraser ? _kPrimary : _kPill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.auto_fix_normal_rounded,
                size: 18,
                color: _isEraser ? Colors.white : _kPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _undo,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _kPill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.undo_rounded,
                size: 18,
                color: _kPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _clearCanvas,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Color(0xFFE5689B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() => GestureDetector(
    onTap: _isSubmitting ? null : _submitDrawing,
    child: Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPrimaryLight, _kPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: _isSubmitting
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '동화 만드는 중...',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_stories_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'AI로 동화 완성하기!',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
      ),
    ),
  );
}
