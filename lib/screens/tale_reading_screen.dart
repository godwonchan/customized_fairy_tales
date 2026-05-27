import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'fairy_tale_list_screen.dart';
import 'page_selection_screen.dart';

// ═══════════════════════════════════════════════════════════════
//  동화 페이지 데이터 모델
// ═══════════════════════════════════════════════════════════════

class TalePage {
  final int pageNumber;
  final String imagePath;
  final String text;
  final String? highlightText;

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

  TaleBook({required this.tale, required this.pages});

  int get totalPages => pages.length;
}

TaleBook getTaleBook(FairyTale tale) {
  if (tale.title == '백설공주') {
    return TaleBook(
      tale: tale,
      pages: [
        TalePage(pageNumber: 1, imagePath: 'assets/book_001_Snow_White/Snow_White_01.png', text: '옛날 옛적, 깊은 숲 속 왕국에 눈처럼 하얀 피부를 가진 아름다운 공주가 살았어요.'),
        TalePage(pageNumber: 2, imagePath: 'assets/book_001_Snow_White/Snow_White_02.png', text: '왕국에는 마법 거울을 가진 새 왕비가 있었어요.', highlightText: '"거울아 거울아, 세상에서 누가 제일 예쁘니?"'),
        TalePage(pageNumber: 3, imagePath: 'assets/book_001_Snow_White/Snow_White_03.png', text: '어느 날, 거울이 백설공주가 더 아름답다고 대답했어요.'),
        TalePage(pageNumber: 4, imagePath: 'assets/book_001_Snow_White/Snow_White_04.png', text: '마음 착한 사냥꾼은 백설공주를 살려주었어요.'),
        TalePage(pageNumber: 5, imagePath: 'assets/book_001_Snow_White/Snow_White_05.png', text: '오두막에는 일곱 난쟁이가 살고 있었어요.', highlightText: '"우리와 함께 살아요!"'),
        TalePage(pageNumber: 6, imagePath: 'assets/book_001_Snow_White/Snow_White_06.png', text: '마침내 왕자님이 나타나 백설공주에게 입맞춤을 하자 마법이 풀렸어요.', highlightText: '"영원히 함께해요!"'),
      ],
    );
  }

  return TaleBook(
    tale: tale,
    pages: List.generate(5, (index) => TalePage(
      pageNumber: index + 1,
      imagePath: 'assets/${tale.imagePath}',
      text: '${tale.title} ${index + 1}페이지 내용이에요.',
    )),
  );
}

