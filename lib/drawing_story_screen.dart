import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
<<<<<<< Updated upstream
import 'show.dart';
=======
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

// ═══════════════════════════════════════════════════════════════
//  OpenAI API 키
// ═══════════════════════════════════════════════════════════════

const String kOpenAiApiKeyDrawing =
    'YOUR_OPENAI_API_KEY';
>>>>>>> Stashed changes

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
    const Color(0xFFE53935),
    const Color(0xFFFF8F00),
    const Color(0xFFFFD600),
    const Color(0xFF43A047),
    const Color(0xFF1E88E5),
    const Color(0xFF8E24AA),
    const Color(0xFFEC407A),
    const Color(0xFF795548),
    const Color(0xFF546E7A),
    const Color(0xFF80DEEA),
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

  // ── 캔버스 → base64 변환 ──
  Future<String?> _captureCanvasAsBase64() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return base64Encode(byteData.buffer.asUint8List());
    } catch (e) {
      debugPrint('캔버스 캡처 에러: $e');
      return null;
    }
  }

  // ── AI 분석 (실제 GPT-4o Vision) ──
  void _analyzeDrawing() async {
    if (_paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 그림을 그려주세요!'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _isAnalyzed = false;
      _aiDescription = '';
      _aiKeywords = [];
      _selectedKeywords = [];
    });

    try {
      // 1. 캔버스 캡처
      final base64Image = await _captureCanvasAsBase64();
      if (base64Image == null) throw Exception('캔버스 캡처 실패');

      // 2. GPT-4o Vision API 호출
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $kOpenAiApiKeyDrawing',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-4o',
              'max_tokens': 300,
              'messages': [
                {
                  'role': 'system',
                  'content': '''
너는 어린이 그림책 전문가야. 사용자가 그린 낙서/스케치를 보고 아래 형식으로만 답해줘.
 
형식:
설명: (그림에 보이는 요소들을 한국어 명사로 쉼표 구분, 예: 집, 나무, 고양이, 해, 구름)
키워드: (이 그림으로 만들 수 있는 동화 키워드 5개를 쉼표로 구분, 예: 마법의 집, 용감한 고양이, 비밀의 숲, 새로운 친구, 신나는 모험)
 
반드시 설명과 키워드만 출력해. 다른 말은 하지 마.
''',
                },
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': '이 그림을 분석해서 설명과 키워드를 알려줘.'},
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/png;base64,$base64Image',
                        
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('API 응답: ${response.statusCode} - ${response.body}');
      if (response.statusCode != 200) {
        throw Exception('API 오류 (${response.statusCode}): ${response.body}');
      }

      // 3. 응답 파싱
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'] as String;

      String description = '';
      List<String> keywords = [];

      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('설명:')) {
          description = trimmed.replaceFirst('설명:', '').trim();
        } else if (trimmed.startsWith('키워드:')) {
          final keywordStr = trimmed.replaceFirst('키워드:', '').trim();
          keywords = keywordStr
              .split(',')
              .map((k) => k.trim())
              .where((k) => k.isNotEmpty)
              .toList();
        }
      }

      setState(() {
        _isAnalyzing = false;
        _isAnalyzed = true;
        _aiDescription = description.isNotEmpty ? description : '그림을 분석했어요!';
        _aiKeywords = keywords.isNotEmpty
            ? keywords
            : ['동화', '모험', '마법', '친구', '용기'];
        _selectedKeywords = [];
      });

      _animController.forward(from: 0);
    } catch (e) {
      debugPrint('AI 분석 에러: $e');
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('분석 실패: $e'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
    }
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
              child: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
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
      padding: EdgeInsets.fromLTRB(
        isTablet ? 32 : 16,
        16,
        isTablet ? 32 : 16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '05 그림으로 동화 만들기 – 그림 업로드/그리기',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Color(0xFF7E57C2),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '그림으로 동화 만들기',
                style: TextStyle(
                  fontSize: isTablet ? 22 : 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D2C8D),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Expanded(flex: 4, child: _buildAIPanel()),
        ],
      ),
    );
  }

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

  Widget _buildTabBar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF7E57C2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '내가 그린 그림',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('업로드 기능은 준비 중이에요!'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
              ],
            ),
            child: Text(
              '그림 업로드',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _clearCanvas,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.refresh, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '지우개',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _undo,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
              ],
            ),
            child: Icon(Icons.undo, size: 18, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
            ],
          ),
          child: Icon(Icons.redo, size: 18, color: Colors.grey[300]),
        ),
      ],
    );
  }

  Widget _buildCanvas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
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
            if (_paths.isEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.brush, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text(
                      '여기에 그림을 그려보세요!',
                      style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        _toolButton(
          Icons.edit,
          '펜',
          !_isEraser,
          () => setState(() => _isEraser = false),
        ),
        const SizedBox(width: 8),
        _toolButton(
          Icons.auto_fix_high,
          '지우개',
          _isEraser,
          () => setState(() => _isEraser = true),
        ),
        const SizedBox(width: 8),
        _toolButton(Icons.text_fields, '텍스트', false, () {}),
        const SizedBox(width: 8),
        _toolButton(Icons.search, '돋보기', false, () {}),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '굵기',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
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
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF7E57C2)
                          : Colors.grey[300]!,
                      width: isSelected ? 2.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toolButton(
    IconData icon,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7E57C2) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
          ],
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? Colors.white : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildAIPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Color(0xFF7E57C2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI가 이해한 내용',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3D2C8D),
                ),
              ),
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
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        color: Color(0xFF7E57C2),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Text(
                    _isAnalyzed ? _aiDescription : '그림을 그리고 분석 버튼을 눌러주세요',
                    style: TextStyle(
                      fontSize: 13,
                      color: _isAnalyzed
                          ? const Color(0xFF3D2C8D)
                          : Colors.grey[400],
                      height: 1.5,
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          const Text(
            '이 그림으로 만들 이야기 키워드 (선택)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D2C8D),
            ),
          ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF7E57C2)
                            : const Color(0xFFF8F4FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7E57C2)
                              : const Color(0xFFD1C4E9),
                        ),
                      ),
                      child: Text(
                        keyword,
                        style: TextStyle(
                          fontSize: 13,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF7E57C2),
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
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
          if (!_isAnalyzed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _analyzeDrawing,
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_isAnalyzing ? 'AI 분석 중...' : 'AI로 그림 분석하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('이야기 만들기 페이지로 이동!'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      '이 그림으로 이야기 만들기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
