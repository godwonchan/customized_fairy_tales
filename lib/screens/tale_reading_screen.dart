import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'fairy_tale_list_screen.dart';
import 'page_selection_screen.dart';
import '../data/story_asset_repository.dart';
import '../services/api_service.dart';
import '../widgets/story_image_view.dart';

import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'package:audioplayers/audioplayers.dart'; // [추가] 고품질 MP3 오디오 재생용!

class TalePage {
  final int pageNumber;
  final String text;
  final String imagePath;
  final String? highlightText;

  TalePage({
    required this.pageNumber,
    required this.text,
    required this.imagePath,
    this.highlightText,
  });

  TalePage copyWith({
    int? pageNumber,
    String? text,
    String? imagePath,
    String? highlightText,
    bool clearHighlightText = false,
  }) {
    return TalePage(
      pageNumber: pageNumber ?? this.pageNumber,
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
      highlightText: clearHighlightText ? null : (highlightText ?? this.highlightText),
    );
  }
}

class TaleBook {
  final FairyTale tale;
  final List<TalePage> pages;

  TaleBook({required this.tale, required this.pages});

  int get totalPages => pages.length;

  TaleBook copyWith({FairyTale? tale, List<TalePage>? pages}) {
    return TaleBook(tale: tale ?? this.tale, pages: pages ?? this.pages);
  }
}

class TaleReadingScreen extends StatefulWidget {
  final FairyTale tale;
  final int initialPage;
  final bool useCurrentVersion;
  final TaleBook? overrideTaleBook;

  const TaleReadingScreen({
    super.key,
    required this.tale,
    this.initialPage = 0,
    this.useCurrentVersion = false,
    this.overrideTaleBook,
  });

  @override
  State<TaleReadingScreen> createState() => _TaleReadingScreenState();
}

