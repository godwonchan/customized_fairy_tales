import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'page_selection_screen.dart';
import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════════
//  AI 재구성 결과 화면
// ═══════════════════════════════════════════════════════════════

class AIResultScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;
  final int editedPageIndex;
  final Uint8List? generatedImageBytes;
  final String? regeneratedText; // ← 추가

  const AIResultScreen({
    super.key,
    required this.tale,
    required this.taleBook,
    required this.editedPageIndex,
    this.generatedImageBytes,
    this.regeneratedText, // ← 추가
  });

  @override
  State<AIResultScreen> createState() => _AIResultScreenState();
}

class _AIResultScreenState extends State<AIResultScreen>
    with SingleTickerProviderStateMixin {
  late int _currentPage;
  late PageController _pageController;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _isSaved = false;

  // 재구성된 결과 페이지
  late List<Map<String, String>> _resultPages;

  @override
  void initState() {
    super.initState();
    _currentPage = 0;
    _pageController = PageController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _initResultPages();
  }

  void _initResultPages() {
    _resultPages = widget.taleBook.pages.asMap().entries.map((entry) {
      final index = entry.key;
      final page = entry.value;
      return {
        'imagePath': page.imagePath,
        'text':
            index == widget.editedPageIndex && widget.regeneratedText != null
            ? widget.regeneratedText!
            : page.text,
        'title': _getPageTitle(index),
      };
    }).toList();
  }

  String _getPageTitle(int index) {
    final titles = [
      '마법의 성을 찾아서',
      '신비한 만남',
      '새로운 친구들',
      '모험의 시작',
      '마법사의 선물',
      '행복한 결말',
    ];
    return index < titles.length ? titles[index] : '${index + 1}번째 이야기';
  }

  // ── 재구성된 TaleBook 생성 ──
  TaleBook _buildUpdatedTaleBook() {
    final updatedPages = widget.taleBook.pages.asMap().entries.map((entry) {
      final index = entry.key;
      final page = entry.value;
      return TalePage(
        pageNumber: page.pageNumber,
        imagePath: page.imagePath,
        text: _resultPages[index]['text']!,
        highlightText: page.highlightText,
      );
    }).toList();

    return TaleBook(tale: widget.tale, pages: updatedPages);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    setState(() => _currentPage = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    _animController.forward(from: 0);
  }

  void _nextPage() {
    if (_currentPage < _resultPages.length - 1) _goToPage(_currentPage + 1);
  }

  void _prevPage() {
    if (_currentPage > 0) _goToPage(_currentPage - 1);
  }

  // ── 저장하기 ──
  void _saveToBookshelf() {
    setState(() => _isSaved = true);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFEDE7F6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 36,
                  color: Color(0xFF7E57C2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '나의 책장에 저장됐어요!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3D2C8D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"${widget.tale.title}" 이야기가\n나의 책장에 저장됐어요 😊',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7E57C2),
                        side: const BorderSide(color: Color(0xFF7E57C2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('계속 보기'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E57C2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: const Text('책장 보러가기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 다시 만들기 → 원본으로 페이지 선택 ──
  void _goBackToEdit() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFCE4EC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.refresh,
                  size: 32,
                  color: Color(0xFFE91E63),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '처음부터 다시 만들까요?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3D2C8D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '원본 동화로 돌아가서\n처음부터 다시 수정할 수 있어요!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // 원본 동화로 페이지 선택 이동
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PageSelectionScreen(
                              tale: widget.tale,
                              taleBook: widget.taleBook,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE91E63),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: const Text('다시 만들기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 더 수정하기 → 재구성된 동화로 페이지 선택 ──
  void _goToMoreEdit() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFEDE7F6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit,
                  size: 32,
                  color: Color(0xFF7E57C2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '더 수정할까요?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3D2C8D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '재구성된 동화에서\n추가로 수정할 수 있어요!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // 재구성된 동화로 페이지 선택 이동
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PageSelectionScreen(
                              tale: widget.tale,
                              taleBook: _buildUpdatedTaleBook(),
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E57C2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: const Text('더 수정하기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isTablet),
            Expanded(
              child: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
            ),
            _buildThumbnailBar(isTablet),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──
  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 뒤로가기
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chevron_left,
                color: Color(0xFF7E57C2),
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '06 그림으로 동화 만들기 – AI 재구성 결과',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                widget.tale.title,
                style: TextStyle(
                  fontSize: isTablet ? 18 : 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D2C8D),
                ),
              ),
            ],
          ),
          const Spacer(),
          // 다시 만들기 버튼 (핑크-오렌지 그라데이션)
          GestureDetector(
            onTap: _goBackToEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE91E63), Color(0xFFFF5722)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: const [
                  Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    '다시 만들기',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 더 수정하기 버튼 (보라색 그라데이션)
          GestureDetector(
            onTap: _goToMoreEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7E57C2), Color(0xFF9C27B0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7E57C2).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: const [
                  Icon(Icons.edit, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    '더 수정하기',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 공유하기 버튼
          _headerButton(Icons.share_outlined, '공유하기', () {}),
          const SizedBox(width: 8),
          // 저장하기 버튼
          GestureDetector(
            onTap: _saveToBookshelf,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isSaved
                    ? const Color(0xFFEDE7F6)
                    : const Color(0xFF7E57C2),
                borderRadius: BorderRadius.circular(20),
                boxShadow: _isSaved
                    ? []
                    : [
                        BoxShadow(
                          color: const Color(0xFF7E57C2).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Icon(
                    _isSaved ? Icons.bookmark : Icons.bookmark_border,
                    size: 16,
                    color: _isSaved ? const Color(0xFF7E57C2) : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isSaved ? '저장됨' : '저장하기',
                    style: TextStyle(
                      fontSize: 13,
                      color: _isSaved ? const Color(0xFF7E57C2) : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE0D7F5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xFF7E57C2)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7E57C2),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 태블릿 레이아웃 ──
  Widget _buildTabletLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(flex: 55, child: _buildImageArea(isTablet: true)),
          const SizedBox(width: 32),
          Expanded(flex: 45, child: _buildTextArea(isTablet: true)),
        ],
      ),
    );
  }

  // ── 폰 레이아웃 ──
  Widget _buildPhoneLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildImageArea(isTablet: false),
          const SizedBox(height: 20),
          _buildTextArea(isTablet: false),
        ],
      ),
    );
  }

  // ── 이미지 영역 ──
  Widget _buildImageArea({required bool isTablet}) {
    final page = _resultPages[_currentPage];

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(4, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(-2, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),

            child: FadeTransition(
              opacity: _fadeAnim,
              child:
                  _currentPage == widget.editedPageIndex &&
                      widget.generatedImageBytes != null
                  ? Image.memory(
                      widget.generatedImageBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: isTablet ? double.infinity : 320,
                    )
                  : Image.asset(
                      page['imagePath']!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: isTablet ? double.infinity : 320,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: isTablet ? 400 : 320,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.tale.cardColor,
                              widget.tale.cardColor.withOpacity(0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.auto_stories,
                            size: 80,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        // AI 재구성 뱃지
        if (_currentPage == widget.editedPageIndex)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7E57C2), Color(0xFF9C27B0)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: const [
                  Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'AI 재구성',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 이전 버튼
        Positioned(
          left: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _prevPage,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chevron_left,
                  color: _currentPage > 0
                      ? const Color(0xFF7E57C2)
                      : Colors.grey[300],
                ),
              ),
            ),
          ),
        ),
        // 다음 버튼
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _nextPage,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chevron_right,
                  color: _currentPage < _resultPages.length - 1
                      ? const Color(0xFF7E57C2)
                      : Colors.grey[300],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 텍스트 영역 ──
  Widget _buildTextArea({required bool isTablet}) {
    final page = _resultPages[_currentPage];

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE7F6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentPage + 1} / ${_resultPages.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7E57C2),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (_currentPage == widget.editedPageIndex)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.auto_awesome,
                          size: 12,
                          color: Color(0xFF7E57C2),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '새롭게 재구성됨',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7E57C2),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              page['title']!,
              style: TextStyle(
                fontSize: isTablet ? 24 : 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D2C8D),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  page['text']!,
                  style: TextStyle(
                    fontSize: isTablet ? 16 : 14,
                    color: const Color(0xFF3D2C8D),
                    height: 1.9,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_currentPage > 0)
                  TextButton.icon(
                    onPressed: _prevPage,
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: Color(0xFF7E57C2),
                    ),
                    label: const Text(
                      '이전',
                      style: TextStyle(color: Color(0xFF7E57C2)),
                    ),
                  ),
                const Spacer(),
                if (_currentPage < _resultPages.length - 1)
                  ElevatedButton.icon(
                    onPressed: _nextPage,
                    icon: const Text(
                      '다음',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    label: const Icon(Icons.arrow_forward, size: 16),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _saveToBookshelf,
                    icon: const Icon(Icons.bookmark, size: 16),
                    label: const Text(
                      '책장에 저장하기',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 하단 썸네일 바 ──
  Widget _buildThumbnailBar(bool isTablet) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        height: isTablet ? 72 : 64,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _resultPages.length,
          itemBuilder: (context, index) {
            final isSelected = _currentPage == index;
            final isEdited = index == widget.editedPageIndex;
            final page = _resultPages[index];

            return GestureDetector(
              onTap: () => _goToPage(index),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    Container(
                      width: isTablet ? 60 : 52,
                      height: isTablet ? 60 : 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7E57C2)
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFF7E57C2,
                                  ).withOpacity(0.3),
                                  blurRadius: 8,
                                ),
                              ]
                            : [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            index == widget.editedPageIndex &&
                                widget.generatedImageBytes != null
                            ? Image.memory(
                                widget.generatedImageBytes!,
                                fit: BoxFit.cover,
                              )
                            : Image.asset(
                                page['imagePath']!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      color: widget.tale.cardColor,
                                      child: Center(
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: widget.tale.cardColor
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                    ),
                              ),
                      ),
                    ),
                    if (isEdited)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFF7E57C2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
