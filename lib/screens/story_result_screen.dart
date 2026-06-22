import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

// ===== 공통 라벤더 팔레트 =====
const _kBg = Color(0xFFF8F4FF);
const _kPrimary = Color(0xFF7E57C2);
const _kPrimaryLight = Color(0xFF9575CD);
const _kPill = Color(0xFFEDE7F6);
const _kInk = Color(0xFF3D2C8D);
const _kSub = Color(0xFF8B82A8);
const _kInk2 = Color(0xFF4A4466);

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
  List<String?> _pageImages = [];

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _pageController;
  late Animation<Offset> _pageSlide;

  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _pageController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _pageSlide = Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _pageController, curve: Curves.easeOutCubic));

    _generateStory();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _generateStory() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/stories/generate-from-drawing'),
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
        backgroundColor: _kPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned(top: -50, right: -30,
            child: Container(width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: _kPrimaryLight.withOpacity(0.08)))),
          Positioned(bottom: 60, left: -40,
            child: Container(width: 150, height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: const Color(0xFFEC407A).withOpacity(0.05)))),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _kPrimaryLight.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(color: _kPrimary.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _kPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('나의 동화 완성!',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _kInk)),
                Text('AI가 내 그림으로 동화를 만들었어요 🎉',
                    style: TextStyle(fontSize: 11, color: _kSub)),
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
                  gradient: const LinearGradient(colors: [_kPrimaryLight, _kPrimary]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bookmark_add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('저장하기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
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
          gradient: active ? const LinearGradient(colors: [_kPrimaryLight, _kPrimary]) : null,
          color: active ? null : _kPill,
          boxShadow: active ? [BoxShadow(color: _kPrimary.withOpacity(0.4), blurRadius: 8)] : null,
        ),
        child: Center(child: Text('$num', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
            color: active ? Colors.white : _kSub))),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
          color: active ? _kPrimary : _kSub)),
    ],
  );

  Widget _stepConnector(bool active) => Container(
    width: 20, height: 2, margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: active ? _kPrimary : _kPill,
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
              gradient: const LinearGradient(colors: [_kPrimaryLight, _kPrimary]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 24),
          const Text('AI가 동화를 만들고 있어요!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _kInk)),
          const SizedBox(height: 10),
          const Text('내 그림을 분석하고\n5페이지 동화 + AI 삽화를 그리는 중이에요 ✨',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _kSub, height: 1.6)),
          const SizedBox(height: 6),
          const Text('(약 1~2분 소요될 수 있어요)',
              style: TextStyle(fontSize: 12, color: Color(0xFFB6ABD6))),
          const SizedBox(height: 30),
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_kPrimary),
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
                style: const TextStyle(fontSize: 14, color: _kSub, height: 1.6)),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _generateStory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kPrimaryLight, _kPrimary]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: const Text('다시 만들기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
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
            SizedBox(width: 280, child: _buildDrawingPanel()),
            const SizedBox(width: 16),
            Expanded(child: _buildStoryPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawingPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF4CAF82), Color(0xFF2E9E6B)]),
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
            Container(height: 1, color: _kPill),
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
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kPrimary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(_drawingDescription,
                            style: const TextStyle(fontSize: 12, color: _kInk2, height: 1.55)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 동화 제목 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kPrimaryLight, _kPrimary]),
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
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.4)),
                      ),
                      child: const Row(
                        children: [
                          Text('⭐', style: TextStyle(fontSize: 11)),
                          SizedBox(width: 4),
                          Text('나만의 동화',
                              style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
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
                    Text(
                      _storyPages.isNotEmpty ? _storyPages[_currentPage] : '',
                      style: const TextStyle(
                          fontSize: 16, color: _kInk2,
                          height: 1.9, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 20),
                    _buildPageAiImage(),
                  ],
                ),
              ),
            ),
          ),
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
        border: Border.all(color: _kPrimaryLight.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: _kPill,
              child: const Row(
                children: [
                  Text('🎨', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text('AI가 그린 삽화',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _kPrimary)),
                ],
              ),
            ),
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
                color: _kBg,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_kPrimary),
                      strokeWidth: 2,
                    ),
                    SizedBox(height: 10),
                    Text('AI 삽화 준비 중...',
                        style: TextStyle(fontSize: 12, color: _kSub)),
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
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kPill)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _currentPage > 0 ? _kPill : const Color(0xFFF1ECFA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16,
                  color: _currentPage > 0 ? _kPrimary : const Color(0xFFC9BEE6)),
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
                          ? const LinearGradient(colors: [_kPrimaryLight, _kPrimary])
                          : null,
                      color: isActive ? null : _kPill,
                      borderRadius: BorderRadius.circular(4),
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
                    ? const LinearGradient(colors: [_kPrimaryLight, _kPrimary])
                    : null,
                color: _currentPage < _storyPages.length - 1 ? null : const Color(0xFFF1ECFA),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _currentPage < _storyPages.length - 1
                    ? [BoxShadow(color: _kPrimary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
                    : null,
              ),
              child: Icon(Icons.arrow_forward_ios_rounded, size: 16,
                  color: _currentPage < _storyPages.length - 1
                      ? Colors.white : const Color(0xFFC9BEE6)),
            ),
          ),
        ],
      ),
    );
  }
}