class _TaleReadingScreenState extends State<TaleReadingScreen>
    with TickerProviderStateMixin {
  PageController? _pageController;
  TaleBook? _taleBook;
  int _currentPageIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isResettingForEdit = false;

  // [병규 튜토리얼] 재생 버튼과 수정 모드 버튼을 위한 GlobalKey
  final GlobalKey _audioPlayButtonKey = GlobalKey();
  final GlobalKey _editButtonKey = GlobalKey();
  TutorialCoachMark? _tutorialCoachMark;
  List<TargetFocus> _targets = [];

  late AnimationController _pageFlipController;
  late Animation<double> _pageFlipAnim;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  bool _autoNextPage = true;
  double _volume = 0.7;
  double _progress = 0.0;
  double _totalDuration = 0.0;
  double _currentPosition = 0.0;
  double _fontSize = 15.0;
  double _speechRate = 1.0; // 기존 0.5 -> 1.0으로 수정

  // [추가] 고품질 AI 음성 및 영어 번역 상태 변수
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isEnglish = false;       // 현재 언어 모드 (false: 한국어, true: 영어)
  bool _isTranslating = false;   // 번역 진행 중 로딩 여부
  bool _isAudioLoading = false;  // 백엔드에서 음성 받아오는 중 로딩 여부
  final Map<int, String> _translatedPagesCache = {}; // 페이지별 영어 번역문 캐시

  bool _useOriginalTts = false; // true로 바꾸면 기존 스마트폰 기계음, false면 새 Edge-TTS


  bool get _shouldLoadServerPages {
    return widget.overrideTaleBook == null &&
        widget.tale.storyId != null &&
        (widget.useCurrentVersion || widget.tale.isUserStory);
  }

  @override
  void initState() {
    super.initState();
    _pageFlipController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _pageFlipAnim = CurvedAnimation(parent: _pageFlipController, curve: Curves.easeInOut);
    _loadBook();
    _initAudioPlayer(); // [수정] 새 고품질 오디오 플레이어 초기화 기존 : _initTts();
  }

  // [추가] 고품질 AI 음성 리스너 초기화
  void _initAudioPlayer() {
    _audioPlayer.setVolume(_volume);

    // 재생 완료 시 다음 페이지 자동 넘김
    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _progress = 1.0;
      });

      if (_autoNextPage && _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _goNext();
          Future.delayed(const Duration(milliseconds: 500), () { _togglePlay(); });
        });
      }
    });

    // 재생 위치 및 진행률 업데이트
    _audioPlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() {
        _currentPosition = p.inMilliseconds / 1000.0;
        if (_totalDuration > 0) {
          _progress = (_currentPosition / _totalDuration).clamp(0.0, 1.0);
        }
      });
    });

    // 전체 길이 업데이트
    _audioPlayer.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() {
        _totalDuration = d.inMilliseconds / 1000.0;
      });
    });
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(_volume);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      setState(() { _isPlaying = false; _progress = 1.0; });
      if (_autoNextPage && _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _goNext();
          Future.delayed(const Duration(milliseconds: 500), () { _togglePlay(); });
        });
      }
    });

    _flutterTts.setProgressHandler((String text, int startOffset, int endOffset, String word) {
      if (_totalDuration > 0) {
        setState(() {
          _progress = endOffset / text.length;
          _currentPosition = _progress * _totalDuration;
        });
      }
    });

    _flutterTts.setErrorHandler((msg) => setState(() => _isPlaying = false));
  }

  Future<TaleBook> _loadBookFromServer() async {
    final storyId = widget.tale.storyId!;
    final rawPages = await ApiService.getCurrentPages(storyId);
    final pages = rawPages.map((raw) {
      final item = raw as Map<String, dynamic>;
      final pageNumber = item['page_number'] as int? ?? item['pageNumber'] as int? ?? 1;
      final text = (item['text_content'] ?? item['text'] ?? item['content'] ?? '').toString();
      final highlightText = item['highlight_text']?.toString();
      final imagePath = (item['image_url']?.toString().isNotEmpty ?? false)
          ? item['image_url'].toString()
          : ApiService.storyPageImageUrl(storyId, pageNumber);
      return TalePage(pageNumber: pageNumber, text: text, imagePath: imagePath, highlightText: highlightText);
    }).toList()..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return TaleBook(tale: widget.tale, pages: pages);
  }

  Future<void> _loadBook() async {
    try {
      final book = widget.overrideTaleBook != null
          ? widget.overrideTaleBook!
          : _shouldLoadServerPages
              ? await _loadBookFromServer()
              : await StoryAssetRepository.loadTaleBook(widget.tale);
      final initial = widget.initialPage.clamp(0, book.totalPages - 1);
      if (!mounted) return;
      setState(() {
        _taleBook = book;
        _currentPageIndex = initial;
        _pageController = PageController(initialPage: initial);
        _isLoading = false;
      });

      // [병규 튜토리얼 추가] 책 데이터 로딩 및 화면 렌더링 완료 후 튜토리얼 시작
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowTutorial();
      });

    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _startEditingFromOriginal() async {
    if (_taleBook == null) return;
    _audioPlayer.stop(); // [수정] 이동하기 전에 새 AI 오디오 확실히 정지!
    setState(() => _isPlaying = false); // [수정] 이동하기 전에 새 AI 오디오 확실히 정지!

    if (widget.tale.storyId == null || !widget.tale.isUserStory) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PageSelectionScreen(tale: widget.tale, taleBook: _taleBook!)));
      return;
    }
    setState(() => _isResettingForEdit = true);
    try {
      await ApiService.resetToOriginal(storyId: widget.tale.storyId!);
      final resetBook = await _loadBookFromServer();
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => PageSelectionScreen(tale: widget.tale, taleBook: resetBook)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('원본으로 초기화 실패: $e')));
    } finally {
      if (mounted) setState(() => _isResettingForEdit = false);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _audioPlayer.dispose(); // [추가] 화면 나갈 때 오디오 완전 해제
    _pageController?.dispose();
    _pageFlipController.dispose();
    super.dispose();
  }

  void _goPrev() {
    if (_pageController != null && _currentPageIndex > 0) {
      _flutterTts.stop();
      _audioPlayer.stop(); // [추가]
      setState(() => _isPlaying = false);
      _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
      _pageController!.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  void _goNext() {
    if (_pageController != null && _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1) {
      _flutterTts.stop();
      _audioPlayer.stop(); // [추가]
      setState(() => _isPlaying = false);
      _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
      _pageController!.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  Future<void> _togglePlay() async {
    if (_taleBook == null) return;

    if (_isPlaying) {
      await _audioPlayer.stop();
      await _flutterTts.stop();
      setState(() => _isPlaying = false);
      return;
    }

    final page = _taleBook!.pages[_currentPageIndex];

    // ============================================
    // 💡 [기존 기기 내장 TTS 모드]
    // ============================================
    if (_useOriginalTts) {
      final text = page.highlightText != null ? '${page.text} ${page.highlightText}' : page.text;
      await _flutterTts.setLanguage('ko-KR');
      await _flutterTts.setVolume(_volume);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
      setState(() => _isPlaying = true);
      return;
    }

    // ============================================
    // 💡 [새 고품질 Edge-TTS AI 음성 모드]
    // ============================================
    setState(() => _isAudioLoading = true);
    try {
      if (_isEnglish && !_translatedPagesCache.containsKey(page.pageNumber)) {
        final fullKoreanText = page.highlightText != null ? '${page.text} ${page.highlightText}' : page.text;
        final translated = await ApiService.translateToEnglish(fullKoreanText);
        _translatedPagesCache[page.pageNumber] = translated;
      }

      final targetText = _isEnglish
          ? _translatedPagesCache[page.pageNumber]!
          : (page.highlightText != null ? '${page.text} ${page.highlightText}' : page.text);

      final audioBytes = await ApiService.getStoryTTS(
        text: targetText,
        language: _isEnglish ? 'en' : 'ko',
      );

      await _audioPlayer.play(BytesSource(audioBytes));
      await _audioPlayer.setPlaybackRate(_speechRate);

      if (!mounted) return;
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 음성 재생 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isAudioLoading = false);
    }
  }
  // [추가] 한국어 <-> 영어 전환 함수
  Future<void> _toggleLanguage() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    }

    if (_taleBook == null) return;
    final page = _taleBook!.pages[_currentPageIndex];

    // 영어가 아닌 상태에서 영어로 바꾸려는데, 아직 번역 캐시가 없는 경우 번역 API 호출
    if (!_isEnglish && !_translatedPagesCache.containsKey(page.pageNumber)) {
      setState(() => _isTranslating = true);
      try {
        final fullKoreanText = page.highlightText != null
            ? '${page.text} ${page.highlightText}'
            : page.text;

        final translated = await ApiService.translateToEnglish(fullKoreanText);
        if (!mounted) return;
        setState(() {
          _translatedPagesCache[page.pageNumber] = translated;
          _isEnglish = true;
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('번역 실패: $e')),
        );
      } finally {
        if (mounted) setState(() => _isTranslating = false);
      }
    } else {
      // 이미 번역 캐시가 있거나 한국어로 돌아가는 경우 즉시 토글
      setState(() {
        _isEnglish = !_isEnglish;
      });
    }
  }

  Future<void> _translateCurrentPage() async {
    if (_taleBook == null) return;
    final page = _taleBook!.pages[_currentPageIndex];

    if (_translatedPagesCache.containsKey(page.pageNumber)) return;

    setState(() => _isTranslating = true);
    try {
      final fullKoreanText = page.highlightText != null
          ? '${page.text} ${page.highlightText}'
          : page.text;

      final translated = await ApiService.translateToEnglish(fullKoreanText);
      if (!mounted) return;
      setState(() {
        _translatedPagesCache[page.pageNumber] = translated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('번역 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  String _formatTime(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: const Color(0xFF3D2C8D), elevation: 0, title: Text(widget.tale.title)),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF7E57C2))),
      );
    }
    if (_errorMessage != null || _taleBook == null || _pageController == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F4FF),
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: const Color(0xFF3D2C8D), elevation: 0, title: Text(widget.tale.title)),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_errorMessage ?? '동화를 불러오지 못했어요.', textAlign: TextAlign.center))),
      );
    }
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final isLastPage = _currentPageIndex == _taleBook!.totalPages - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isTablet),
            Expanded(child: isTablet ? _buildTabletLayout() : _buildPhoneLayout()),
            _buildThumbnailBar(isTablet),
            _buildBottomBar(isTablet, isLastPage),
          ],
        ),
      ),
    );
  }

  // ✅ 헤더: 재생 버튼과 언어 전환 버튼 정상 매핑
  Widget _buildHeader(BuildContext context, bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF5F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // 1. 헤더 재생/일시정지 버튼 (_togglePlay 연결)
          GestureDetector(
            onTap: _isAudioLoading ? null : _togglePlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isPlaying ? const Color(0xFF7E57C2) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF7E57C2), width: 1.5),
                boxShadow: [BoxShadow(color: const Color(0xFF7E57C2).withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  if (_isAudioLoading)
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7E57C2)),
                    )
                  else
                    Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        size: 20, color: _isPlaying ? Colors.white : const Color(0xFF7E57C2)),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_isPlaying ? '일시정지' : '읽어주기',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: _isPlaying ? Colors.white : const Color(0xFF7E57C2))),
                      Text(_isPlaying ? '탭하면 멈춰요' : 'AI가 읽어드려요',
                          style: TextStyle(fontSize: 9, color: _isPlaying ? Colors.white.withOpacity(0.8) : Colors.grey[400])),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _headerBtn(Icons.list_rounded, '목차', () => Navigator.pop(context)),
          const SizedBox(width: 8),
          _headerBtn(Icons.text_fields_rounded, '가 글자 크기', _showFontSizeDialog),

          // 2. 언어 전환 버튼 (_toggleLanguage 연결)
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isTranslating ? null : _toggleLanguage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isEnglish ? const Color(0xFF7E57C2) : const Color(0xFFF8F4FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF7E57C2)),
              ),
              child: Row(
                children: [
                  if (_isTranslating)
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7E57C2)),
                    )
                  else
                    Icon(
                      Icons.translate_rounded,
                      size: 16,
                      color: _isEnglish ? Colors.white : const Color(0xFF7E57C2),
                    ),
                  const SizedBox(width: 4),
                  Text(
                    _isEnglish ? '🇺🇸 English' : '🇰🇷 한국어',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isEnglish ? Colors.white : const Color(0xFF7E57C2),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _headerBtn(Icons.help_outline_rounded, '도움말', () => _checkAndShowTutorial(force: true)),
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
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _taleBook!.totalPages,
      // [수정] 페이지를 손으로 넘겼을 때 오디오 정지 및 영어 모드 번역 실행
      onPageChanged: (index) {
        _audioPlayer.stop();
        setState(() {
          _isPlaying = false;
          _currentPageIndex = index;
        });
        if (_isEnglish) _translateCurrentPage();
      },
      itemBuilder: (context, index) {
        final page = _taleBook!.pages[index];
        // 👇 현재 보고 있는 페이지인지 확인해서 넘겨줌
        final isCurrent = index == _currentPageIndex;
        return Padding(padding: const EdgeInsets.all(16), child: _buildTabletPageContent(page));
      },
    );
  }

  Widget _buildTabletPageContent(TalePage page, {bool isCurrentPage = false}) {
    return AnimatedBuilder(
      animation: _pageFlipAnim,
      builder: (context, child) => Opacity(opacity: 1.0 - (_pageFlipAnim.value * 0.3), child: child),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 55, child: _buildImageArea(page, isTablet: true)),
          const SizedBox(width: 24),
          // 👇 isCurrentPage 전달
          Expanded(flex: 45, child: _buildTextAndAudioArea(page, isTablet: true, isCurrentPage: isCurrentPage)),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _taleBook!.totalPages,
      // [수정] 태블릿과 동일하게 스와이프 시 오디오 정지 및 번역 처리
      onPageChanged: (index) {
        _audioPlayer.stop();
        setState(() {
          _isPlaying = false;
          _currentPageIndex = index;
        });
        if (_isEnglish) _translateCurrentPage();
      },
      itemBuilder: (context, index) {
        final page = _taleBook!.pages[index];
        return AnimatedBuilder(
          animation: _pageFlipAnim,
          builder: (context, child) => Opacity(opacity: 1.0 - (_pageFlipAnim.value * 0.3), child: child),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _buildImageArea(page, isTablet: false),
              const SizedBox(height: 16),
            // 💡 index == _currentPageIndex 직접 전달
            _buildTextAndAudioArea(
                page,
                isTablet: false,
                isCurrentPage: index == _currentPageIndex,
              ),
            ]),
          ),
        );
      },
    );
  }

  // 🔍 3분할 만화 컷 및 일러스트 전체화면 확대 모달
  void _showFullScreenImage(String imagePath) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.88),
      builder: (dialogContext) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 1. 핀치 줌 & 패닝 가능한 대형 이미지 뷰어
              Center(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0, // 최대 4배까지 부드럽게 확대 가능
                  clipBehavior: Clip.none,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(dialogContext).size.width * 0.92,
                      maxHeight: MediaQuery.of(dialogContext).size.height * 0.88,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: StoryImageView(
                        imagePath: imagePath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),

              // 2. 우측 상단 닫기(X) 버튼
              Positioned(
                top: 24,
                right: 24,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(dialogContext),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),

              // 3. 하단 힌트 라벨
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '두 손가락으로 확대하거나 드래그할 수 있어요 ✨',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageArea(TalePage page, {required bool isTablet}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 1. 🌟 좌우 화살표의 정중앙에 배치된 동화 일러스트 카드
        Center(
          child: Container(
            height: isTablet ? double.infinity : 300,
            decoration: BoxDecoration(
              color: widget.tale.cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7E57C2).withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: StoryImageView(
                    imagePath: page.imagePath,
                    fit: BoxFit.cover,
                  ),
                ),
                // 💡 전체화면 버튼이 허공이 아니라 '그림 카드 오른쪽 위 모퉁이'에 쏙 들어가도록 배치
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => _showFullScreenImage(page.imagePath),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.fullscreen,
                        size: 20,
                        color: Color(0xFF7E57C2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. ◀ 좌측 이전 페이지 이동 화살표
        Positioned(
          left: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _goPrev,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
                  ],
                ),
                child: Icon(
                  Icons.chevron_left,
                  color: _currentPageIndex > 0 ? const Color(0xFF7E57C2) : Colors.grey[300],
                ),
              ),
            ),
          ),
        ),

        // 3. ▶ 우측 다음 페이지 이동 화살표
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _goNext,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
                  ],
                ),
                child: Icon(
                  Icons.chevron_right,
                  color: _taleBook != null && _currentPageIndex < _taleBook!.totalPages - 1
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

  Widget _buildTextAndAudioArea(TalePage page, {required bool isTablet, bool isCurrentPage = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(20)),
          child: Text('${page.pageNumber} / ${_taleBook!.totalPages}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 14),
        Text(widget.tale.title,
            style: TextStyle(fontSize: isTablet ? 28 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF3D2C8D))),
        const SizedBox(height: 14),

        // [수정 1] 영어 모드 / 한국어 모드에 따라 본문 분기
        Text(
          _isEnglish
              ? (_translatedPagesCache[page.pageNumber] ?? (_isTranslating ? '영어로 마법처럼 번역하고 있어요... ✨' : page.text))
              : page.text,
          style: TextStyle(fontSize: _fontSize, color: const Color(0xFF3D2C8D), height: 1.8),
        ),

        // [수정 2] 영어 모드가 아닐 때(!_isEnglish)만 기존 한국어 대사 강조 상자 노출
        if (!_isEnglish && page.highlightText != null && page.highlightText!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE082), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_isPlaying ? Icons.volume_up : Icons.volume_up_outlined, size: 16, color: const Color(0xFFFF8F00)),
                const SizedBox(width: 8),
                Expanded(child: Text('"${page.highlightText!}"',
                    style: TextStyle(fontSize: _fontSize, color: const Color(0xFF5D4037), fontStyle: FontStyle.italic, height: 1.6))),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        // 👇 isCurrentPage 전달
        _buildAudioPlayer(isTablet, isCurrentPage: isCurrentPage),
      ],
    );
  }

  Widget _buildAudioPlayer(bool isTablet, {bool isCurrentPage = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFAF8FF), Color(0xFFF0EBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8DCFF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9575CD).withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 상단 자동 넘김 토글 영역
          Row(
            children: [
              const Icon(Icons.headphones_rounded, size: 16, color: Color(0xFF7E57C2)),
              const SizedBox(width: 6),
              const Text(
                  '이야기 들려주기',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))
              ),
              const Spacer(),
              Text('자동 넘김:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _autoNextPage = !_autoNextPage),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 24,
                  decoration: BoxDecoration(
                    color: _autoNextPage ? const Color(0xFF7E57C2) : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _autoNextPage ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      width: 20, height: 20,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 컨트롤러 버튼 및 볼륨 조절 영역
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
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    trackHeight: 3,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0,
                    max: 1,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      _audioPlayer.setVolume(v); // [수정] _audioPlayer 볼륨 적용
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
              _audioBtn(Icons.skip_previous_rounded, _goPrev),
              const SizedBox(width: 8),

              // [수정] 재생 버튼: 튜토리얼 key 유지 + 음성 생성 로딩 인디케이터 적용
              GestureDetector(
                key: isCurrentPage ? _audioPlayButtonKey : null,
                onTap: _isAudioLoading ? null : _togglePlay,
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: Color(0xFF7E57C2), shape: BoxShape.circle),
                  child: _isAudioLoading
                      ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                      : Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _audioBtn(Icons.skip_next_rounded, _goNext),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showSpeedDialog,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.settings_rounded, size: 20, color: Color(0xFF7E57C2)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 재생 위치 및 진행바 영역
          Row(
            children: [
              Text(_formatTime(_currentPosition), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFF7E57C2),
                    inactiveTrackColor: Colors.grey[200],
                    thumbColor: const Color(0xFF7E57C2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 3,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _progress.clamp(0.0, 1.0),
                    min: 0,
                    max: 1,
                    onChanged: (v) {
                      final targetSeconds = v * _totalDuration;
                      setState(() {
                        _progress = v;
                        _currentPosition = targetSeconds;
                      });
                      // [추가] 슬라이더 조작 시 실제 오디오 재생 위치 탐색(Seek)
                      _audioPlayer.seek(Duration(milliseconds: (targetSeconds * 1000).toInt()));
                    },
                  ),
                ),
              ),
              Text(_formatTime(_totalDuration), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audioBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 36, height: 36,
        decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: const Color(0xFF7E57C2))),
    );
  }

  Widget _buildThumbnailBar(bool isTablet) {
    if (_taleBook == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4FF),
        border: Border(top: BorderSide(color: const Color(0xFFEDE7F6), width: 1.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.grid_view_rounded, size: 16, color: Color(0xFF7E57C2)),
            const SizedBox(width: 6),
            const Text('전체 페이지', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_taleBook!.totalPages, (index) {
                final isSelected = _currentPageIndex == index;
                final page = _taleBook!.pages[index];
                return GestureDetector(
                  onTap: () {
                    _audioPlayer.stop(); // [수정] _flutterTts 대신 _audioPlayer 정지
                    setState(() { _isPlaying = false; _currentPageIndex = index; });
                    if (_isEnglish) _translateCurrentPage(); // [추가] 영어 모드면 해당 페이지 번역 자동 실행
                    _pageFlipController.forward(from: 0).then((_) => _pageFlipController.reverse());
                    _pageController?.animateToPage(index, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      Container(
                        width: 50, height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent, width: 2.5),
                          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF7E57C2).withOpacity(0.3), blurRadius: 8)] : [],
                        ),
                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.cover)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent, shape: BoxShape.circle),
                        child: Center(child: Text('${index + 1}',
                            style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : Colors.grey[400], fontWeight: FontWeight.w600))),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isTablet, bool isLastPage) {
    return Container(
      padding: EdgeInsets.fromLTRB(isTablet ? 24 : 16, 12, isTablet ? 24 : 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF5F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.emoji_nature, size: 24, color: Color(0xFF7E57C2))),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isLastPage ? '이야기를 다 읽었나요?' : '${_currentPageIndex + 1} / ${_taleBook!.totalPages} 페이지',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2C8D))),
              Text(isLastPage ? '이제 내가 바꾸고 싶은 장면을 선택해볼까요?' : '계속 읽어볼까요?',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            key: _editButtonKey, // [추가] 2단계 타깃: 수정 모드로 가기 버튼
            onPressed: _isResettingForEdit ? null : _startEditingFromOriginal,
            icon: _isResettingForEdit
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.edit, size: 16),
            label: const Text('수정 모드로 가기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7E57C2), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  void _showFontSizeDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('글자 크기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              ...[
                {'label': '작게', 'size': 13.0},
                {'label': '중간', 'size': 15.0},
                {'label': '크게', 'size': 18.0},
              ].map((item) {
                final isSelected = _fontSize == item['size'];
                return GestureDetector(
                  onTap: () { setState(() => _fontSize = item['size'] as double); Navigator.pop(context); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEDE7F6) : const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent),
                    ),
                    child: Row(children: [
                      Text(item['label'] as String,
                          style: TextStyle(fontSize: 14, color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFF3D2C8D),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                      const Spacer(),
                      if (isSelected) const Icon(Icons.check, size: 18, color: Color(0xFF7E57C2)),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('읽기 속도', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              ...[
                {'label': '느리게', 'rate': 0.3},
                {'label': '보통', 'rate': 0.5},
                {'label': '빠르게', 'rate': 0.7},
              ].map((item) {
                final isSelected = _speechRate == item['rate'];
                return GestureDetector(
                  onTap: () async {
                    final rate = item['rate'] as double;
                    setState(() => _speechRate = item['rate'] as double);
                    // 1. [교체] _flutterTts 대신 새 오디오 플레이어에 배속 적용
                    await _audioPlayer.setPlaybackRate(rate);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEDE7F6) : const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? const Color(0xFF7E57C2) : Colors.transparent),
                    ),
                    child: Row(children: [
                      Text(item['label'] as String,
                          style: TextStyle(fontSize: 14, color: isSelected ? const Color(0xFF7E57C2) : const Color(0xFF3D2C8D),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                      const Spacer(),
                      if (isSelected) const Icon(Icons.check, size: 18, color: Color(0xFF7E57C2)),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
  // [병규 튜토리얼] 최초 1회 실행 체크
  Future<void> _checkAndShowTutorial({bool force = false}) async {
    if (!mounted || _isLoading || _taleBook == null) return;

    await Future.delayed(const Duration(milliseconds: 600)); // 화면 위젯 렌더링 완료 대기
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isTutorialSeen = prefs.getBool('is_reading_tutorial_seen') ?? false;

      if (!isTutorialSeen || force) {
        _initTutorialTargets();
        _tutorialCoachMark = TutorialCoachMark(
          targets: _targets,
          colorShadow: const Color(0xFF2D3436),
          textSkip: "건너뛰기",
          paddingFocus: 8,
          opacityShadow: 0.8,
          onFinish: () async {
            await prefs.setBool('is_reading_tutorial_seen', true);
          },
          onSkip: () {
            prefs.setBool('is_reading_tutorial_seen', true);
            return true;
          },
        )..show(context: context);
      }
    } catch (e) {
      debugPrint('튜토리얼 실행 예외 무시: $e');
    }
  }

  // [병규 튜토리얼] 2단계 타깃 정의
  void _initTutorialTargets() {
    _targets = [
      // 1단계: 재생 버튼 강조
      TargetFocus(
        identify: "audioPlayButtonTarget",
        keyTarget: _audioPlayButtonKey,
        shape: ShapeLightFocus.Circle,
        paddingFocus: 6,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top, // 재생 컨트롤러 위쪽으로 말풍선 배치
            builder: (context, controller) {
              return _buildTutorialBubble(
                context: context,
                title: "1단계: 실감 나게 이야기 듣기",
                description: "이 재생 버튼을 누르면 이야기 요정이\n실감 나는 목소리로 동화를 직접 읽어줘요!",
                fairyOnLeft: true,
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),

      // 2단계: 수정 모드로 가기 유도
      TargetFocus(
        identify: "editButtonTarget",
        keyTarget: _editButtonKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        paddingFocus: 6,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top, // 하단 버튼 위쪽으로 말풍선 배치
            builder: (context, controller) {
              return _buildTutorialBubble(
                context: context,
                title: "2단계: 나만의 이야기 만들기",
                description: "동화 내용이나 그림을 내 마음대로 바꾸고 싶다면\n'수정 모드로 가기'를 눌러 새로운 이야기를 만들어보세요!",
                isLast: true,
                fairyOnLeft: true,
                onNext: () => controller.next(),
              );
            },
          ),
        ],
      ),
    ];
  }

  // [병규 튜토리얼] 요정 + 말풍선 UI 컴포넌트
  Widget _buildTutorialBubble({
    required BuildContext context,
    required String title,
    required String description,
    required VoidCallback onNext,
    bool isLast = false,
    bool fairyOnLeft = true,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final fairyHeight = (screenSize.height * 0.38).clamp(200.0, 340.0);

    final fairyCharacter = SizedBox(
      height: fairyHeight,
      width: fairyHeight * 0.75,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Lottie.asset(
              'assets/animations/fairy.json',
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7E57C2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "이야기 요정",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );

    final speechBubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (screenSize.width * 0.45).clamp(260.0, 380.0),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD1C4E9), width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3D2C8D),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4A4A4A),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  isLast ? "확인했어요!" : "다음으로",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: fairyOnLeft
            ? [fairyCharacter, const SizedBox(width: 14), speechBubble]
            : [speechBubble, const SizedBox(width: 14), fairyCharacter],
      ),
    );
  }
}