// ═══════════════════════════════════════════════════════════════
//  동화 읽기 화면 (TTS 오디오 포함)
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
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _isFavorite = false;

  // ── 오디오 상태 ──
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  bool _autoNextPage = true;
  double _volume = 0.7;
  double _progress = 0.0;
  double _totalDuration = 0.0;
  double _currentPosition = 0.0;
  double _fontSize = 15.0;
  double _speechRate = 0.5;

  @override
  void initState() {
    super.initState();
    _taleBook = getTaleBook(widget.tale);
    _currentPage = widget.initialPage;
    _isFavorite = widget.tale.isFavorite;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _initTts();
  }

  // ── TTS 초기화 ──
  Future<void> _initTts() async {
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(_volume);
    await _flutterTts.setPitch(1.0);

    // 재생 완료 시
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
        _progress = 1.0;
      });
      // 자동 넘김 켜져 있으면 다음 페이지로
      if (_autoNextPage && _currentPage < _taleBook.totalPages - 1) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _nextPage();
          _togglePlay();
        });
      }
    });

    // 진행 상태 업데이트
    _flutterTts.setProgressHandler(
        (String text, int startOffset, int endOffset, String word) {
      if (_totalDuration > 0) {
        setState(() {
          _progress = endOffset / text.length;
          _currentPosition = _progress * _totalDuration;
        });
      }
    });

    // 에러 처리
    _flutterTts.setErrorHandler((msg) {
      setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _animController.dispose();
    super.dispose();
  }

  // ── 페이지 이동 ──
  void _goToPage(int index) {
    if (index < 0 || index >= _taleBook.totalPages) return;
    _flutterTts.stop();
    setState(() {
      _currentPage = index;
      _isPlaying = false;
      _progress = 0.0;
      _currentPosition = 0.0;
    });
    _animController.forward(from: 0);
  }

  void _nextPage() => _goToPage(_currentPage + 1);
  void _prevPage() => _goToPage(_currentPage - 1);

  // ── 재생/일시정지 ──
  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _flutterTts.pause();
      setState(() => _isPlaying = false);
    } else {
      final page = _taleBook.pages[_currentPage];
      final text = page.highlightText != null
          ? '${page.text} ${page.highlightText}'
          : page.text;

      // 텍스트 길이 기반 예상 시간 계산
      _totalDuration = (text.length / 5) / _speechRate;

      await _flutterTts.setVolume(_volume);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.speak(text);
      setState(() => _isPlaying = true);
    }
  }

  String _formatTime(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
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
              child: isTablet
                  ? _buildTabletLayout()
                  : _buildPhoneLayout(),
            ),
            _buildThumbnailBar(isTablet),
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
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _flutterTts.stop();
              Navigator.pop(context);
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: const Color(0xFFF8F4FF),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.chevron_left,
                  color: Color(0xFF7E57C2), size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('동화 읽기',
                      style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF3D2C8D))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7E57C2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book,
                        size: 14, color: Colors.white),
                  ),
                ],
              ),
              Text('이야기를 처음부터 끝까지 읽어보아요.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
          const Spacer(),
          // 읽어주기 버튼 (재생 상태 표시)
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isPlaying
                    ? const Color(0xFF7E57C2)
                    : const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE0D7F5)),
              ),
              child: Row(
                children: [
                  Icon(
                    _isPlaying
                        ? Icons.pause_rounded
                        : Icons.volume_up_rounded,
                    size: 16,
                    color: _isPlaying
                        ? Colors.white
                        : const Color(0xFF7E57C2),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isPlaying ? '일시정지' : '읽어주기',
                    style: TextStyle(
                        fontSize: 12,
                        color: _isPlaying
                            ? Colors.white
                            : const Color(0xFF7E57C2),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _headerBtn(Icons.list_rounded, '목차', () {}),
          const SizedBox(width: 8),
          _headerBtn(Icons.text_fields_rounded, '가 글자 크기',
              _showFontSizeDialog),
        ],
      ),
    );
  }

  Widget _headerBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }

  // ── 태블릿 레이아웃 ──
  Widget _buildTabletLayout() {
    final page = _taleBook.pages[_currentPage];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 55, child: _buildImageArea(page, isTablet: true)),
          const SizedBox(width: 24),
          Expanded(
              flex: 45,
              child: _buildTextAndAudioArea(page, isTablet: true)),
        ],
      ),
    );
  }

  // ── 폰 레이아웃 ──
  Widget _buildPhoneLayout() {
    final page = _taleBook.pages[_currentPage];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildImageArea(page, isTablet: false),
          const SizedBox(height: 16),
          _buildTextAndAudioArea(page, isTablet: false),
        ],
      ),
    );
  }

  // ── 이미지 영역 ──
  Widget _buildImageArea(TalePage page, {required bool isTablet}) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Image.asset(
              page.imagePath,
              fit: BoxFit.cover,
              width: double.infinity,
              height: isTablet ? double.infinity : 320,
              errorBuilder: (_, __, ___) => Container(
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
        Positioned(
          left: 8, top: 0, bottom: 0,
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
        Positioned(
          right: 8, top: 0, bottom: 0,
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

  // ── 텍스트 + 오디오 영역 ──
  Widget _buildTextAndAudioArea(TalePage page, {required bool isTablet}) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
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
                Icon(Icons.list_rounded, size: 22, color: Colors.grey[400]),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() => _isFavorite = !_isFavorite),
                  child: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 22,
                    color: _isFavorite
                        ? const Color(0xFFE91E63)
                        : Colors.grey[400],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.tale.title,
              style: TextStyle(
                fontSize: isTablet ? 28 : 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D2C8D),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              page.text,
              style: TextStyle(
                fontSize: _fontSize,
                color: const Color(0xFF3D2C8D),
                height: 1.8,
              ),
            ),
            if (page.highlightText != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFFE082), width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _isPlaying
                          ? Icons.volume_up
                          : Icons.volume_up_outlined,
                      size: 16,
                      color: const Color(0xFFFF8F00),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        page.highlightText!,
                        style: TextStyle(
                          fontSize: _fontSize,
                          color: const Color(0xFF5D4037),
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            _buildAudioPlayer(isTablet),
            const SizedBox(height: 16),
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
      ),
    );
  }

  // ── 오디오 플레이어 ──
  Widget _buildAudioPlayer(bool isTablet) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // 제목 + 자동 넘김 토글
          Row(
            children: [
              const Icon(Icons.headphones_rounded,
                  size: 16, color: Color(0xFF7E57C2)),
              const SizedBox(width: 6),
              const Text('이야기 들려주기',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3D2C8D))),
              const Spacer(),
              Text('자동 넘김:',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 6),
              // 자동 넘김 토글
              GestureDetector(
                onTap: () =>
                    setState(() => _autoNextPage = !_autoNextPage),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 24,
                  decoration: BoxDecoration(
                    color: _autoNextPage
                        ? const Color(0xFF7E57C2)
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _autoNextPage
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      width: 20, height: 20,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 볼륨 + 컨트롤 버튼
          Row(
            children: [
              Icon(Icons.volume_up, size: 18, color: Colors.grey[500]),
              Expanded(
                flex: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFF7E57C2),
                    inactiveTrackColor: Colors.grey[200],
                    thumbColor: const Color(0xFF7E57C2),
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7),
                    trackHeight: 3,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0, max: 1,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      _flutterTts.setVolume(v);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${(_volume * 100).toInt()}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
              const Spacer(),
              // 이전 페이지
              _audioBtn(Icons.skip_previous_rounded, _prevPage),
              const SizedBox(width: 8),
              // 재생/일시정지
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF7E57C2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 다음 페이지
              _audioBtn(Icons.skip_next_rounded, _nextPage),
              const SizedBox(width: 8),
              // 속도 설정
              GestureDetector(
                onTap: _showSpeedDialog,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.settings_rounded,
                      size: 20, color: Color(0xFF7E57C2)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 진행 바
          Row(
            children: [
              Text(_formatTime(_currentPosition),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFF7E57C2),
                    inactiveTrackColor: Colors.grey[200],
                    thumbColor: const Color(0xFF7E57C2),
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                    trackHeight: 3,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _progress.clamp(0.0, 1.0),
                    min: 0, max: 1,
                    onChanged: (v) {
                      setState(() {
                        _progress = v;
                        _currentPosition = v * _totalDuration;
                      });
                    },
                  ),
                ),
              ),
              Text(_formatTime(_totalDuration),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audioBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF7E57C2)),
      ),
    );
  }

  // ── 속도 설정 다이얼로그 ──
  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('읽기 속도',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              ...[
                {'label': '느리게', 'rate': 0.3},
                {'label': '보통', 'rate': 0.5},
                {'label': '빠르게', 'rate': 0.7},
              ].map((item) {
                final isSelected = _speechRate == item['rate'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _speechRate = item['rate'] as double);
                    _flutterTts.setSpeechRate(item['rate'] as double);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEDE7F6)
                          : const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7E57C2)
                              : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        Text(item['label'] as String,
                            style: TextStyle(
                                fontSize: 14,
                                color: isSelected
                                    ? const Color(0xFF7E57C2)
                                    : const Color(0xFF3D2C8D),
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                        const Spacer(),
                        if (isSelected)
                          const Icon(Icons.check,
                              size: 18, color: Color(0xFF7E57C2)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
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
              offset: const Offset(0, -2)),
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
            height: isTablet ? 80 : 72,
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
                          width: isTablet ? 56 : 50,
                          height: isTablet ? 52 : 46,
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
                                      color: const Color(0xFF7E57C2)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                    )
                                  ]
                                : [],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              page.imagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: widget.tale.cardColor,
                                child: Center(
                                  child: Text('${index + 1}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: widget.tale.cardColor
                                              .withOpacity(0.5))),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF7E57C2)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('${index + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey[400],
                                  fontWeight: FontWeight.w600,
                                )),
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
          ElevatedButton.icon(
            onPressed: () {
              _flutterTts.stop();
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

  // ── 글자 크기 다이얼로그 ──
  void _showFontSizeDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('글자 크기',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              ...[
                {'label': '작게', 'size': 13.0},
                {'label': '중간', 'size': 15.0},
                {'label': '크게', 'size': 18.0},
              ].map((item) {
                final isSelected = _fontSize == item['size'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _fontSize = item['size'] as double);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEDE7F6)
                          : const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7E57C2)
                              : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        Text(item['label'] as String,
                            style: TextStyle(
                                fontSize: 14,
                                color: isSelected
                                    ? const Color(0xFF7E57C2)
                                    : const Color(0xFF3D2C8D),
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                        const Spacer(),
                        if (isSelected)
                          const Icon(Icons.check,
                              size: 18, color: Color(0xFF7E57C2)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}