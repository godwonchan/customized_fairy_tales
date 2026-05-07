import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════════
//  그림으로 동화 만들기 화면
// ═══════════════════════════════════════════════════════════════

class DrawingStoryScreen extends StatefulWidget {
  const DrawingStoryScreen({super.key});

  @override
  State<DrawingStoryScreen> createState() => _DrawingStoryScreenState();
}

class _DrawingStoryScreenState extends State<DrawingStoryScreen>
    with SingleTickerProviderStateMixin {
  // ── 그림판 관련 ──
  final List<DrawingPath> _paths = [];
  DrawingPath? _currentPath;
  Color _selectedColor = Colors.black;
  double _strokeWidth = 4.0;
  bool _isEraser = false;
  final GlobalKey _canvasKey = GlobalKey();

  // ── AI 분석 관련 ──
  bool _isAnalyzing = false;
  bool _isAnalyzed = false;
  List<String> _aiKeywords = [];
  String _aiDescription = '';
  List<String> _selectedKeywords = [];

  // ── 애니메이션 ──
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final List<Color> _colorPalette = [
    Colors.black,
    Colors.white,
    const Color(0xFFE53935), // 빨강
    const Color(0xFFFF8F00), // 주황
    const Color(0xFFFFD600), // 노랑
    const Color(0xFF43A047), // 초록
    const Color(0xFF1E88E5), // 파랑
    const Color(0xFF8E24AA), // 보라
    const Color(0xFFEC407A), // 분홍
    const Color(0xFF795548), // 갈색
    const Color(0xFF546E7A), // 회색
    const Color(0xFF80DEEA), // 하늘
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── 그림 지우기 ──
  void _clearCanvas() {
    setState(() {
      _paths.clear();
      _isAnalyzed = false;
      _aiKeywords = [];
      _aiDescription = '';
      _selectedKeywords = [];
    });
  }

  // ── 실행 취소 ──
  void _undo() {
    if (_paths.isNotEmpty) {
      setState(() => _paths.removeLast());
    }
  }

  // ── AI 분석 (시뮬레이션) ──
  void _analyzeDrawing() async {
    if (_paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 그림을 그려주세요!'), duration: Duration(seconds: 1)),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    // AI 분석 시뮬레이션 (실제로는 API 연동)
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isAnalyzing = false;
      _isAnalyzed = true;
      _aiDescription = '성(성), 나무, 소녀, 꽃, 태양, 구름';
      _aiKeywords = ['마법의 성', '용감한 소녀', '비밀의 숲', '친구', '모험'];
      _selectedKeywords = [];
    });

    _animController.forward(from: 0);
  }

  // ── 키워드 선택 토글 ──
  void _toggleKeyword(String keyword) {
    setState(() {
      if (_selectedKeywords.contains(keyword)) {
        _selectedKeywords.remove(keyword);
      } else {
        _selectedKeywords.add(keyword);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: isTablet
                  ? _buildTabletLayout()
                  : _buildPhoneLayout(),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──
  Widget _buildHeader(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Padding(
      padding: EdgeInsets.fromLTRB(isTablet ? 32 : 16, 16, isTablet ? 32 : 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('05 그림으로 동화 만들기 – 그림 업로드/그리기',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.chevron_left, color: Color(0xFF7E57C2), size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Text('그림으로 동화 만들기',
                  style: TextStyle(
                    fontSize: isTablet ? 22 : 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3D2C8D),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  // ── 태블릿 레이아웃 (좌우 분할) ──
  Widget _buildTabletLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 왼쪽 — 그림판
          Expanded(
            flex: 6,
            child: Column(
              children: [
                _buildTabBar(),
                const SizedBox(height: 12),
                Expanded(child: _buildCanvas()),
                const SizedBox(height: 12),
                _buildToolbar(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // 오른쪽 — AI 분석
          Expanded(
            flex: 4,
            child: _buildAIPanel(),
          ),
        ],
      ),
    );
  }

  // ── 폰 레이아웃 (상하 분할) ──
  Widget _buildPhoneLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTabBar(),
          const SizedBox(height: 12),
          SizedBox(height: 320, child: _buildCanvas()),
          const SizedBox(height: 12),
          _buildToolbar(),
          const SizedBox(height: 20),
          _buildAIPanel(),
        ],
      ),
    );
  }

  // ── 탭 바 (내가 그린 그림 / 업로드) ──
  Widget _buildTabBar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF7E57C2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('내가 그린 그림',
              style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('업로드 기능은 준비 중이에요!'), duration: Duration(seconds: 1)),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
            ),
            child: Text('그림 업로드',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
        ),
        const Spacer(),
        // 지우기 버튼
        GestureDetector(
          onTap: _clearCanvas,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
            ),
            child: Row(
              children: [
                Icon(Icons.refresh, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('지우개', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 실행 취소
        GestureDetector(
          onTap: _undo,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
            ),
            child: Icon(Icons.undo, size: 18, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(width: 8),
        // 다시 실행
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
          ),
          child: Icon(Icons.redo, size: 18, color: Colors.grey[300]),
        ),
      ],
    );
  }

  // ── 그림판 캔버스 ──
  Widget _buildCanvas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 그림판 영역
            RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _currentPath = DrawingPath(
                      color: _isEraser ? Colors.white : _selectedColor,
                      strokeWidth: _isEraser ? 20 : _strokeWidth,
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
                onPanEnd: (_) {
                  _currentPath = null;
                },
                child: CustomPaint(
                  painter: DrawingPainter(_paths),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
            // 빈 상태 힌트
            if (_paths.isEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.brush, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text('여기에 그림을 그려보세요!',
                        style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 도구 모음 ──
  Widget _buildToolbar() {
    return Row(
      children: [
        // 도구 버튼들
        _toolButton(Icons.edit, '펜', !_isEraser, () => setState(() => _isEraser = false)),
        const SizedBox(width: 8),
        _toolButton(Icons.auto_fix_high, '지우개', _isEraser, () => setState(() => _isEraser = true)),
        const SizedBox(width: 8),
        _toolButton(Icons.text_fields, '텍스트', false, () {}),
        const SizedBox(width: 8),
        _toolButton(Icons.search, '돋보기', false, () {}),
        const SizedBox(width: 12),
        // 굵기 슬라이더
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('굵기', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Slider(
                value: _strokeWidth,
                min: 1,
                max: 20,
                activeColor: const Color(0xFF7E57C2),
                onChanged: (v) => setState(() => _strokeWidth = v),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // 색상 팔레트
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: _colorPalette.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final color = _colorPalette[index];
              final isSelected = _selectedColor == color && !_isEraser;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedColor = color;
                  _isEraser = false;
                }),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF7E57C2) : Colors.grey[300]!,
                      width: isSelected ? 2.5 : 1,
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toolButton(IconData icon, String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7E57C2) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
        ),
        child: Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.grey[600]),
      ),
    );
  }

  // ── AI 분석 패널 ──
  Widget _buildAIPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI가 이해한 내용
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7E57C2)),
              ),
              const SizedBox(width: 8),
              const Text('AI가 이해한 내용',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _isAnalyzing
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF7E57C2), strokeWidth: 2))
                : Text(
                    _isAnalyzed ? _aiDescription : '그림을 그리고 분석 버튼을 눌러주세요',
                    style: TextStyle(
                      fontSize: 13,
                      color: _isAnalyzed ? const Color(0xFF3D2C8D) : Colors.grey[400],
                      height: 1.5,
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // 키워드 선택
          const Text('이 그림으로 만들 이야기 키워드 (선택)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
          const SizedBox(height: 12),
          if (_isAnalyzed)
            FadeTransition(
              opacity: _fadeAnim,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _aiKeywords.map((keyword) {
                  final isSelected = _selectedKeywords.contains(keyword);
                  return GestureDetector(
                    onTap: () => _toggleKeyword(keyword),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFFF8F4FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFFD1C4E9),
                        ),
                      ),
                      child: Text(
                        keyword,
                        style: TextStyle(
                          fontSize: 13,
                          color: isSelected ? Colors.white : const Color(0xFF7E57C2),
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'AI 분석 후 키워드가 나타납니다',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 24),

          // 분석 버튼 또는 이야기 만들기 버튼
          if (!_isAnalyzed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _analyzeDrawing,
                icon: _isAnalyzing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_isAnalyzing ? 'AI 분석 중...' : 'AI로 그림 분석하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // 이야기 만들기 페이지로 이동
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('이야기 만들기 페이지로 이동!'), duration: Duration(seconds: 1)),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('이 그림으로 이야기 만들기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  그림 데이터 모델
// ═══════════════════════════════════════════════════════════════

class DrawingPath {
  final Color color;
  final double strokeWidth;
  final List<Offset> points;

  DrawingPath({
    required this.color,
    required this.strokeWidth,
    required this.points,
  });
}

// ═══════════════════════════════════════════════════════════════
//  커스텀 페인터
// ═══════════════════════════════════════════════════════════════

class DrawingPainter extends CustomPainter {
  final List<DrawingPath> paths;

  DrawingPainter(this.paths);

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
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}