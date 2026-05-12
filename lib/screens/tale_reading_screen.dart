import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'page_selection_screen.dart';

// ═══════════════════════════════════════════════════════════════
//  동화 페이지 데이터 모델
// ═══════════════════════════════════════════════════════════════

class TalePage {
  final int pageNumber;
  final String imagePath;
  final String text;
  final String? highlightText; // 강조 텍스트 (말풍선)

  TalePage({
    required this.pageNumber,
    required this.imagePath,
    required this.text,
    this.highlightText,
  });
}

class TaleBook {
  final FairyTale tale;
  final List<TalePage> pages;

  TaleBook({
    required this.tale,
    required this.pages,
  });

  int get totalPages => pages.length;
}

// ═══════════════════════════════════════════════════════════════
//  샘플 동화 데이터 (각 동화별로 추가하면 됨)
// ═══════════════════════════════════════════════════════════════

TaleBook getTaleBook(FairyTale tale) {
  // 백설공주 데이터
  if (tale.title == '백설공주') {
    return TaleBook(
      tale: tale,
      pages: [
        TalePage(
          pageNumber: 1,
          imagePath: 'assets/book_001_Snow_White/Snow_White_01.png',
          text: '옛날 옛적, 깊은 숲 속 왕국에 눈처럼 하얀 피부를 가진 아름다운 공주가 살았어요. 사람들은 그녀를 백설공주라고 불렀답니다.',
        ),
        TalePage(
          pageNumber: 2,
          imagePath: 'assets/book_001_Snow_White/Snow_White_02.png',
          text: '왕국에는 마법 거울을 가진 새 왕비가 있었어요. 왕비는 매일 거울에게 물었어요.',
          highlightText: '"거울아 거울아, 세상에서 누가 제일 예쁘니?"',
        ),
        TalePage(
          pageNumber: 3,
          imagePath: 'assets/book_001_Snow_White/Snow_White_03.png',
          text: '어느 날, 거울이 백설공주가 더 아름답다고 대답했어요. 화가 난 왕비는 사냥꾼을 불러 백설공주를 숲으로 데려가라고 명령했어요.',
        ),
        TalePage(
          pageNumber: 4,
          imagePath: 'assets/book_001_Snow_White/Snow_White_04.png',
          text: '마음 착한 사냥꾼은 백설공주를 살려주었어요. 백설공주는 깊은 숲 속을 헤매다가 작은 오두막집을 발견했어요.',
        ),
        TalePage(
          pageNumber: 5,
          imagePath: 'assets/book_001_Snow_White/Snow_White_05.png',
          text: '오두막에는 일곱 난쟁이가 살고 있었어요. 일곱 난쟁이는 백설공주를 따뜻하게 맞아주었고, 백설공주는 그들과 함께 살게 되었어요.',
          highlightText: '"우리와 함께 살아요!"',
        ),
        TalePage(
          pageNumber: 6,
          imagePath: 'assets/book_001_Snow_White/Snow_White_06.png',
          text: '마침내 왕자님이 나타나 백설공주에게 입맞춤을 하자 마법이 풀렸어요. 백설공주와 왕자님은 행복하게 살았답니다.',
          highlightText: '"영원히 함께해요!"',
        ),
      ],
    );
  }

  // 다른 동화는 기본 데이터로 표시 (나중에 추가)
  return TaleBook(
    tale: tale,
    pages: List.generate(
      5,
      (index) => TalePage(
        pageNumber: index + 1,
        imagePath: 'assets/${tale.imagePath}',
        text: '${tale.title} ${index + 1}페이지 내용이 들어갈 자리예요. 동화 데이터를 추가해주세요.',
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
//  동화 읽기 화면
// ═══════════════════════════════════════════════════════════════

class TaleReadingScreen extends StatefulWidget {
  final FairyTale tale;
  final int initialPage;

  const TaleReadingScreen({
    super.key,
    required this.tale,
    this.initialPage = 0,
  });

  @override
  State<TaleReadingScreen> createState() => _TaleReadingScreenState();
}

class _TaleReadingScreenState extends State<TaleReadingScreen>
    with SingleTickerProviderStateMixin {
  late TaleBook _taleBook;
  late int _currentPage;
  late PageController _pageController;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _taleBook = getTaleBook(widget.tale);
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: _currentPage);
    _isFavorite = widget.tale.isFavorite;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
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
    if (_currentPage < _taleBook.totalPages - 1) {
      _goToPage(_currentPage + 1);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _goToPage(_currentPage - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            // 상단 헤더
            _buildHeader(context, isTablet),
            // 메인 콘텐츠
            Expanded(
              child: isTablet
                  ? _buildTabletLayout(context)
                  : _buildPhoneLayout(context),
            ),
            // 하단 썸네일
            _buildThumbnailBar(isTablet),
            // 맨 하단 액션 바
            _buildBottomBar(isTablet),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──
  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 16, vertical: 12),
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
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chevron_left,
                  color: Color(0xFF7E57C2), size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // 제목 + 부제목
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '동화 읽기',
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3D2C8D),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7E57C2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book, size: 14, color: Colors.white),
                  ),
                ],
              ),
              Text(
                '이야기를 처음부터 끝까지 읽어보아요.',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const Spacer(),
          // 읽어주기 버튼
          _headerButton(Icons.volume_up_rounded, '읽어주기'),
          const SizedBox(width: 8),
          // 목차 버튼
          _headerButton(Icons.list_rounded, '목차'),
          const SizedBox(width: 8),
          // 글자 크기 버튼
          _headerButton(Icons.text_fields_rounded, '가 글자 크기'),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0D7F5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF7E57C2)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7E57C2),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── 태블릿 레이아웃 ──
  Widget _buildTabletLayout(BuildContext context) {
    final page = _taleBook.pages[_currentPage];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // 왼쪽 — 이미지
          Expanded(
            flex: 55,
            child: _buildImageArea(page, isTablet: true),
          ),
          const SizedBox(width: 32),
          // 오른쪽 — 텍스트
          Expanded(
            flex: 45,
            child: _buildTextArea(page, isTablet: true),
          ),
        ],
      ),
    );
  }

  // ── 폰 레이아웃 ──
  Widget _buildPhoneLayout(BuildContext context) {
    final page = _taleBook.pages[_currentPage];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildImageArea(page, isTablet: false),
          const SizedBox(height: 20),
          _buildTextArea(page, isTablet: false),
        ],
      ),
    );
  }

  // ── 이미지 영역 ──
  Widget _buildImageArea(TalePage page, {required bool isTablet}) {
    return Stack(
      children: [
        // 메인 이미지
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Image.asset(
              page.imagePath,
              fit: BoxFit.cover,
              width: double.infinity,
              height: isTablet ? double.infinity : 320,
              errorBuilder: (context, error, stackTrace) => Container(
                height: isTablet ? 400 : 320,
                decoration: BoxDecoration(
                  color: widget.tale.cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Icon(Icons.auto_stories,
                      size: 80,
                      color: widget.tale.cardColor.withOpacity(0.4)),
                ),
              ),
            ),
          ),
        ),
        // 확대 버튼
        Positioned(
          top: 12, right: 12,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.fullscreen,
                size: 20, color: Color(0xFF7E57C2)),
          ),
        ),
        // 이전 버튼
        Positioned(
          left: 8,
          top: 0, bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _prevPage,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8)
                  ],
                ),
                child: Icon(Icons.chevron_left,
                    color: _currentPage > 0
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[300]),
              ),
            ),
          ),
        ),
        // 다음 버튼
        Positioned(
          right: 8,
          top: 0, bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _nextPage,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8)
                  ],
                ),
                child: Icon(Icons.chevron_right,
                    color: _currentPage < _taleBook.totalPages - 1
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[300]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 텍스트 영역 ──
  Widget _buildTextArea(TalePage page, {required bool isTablet}) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 페이지 번호 + 즐겨찾기
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${page.pageNumber} / ${_taleBook.totalPages}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7E57C2),
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _isFavorite = !_isFavorite),
                child: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite
                      ? const Color(0xFFE91E63)
                      : Colors.grey[400],
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 동화 제목
          Text(
            widget.tale.title,
            style: TextStyle(
              fontSize: isTablet ? 28 : 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF3D2C8D),
            ),
          ),
          const SizedBox(height: 16),
          // 본문 텍스트
          Text(
            page.text,
            style: TextStyle(
              fontSize: isTablet ? 16 : 14,
              color: const Color(0xFF3D2C8D),
              height: 1.8,
            ),
          ),
          // 말풍선 텍스트 (있을 때만)
          if (page.highlightText != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFFE082), width: 1.5),
              ),
              child: Text(
                page.highlightText!,
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  color: const Color(0xFF5D4037),
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          // 다음 페이지 버튼
          if (_currentPage < _taleBook.totalPages - 1)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('다음 페이지',
                        style: TextStyle(
                            fontSize: isTablet ? 16 : 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 하단 썸네일 바 ──
  Widget _buildThumbnailBar(bool isTablet) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view_rounded,
                  size: 16, color: Color(0xFF7E57C2)),
              const SizedBox(width: 6),
              const Text('전체 페이지',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3D2C8D))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: isTablet ? 80 : 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _taleBook.totalPages,
              itemBuilder: (context, index) {
                final isSelected = _currentPage == index;
                final page = _taleBook.pages[index];

                return GestureDetector(
                  onTap: () => _goToPage(index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        Container(
                          width: isTablet ? 60 : 52,
                          height: isTablet ? 56 : 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF7E57C2)
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              page.imagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: widget.tale.cardColor,
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: widget.tale.cardColor
                                            .withOpacity(0.6),
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 선택된 페이지 표시
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF7E57C2)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[400],
                                fontWeight: FontWeight.w600,
                              ),
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
        ],
      ),
    );
  }

  // ── 하단 액션 바 ──
  Widget _buildBottomBar(bool isTablet) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          isTablet ? 24 : 16, 12, isTablet ? 24 : 16, 12),
      color: Colors.white,
      child: Row(
        children: [
          // 토끼 캐릭터 + 안내 메시지
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.emoji_nature,
                size: 24, color: Color(0xFF7E57C2)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentPage == _taleBook.totalPages - 1
                    ? '이야기를 다 읽었나요?'
                    : '${_currentPage + 1} / ${_taleBook.totalPages} 페이지',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3D2C8D)),
              ),
              Text(
                _currentPage == _taleBook.totalPages - 1
                    ? '이제 내가 바꾸고 싶은 장면을 선택해볼까요?'
                    : '계속 읽어볼까요?',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          const Spacer(),
          // 수정 모드로 가기 버튼
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PageSelectionScreen(
                    tale: widget.tale,
                    taleBook: _taleBook,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('수정 모드로 가기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7E57C2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}