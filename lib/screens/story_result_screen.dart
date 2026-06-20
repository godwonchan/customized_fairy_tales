import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class StoryResultScreen extends StatefulWidget {
  final String character;
  final String background;
  final String drawingBase64;

  const StoryResultScreen({
    super.key,
    required this.character,
    required this.background,
    required this.drawingBase64,
  });

  @override
  State<StoryResultScreen> createState() => _StoryResultScreenState();
}

class _StoryResultScreenState extends State<StoryResultScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;

  String _storyTitle = '';
  String _drawingDescription = '';
  List<String> _storyPages = [];
  List<String?> _pageImages = []; // 페이지별 AI 이미지 base64

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _pageController;
  late Animation<Offset> _pageSlide;
  late AnimationController _starController;
  late Animation<double> _starAnim;

  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _pageController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _pageSlide = Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _pageController, curve: Curves.easeOutCubic));

    _starController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _starAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _starController, curve: Curves.easeInOut));

    _generateStory();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    _starController.dispose();
    super.dispose();
  }

  Future<void> _generateStory() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:8000/stories/generate-from-drawing'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'character': widget.character,
          'background': widget.background,
          'drawing_base64': widget.drawingBase64,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _storyTitle = data['title'] ?? '나만의 동화';
          _drawingDescription = data['drawing_description'] ?? '';
          _storyPages = List<String>.from(data['pages'] ?? []);
          _pageImages = List<String?>.from(data['page_images'] ?? []);
          _isLoading = false;
        });
        _fadeController.forward();
        _pageController.forward();
      } else {
        setState(() { _error = '동화 생성에 실패했어요. 다시 시도해주세요.'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = '서버 연결 실패: $e'; _isLoading = false; });
    }
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _storyPages.length) return;
    _pageController.reset();
    setState(() => _currentPage = index);
    _pageController.forward();
  }

  void _saveStory() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('동화가 저장되었어요! 📚'),
        backgroundColor: const Color(0xFF7E57C2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 배경
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A0050), Color(0xFF2D1B69), Color(0xFF1A237E), Color(0xFF283593)],
                stops: [0.0, 0.35, 0.65, 1.0],
              ),
            ),
          ),
          Positioned(top: -50, right: -30,
            child: Container(width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: const Color(0xFF7C4DFF).withOpacity(0.1)))),
          Positioned(bottom: 60, left: -40,
            child: Container(width: 150, height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: const Color(0xFF1565C0).withOpacity(0.12)))),
          // 별 장식
          Positioned(top: 90, right: 60,
            child: AnimatedBuilder(animation: _starAnim,
              builder: (_, __) => Opacity(opacity: _starAnim.value * 0.6,
                child: const Text('⭐', style: TextStyle(fontSize: 16))))),
          Positioned(top: 180, left: 40,
            child: AnimatedBuilder(animation: _starAnim,
              builder: (_, __) => Opacity(opacity: (1 - _starAnim.value) * 0.6 + 0.3,
                child: const Text('✨', style: TextStyle(fontSize: 14))))),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading ? _buildLoadingState()
                      : _error != null ? _buildErrorState()
                      : _buildStoryContent(),
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
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withOpacity(0.25)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('나의 동화 완성!',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('AI가 내 그림으로 동화를 만들었어요 🎉',
                    style: TextStyle(fontSize: 11, color: Colors.white60)),
              ],
            ),
          ),
          _miniStep(1, '입력', false),
          _stepConnector(true),
          _miniStep(2, '그리기', false),
          _stepConnector(true),
          _miniStep(3, '완성', true),
          const SizedBox(width: 12),
          if (!_isLoading && _error == null)
            GestureDetector(
              onTap: _saveStory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFE57F), Color(0xFFFFAB00)]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: const Color(0xFFFFAB00).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bookmark_add_rounded, color: Color(0xFF4A148C), size: 16),
                    SizedBox(width: 4),
                    Text('저장하기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF4A148C))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniStep(int num, String label, bool active) => Column(
    children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active ? const LinearGradient(colors: [Color(0xFFFFE57F), Color(0xFFFFAB00)]) : null,
          color: active ? null : Colors.white.withOpacity(0.15),
          boxShadow: active ? [BoxShadow(color: const Color(0xFFFFAB00).withOpacity(0.5), blurRadius: 8)] : null,
        ),
        child: Center(child: Text('$num', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
            color: active ? const Color(0xFF4A148C) : Colors.white.withOpacity(0.5)))),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
          color: active ? const Color(0xFFFFD54F) : Colors.white.withOpacity(0.4))),
    ],
  );

  Widget _stepConnector(bool active) => Container(
    width: 20, height: 2, margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      gradient: active ? const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFFAB00)]) : null,
      color: active ? null : Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFE57F), Color(0xFFFFAB00)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFFFFAB00).withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF4A148C), size: 48),
          ),
          const SizedBox(height: 24),
          const Text('AI가 동화를 만들고 있어요!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 10),
          Text('내 그림을 분석하고\n5페이지 동화 + AI 삽화를 그리는 중이에요 ✨',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7), height: 1.6)),
          const SizedBox(height: 6),
          Text('(약 1~2분 소요될 수 있어요)',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.45))),
          const SizedBox(height: 30),
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD54F)),
            strokeWidth: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😢', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7), height: 1.6)),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _generateStory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFE57F), Color(0xFFFFAB00)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: const Color(0xFFFFAB00).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: const Text('다시 만들기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF4A148C))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryContent() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 왼쪽: 내가 그린 그림 + AI 해석
            SizedBox(width: 280, child: _buildDrawingPanel()),
            const SizedBox(width: 16),
            // 오른쪽: 동화 내용 + AI 삽화
            Expanded(child: _buildStoryPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawingPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF26A69A), Color(0xFF00796B)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: const Row(
              children: [
                Icon(Icons.brush_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('내가 그린 그림',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: Image.memory(
                base64Decode(widget.drawingBase64),
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          ),
          if (_drawingDescription.isNotEmpty) ...[
            Container(height: 1, color: Colors.white.withOpacity(0.15)),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text('✨', style: TextStyle(fontSize: 13)),
                        SizedBox(width: 4),
                        Text('AI의 그림 해석',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFFD54F))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(_drawingDescription,
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85), height: 1.55)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoryPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 동화 제목 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7E57C2), Color(0xFF512DA8)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_stories_rounded, color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text('${_currentPage + 1} / ${_storyPages.length} 페이지',
                        style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD54F).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.5)),
                      ),
                      child: const Row(
                        children: [
                          Text('⭐', style: TextStyle(fontSize: 11)),
                          SizedBox(width: 4),
                          Text('나만의 동화',
                              style: TextStyle(fontSize: 11, color: Color(0xFFFFD54F), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_storyTitle,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, height: 1.3)),
              ],
            ),
          ),
          // 동화 내용 + AI 삽화
          Expanded(
            child: SlideTransition(
              position: _pageSlide,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── 동화 텍스트 ───
                    Text(
                      _storyPages.isNotEmpty ? _storyPages[_currentPage] : '',
                      style: TextStyle(
                          fontSize: 16, color: Colors.white.withOpacity(0.9),
                          height: 1.9, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 20),
                    // ─── AI 삽화 ───
                    _buildPageAiImage(),
                  ],
                ),
              ),
            ),
          ),
          // 페이지 네비게이션
          _buildPageNav(),
        ],
      ),
    );
  }

  Widget _buildPageAiImage() {
    final hasImage = _pageImages.isNotEmpty &&
        _currentPage < _pageImages.length &&
        _pageImages[_currentPage] != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI 삽화 레이블
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFFFD54F).withOpacity(0.25), const Color(0xFFFFAB00).withOpacity(0.15)],
                ),
              ),
              child: const Row(
                children: [
                  Text('🎨', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text('AI가 그린 삽화',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFFFD54F))),
                ],
              ),
            ),
            // 이미지
            if (hasImage)
              Image.memory(
                base64Decode(_pageImages[_currentPage]!),
                width: double.infinity,
                fit: BoxFit.cover,
              )
            else
              Container(
                width: double.infinity,
                height: 180,
                color: Colors.white.withOpacity(0.05),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD54F)),
                      strokeWidth: 2,
                    ),
                    const SizedBox(height: 10),
                    Text('AI 삽화 준비 중...',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _currentPage > 0 ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16,
                  color: _currentPage > 0 ? Colors.white : Colors.white.withOpacity(0.2)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_storyPages.length, (i) {
                final isActive = i == _currentPage;
                return GestureDetector(
                  onTap: () => _goToPage(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isActive ? 24 : 8, height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? const LinearGradient(colors: [Color(0xFFFFE57F), Color(0xFFFFAB00)])
                          : null,
                      color: isActive ? null : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isActive
                          ? [BoxShadow(color: const Color(0xFFFFAB00).withOpacity(0.4), blurRadius: 6)]
                          : null,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _currentPage < _storyPages.length - 1 ? () => _goToPage(_currentPage + 1) : null,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: _currentPage < _storyPages.length - 1
                    ? const LinearGradient(colors: [Color(0xFFFFE57F), Color(0xFFFFAB00)])
                    : null,
                color: _currentPage < _storyPages.length - 1 ? null : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _currentPage < _storyPages.length - 1
                    ? [BoxShadow(color: const Color(0xFFFFAB00).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))]
                    : null,
              ),
              child: Icon(Icons.arrow_forward_ios_rounded, size: 16,
                  color: _currentPage < _storyPages.length - 1
                      ? const Color(0xFF4A148C) : Colors.white.withOpacity(0.2)),
            ),
          ),
        ],
      ),
    );
  }
}